defmodule SelectoMix.DomainGenerator.SchemaExpansion do
  @moduledoc false

  def introspect_related_schema(schema_module) do
    try do
      # Try to load the module and introspect it
      # Ensure the module is loaded
      case Code.ensure_loaded(schema_module) do
        {:module, _} ->
          if function_exported?(schema_module, :__schema__, 1) do
            fields = schema_module.__schema__(:fields)
            primary_key = schema_module.__schema__(:primary_key) |> List.first() || :id

            # Convert types to simplified format
            field_types =
              fields
              |> Enum.into(%{}, fn field ->
                type = schema_module.__schema__(:type, field)
                simplified_type = simplify_ecto_type(type)
                {field, simplified_type}
              end)

            # No associations in expanded schemas to avoid circular references
            associations = %{}

            {:ok,
             %{
               fields: fields,
               field_types: field_types,
               primary_key: primary_key,
               associations: associations
             }}
          else
            {:error, :not_ecto_schema}
          end

        {:error, _reason} ->
          {:error, :module_not_loaded}
      end
    rescue
      _ ->
        {:error, :introspection_failed}
    end
  end

  defp simplify_ecto_type({:parameterized, Ecto.Enum, _}), do: :string
  defp simplify_ecto_type({:array, inner_type}), do: {:array, simplify_ecto_type(inner_type)}
  defp simplify_ecto_type(:id), do: :integer
  defp simplify_ecto_type(:binary_id), do: :binary_id
  defp simplify_ecto_type(:uuid), do: :uuid
  defp simplify_ecto_type(:naive_datetime), do: :naive_datetime
  defp simplify_ecto_type(:utc_datetime), do: :utc_datetime
  defp simplify_ecto_type(type) when is_atom(type), do: type
  defp simplify_ecto_type(_), do: :string

  # Detect polymorphic associations in a schema.
  #
  # Looks for patterns like:
  # - commentable_type + commentable_id
  # - taggable_type + taggable_id
  # - attachable_type + attachable_id
  #
  # Returns a list of polymorphic associations:
  # [
  #   %{
  #     base_name: "commentable",
  #     type_field: :commentable_type,
  #     id_field: :commentable_id,
  #     suggested_types: ["Product", "Order", "Customer"]  # From seed data or manual
  #   }
  # ]
  def detect_polymorphic_associations(fields, _field_types) do
    # Find all fields ending in _type
    type_fields =
      Enum.filter(fields, fn field ->
        field_str = to_string(field)
        String.ends_with?(field_str, "_type")
      end)

    # For each type field, check if corresponding _id field exists
    Enum.flat_map(type_fields, fn type_field ->
      type_field_str = to_string(type_field)
      base_name = String.replace_suffix(type_field_str, "_type", "")
      id_field = SelectoMix.Identifier.to_atom!(base_name <> "_id")

      if id_field in fields do
        # Found a polymorphic pair!
        [
          %{
            base_name: base_name,
            type_field: type_field,
            id_field: id_field,
            # Default suggested types - can be overridden by --expand-polymorphic option
            suggested_types: ["Product", "Order", "Customer"]
          }
        ]
      else
        []
      end
    end)
  end

  def guess_table_name(schema_module) when is_atom(schema_module) do
    schema_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> Igniter.Inflex.pluralize()
  end

  def guess_table_name(schema_module) when is_binary(schema_module) do
    schema_module
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> Igniter.Inflex.pluralize()
  end

  def guess_table_name(schema_module) do
    raise ArgumentError, "cannot guess table name from #{inspect(schema_module)}"
  end

  def get_schema_name_from_module(schema_module) when is_atom(schema_module) do
    schema_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> SelectoMix.Identifier.to_atom!()
  end

  def get_schema_name_from_module(schema_module) when is_binary(schema_module) do
    schema_module
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> SelectoMix.Identifier.to_atom!()
  end

  def get_schema_name_from_module(_), do: :unknown
end
