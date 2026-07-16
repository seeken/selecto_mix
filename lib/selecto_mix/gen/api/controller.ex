defmodule SelectoMix.Gen.Api.Controller do
  @moduledoc false

  def render(config) do
    """
    defmodule #{config.web_module}.#{config.name_module}ApiController do
      use #{config.web_module}, :controller

      plug :reject_large_payload when action in [:create, :query, :preview_action, :apply_action]
      plug :throttle_requests when action in [:create, :query, :show, :preview_action, :apply_action]

      alias #{config.app_module}.UpdatoApi.#{config.name_module}Api

      def create(conn, params) do
        with :ok <- authorize_api_request(conn, :create),
             {:ok, payload} <- #{config.name_module}Api.execute(params, api_config(conn)) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
          end
      end

      def preview_action(conn, %{"action" => action} = params) do
        with :ok <- authorize_api_request(conn, {:preview_action, action}),
             {:ok, payload} <- #{config.name_module}Api.preview_domain_action(action, params, api_config(conn)) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      def apply_action(conn, %{"action" => action} = params) do
        with :ok <- authorize_api_request(conn, {:apply_action, action}),
             {:ok, payload} <- #{config.name_module}Api.apply_domain_action(action, params, api_config(conn)) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      def query(conn, params) do
        with :ok <- authorize_api_request(conn, :query),
             {:ok, payload} <- #{config.name_module}Api.query(params) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      def show(conn, %{"id" => id} = params) do
        opts = [select: Map.get(params, "select")]

        with :ok <- authorize_api_request(conn, :show),
             {:ok, payload} <-
               #{config.name_module}Api.get_by_id(
                 id,
                 #{config.name_module}Api.default_config(),
                 opts
               ) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(error_envelope(conn, :not_found))

          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      def config(conn, _params) do
        with :ok <- authorize_api_request(conn, :config),
             {:ok, write_contract, _diagnostics} <- #{config.name_module}Api.write_contract() do
          json(
            conn,
            success_envelope(conn, %{
              config: #{config.name_module}Api.default_config(),
              write_contract: write_contract,
              capabilities: #{config.name_module}Api.write_contract_summary()
            })
          )
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      defp authorize_api_request(_conn, _action), do: :ok

      defp api_config(_conn) do
        #{config.name_module}Api.default_config()
      end

      defp reject_large_payload(conn, _opts) do
        max_bytes = Application.get_env(:#{config.app}, :selecto_api_max_request_bytes, 200_000)

        case List.first(get_req_header(conn, "content-length")) do
          nil ->
            conn

          content_length ->
            case Integer.parse(content_length) do
              {size, _} when size > max_bytes ->
                conn
                |> put_status(:payload_too_large)
                |> json(error_envelope(conn, {:payload_too_large, max_bytes}))
                |> halt()

              _ ->
                conn
            end
        end
      end

      defp throttle_requests(conn, _opts) do
        case Application.get_env(:#{config.app}, :selecto_api_throttler) do
          nil ->
            conn

          throttler when is_atom(throttler) ->
            case throttler.allow?(conn) do
              :ok ->
                conn

              {:error, reason} ->
                conn
                |> put_status(:too_many_requests)
                |> json(error_envelope(conn, {:rate_limited, reason}))
                |> halt()
            end
        end
      end

      defp success_envelope(conn, payload) do
        %{ok: true, data: normalize_for_json(payload), meta: %{request_id: request_id(conn)}}
      end

      defp normalize_for_json(value) when is_list(value) do
        Enum.map(value, &normalize_for_json/1)
      end

      defp normalize_for_json(%_{} = value) do
        case Jason.encode(value) do
          {:ok, _} ->
            value

          {:error, %Protocol.UndefinedError{}} ->
            value
            |> Map.from_struct()
            |> Map.delete(:__meta__)
            |> normalize_for_json()

          {:error, _} ->
            value
            |> Map.from_struct()
            |> Map.delete(:__meta__)
            |> normalize_for_json()
        end
      end

      defp normalize_for_json(value) when is_map(value) do
        Map.new(value, fn {k, v} -> {k, normalize_for_json(v)} end)
      end

      defp normalize_for_json(value), do: value

      defp error_envelope(conn, {:validation_error, message}) do
        %{
          ok: false,
          error: %{code: "validation_error", message: message, details: nil},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:validation_error, message, details}) do
        %{
          ok: false,
          error: %{code: "validation_error", message: message, details: details},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:invalid_request, message}) do
        %{
          ok: false,
          error: %{code: "invalid_request", message: message, details: nil},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:invalid_query, message}) do
        %{
          ok: false,
          error: %{code: "invalid_query", message: message, details: nil},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, :not_found) do
        %{
          ok: false,
          error: %{code: "not_found", message: "not found", details: nil},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:payload_too_large, max_bytes}) do
        %{
          ok: false,
          error: %{code: "payload_too_large", message: "payload exceeds configured size limit", details: %{max_bytes: max_bytes}},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:rate_limited, reason}) do
        %{
          ok: false,
          error: %{code: "rate_limited", message: "rate limit exceeded", details: inspect(reason)},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, reason) do
        %{
          ok: false,
          error: %{code: "execution_error", message: "request failed", details: inspect(reason)},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp request_id(conn) do
        conn.assigns[:request_id] || List.first(get_resp_header(conn, "x-request-id"))
      end

      defp status_for_reason({:validation_error, _}), do: :bad_request
      defp status_for_reason({:validation_error, _, _}), do: :bad_request
      defp status_for_reason({:invalid_request, _}), do: :bad_request
      defp status_for_reason({:invalid_query, _}), do: :bad_request
      defp status_for_reason({:payload_too_large, _}), do: :payload_too_large
      defp status_for_reason({:rate_limited, _}), do: :too_many_requests
      defp status_for_reason(:not_found), do: :not_found
      defp status_for_reason(_), do: :unprocessable_entity
    end
    """
  end
end
