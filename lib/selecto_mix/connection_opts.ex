defmodule SelectoMix.ConnectionOpts do
  @moduledoc """
  Shared helper for parsing adapter-backed connection flags.
  """

  @doc """
  Parse connection-related options from a parsed args map.
  """
  def from_parsed_args(parsed_args) do
    cond do
      url = parsed_args[:database_url] ->
        SelectoMix.Connection.parse_database_url(url)

      parsed_args[:database] ->
        [database: parsed_args[:database]]
        |> maybe_put(:hostname, parsed_args[:host])
        |> maybe_put(:port, parsed_args[:port])
        |> maybe_put(:username, parsed_args[:username])
        |> maybe_put(:password, parsed_args[:password])
        |> Keyword.put_new(:hostname, "localhost")

      url = System.get_env("DATABASE_URL") ->
        SelectoMix.Connection.parse_database_url(url)

      true ->
        []
    end
  end

  @doc """
  Returns the Igniter option schema for connection flags.
  """
  def connection_schema do
    [
      adapter: :string,
      table: :string,
      view: :string,
      materialized_view: :string,
      primary_key: :string,
      include_views: :boolean,
      database_url: :string,
      host: :string,
      port: :integer,
      database: :string,
      username: :string,
      password: :string,
      connection_name: :string,
      schema: :string,
      expand: :boolean
    ]
  end

  @doc """
  Returns Igniter aliases for connection flags.
  """
  def connection_aliases do
    [
      A: :adapter,
      t: :table,
      v: :view,
      u: :database_url,
      h: :host,
      P: :port,
      D: :database,
      U: :username,
      W: :password
    ]
  end

  @doc """
  System tables to exclude from auto-discovery.
  """
  def system_tables do
    [
      "schema_migrations",
      "ar_internal_metadata",
      "pg_stat_statements",
      "spatial_ref_sys"
    ]
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
