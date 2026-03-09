defmodule Mix.Tasks.Selecto.Gen.Api do
  @moduledoc """
  Generates a Selecto API endpoint and LiveView control panel.

  The generator creates:

  - a domain-aware API module that maps JSON payloads to SelectoUpdato operations
  - Selecto-powered read/query handlers
  - a Phoenix controller for the API endpoint
  - a LiveView control panel for editing configuration and sending requests

  ## Usage

      mix selecto.gen.api orders --domain MyApp.OrdersDomain

  ## Options

    * `--domain` - Domain module used by generated API module (default: inferred)
    * `--schema` - Ecto schema module used for write operations (default: inferred)
    * `--repo` - Repo module used for execution (default: `MyApp.Repo`)
    * `--api-path` - Route path used in controller docs (default: `/api/v1/updato/<name>`)
    * `--panel-path` - Route path used for the control panel (default: `/updato/<name>/control`)
    * `--panel-in-prod` - Include control panel route in production snippets (default: false)
    * `--force` - Overwrite generated files

  The task prints route snippets to add into your `router.ex`.
  """

  use Mix.Task

  import Mix.Generator

  @shortdoc "Generates Selecto API + control panel"

  @switches [
    domain: :string,
    schema: :string,
    repo: :string,
    api_path: :string,
    panel_path: :string,
    panel_in_prod: :boolean,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    case invalid do
      [] -> :ok
      _ -> Mix.raise("Unknown options: #{inspect(invalid)}")
    end

    name = parse_name!(positional)
    app = Mix.Project.config()[:app] |> to_string()
    app_module = Macro.camelize(app)
    web_module = app_module <> "Web"
    name_module = name |> Macro.camelize() |> singularize()
    name_snake = Macro.underscore(name)

    config =
      %{
        app: app,
        app_module: app_module,
        web_module: web_module,
        name_module: name_module,
        name_snake: name_snake,
        domain_module: opts[:domain] || infer_domain_module(app_module, name_module),
        schema_module: opts[:schema] || infer_schema_module(app_module, name_module),
        repo_module: opts[:repo] || app_module <> ".Repo",
        api_path: opts[:api_path] || "/api/v1/updato/#{name_snake}",
        panel_path: opts[:panel_path] || "/updato/#{name_snake}/control",
        panel_in_prod?: !!opts[:panel_in_prod],
        force?: !!opts[:force]
      }

    Mix.shell().info("Generating Selecto API files for #{name}...")

    generate_files(config)
    print_router_snippet(config)
    print_next_steps(config)
  end

  defp parse_name!([name | _]) do
    value = String.trim(name)

    if value == "" do
      Mix.raise("Expected NAME (for example: mix selecto.gen.api orders)")
    end

    value
  end

  defp parse_name!([]) do
    Mix.raise("Missing NAME. Example: mix selecto.gen.api orders")
  end

  defp singularize(value) do
    case String.ends_with?(value, "s") do
      true -> String.slice(value, 0, max(String.length(value) - 1, 1))
      false -> value
    end
  end

  defp infer_domain_module(app_module, name_module) do
    app_module <> "." <> name_module <> "Domain"
  end

  defp infer_schema_module(app_module, name_module) do
    app_module <> ".Hierarchy." <> name_module
  end

  defp generate_files(config) do
    maybe_create(config_path(config, :api_module), api_module_template(config), config.force?)
    maybe_create(config_path(config, :controller), controller_template(config), config.force?)

    maybe_create(
      config_path(config, :control_panel_live),
      control_panel_template(config),
      config.force?
    )
  end

  defp maybe_create(path, content, true), do: create_file(path, content, force: true)
  defp maybe_create(path, content, false), do: create_file(path, content)

  defp config_path(config, :api_module) do
    "lib/#{config.app}/updato_api/#{config.name_snake}_api.ex"
  end

  defp config_path(config, :controller) do
    "lib/#{config.app}_web/controllers/#{config.name_snake}_api_controller.ex"
  end

  defp config_path(config, :control_panel_live) do
    "lib/#{config.app}_web/live/#{config.name_snake}_api_control_panel_live.ex"
  end

  defp api_module_template(config) do
    """
    defmodule #{config.app_module}.UpdatoApi.#{config.name_module}Api do
      @moduledoc \"\"\"
      Generated endpoint adapter for #{config.domain_module}.

      Expected write payload:

          %{
            "action" => "insert" | "update" | "upsert" | "delete",
            "attributes" => map(),
            "filters" => [ [field, value] | %{\"field\" => field, \"value\" => value} ],
            "confirm_bulk_delete" => boolean()
          }

      Expected read payload:

          %{
            "select" => ["id", "name"],
            "filters" => [["status", "active"]],
            "order_by" => [["inserted_at", "desc"]],
            "limit" => 50,
            "offset" => 0
          }
      \"\"\"

      alias Selecto
      alias SelectoUpdato

      @allowed_actions ["insert", "update", "upsert", "delete"]

      @default_config %{
        name: "#{config.name_snake}",
        api_path: "#{config.api_path}",
        panel_path: "#{config.panel_path}",
        domain_module: #{config.domain_module},
        schema_module: #{config.schema_module},
        repo: #{config.repo_module}
      }

      def default_config, do: @default_config

      def execute(params, config \\\\ @default_config) when is_map(params) do
        with :ok <- validate_write_params(params),
             {:ok, operation} <- build_operation(params, config),
             {:ok, result} <- SelectoUpdato.execute(operation, config.repo) do
          {:ok, %{result: result, action: Map.get(params, "action", "insert")}}
        end
      end

      def query(params, config \\\\ @default_config) when is_map(params) do
        requested_limit = Map.get(params, "limit")
        query_params = apply_execution_limit(params, requested_limit)

        with :ok <- validate_query_params(params),
             {:ok, selecto} <- build_query(query_params, config),
             {:ok, {rows, columns, aliases}} <- Selecto.execute(selecto) do
          {rows, page_meta} = paginate_rows(rows, requested_limit, Map.get(params, "offset", 0))

          {:ok, %{rows: rows, columns: columns, aliases: aliases, page: page_meta}}
        end
      end

      def get_by_id(id, config \\\\ @default_config, opts \\\\ []) do
        with :ok <- validate_id(id) do
        primary_key = primary_key(config)

        params = %{
          "filters" => [[to_string(primary_key), id]],
          "limit" => 1,
          "select" => Keyword.get(opts, :select)
        }

        with {:ok, %{rows: rows, aliases: aliases}} <- query(params, config) do
          case rows do
            [row | _] -> {:ok, %{row: row, aliases: aliases}}
            _ -> {:error, :not_found}
          end
        end
        end
      end

      defp build_operation(params, config) do
        action = params |> Map.get("action", "insert") |> normalize_action()
        attributes = normalize_attributes(Map.get(params, "attributes", %{}), config)
        filters = normalize_filters(Map.get(params, "filters", []))
        domain = domain_for_write(config)

        operation =
          domain
          |> SelectoUpdato.new()
          |> apply_filters(filters)
          |> apply_action(action, attributes, params)

        {:ok, operation}
      rescue
        error -> {:error, {:invalid_request, Exception.message(error)}}
      end

      defp build_query(params, config) do
        domain = config.domain_module.domain()

        selecto =
          domain
          |> Selecto.configure(config.repo)
          |> maybe_select(Map.get(params, "select"))
          |> apply_query_filters(normalize_filters(Map.get(params, "filters", [])))
          |> apply_order_by(normalize_order_by(Map.get(params, "order_by", [])), config)
          |> maybe_limit(Map.get(params, "limit"))
          |> maybe_offset(Map.get(params, "offset"))

        {:ok, selecto}
      rescue
        error -> {:error, {:invalid_query, Exception.message(error)}}
      end

      defp normalize_action(value) when is_binary(value), do: String.downcase(value)
      defp normalize_action(value) when is_atom(value), do: value |> Atom.to_string() |> String.downcase()
      defp normalize_action(_), do: "insert"

      defp validate_id(id) when id in [nil, ""], do: {:error, {:validation_error, "id is required"}}
      defp validate_id(_id), do: :ok

      defp validate_write_params(params) when is_map(params) do
        action = params |> Map.get("action", "insert") |> normalize_action()

        cond do
          action not in @allowed_actions ->
            {:error, {:validation_error, "action must be one of insert|update|upsert|delete"}}

          action in ["insert", "update", "upsert"] and not is_map(Map.get(params, "attributes", %{})) ->
            {:error, {:validation_error, "attributes must be a map for insert/update/upsert"}}

          action == "delete" and Map.has_key?(params, "confirm_bulk_delete") and
              not is_boolean(Map.get(params, "confirm_bulk_delete")) ->
            {:error, {:validation_error, "confirm_bulk_delete must be a boolean"}}

          Map.has_key?(params, "filters") and not is_list(Map.get(params, "filters")) ->
            {:error, {:validation_error, "filters must be a list"}}

          true ->
            :ok
        end
      end

      defp validate_query_params(params) when is_map(params) do
        cond do
          Map.has_key?(params, "filters") and not is_list(Map.get(params, "filters")) ->
            {:error, {:validation_error, "filters must be a list"}}

          Map.has_key?(params, "order_by") and not is_list(Map.get(params, "order_by")) ->
            {:error, {:validation_error, "order_by must be a list"}}

          Map.has_key?(params, "select") and not valid_select?(Map.get(params, "select")) ->
            {:error, {:validation_error, "select must be a string or list"}}

          Map.has_key?(params, "limit") and not valid_limit?(Map.get(params, "limit")) ->
            {:error, {:validation_error, "limit must be a positive integer"}}

          Map.has_key?(params, "offset") and not valid_offset?(Map.get(params, "offset")) ->
            {:error, {:validation_error, "offset must be a non-negative integer"}}

          true ->
            :ok
        end
      end

      defp valid_select?(value) when is_binary(value) or is_list(value), do: true
      defp valid_select?(_), do: false

      defp valid_limit?(value) when is_integer(value) and value > 0, do: true
      defp valid_limit?(_), do: false

      defp valid_offset?(value) when is_integer(value) and value >= 0, do: true
      defp valid_offset?(_), do: false

      defp apply_filters(operation, filters) do
        Enum.reduce(filters, operation, fn {field, value}, op ->
          SelectoUpdato.filter(op, {field, value})
        end)
      end

      defp apply_action(operation, "insert", attributes, _params),
        do: SelectoUpdato.insert(operation, attributes)

      defp apply_action(operation, "update", attributes, _params),
        do: SelectoUpdato.update(operation, attributes)

      defp apply_action(operation, "upsert", attributes, params) do
        operation = SelectoUpdato.upsert(operation, attributes)

        case Map.get(params, "conflict_target") do
          nil -> operation
          target -> SelectoUpdato.conflict_target(operation, target)
        end
      end

      defp apply_action(operation, "delete", _attributes, params) do
        operation = SelectoUpdato.delete(operation)

        if Map.get(params, "confirm_bulk_delete", false) do
          SelectoUpdato.confirm_bulk_delete(operation, true)
        else
          operation
        end
      end

      defp apply_action(operation, _action, attributes, _params),
        do: SelectoUpdato.insert(operation, attributes)

      defp apply_query_filters(selecto, filters) do
        Enum.reduce(filters, selecto, fn {field, value}, query ->
          Selecto.filter(query, {field, value})
        end)
      end

      defp apply_order_by(selecto, orders, config) do
        case orders do
          [] -> Selecto.order_by(selecto, {to_string(primary_key(config)), :asc})

          _ ->
            Enum.reduce(orders, selecto, fn {field, dir}, query ->
              Selecto.order_by(query, {field, normalize_order_dir(dir)})
            end)
        end
      end

      defp maybe_select(selecto, nil), do: selecto
      defp maybe_select(selecto, []), do: selecto
      defp maybe_select(selecto, fields) when is_list(fields), do: Selecto.select(selecto, fields)
      defp maybe_select(selecto, field) when is_binary(field), do: Selecto.select(selecto, [field])
      defp maybe_select(selecto, _), do: selecto

      defp maybe_limit(selecto, value) when is_integer(value) and value > 0,
        do: Selecto.limit(selecto, value)

      defp maybe_limit(selecto, _), do: selecto

      defp maybe_offset(selecto, value) when is_integer(value) and value >= 0,
        do: Selecto.offset(selecto, value)

      defp maybe_offset(selecto, _), do: selecto

      defp normalize_order_by(orders) when is_list(orders) do
        orders
        |> Enum.map(&normalize_order_spec/1)
        |> Enum.reject(&is_nil/1)
      end

      defp normalize_order_by(_), do: []

      defp normalize_order_spec([field, dir]), do: {to_string(field), dir}
      defp normalize_order_spec({field, dir}), do: {to_string(field), dir}

      defp normalize_order_spec(%{"field" => field, "dir" => dir}),
        do: {to_string(field), dir}

      defp normalize_order_spec(_), do: nil

      defp normalize_order_dir(dir) when dir in [:asc, "asc", :ASC, "ASC"], do: :asc
      defp normalize_order_dir(_), do: :desc

      defp primary_key(config) do
        domain = config.domain_module.domain()

        source =
          case domain do
            %{source: source_map} when is_map(source_map) -> source_map
            _ -> %{}
          end

        source[:primary_key] || source["primary_key"] || :id
      end

      defp normalize_filters(filters) when is_list(filters) do
        filters
        |> Enum.map(&normalize_filter/1)
        |> Enum.reject(&is_nil/1)
      end

      defp normalize_filters(_), do: []

      defp normalize_filter([field, value]), do: {to_string(field), value}
      defp normalize_filter({field, value}), do: {to_string(field), value}

      defp normalize_filter(%{"field" => field, "value" => value}) do
        {to_string(field), value}
      end

      defp normalize_filter(_), do: nil

      defp apply_execution_limit(params, requested_limit)

      defp apply_execution_limit(params, requested_limit)
           when is_integer(requested_limit) and requested_limit > 0 do
        Map.put(params, "limit", requested_limit + 1)
      end

      defp apply_execution_limit(params, _), do: params

      defp paginate_rows(rows, requested_limit, offset)

      defp paginate_rows(rows, requested_limit, offset)
           when is_integer(requested_limit) and requested_limit > 0 do
        has_more = length(rows) > requested_limit
        page_rows = if has_more, do: Enum.take(rows, requested_limit), else: rows

        {page_rows,
         %{
           count: length(page_rows),
           limit: requested_limit,
           offset: normalize_offset(offset),
           has_more: has_more
         }}
      end

      defp paginate_rows(rows, _requested_limit, offset) do
        {rows,
         %{
           count: length(rows),
           limit: nil,
           offset: normalize_offset(offset),
           has_more: false
         }}
      end

      defp normalize_offset(value) when is_integer(value) and value >= 0, do: value
      defp normalize_offset(_), do: 0

      defp normalize_attributes(attrs, config) when is_map(attrs) do
        allowed_fields =
          config.domain_module.domain()
          |> Map.get(:source, %{})
          |> Map.get(:columns, %{})
          |> Map.keys()
          |> MapSet.new()

        Enum.reduce(attrs, %{}, fn {key, value}, acc ->
          key_string = to_string(key)
          key_atom = to_existing_atom_safe(key_string)

          if key_atom && MapSet.member?(allowed_fields, key_atom) do
            Map.put(acc, key_atom, value)
          else
            acc
          end
        end)
      end

      defp normalize_attributes(_, _), do: %{}

      defp to_existing_atom_safe(value) when is_binary(value) do
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError -> nil
        end
      end

      defp domain_for_write(config) do
        domain = config.domain_module.domain()
        source_map = Map.get(domain, :source, %{})
        columns = if is_map(source_map), do: Map.get(source_map, :columns, %{}), else: %{}

        domain
        |> Map.put(:source, config.schema_module)
        |> Map.put_new(:columns, columns)
      end
    end
    """
  end

  defp controller_template(config) do
    """
    defmodule #{config.web_module}.#{config.name_module}ApiController do
      use #{config.web_module}, :controller

      plug :reject_large_payload when action in [:create, :query]
      plug :throttle_requests when action in [:create, :query, :show]

      alias #{config.app_module}.UpdatoApi.#{config.name_module}Api

      def create(conn, params) do
        with :ok <- authorize_api_request(conn, :create),
             {:ok, payload} <- #{config.name_module}Api.execute(params) do
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
        json(conn, success_envelope(conn, %{config: #{config.name_module}Api.default_config()}))
      end

      defp authorize_api_request(_conn, _action), do: :ok

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
      defp status_for_reason({:invalid_request, _}), do: :bad_request
      defp status_for_reason({:invalid_query, _}), do: :bad_request
      defp status_for_reason({:payload_too_large, _}), do: :payload_too_large
      defp status_for_reason({:rate_limited, _}), do: :too_many_requests
      defp status_for_reason(:not_found), do: :not_found
      defp status_for_reason(_), do: :unprocessable_entity
    end
    """
  end

  defp control_panel_template(config) do
    """
    defmodule #{config.web_module}.#{config.name_module}ApiControlPanelLive do
      use #{config.web_module}, :live_view

      alias #{config.app_module}.UpdatoApi.#{config.name_module}Api

      @impl true
      def mount(_params, _session, socket) do
        request_json =
          Jason.encode!(%{
            action: "insert",
            attributes: %{},
            filters: []
          }, pretty: true)

        query_json =
          Jason.encode!(%{
            select: [],
            filters: [],
            order_by: [],
            limit: 50,
            offset: 0
          }, pretty: true)

        {:ok,
         assign(socket,
           endpoint_config: #{config.name_module}Api.default_config(),
           request_json: request_json,
           query_json: query_json,
           last_result: nil,
           error: nil
         )}
      end

      @impl true
      def handle_event("request_changed", %{"request_json" => request_json}, socket) do
        {:noreply, assign(socket, request_json: request_json)}
      end

      def handle_event("query_changed", %{"query_json" => query_json}, socket) do
        {:noreply, assign(socket, query_json: query_json)}
      end

      def handle_event("send_request", _params, socket) do
        with {:ok, payload} <- Jason.decode(socket.assigns.request_json),
             {:ok, result} <- #{config.name_module}Api.execute(payload) do
          {:noreply, assign(socket, last_result: Jason.encode!(result, pretty: true), error: nil)}
        else
          {:error, reason} ->
            {:noreply,
             assign(socket,
               error: format_reason(reason),
               last_result: nil
             )}
        end
      end

      def handle_event("send_query", _params, socket) do
        with {:ok, payload} <- Jason.decode(socket.assigns.query_json),
             {:ok, result} <- #{config.name_module}Api.query(payload) do
          {:noreply, assign(socket, last_result: Jason.encode!(result, pretty: true), error: nil)}
        else
          {:error, reason} ->
            {:noreply, assign(socket, error: format_reason(reason), last_result: nil)}
        end
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <div class="min-h-screen bg-gradient-to-b from-amber-50 via-white to-sky-50 py-10">
          <div class="mx-auto max-w-6xl px-4 sm:px-8">
            <div class="rounded-3xl border border-slate-200 bg-white/85 p-8 shadow-xl backdrop-blur">
              <h1 class="text-3xl font-semibold tracking-tight text-slate-900">Updato API Control Panel</h1>
              <p class="mt-2 text-sm text-slate-600">
                Endpoint: <code class="rounded bg-slate-100 px-2 py-1 text-xs">{@endpoint_config.api_path}</code>
              </p>

              <section class="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                <h2 class="text-base font-medium text-slate-900">Endpoint Configuration</h2>
                <dl class="mt-4 space-y-2 text-sm text-slate-700">
                  <div><dt class="font-medium">Domain Module</dt><dd>{inspect(@endpoint_config.domain_module)}</dd></div>
                  <div><dt class="font-medium">Repo</dt><dd>{inspect(@endpoint_config.repo)}</dd></div>
                  <div><dt class="font-medium">Panel Path</dt><dd>{@endpoint_config.panel_path}</dd></div>
                </dl>
              </section>

              <section class="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                <h2 class="text-base font-medium text-slate-900">Write Request JSON</h2>
                <form phx-change="request_changed">
                  <textarea
                    name="request_json"
                    class="mt-3 h-80 w-full rounded-xl border border-slate-300 bg-slate-950 p-4 font-mono text-sm text-emerald-100 focus:border-emerald-500 focus:outline-none"
                  ><%= @request_json %></textarea>
                </form>

                <div class="mt-4 flex items-center gap-3">
                  <button
                    phx-click="send_request"
                    class="inline-flex items-center rounded-xl bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700"
                  >
                    Send Write Request
                  </button>

                  <%= if @error do %>
                    <span class="text-sm font-medium text-rose-600">{@error}</span>
                  <% end %>
                </div>
              </section>

              <section class="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                <h2 class="text-base font-medium text-slate-900">Read Query JSON</h2>
                <form phx-change="query_changed">
                  <textarea
                    name="query_json"
                    class="mt-3 h-64 w-full rounded-xl border border-slate-300 bg-slate-900 p-4 font-mono text-sm text-sky-100 focus:border-sky-500 focus:outline-none"
                  ><%= @query_json %></textarea>
                </form>

                <div class="mt-4">
                  <button
                    phx-click="send_query"
                    class="inline-flex items-center rounded-xl bg-cyan-600 px-4 py-2 text-sm font-semibold text-white hover:bg-cyan-700"
                  >
                    Run Read Query
                  </button>
                </div>
              </section>

              <%= if @last_result do %>
                <section class="mt-6 rounded-2xl border border-slate-200 bg-slate-950 p-5">
                  <h2 class="text-base font-medium text-slate-100">Response</h2>
                  <pre class="mt-3 overflow-x-auto whitespace-pre-wrap text-sm text-emerald-100">{@last_result}</pre>
                </section>
              <% end %>
            </div>
          </div>
        </div>
        \"\"\"
      end

      defp format_reason(reason) when is_binary(reason), do: reason
      defp format_reason(reason), do: inspect(reason)
    end
    """
  end

  defp print_router_snippet(config) do
    Mix.shell().info("""

    Add these routes to your router:

        scope "/api", #{config.web_module} do
          pipe_through :api
          post "#{config.api_path |> String.replace_prefix("/api", "")}", #{config.name_module}ApiController, :create
          post "#{config.api_path |> String.replace_prefix("/api", "")}/query", #{config.name_module}ApiController, :query
          get "#{config.api_path |> String.replace_prefix("/api", "")}/:id", #{config.name_module}ApiController, :show
          get "#{config.api_path |> String.replace_prefix("/api", "")}/config", #{config.name_module}ApiController, :config
        end

    #{panel_route_snippet(config)}
    """)
  end

  defp panel_route_snippet(config) do
    if config.panel_in_prod? do
      """
          scope "/", #{config.web_module} do
            pipe_through :browser
            live "#{config.panel_path}", #{config.name_module}ApiControlPanelLive
          end
      """
    else
      """
          if Mix.env() != :prod do
            scope "/", #{config.web_module} do
              pipe_through :browser
              live "#{config.panel_path}", #{config.name_module}ApiControlPanelLive
            end
          end
      """
    end
  end

  defp print_next_steps(config) do
    Mix.shell().info("""

    Generated files:
      - #{config_path(config, :api_module)}
      - #{config_path(config, :controller)}
      - #{config_path(config, :control_panel_live)}

    Next steps:
      1. Wire routes in your router using the snippet above.
      2. Start your server and open #{config.panel_path}.
    """)
  end
end
