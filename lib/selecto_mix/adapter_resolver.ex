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
end
