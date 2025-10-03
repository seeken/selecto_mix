defmodule SelectoMix.DomainGenerator.Postgrex do
  @moduledoc """
  Generates Selecto domain configuration from PostgreSQL introspection data.
  """

  def generate_domain(table_info, app_module, module_name, opts \\ []) do
    first_column = hd(table_info.columns).column_name |> Atom.to_string()
    primary_key = inspect(table_info.primary_key)
    # Convert fields to strings for SelectoComponents compatibility
    fields = inspect(Enum.map(table_info.columns, &(&1.column_name |> Atom.to_string())))
    columns = format_columns(table_info.columns)

    # Generate associations from foreign keys
    associations = format_associations(table_info.foreign_keys)
    # Generate nested schemas if expand option is provided
    expanded_tables = Keyword.get(opts, :expanded_tables, %{})
    schemas = format_schemas(expanded_tables)

    # Get join type configuration
    join_types = Keyword.get(opts, :join_types, %{})

    # Generate joins from foreign keys (when expanded tables are provided)
    joins = format_joins(table_info.foreign_keys, expanded_tables, join_types)

    # Generate default_selected with joined fields if expanded
    default_selected = format_default_selected(table_info.columns, table_info.foreign_keys, expanded_tables)

    "defmodule #{app_module}.SelectoDomains.#{module_name}PostgrexDomain do\n" <>
    "  @moduledoc \"\"\"\n" <>
    "  Selecto domain for #{table_info.table_name} table using direct Postgrex connection.\n" <>
    "  Generated from database schema introspection.\n" <>
    "  \"\"\"\n" <>
    "\n" <>
    "  def domain do\n" <>
    "    %{\n" <>
    "      source: %{\n" <>
    "        source_table: \"#{table_info.table_name}\",\n" <>
    "        primary_key: #{primary_key},\n" <>
    "        fields: #{fields},\n" <>
    "        joins: %{},\n" <>
    "        columns: #{columns},\n" <>
    "        associations: #{associations}\n" <>
    "      },\n" <>
    "      schemas: #{schemas},\n" <>
    "      joins: #{joins},\n" <>
    "      redact_fields: [],\n" <>
    "      default_selected: #{default_selected},\n" <>
    "      default_sort: [%{field: \"#{first_column}\", direction: :asc}],\n" <>
    "      default_page_size: 25\n" <>
    "    }\n" <>
    "  end\n" <>
    "end\n"
  end

  defp format_columns(columns) do
    columns_map = Enum.map(columns, fn col ->
      # Use string keys for Postgrex compatibility
      col_str = col.column_name |> Atom.to_string()
      "        \"#{col_str}\" => %{\n" <>
      "          type: #{inspect(elixir_type(col.data_type))},\n" <>
      "          display_name: \"#{format_display_name(col.column_name)}\"\n" <>
      "        }"
    end)
    |> Enum.join(",\n")

    "%{\n#{columns_map}\n      }"
  end

  defp format_default_selected(columns, foreign_keys, expanded_tables) do
    # Select first 2 columns from main table
    main_cols = columns
    |> Enum.take(2)
    |> Enum.map(& &1.column_name |> Atom.to_string())

    # If we have expanded tables, add representative fields from joined tables
    joined_cols = if map_size(expanded_tables) > 0 do
      foreign_keys
      |> Enum.flat_map(fn fk ->
        table_info = Map.get(expanded_tables, fk.foreign_table_name)
        if table_info do
          # Get the first meaningful column (skip id, inserted_at, updated_at)
          meaningful_col = table_info.columns
          |> Enum.find(fn col ->
            col_str = col.column_name |> Atom.to_string()
            !String.contains?(col_str, "id") &&
            !String.contains?(col_str, "inserted_at") &&
            !String.contains?(col_str, "updated_at")
          end)

          if meaningful_col do
            join_name = singularize(fk.foreign_table_name)
            col_name = meaningful_col.column_name |> Atom.to_string()
            ["#{join_name}.#{col_name}"]
          else
            []
          end
        else
          []
        end
      end)
    else
      []
    end

    all_cols = main_cols ++ joined_cols
    inspect(all_cols)
  end

  defp format_display_name(column_name) do
    column_name
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_associations([]), do: "%{}"
  defp format_associations(foreign_keys) do
    assocs = Enum.map(foreign_keys, fn fk ->
      # Use singularized name for field/association key
      assoc_name = singularize(fk.foreign_table_name)
      col_name_str = fk.column_name |> Atom.to_string()
      foreign_col_str = fk.foreign_column_name |> Atom.to_string()

      # Use atom keys for associations (not strings) - Selecto expects atoms
      # queryable must match the schema key in schemas map (which is the table name)
      # field must be an atom to match join keys
      "      #{assoc_name}: %{\n" <>
      "        queryable: \"#{fk.foreign_table_name}\",\n" <>
      "        field: :#{assoc_name},\n" <>
      "        owner_key: \"#{col_name_str}\",\n" <>
      "        related_key: \"#{foreign_col_str}\"\n" <>
      "      }"
    end)
    |> Enum.join(",\n")

    if assocs == "" do
      "%{}"
    else
      "%{\n#{assocs}\n      }"
    end
  end

  defp format_schemas(expanded_tables) when map_size(expanded_tables) == 0, do: "%{}"
  defp format_schemas(expanded_tables) do
    schemas = Enum.map(expanded_tables, fn {table_name, table_info} ->
      # Use table name as schema key to match queryable in associations
      fields = inspect(Enum.map(table_info.columns, &(&1.column_name |> Atom.to_string())))
      columns = format_columns(table_info.columns)
      primary_key = inspect(table_info.primary_key)
      associations = format_associations(table_info.foreign_keys)

      "      \"#{table_name}\" => %{\n" <>
      "        source_table: \"#{table_name}\",\n" <>
      "        primary_key: #{primary_key},\n" <>
      "        fields: #{fields},\n" <>
      "        columns: #{columns},\n" <>
      "        associations: #{associations},\n" <>
      "        joins: %{},\n" <>
      "        redact_fields: []\n" <>
      "      }"
    end)
    |> Enum.join(",\n")

    "%{\n#{schemas}\n      }"
  end

  defp format_joins([], _expanded_tables, _join_types), do: "%{}"
  defp format_joins(_foreign_keys, expanded_tables, _join_types) when map_size(expanded_tables) == 0, do: "%{}"
  defp format_joins(foreign_keys, expanded_tables, join_types) do
    joins = Enum.map(foreign_keys, fn fk ->
      # Only create joins for tables that were expanded
      if Map.has_key?(expanded_tables, fk.foreign_table_name) do
        join_name = singularize(fk.foreign_table_name)
        join_name_atom = String.to_atom(join_name)
        col_name_str = fk.column_name |> Atom.to_string()
        foreign_col_str = fk.foreign_column_name |> Atom.to_string()

        # Determine join type from configuration or use default :left
        join_type = Map.get(join_types, join_name_atom, :left)

        # Use atom keys for joins (not strings) - Selecto expects atoms
        # The join name must match the association field name
        base_config = "        #{join_name}: %{\n" <>
                      "          type: #{inspect(join_type)},\n" <>
                      "          source: :\"#{fk.foreign_table_name}\",\n" <>
                      "          on: [%{left: \"#{col_name_str}\", right: \"#{foreign_col_str}\"}]"

        # Add specialized join configuration based on type
        additional_config = case join_type do
          :dimension ->
            # For dimension joins, we need to specify which field to display
            table_info = Map.get(expanded_tables, fk.foreign_table_name)
            dimension_field = find_dimension_field(table_info)
            ",\n          dimension: :\"#{dimension_field}\""

          :tagging ->
            # For tagging joins, specify the tag field
            table_info = Map.get(expanded_tables, fk.foreign_table_name)
            tag_field = find_tag_field(table_info)
            ",\n          tag_field: :\"#{tag_field}\""

          :hierarchical ->
            # For hierarchical joins, specify the hierarchy type
            ",\n          hierarchy_type: :adjacency_list,\n          depth_limit: 5"

          :star_dimension ->
            # For star dimension joins
            table_info = Map.get(expanded_tables, fk.foreign_table_name)
            display_field = find_dimension_field(table_info)
            ",\n          display_field: :\"#{display_field}\""

          :snowflake_dimension ->
            # For snowflake dimension joins
            table_info = Map.get(expanded_tables, fk.foreign_table_name)
            display_field = find_dimension_field(table_info)
            ",\n          display_field: :\"#{display_field}\",\n          normalization_joins: []"

          _ ->
            ""
        end

        base_config <> additional_config <> "\n        }"
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",\n")

    if joins == "" do
      "%{}"
    else
      "%{\n#{joins}\n      }"
    end
  end

  # Helper function to find a good field for dimension display (e.g., name, title, label)
  defp find_dimension_field(table_info) do
    # Look for common name-like fields
    name_candidates = [:name, :title, :label, :description]

    found_field = Enum.find(table_info.columns, fn col ->
      col.column_name in name_candidates
    end)

    if found_field do
      found_field.column_name |> Atom.to_string()
    else
      # Fallback to first non-id field
      first_field = Enum.find(table_info.columns, fn col ->
        col_str = col.column_name |> Atom.to_string()
        !String.ends_with?(col_str, "_id")
      end)

      if first_field do
        first_field.column_name |> Atom.to_string()
      else
        "id"
      end
    end
  end

  # Helper function to find tag field (similar to dimension field)
  defp find_tag_field(table_info) do
    find_dimension_field(table_info)
  end

  defp singularize(table_name) do
    # Basic singularization - strips trailing 's' or 'es'
    # For production, consider using Inflex library
    cond do
      String.ends_with?(table_name, "ies") ->
        String.slice(table_name, 0..-4//1) <> "y"
      String.ends_with?(table_name, "ses") || String.ends_with?(table_name, "ches") || String.ends_with?(table_name, "xes") ->
        String.slice(table_name, 0..-3//1)
      String.ends_with?(table_name, "s") ->
        String.slice(table_name, 0..-2//1)
      true ->
        table_name
    end
  end

  defp elixir_type("integer"), do: :integer
  defp elixir_type("bigint"), do: :integer
  defp elixir_type("smallint"), do: :integer
  defp elixir_type("character varying"), do: :string
  defp elixir_type("text"), do: :string
  defp elixir_type("boolean"), do: :boolean
  defp elixir_type("numeric"), do: :decimal
  defp elixir_type("decimal"), do: :decimal
  defp elixir_type("real"), do: :float
  defp elixir_type("double precision"), do: :float
  defp elixir_type("date"), do: :date
  defp elixir_type("timestamp" <> _), do: :naive_datetime
  defp elixir_type("time" <> _), do: :time
  defp elixir_type("uuid"), do: :binary_id
  defp elixir_type(_), do: :string
end
