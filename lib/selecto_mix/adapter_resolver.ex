defmodule SelectoMix.AdapterResolver do
  @moduledoc """
  Resolves adapter CLI values to adapter modules.
  """

  @adapter_aliases %{
    "postgres" => SelectoDBPostgreSQL.Adapter,
    "postgresql" => SelectoDBPostgreSQL.Adapter,
    "mysql" => SelectoDBMySQL.Adapter,
    "mariadb" => SelectoDBMariaDB.Adapter,
    "sqlite" => SelectoDBSQLite.Adapter,
    "duckdb" => SelectoDBDuckDB.Adapter,
    "mssql" => SelectoDBMSSQL.Adapter,
    "sqlserver" => SelectoDBMSSQL.Adapter
  }

  # Hex package to add to `mix.exs` for each known adapter module, used to
  # give actionable errors when an adapter module isn't loaded/compiled.
  @adapter_packages %{
    SelectoDBPostgreSQL.Adapter => "selecto_db_postgresql",
    SelectoDBMySQL.Adapter => "selecto_db_mysql",
    SelectoDBMariaDB.Adapter => "selecto_db_mariadb",
    SelectoDBSQLite.Adapter => "selecto_db_sqlite",
    SelectoDBDuckDB.Adapter => "selecto_db_duckdb",
    SelectoDBMSSQL.Adapter => "selecto_db_mssql"
  }

  @doc """
  Resolve a CLI adapter value to a module.
  """
  def resolve(adapter) when is_atom(adapter), do: {:ok, adapter}

  def resolve(adapter) when is_binary(adapter) do
    trimmed = String.trim(adapter)
    normalized = String.downcase(trimmed)

    cond do
      trimmed == "" ->
        {:error, :missing_adapter}

      Map.has_key?(@adapter_aliases, normalized) ->
        {:ok, Map.fetch!(@adapter_aliases, normalized)}

      true ->
        {:ok, Module.concat([trimmed])}
    end
  end

  def resolve(_adapter), do: {:error, :invalid_adapter}

  @doc """
  Known short adapter names accepted by the CLI.
  """
  def known_adapter_names do
    @adapter_aliases
    |> Map.keys()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  The Hex package name (e.g. `"selecto_db_postgresql"`) that provides
  `adapter_module`, if known.
  """
  def hex_package_for(adapter_module) do
    Map.get(@adapter_packages, adapter_module)
  end

  @doc """
  A human-friendly, actionable message for a `adapter_module` that failed to
  load, naming the Hex package to add when it's a known Selecto adapter.
  """
  def describe_missing_adapter(adapter_module) do
    case hex_package_for(adapter_module) do
      nil ->
        "Adapter module #{inspect(adapter_module)} is not loaded. " <>
          "Make sure its package is added to your deps and run `mix deps.get`."

      package ->
        "Adapter module #{inspect(adapter_module)} is not loaded. " <>
          "Add {:#{package}, \">= 0.0.0\"} to your deps in mix.exs and run `mix deps.get`."
    end
  end

  @doc """
  Formats a `SelectoMix.Connection` / `SelectoMix.Introspector` adapter error
  tuple into a human-readable message, naming the Hex package to add when the
  adapter module itself is missing.
  """
  def format_adapter_error({:adapter_not_loaded, adapter_module}),
    do: describe_missing_adapter(adapter_module)

  def format_adapter_error({:adapter_missing_connect, adapter_module}),
    do: "Adapter module #{inspect(adapter_module)} does not implement connect/1."

  def format_adapter_error({:adapter_missing_introspection, adapter_module}),
    do: "Adapter module #{inspect(adapter_module)} does not implement introspect_table/3."

  def format_adapter_error({:adapter_missing_schema_introspection, adapter_module}),
    do:
      "Adapter module #{inspect(adapter_module)} does not support the :schema_introspection feature."

  def format_adapter_error(other), do: inspect(other)
end
