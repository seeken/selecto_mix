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
    default_selected = format_default_selected(table_info.columns)

    # Generate associations from foreign keys
    associations = format_associations(table_info.foreign_keys)
    # Generate nested schemas if expand option is provided
    schemas = format_schemas(Keyword.get(opts, :expanded_tables, %{}))

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
    "        columns: #{columns},\n" <>
    "        associations: #{associations}\n" <>
    "      },\n" <>
    "      schemas: #{schemas},\n" <>
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

  defp format_default_selected(columns) do
    # Select first 4 columns as default
    # Convert atoms to strings for SelectoComponents compatibility
    default_cols = columns
    |> Enum.take(4)
    |> Enum.map(& &1.column_name |> Atom.to_string())

    inspect(default_cols)
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

      # queryable must match the schema key in schemas map (which is the table name)
      "      \"#{assoc_name}\" => %{\n" <>
      "        queryable: \"#{fk.foreign_table_name}\",\n" <>
      "        field: \"#{assoc_name}\",\n" <>
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
      "        associations: #{associations}\n" <>
      "      }"
    end)
    |> Enum.join(",\n")

    "%{\n#{schemas}\n      }"
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
