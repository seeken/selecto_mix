defmodule SelectoMix.DomainGenerator.Postgrex do
  @moduledoc """
  Generates Selecto domain configuration from PostgreSQL introspection data.
  """

  def generate_domain(table_info, app_module, module_name) do
    first_column = hd(table_info.columns).column_name |> Atom.to_string()
    primary_key = inspect(table_info.primary_key)
    # Convert fields to strings for SelectoComponents compatibility
    fields = inspect(Enum.map(table_info.columns, &(&1.column_name |> Atom.to_string())))
    columns = format_columns(table_info.columns)
    default_selected = format_default_selected(table_info.columns)

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
    "        associations: %{}\n" <>
    "      },\n" <>
    "      schemas: %{},\n" <>
    "      default_selected: #{default_selected},\n" <>
    "      default_sort: [%{field: \"#{first_column}\", direction: :asc}],\n" <>
    "      default_page_size: 25\n" <>
    "    }\n" <>
    "  end\n" <>
    "end\n"
  end

  defp format_columns(columns) do
    columns_map = Enum.map(columns, fn col ->
      "        #{col.column_name}: %{\n" <>
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
