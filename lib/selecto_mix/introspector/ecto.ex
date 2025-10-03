defmodule SelectoMix.Introspector.Ecto do
  @moduledoc """
  Introspects Ecto schemas using __schema__/1 callbacks.

  This module extracts all metadata from Ecto schemas to build standardized
  schema information compatible with the SelectoMix.Introspector protocol.
  """

  @doc """
  Introspect an Ecto schema module and return standardized metadata.

  ## Parameters

  - `schema_module` - Ecto schema module (e.g., `MyApp.User`)
  - `opts` - Options (currently unused, reserved for future use)

  ## Returns

  - `{:ok, metadata}` - Standardized metadata map
  - `{:error, reason}` - Error if schema cannot be introspected
  """
  def introspect(schema_module, opts \\ []) do
    try do
      # Ensure module is loaded
      Code.ensure_loaded!(schema_module)

      # Check if it's an Ecto schema
      unless function_exported?(schema_module, :__schema__, 1) do
        raise ArgumentError, "#{inspect(schema_module)} is not an Ecto schema"
      end

      table_name = get_table_name(schema_module)
      fields = get_schema_fields(schema_module)
      field_types = get_field_types(schema_module)
      primary_key = get_primary_key(schema_module)
      associations = get_associations(schema_module, opts)

      # Build column metadata
      columns =
        fields
        |> Enum.into(%{}, fn field ->
          {field, %{
            type: Map.get(field_types, field),
            nullable: true,  # Ecto doesn't expose this easily
            default: nil
          }}
        end)

      metadata = %{
        table_name: table_name,
        schema: "public",  # Ecto doesn't expose schema name
        fields: fields,
        field_types: field_types,
        primary_key: primary_key,
        associations: associations,
        columns: columns,
        source: :ecto,
        schema_module: schema_module
      }

      {:ok, metadata}
    rescue
      error ->
        {:error, {:ecto_introspection_failed, error}}
    end
  end

  @doc """
  Get the database table name for an Ecto schema.
  """
  def get_table_name(schema_module) do
    schema_module.__schema__(:source)
  end

  @doc """
  Get the primary key field(s) for an Ecto schema.

  Returns single atom for single primary key, list for composite keys,
  or nil if no primary key is defined.
  """
  def get_primary_key(schema_module) do
    case schema_module.__schema__(:primary_key) do
      [] -> nil
      [single_key] -> single_key
      multiple_keys when is_list(multiple_keys) -> multiple_keys
    end
  end

  @doc """
  Get all fields defined in an Ecto schema.
  """
  def get_schema_fields(schema_module) do
    schema_module.__schema__(:fields)
  end

  @doc """
  Map Ecto field types to Selecto/Elixir types.

  Returns a map of field name to type atom.
  """
  def get_field_types(schema_module) do
    fields = get_schema_fields(schema_module)

    Enum.into(fields, %{}, fn field ->
      ecto_type = schema_module.__schema__(:type, field)
      selecto_type = map_ecto_type_to_selecto(ecto_type)
      {field, selecto_type}
    end)
  end

  @doc """
  Extract association information for join configuration.

  Returns a map of association name to association metadata.
  """
  def get_associations(schema_module, opts \\ []) do
    include_through = Keyword.get(opts, :include_through, false)

    associations = schema_module.__schema__(:associations)

    associations
    |> Enum.into(%{}, fn assoc_name ->
      assoc = schema_module.__schema__(:association, assoc_name)
      metadata = analyze_association(assoc)

      # Filter out through associations unless explicitly requested
      if include_through or not metadata.is_through do
        {assoc_name, metadata}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end

  # Private helper functions

  defp map_ecto_type_to_selecto(ecto_type) do
    case ecto_type do
      :id -> :integer
      :binary_id -> :binary_id
      :integer -> :integer
      :string -> :string
      :binary -> :string
      :boolean -> :boolean
      :decimal -> :decimal
      :float -> :float
      :date -> :date
      :time -> :time
      :utc_datetime -> :utc_datetime
      :naive_datetime -> :naive_datetime
      {:array, inner_type} -> {:array, map_ecto_type_to_selecto(inner_type)}
      {Ecto.Enum, _values} -> :string
      {:parameterized, Ecto.Enum, _values} -> :string
      _ -> :string  # Default fallback
    end
  end

  defp analyze_association(assoc) do
    base_metadata = %{
      type: get_association_type(assoc),
      association_type: get_association_type(assoc),
      related_schema: get_related_schema(assoc),
      owner_key: get_owner_key(assoc),
      related_key: get_related_key(assoc),
      join_type: suggest_join_type(assoc),
      is_through: is_through_association?(assoc),
      queryable: get_queryable(assoc)
    }

    # Add many-to-many specific metadata
    if get_association_type(assoc) == :many_to_many do
      Map.put(base_metadata, :join_through, get_join_through(assoc))
    else
      base_metadata
    end
  end

  # Get the junction table name for many-to-many associations
  defp get_join_through(%{join_through: join_through}) when is_binary(join_through) do
    join_through
  end
  defp get_join_through(%{join_through: join_through_schema}) when is_atom(join_through_schema) do
    # If it's a schema module, get its table name
    try do
      join_through_schema.__schema__(:source)
    rescue
      _ -> to_string(join_through_schema)
    end
  end
  defp get_join_through(_), do: nil

  defp get_association_type(%{__struct__: struct}) do
    case struct do
      Ecto.Association.Has -> :has_many
      Ecto.Association.BelongsTo -> :belongs_to
      Ecto.Association.HasThrough -> :has_many_through
      Ecto.Association.ManyToMany -> :many_to_many
      _ -> :unknown
    end
  end

  defp get_related_schema(%{related: related}), do: related
  defp get_related_schema(%{through: [through_assoc, _]}), do: through_assoc
  defp get_related_schema(_), do: nil

  defp get_owner_key(%{owner_key: owner_key}), do: owner_key
  defp get_owner_key(%{through: _}), do: :id
  defp get_owner_key(_), do: :id

  defp get_related_key(%{related_key: related_key}), do: related_key
  defp get_related_key(%{through: _}), do: :id
  defp get_related_key(_), do: :id

  defp get_queryable(%{queryable: queryable}) when is_atom(queryable) do
    # Convert module name to atom (e.g., MyApp.Category -> :categories)
    queryable
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>("s")  # Simple pluralization
    |> String.to_atom()
  end
  defp get_queryable(_), do: :unknown

  defp suggest_join_type(%{__struct__: Ecto.Association.BelongsTo}), do: :inner
  defp suggest_join_type(_), do: :left

  defp is_through_association?(%{through: _}), do: true
  defp is_through_association?(_), do: false
end
