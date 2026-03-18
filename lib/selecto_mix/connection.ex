defmodule SelectoMix.Connection do
  @moduledoc """
  Adapter-aware connection helpers for Selecto mix tasks.
  """

  @doc """
  Parse a database URL into generic connection options.
  """
  def parse_database_url(url) when is_binary(url) do
    uri = URI.parse(url)

    {username, password} =
      case uri.userinfo do
        nil ->
          {nil, nil}

        info ->
          case String.split(info, ":", parts: 2) do
            [user] -> {user, nil}
            [user, pass] -> {user, pass}
          end
      end

    database =
      case uri.path do
        nil -> nil
        "/" -> nil
        "/" <> db_name -> db_name
      end

    [
      hostname: uri.host || "localhost",
      port: uri.port,
      database: database,
      username: username,
      password: password
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  Connect through the selected adapter.
  """
  def connect(adapter, opts) when is_atom(adapter) do
    with :ok <- ensure_adapter_loaded(adapter),
         true <- function_exported?(adapter, :connect, 1) do
      adapter.connect(opts)
    else
      false -> {:error, {:adapter_missing_connect, adapter}}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Connect, run a function, then best-effort disconnect.
  """
  def with_connection(adapter, opts, fun) when is_function(fun, 1) do
    case connect(adapter, opts) do
      {:ok, conn} ->
        try do
          {:ok, fun.(conn)}
        after
          disconnect(conn, opts)
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Best-effort disconnect for short-lived task connections.
  """
  def disconnect(conn, original_opts \\ nil)

  def disconnect(conn, _original_opts) when is_pid(conn) do
    GenServer.stop(conn, :normal)
  catch
    :exit, _ -> :ok
  end

  def disconnect(_conn, _original_opts), do: :ok

  defp ensure_adapter_loaded(adapter) do
    if Code.ensure_loaded?(adapter) do
      :ok
    else
      {:error, {:adapter_not_loaded, adapter}}
    end
  end
end
