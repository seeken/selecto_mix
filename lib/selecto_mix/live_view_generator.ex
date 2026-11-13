defmodule SelectoMix.LiveViewGenerator do
  @moduledoc """
  Generates LiveView file paths and templates for Selecto domains.
  """

  def live_view_file_path(app_name, source) do
    app_name = app_name |> to_string() |> Macro.underscore()
    schema_name = source_live_name(source) |> Macro.underscore()
    "lib/#{app_name}_web/#{schema_name}_live.ex"
  end

  def live_view_html_file_path(app_name, source) do
    app_name = app_name |> to_string() |> Macro.underscore()
    schema_name = source_live_name(source) |> Macro.underscore()
    "lib/#{app_name}_web/#{schema_name}_live.html.heex"
  end

  def render_live_view_template(app_name, source, domain_module, opts) do
    app_name = app_name |> to_string() |> Macro.camelize()
    schema_name = source_live_name(source)
    web_module = "#{app_name}Web"
    connection_ref = live_view_connection_ref(source, app_name, opts)
    adapter_ref = live_view_adapter_ref(source, app_name, opts)

    """
    defmodule #{web_module}.#{schema_name}Live do
      @moduledoc \"\"\"
      LiveView for #{schema_name} using the SelectoViews Explorer.

      ## Quick Setup

      1. Serve the packaged stylesheet from your endpoint, before the router:
         ```elixir
         plug Plug.Static,
           at: "/selecto-views",
           from: :selecto_views,
           gzip: false,
           only: ~w(selecto-views.css)
         ```

      2. Import the hooks in `assets/js/app.js`:
         ```javascript
         import {hooks as selectoViewsHooks} from "phoenix-colocated/selecto_views"
         // Add to your liveSocket hooks: { ...selectoViewsHooks }
         ```

      3. Run `mix assets.build`

      `mix selecto.views.integrate` performs step 2 for you.

      The Explorer provides the Detail, Aggregate, and Graph views. This
      LiveView only supplies a configured Selecto value and the request params,
      so reloads and shared links restore the query.
      \"\"\"

      use #{web_module}, :live_view

      @impl true
      def mount(params, _session, socket) do
        domain_ref = #{domain_module}.domain_ref()

        selecto =
          Selecto.configure_registered(domain_ref, #{connection_ref}, adapter: #{adapter_ref})

        {:ok,
         socket
         |> assign(:page_title, "#{schema_name}")
         |> assign(:params, params)
         |> assign(:selecto, selecto)}
      end
    end
    """
  end

  def render_live_view_html_template(source, _opts) do
    schema_name = source_live_name(source)
    explorer_id = "#{schema_name |> Macro.underscore() |> String.replace("_", "-")}-explorer"

    """
    <Layouts.app flash={@flash}>
      <.live_component
        module={SelectoViews.Explorer}
        id="#{explorer_id}"
        selecto={@selecto}
        params={@params}
        options={[
          title: "#{schema_name}",
          default_limit: 25,
          max_limit: 100,
          show_sql: false,
          query_params: true,
          stylesheet_href: "/selecto-views/selecto-views.css"
        ]}
      />
    </Layouts.app>
    """
  end

  def route_suggestion(source, opts) do
    schema_name = source_live_name(source)
    schema_underscore = Macro.underscore(schema_name)

    route_path =
      (opts[:path] || schema_underscore)
      |> to_string()
      |> String.trim("/")

    """

    Add this LiveView route inside your app's aliased web scope:
      live "/#{route_path}", #{schema_name}Live, :index

    Serve the SelectoViews stylesheet from your endpoint, before the router:
      plug Plug.Static,
        at: "/selecto-views",
        from: :selecto_views,
        gzip: false,
        only: ~w(selecto-views.css)
    """
  end

  @doc """
  Returns the named runtime connection expected by a DB-backed generated
  LiveView.

  `--database-url` and the other connection flags are used only by the
  generator while it introspects the database. The host application must
  supervise its runtime connection under this name.
  """
  def runtime_connection_name(app_name, opts) do
    opts[:connection_name] ||
      "#{app_name |> to_string() |> Macro.camelize()}.Database"
  end

  @doc """
  Renders setup guidance for the runtime connection used by a DB-backed
  generated LiveView.
  """
  def runtime_connection_guidance(app_name, opts) do
    connection_name = runtime_connection_name(app_name, opts)
    otp_app = app_name |> to_string() |> Macro.underscore()
    adapter_guidance = adapter_runtime_guidance(opts[:adapter], connection_name, otp_app)

    """

    DB-backed LiveView runtime connection:
      The generated LiveView uses #{connection_name}.
      Generation-time database flags are not embedded into application code.
      Supervise your adapter connection under that name before opening the LiveView.

    #{adapter_guidance}

      Use --connection-name MyApp.CustomDatabase to target an existing named
      connection instead.
    """
  end

  defp adapter_runtime_guidance(adapter, connection_name, otp_app)
       when adapter in ["postgres", "postgresql"] do
    """
      PostgreSQL example for your application children:

        database_options = Application.fetch_env!(:#{otp_app}, :database)
        children = [
          {Postgrex, Keyword.put(database_options, :name, #{connection_name})}
        ]

      Configure the runtime options separately, for example:

        config :#{otp_app}, :database,
          hostname: "localhost",
          database: "#{otp_app}_dev"
    """
  end

  defp adapter_runtime_guidance(adapter, connection_name, _otp_app) do
    """
      Configure and supervise your #{adapter || "database"} adapter's runtime
      connection as #{connection_name}. Consult the adapter package for its
      child specification and connection options.
    """
  end

  def source_live_name({:db, _adapter, _conn, table, _opts}) do
    table
    |> SelectoMix.Inflect.singularize()
    |> Macro.camelize()
  end

  def source_live_name({:db, _adapter, _conn, table}) do
    table
    |> SelectoMix.Inflect.singularize()
    |> Macro.camelize()
  end

  def source_live_name(source) when is_atom(source) do
    source |> to_string() |> String.split(".") |> List.last()
  end

  def source_live_name(source) when is_binary(source) do
    source
    |> SelectoMix.Inflect.singularize()
    |> Macro.camelize()
  end

  def source_live_name(source) do
    source |> to_string() |> SelectoMix.Inflect.singularize() |> Macro.camelize()
  end

  defp live_view_connection_ref(source, app_name, opts) do
    case source do
      {:db, _adapter, _conn, _table, _source_opts} ->
        runtime_connection_name(app_name, opts)

      {:db, _adapter, _conn, _table} ->
        runtime_connection_name(app_name, opts)

      _ ->
        "#{app_name}.Repo"
    end
  end

  defp live_view_adapter_ref({:db, adapter, _conn, _table, _source_opts}, _app_name, _opts),
    do: inspect(adapter)

  defp live_view_adapter_ref({:db, adapter, _conn, _table}, _app_name, _opts),
    do: inspect(adapter)

  defp live_view_adapter_ref(_source, app_name, opts) do
    case opts[:adapter] do
      adapter when is_atom(adapter) and not is_nil(adapter) ->
        inspect(adapter)

      adapter when is_binary(adapter) ->
        case SelectoMix.AdapterResolver.resolve(adapter) do
          {:ok, module} -> inspect(module)
          {:error, _reason} -> configured_adapter_ref(app_name)
        end

      _other ->
        configured_adapter_ref(app_name)
    end
  end

  defp configured_adapter_ref(app_name) do
    otp_app = app_name |> to_string() |> Macro.underscore()
    "Application.fetch_env!(:#{otp_app}, :selecto_adapter)"
  end
end
