defmodule SelectoMix.SchemaIntrospector do
  @moduledoc """
  Unified interface for introspecting schemas from any source.

  Supports both Ecto schemas and direct database connections via Postgrex.
  This module provides backward compatibility with the original Ecto-only
  interface while delegating to `SelectoMix.Introspector` (and its backends,
  e.g. `SelectoMix.Introspector.Ecto`) under the hood.

  ## Usage

      # Ecto schema (original interface - still works)
      config = SelectoMix.SchemaIntrospector.introspect_schema(MyApp.User)

      # Postgrex connection (new interface)
      {:ok, conn} = Postgrex.start_link(...)
      config = SelectoMix.SchemaIntrospector.introspect_schema(
        {:postgrex, conn, "users"}
      )
  """

  @doc """
  Introspect a schema source and return Selecto domain configuration data.

  Accepts either an Ecto schema module or a Postgrex connection tuple.

  ## Parameters

  - `source` - Either:
    - Ecto schema module (e.g., `MyApp.User`)
    - `{:postgrex, conn, table_name}` tuple
    - `{:postgrex, conn, table_name, schema}` tuple

  ## Options

    * `:include_associations` - Include schema associations as joins (default: true)
    * `:redact_fields` - List of field names to mark as redacted
    * `:default_limit` - Default limit for queries (default: 50)
    * `:include_timestamps` - Include timestamp fields in default selects (default: false)

  ## Returns

  A configuration map containing:
    - `:schema_module` - The source module or table name
    - `:table_name` - Database table name
    - `:primary_key` - Primary key field name
    - `:fields` - List of all available fields
    - `:field_types` - Map of field names to their Selecto types
    - `:associations` - Association metadata for joins
    - `:suggested_defaults` - Recommended default configuration
    - `:redacted_fields` - Fields that should be excluded from queries
  On failure, the map contains `:error` and `:schema_module`, matching the
  original public API. Use `introspect_schema_result/2` when tagged tuples are
  preferable.
  """
  @spec introspect_schema(term(), keyword()) :: map()
  def introspect_schema(source, opts \\ []) do
    case introspect_schema_result(source, opts) do
      {:ok, config} -> config
      {:error, reason} -> %{error: reason, schema_module: source}
    end
  end

  @doc """
  Introspects a schema while preserving success and failure as tagged tuples.

  Use this at task boundaries that need to stop generation on an introspection
  failure. `introspect_schema/2` retains the package's original map-returning
  API for backward compatibility.
  """
  @spec introspect_schema_result(term(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def introspect_schema_result(source, opts \\ []) do
    include_associations = Keyword.get(opts, :include_associations, true)
    redact_fields = Keyword.get(opts, :redact_fields, [])

    # Use new introspector protocol
    case SelectoMix.Introspector.introspect(source, opts) do
      {:ok, metadata} ->
        # Filter associations if not requested
        associations = if include_associations, do: metadata.associations, else: %{}

        # Generate suggested defaults based on metadata
        suggested_defaults =
          generate_suggested_defaults_from_metadata(
            metadata.fields,
            metadata.field_types,
            opts
          )

        # Extract additional metadata
        extra_metadata = extract_metadata_from_source(source, metadata)

        {:ok,
         %{
           schema_module: Map.get(metadata, :schema_module, source),
           table_name: metadata.table_name,
           primary_key: metadata.primary_key,
           fields: metadata.fields,
           field_types: metadata.field_types,
           associations: associations,
           suggested_defaults: suggested_defaults,
           redacted_fields: redact_fields,
           metadata: extra_metadata,
           columns: Map.get(metadata, :columns, %{}),
           source: Map.get(metadata, :source),
           source_kind: Map.get(metadata, :source_kind),
           readonly: Map.get(metadata, :readonly),
           source_type: Map.get(metadata, :source_type, source_type_for(source)),
           adapter: Map.get(metadata, :adapter)
         }}

      {:error, reason} ->
        {:error, "Failed to introspect schema #{inspect(source)}: #{inspect(reason)}"}
    end
  end

  @doc """
  Same as `introspect_schema/2`, but raises `Mix.Error` on failure and
  returns the config map directly. Intended for use at Mix task boundaries.
  """
  @spec introspect_schema!(term(), keyword()) :: map()
  def introspect_schema!(source, opts \\ []) do
    case introspect_schema_result(source, opts) do
      {:ok, config} -> config
      {:error, reason} -> Mix.raise(to_string(reason))
    end
  end

  @doc """
  Get the database table name for an Ecto schema.

  Delegates to `SelectoMix.Introspector.Ecto.get_table_name/1`.
  """
  def get_table_name(schema_module) do
    SelectoMix.Introspector.Ecto.get_table_name(schema_module)
  end

  @doc """
  Get the primary key field(s) for an Ecto schema.

  Delegates to `SelectoMix.Introspector.Ecto.get_primary_key/1`, which
  returns the full list of keys for composite primary keys and `nil` when
  the schema has none (rather than collapsing to a single field or `:id`).
  """
  def get_primary_key(schema_module) do
    SelectoMix.Introspector.Ecto.get_primary_key(schema_module)
  end

  @doc """
  Get all fields defined in an Ecto schema.

  Delegates to `SelectoMix.Introspector.Ecto.get_schema_fields/1`.
  """
  def get_schema_fields(schema_module) do
    SelectoMix.Introspector.Ecto.get_schema_fields(schema_module)
  end

  @doc """
  Map Ecto field types to Selecto types.

  Delegates to `SelectoMix.Introspector.Ecto.get_field_types/1`.
  """
  def get_field_types(schema_module) do
    SelectoMix.Introspector.Ecto.get_field_types(schema_module)
  end

  @doc """
  Extract association information for join configuration.

  Delegates to `SelectoMix.Introspector.Ecto.get_associations/2`, which
  additionally covers `:many_to_many` associations (with `join_through` /
  `join_keys`) that this module's earlier standalone implementation did not.
  """
  def get_associations(schema_module, opts \\ []) do
    SelectoMix.Introspector.Ecto.get_associations(schema_module, opts)
  end

  @doc """
  Generate suggested default configuration based on schema analysis.
  """
  def generate_suggested_defaults(schema_module, opts) do
    fields = get_schema_fields(schema_module)
    field_types = get_field_types(schema_module)
    generate_suggested_defaults_from_metadata(fields, field_types, opts)
  end

  # Generate suggested defaults from field metadata (works with any source)
  defp generate_suggested_defaults_from_metadata(fields, field_types, opts) do
    include_timestamps = Keyword.get(opts, :include_timestamps, false)

    # Suggest reasonable default selected fields
    default_selected = suggest_default_selected_fields(fields, field_types, include_timestamps)

    # Suggest default filters based on common patterns
    default_filters = suggest_default_filters(fields, field_types)

    # Suggest ordering
    default_order = suggest_default_ordering(fields, field_types)

    %{
      default_selected: default_selected,
      default_filters: default_filters,
      default_order: default_order,
      default_limit: Keyword.get(opts, :default_limit, 50)
    }
  end

  @doc """
  Extract additional metadata about the schema.
  """
  def extract_metadata(schema_module) do
    %{
      module_name: get_module_name(schema_module),
      context_name: get_context_name(schema_module),
      has_timestamps: has_timestamps?(schema_module),
      estimated_complexity: estimate_schema_complexity(schema_module)
    }
  end

  # Extract metadata from any source type
  defp extract_metadata_from_source(source, metadata) when is_atom(source) do
    # Ecto schema module
    %{
      module_name: get_module_name(source),
      context_name: get_context_name(source),
      has_timestamps: has_timestamps_in_fields?(metadata.fields),
      estimated_complexity: estimate_complexity_from_metadata(metadata)
    }
  end

  defp extract_metadata_from_source({:postgrex, _conn, table_name}, metadata) do
    # Postgrex connection
    %{
      module_name: Macro.camelize(table_name),
      context_name: "Database",
      has_timestamps: has_timestamps_in_fields?(metadata.fields),
      estimated_complexity: estimate_complexity_from_metadata(metadata)
    }
  end

  defp extract_metadata_from_source({:postgrex, _conn, table_name, _schema}, metadata) do
    %{
      module_name: Macro.camelize(table_name),
      context_name: "Database",
      has_timestamps: has_timestamps_in_fields?(metadata.fields),
      estimated_complexity: estimate_complexity_from_metadata(metadata)
    }
  end

  defp extract_metadata_from_source({:db, adapter, _conn, table_name}, metadata) do
    %{
      module_name: module_name_from_table(table_name),
      context_name: adapter_context_name(adapter),
      has_timestamps: has_timestamps_in_fields?(metadata.fields),
      estimated_complexity: estimate_complexity_from_metadata(metadata)
    }
  end

  defp extract_metadata_from_source({:db, adapter, _conn, table_name, _opts}, metadata) do
    %{
      module_name: module_name_from_table(table_name),
      context_name: adapter_context_name(adapter),
      has_timestamps: has_timestamps_in_fields?(metadata.fields),
      estimated_complexity: estimate_complexity_from_metadata(metadata)
    }
  end

  defp extract_metadata_from_source(_source, metadata) do
    %{
      module_name: "Unknown",
      context_name: "Unknown",
      has_timestamps: has_timestamps_in_fields?(metadata.fields),
      estimated_complexity: estimate_complexity_from_metadata(metadata)
    }
  end

  defp has_timestamps_in_fields?(fields) do
    Enum.any?(fields, fn field ->
      field_str = to_string(field)
      String.contains?(field_str, ["inserted_at", "updated_at"])
    end)
  end

  defp estimate_complexity_from_metadata(metadata) do
    field_count = length(metadata.fields)
    assoc_count = map_size(metadata.associations)

    cond do
      field_count <= 5 and assoc_count <= 2 -> :simple
      field_count <= 15 and assoc_count <= 5 -> :moderate
      true -> :complex
    end
  end

  # Private helper functions

  defp suggest_default_selected_fields(fields, field_types, include_timestamps) do
    # Start with common display fields
    candidates =
      Enum.filter(fields, fn field ->
        field_str = to_string(field)

        # Include name/title fields
        name_field = String.contains?(field_str, ["name", "title", "email", "username"])

        # Include ID fields
        id_field = String.ends_with?(field_str, "_id") or field == :id

        # Include status/active fields
        status_field = String.contains?(field_str, ["status", "active", "enabled"])

        # Include timestamps if requested
        timestamp_field = include_timestamps and String.contains?(field_str, ["_at", "date"])

        # Exclude binary and large text fields from defaults
        suitable_type =
          field_types[field] in [:string, :integer, :decimal, :boolean, :date, :utc_datetime]

        (name_field or id_field or status_field or timestamp_field) and suitable_type
      end)

    # Limit to reasonable number of fields
    candidates |> Enum.take(5)
  end

  defp suggest_default_filters(fields, field_types) do
    # Look for common filter patterns
    filter_fields =
      Enum.filter(fields, fn field ->
        field_str = to_string(field)
        field_type = field_types[field]

        # Boolean fields make good filters
        boolean_filter = field_type == :boolean

        # Status/category fields
        status_filter = String.contains?(field_str, ["status", "type", "category", "role"])

        # Date fields for range filtering
        date_filter =
          field_type in [:date, :utc_datetime] and
            String.contains?(field_str, ["created", "updated"])

        boolean_filter or status_filter or date_filter
      end)

    # Generate filter configurations
    Enum.into(filter_fields, %{}, fn field ->
      field_type = field_types[field]
      filter_config = generate_filter_config(field, field_type)
      {to_string(field), filter_config}
    end)
  end

  defp generate_filter_config(field, field_type) do
    _field_str = to_string(field)

    base_config = %{
      name: humanize_field_name(field),
      type: filter_type_for_selecto_type(field_type)
    }

    case field_type do
      :boolean ->
        Map.put(base_config, :default, true)

      type when type in [:date, :utc_datetime] ->
        Map.put(base_config, :operator, "gte")

      _ ->
        base_config
    end
  end

  defp filter_type_for_selecto_type(selecto_type) do
    case selecto_type do
      :boolean -> :boolean
      :integer -> :integer
      :decimal -> :decimal
      :float -> :float
      :date -> :date
      :utc_datetime -> :utc_datetime
      :naive_datetime -> :naive_datetime
      :string -> :string
      :text -> :string
      _ -> :string
    end
  end

  defp suggest_default_ordering(fields, field_types) do
    # Look for good ordering fields
    order_candidates =
      Enum.filter(fields, fn field ->
        field_str = to_string(field)
        field_type = field_types[field]

        # Timestamp fields for chronological ordering
        timestamp_field =
          field_type in [:date, :utc_datetime] and
            String.contains?(field_str, ["created", "updated", "published"])

        # Name fields for alphabetical ordering
        name_field =
          field_type == :string and
            String.contains?(field_str, ["name", "title"])

        # ID for natural ordering
        id_field = field == :id

        timestamp_field or name_field or id_field
      end)

    case order_candidates do
      [] -> []
      [first | _] -> [%{"field" => to_string(first), "direction" => "asc"}]
    end
  end

  defp get_module_name(schema_module) do
    schema_module
    |> Module.split()
    |> List.last()
  end

  defp get_context_name(schema_module) do
    parts = Module.split(schema_module)

    case parts do
      [_app, context | _] -> context
      _ -> "Unknown"
    end
  end

  defp has_timestamps?(schema_module) do
    fields = get_schema_fields(schema_module)

    Enum.any?(fields, fn field ->
      field_str = to_string(field)
      String.contains?(field_str, ["inserted_at", "updated_at"])
    end)
  end

  defp estimate_schema_complexity(schema_module) do
    field_count = length(get_schema_fields(schema_module))
    assoc_count = length(schema_module.__schema__(:associations))

    cond do
      field_count <= 5 and assoc_count <= 2 -> :simple
      field_count <= 15 and assoc_count <= 5 -> :moderate
      true -> :complex
    end
  end

  defp humanize_field_name(field) do
    field
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp source_type_for(source) when is_atom(source), do: :ecto
  defp source_type_for({:postgrex, _conn, _table_name}), do: :db
  defp source_type_for({:postgrex, _conn, _table_name, _schema}), do: :db
  defp source_type_for({:db, _adapter, _conn, _table_name}), do: :db
  defp source_type_for({:db, _adapter, _conn, _table_name, _opts}), do: :db
  defp source_type_for(_source), do: :unknown

  defp module_name_from_table(table_name) do
    table_name
    |> to_string()
    |> String.trim()
    |> String.trim_leading("public.")
    |> SelectoMix.Inflect.singularize()
    |> Macro.camelize()
  end

  defp adapter_context_name(adapter) when is_atom(adapter) do
    adapter
    |> Module.split()
    |> Enum.at(-2, "Database")
    |> to_string()
    |> String.replace_prefix("SelectoDB", "")
  end

  defp adapter_context_name(_adapter), do: "Database"
end
