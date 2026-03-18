defmodule SelectoMix.Introspector do
  @moduledoc """
  Protocol for introspecting different schema sources.

  This protocol provides a unified interface for discovering database schema
  information from different sources:

  - Ecto schema modules (via `__schema__/1` callbacks)
  - Direct PostgreSQL connections (via Postgrex and system catalogs)
  - Future: Other database types (MySQL, SQLite, etc.)

  ## Usage

      # Ecto schema
      {:ok, metadata} = SelectoMix.Introspector.introspect(MyApp.User, [])

      # Postgrex connection
      {:ok, conn} = Postgrex.start_link(...)
      {:ok, metadata} = SelectoMix.Introspector.introspect(
        {:postgrex, conn, "users"},
        []
      )

  ## Metadata Format

  All introspectors return a standardized metadata map:

      %{
        table_name: "users",
        schema: "public",
        fields: [:id, :name, :email, :inserted_at, :updated_at],
        field_types: %{
          id: :integer,
          name: :string,
          email: :string,
          inserted_at: :naive_datetime,
          updated_at: :naive_datetime
        },
        primary_key: :id,  # or [:id, :tenant_id] for composite
        associations: %{
          posts: %{
            type: :has_many,
            ...
          },
          profile: %{
            type: :has_one,
            ...
          }
        },
        columns: %{
          id: %{type: :integer, nullable: false, ...},
          name: %{type: :string, nullable: false, ...},
          ...
        },
        source: :ecto  # or :postgres, :mysql, etc.
      }
  """

  @type source ::
          module()
          | {:db, module(), term(), table_name :: String.t()}
          | {:db, module(), term(), table_name :: String.t(), keyword()}
          | {:postgrex, pid() | atom(), table_name :: String.t()}
          | {:postgrex, pid() | atom(), table_name :: String.t(), schema :: String.t()}

  @type metadata :: %{
          table_name: String.t(),
          schema: String.t(),
          fields: [atom()],
          field_types: %{atom() => atom()},
          primary_key: atom() | [atom()] | nil,
          associations: %{atom() => map()},
          columns: %{atom() => map()},
          source: :ecto | :postgres | atom()
        }

  @type opts :: keyword()

  @doc """
  Introspect a schema source and return standardized metadata.

  ## Parameters

  - `source` - Schema source (Ecto module, Postgrex connection tuple, etc.)
  - `opts` - Options passed to the specific introspector

  ## Returns

  - `{:ok, metadata}` - Standardized metadata map
  - `{:error, reason}` - Error details
  """
  @callback introspect(source, opts) :: {:ok, metadata} | {:error, term()}

  @doc """
  Convenience function that delegates to protocol implementation.
  """
  def introspect(source, opts \\ []) do
    case source do
      {:db, adapter, connection, table_name} ->
        introspect_db({:db, adapter, connection, table_name, []}, opts)

      {:db, adapter, connection, table_name, source_opts} ->
        introspect_db({:db, adapter, connection, table_name, source_opts}, opts)

      # Ecto schema module
      module when is_atom(module) ->
        SelectoMix.Introspector.Ecto.introspect(module, opts)

      # Postgrex connection tuple
      {:postgrex, _conn, _table_name} = tuple ->
        introspect_postgrex(tuple, opts)

      {:postgrex, _conn, _table_name, _schema} = tuple ->
        introspect_postgrex(tuple, opts)

      # Future: other database types
      {:mysql, _conn, _table_name} ->
        {:error, :mysql_not_yet_supported}

      {:sqlite, _conn, _table_name} ->
        {:error, :sqlite_not_yet_supported}

      other ->
        {:error, {:unsupported_source_type, other}}
    end
  end

  defp introspect_postgrex({:postgrex, conn, table_name}, opts) do
    SelectoMix.Introspector.Postgres.introspect_table(conn, table_name, opts)
  end

  defp introspect_postgrex({:postgrex, conn, table_name, schema}, opts) do
    opts = Keyword.put(opts, :schema, schema)
    SelectoMix.Introspector.Postgres.introspect_table(conn, table_name, opts)
  end

  defp introspect_db({:db, adapter, connection, table_name, source_opts}, opts) do
    with :ok <- ensure_adapter_ready(adapter),
         true <- function_exported?(adapter, :introspect_table, 3) do
      merged_opts = Keyword.merge(source_opts, opts)

      case adapter.introspect_table(connection, table_name, merged_opts) do
        {:ok, metadata} ->
          {:ok, normalize_db_metadata(metadata, adapter, table_name, merged_opts)}

        {:error, _reason} = error ->
          error
      end
    else
      false -> {:error, {:adapter_missing_introspection, adapter}}
      {:error, _reason} = error -> error
    end
  end

  defp ensure_adapter_ready(adapter) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        {:error, {:adapter_not_loaded, adapter}}

      function_exported?(adapter, :supports?, 1) and not adapter.supports?(:schema_introspection) ->
        {:error, {:adapter_missing_schema_introspection, adapter}}

      true ->
        :ok
    end
  end

  defp normalize_db_metadata(metadata, adapter, table_name, opts) do
    metadata
    |> Map.put_new(:table_name, table_name)
    |> Map.put_new(:schema, Keyword.get(opts, :schema, "public"))
    |> Map.put_new(:source, adapter_source_name(adapter))
    |> Map.put(:source_type, :db)
    |> Map.put(:adapter, adapter)
  end

  defp adapter_source_name(adapter) do
    if function_exported?(adapter, :name, 0) do
      adapter.name()
    else
      :db
    end
  end
end
