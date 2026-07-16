defmodule SelectoMix.PersistenceGenerator do
  @moduledoc false

  @doc """
  Generates a migration-style UTC timestamp (`YYYYMMDDHHMMSS`), matching the
  format Ecto migrations expect.
  """
  @spec timestamp() :: String.t()
  def timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()
    "#{year}#{pad(month)}#{pad(day)}#{pad(hour)}#{pad(minute)}#{pad(second)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  @doc """
  Resolves a module name option (either a binary or an already-resolved
  atom) to a module atom via `Module.concat/1`.
  """
  @spec parse_module_name(String.t() | module()) :: module()
  def parse_module_name(module_string) when is_binary(module_string) do
    Module.concat([module_string])
  end

  def parse_module_name(module) when is_atom(module), do: module

  @doc """
  Validates a persistence table name, raising `Mix.Error` on failure.
  Returns the validated binary.
  """
  @spec validate_table_name!(term()) :: String.t()
  def validate_table_name!(name) do
    case SelectoMix.Identifier.validate_sql_identifier(name) do
      {:ok, valid} -> valid
      {:error, reason} -> Mix.raise(reason)
    end
  end

  @doc """
  Builds a migration file path under `priv/repo/migrations/` for the given
  timestamp and migration name slug.
  """
  @spec migration_file_path(String.t(), String.t()) :: String.t()
  def migration_file_path(timestamp, name) when is_binary(timestamp) and is_binary(name) do
    Path.join(["priv", "repo", "migrations", "#{timestamp}_#{name}.exs"])
  end
end
