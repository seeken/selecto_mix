defmodule SelectoMix.LiveViewGenerator do
  @moduledoc """
  Generates LiveView file paths and templates for Selecto domains.
  """

  def live_view_file_path(app_name, source) do
    app_name = app_name |> to_string() |> Macro.underscore()
    schema_name = source_live_name(source) |> Macro.underscore()
    "lib/#{app_name}_web/live/#{schema_name}_live.ex"
  end

  def live_view_html_file_path(app_name, source) do
    app_name = app_name |> to_string() |> Macro.underscore()
    schema_name = source_live_name(source) |> Macro.underscore()
    "lib/#{app_name}_web/live/#{schema_name}_live.html.heex"
  end

  def render_live_view_template(app_name, source, domain_module, opts, components_location) do
    app_name = app_name |> to_string() |> Macro.camelize()
    schema_name = source_live_name(source)
    schema_underscore = Macro.underscore(schema_name)
    web_module = "#{app_name}Web"
    connection_ref = live_view_connection_ref(source, app_name, opts)

    route_path = opts[:path] || "/#{schema_underscore}"
    route_path = if String.starts_with?(route_path, "/"), do: route_path, else: "/#{route_path}"

    saved_views_code =
      if opts[:saved_views] do
        """
          saved_views = #{domain_module}.get_view_names(path)

          socket =
            assign(socket,
              show_view_configurator: false,
              views: views,
              my_path: path,
              saved_view_module: #{domain_module},
              saved_view_context: path,
              path: path,
              available_saved_views: saved_views
            )
        """
      else
        """
          socket =
            assign(socket,
              show_view_configurator: false,
              views: views,
              my_path: path
            )
        """
      end

    """
    defmodule #{web_module}.#{schema_name}Live do
      @moduledoc \"\"\"
      LiveView for #{schema_name} using SelectoComponents.

      ## Quick Setup (Phoenix 1.7+)

      1. Import hooks in `assets/js/app.js`:
         ```javascript
         import {hooks as selectoHooks} from "phoenix-colocated/selecto_components"
         // Add to your liveSocket hooks: { ...selectoHooks }
         ```

      2. Add to Tailwind in `assets/css/app.css`:
         ```css
         @source "../../#{components_location}/selecto_components/lib/**/*.{ex,heex}";
         ```

      3. Run `mix assets.build`

      That's it! The drag-and-drop query builder and charts will work automatically.
      \"\"\"

      use #{web_module}, :live_view
      use SelectoComponents.Form

      @impl true
      def mount(_params, _session, socket) do
        domain = #{domain_module}.domain()
        path = "#{route_path}"

        selecto = Selecto.configure(domain, #{connection_ref})

        views = [
          {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate View", %{drill_down: :detail}},
          {:detail, SelectoComponents.Views.Detail, "Detail View", %{}},
          {:graph, SelectoComponents.Views.Graph, "Graph View", %{}}
        ]

        state = get_initial_state(views, selecto)

    #{saved_views_code}

        {:ok, assign(socket, state), layout: {#{web_module}.Layouts, :root}}
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <div class="container mx-auto px-4 py-8">
          #{render_inline_header(schema_name, opts)}

          <.live_component
            module={SelectoComponents.Form}
            id="#{schema_underscore}-form"
            #{if opts[:enable_modal], do: "enable_modal_detail={true}", else: ""}
            {assigns}
          />

          <.live_component
            module={SelectoComponents.Results}
            id="#{schema_underscore}-results"
            {assigns}
          />
        </div>
        \"\"\"
      end

      @impl true
      def handle_event("toggle_show_view_configurator", _params, socket) do
        {:noreply, assign(socket, show_view_configurator: !socket.assigns.show_view_configurator)}
      end
    end
    """
  end

  def render_live_view_html_template(source, opts) do
    schema_name = source_live_name(source)

    saved_views_dropdown =
      if opts[:saved_views] do
        ~S"""
        <details :if={@available_saved_views != []} id="saved-views-dropdown" class="dropdown">
          <summary class="btn btn-sm btn-outline gap-1">Saved Views</summary>
          <ul class="menu dropdown-content z-[1] mt-2 w-56 rounded-box border border-base-300 bg-base-100 p-2 shadow">
            <li :for={v <- @available_saved_views}>
              <.link href={"#{@path}?saved_view=#{v}"}>{v}</.link>
            </li>
          </ul>
        </details>
        """
      else
        ""
      end

    saved_view_assigns =
      if opts[:saved_views] do
        """
            saved_view_module={@saved_view_module}
            saved_view_context={@saved_view_context}
        """
      else
        ""
      end

    """
    <div class="flex items-center gap-4 mb-6">
      <h1 class="text-3xl font-bold">#{schema_name} Data View</h1>
      #{saved_views_dropdown}
    </div>

    <div :if={@show_view_configurator}>
      <.live_component
        module={SelectoComponents.Form}
        id="config"
        view_config={@view_config}
        selecto={@selecto}
        executed={@executed}
        applied_view={nil}
        active_tab={@active_tab}
        views={@views}
        #{if opts[:enable_modal], do: "enable_modal_detail={true}", else: ""}#{saved_view_assigns}
      />
    </div>

    <.live_component
      module={SelectoComponents.Results}
      selecto={@selecto}
      query_results={@query_results}
      applied_view={@applied_view}
      executed={@executed}
      views={@views}
      view_meta={@view_meta}
      id="results"
    />
    """
  end

  def route_suggestion(source, opts) do
    schema_name = source_live_name(source)
    schema_underscore = Macro.underscore(schema_name)
    route_path = opts[:path] || schema_underscore
    route_path = String.replace_prefix(route_path, "/", "")

    """

    Add this route to your router.ex:
      live "/#{route_path}", #{schema_name}Live, :index
    """
  end

  def source_live_name({:db, _adapter, _conn, table, _opts}) do
    table
    |> singularize_table_name()
    |> Macro.camelize()
  end

  def source_live_name({:db, _adapter, _conn, table}) do
    table
    |> singularize_table_name()
    |> Macro.camelize()
  end

  def source_live_name(source) when is_atom(source) do
    source |> to_string() |> String.split(".") |> List.last()
  end

  def source_live_name(source) when is_binary(source) do
    source
    |> singularize_table_name()
    |> Macro.camelize()
  end

  def source_live_name(source) do
    source |> to_string() |> singularize_table_name() |> Macro.camelize()
  end

  defp live_view_connection_ref(source, app_name, opts) do
    case source do
      {:db, _adapter, _conn, _table, _source_opts} ->
        opts[:connection_name] || "#{app_name}.Database"

      {:db, _adapter, _conn, _table} ->
        opts[:connection_name] || "#{app_name}.Database"

      _ ->
        "#{app_name}.Repo"
    end
  end

  defp render_inline_header(schema_name, opts) do
    if opts[:saved_views] do
      """
      <div class="flex items-center gap-4 mb-6">
            <h1 class="text-3xl font-bold">#{schema_name} Explorer</h1>

            <details :if={@available_saved_views != []} id="saved-views-dropdown" class="dropdown">
              <summary class="btn btn-sm btn-outline gap-1">Saved Views</summary>
              <ul class="menu dropdown-content z-[1] mt-2 w-56 rounded-box border border-base-300 bg-base-100 p-2 shadow">
                <li :for={v <- @available_saved_views}>
                  <.link href={\"\#{@path}?saved_view=\#{v}\"}>{v}</.link>
                </li>
              </ul>
            </details>
          </div>
      """
    else
      """
      <h1 class="text-3xl font-bold mb-6">#{schema_name} Explorer</h1>
      """
    end
  end

  defp singularize_table_name(table_name) do
    cond do
      String.ends_with?(table_name, "ies") ->
        String.replace_suffix(table_name, "ies", "y")

      String.ends_with?(table_name, "sses") ->
        String.replace_suffix(table_name, "sses", "ss")

      String.ends_with?(table_name, "ses") ->
        String.replace_suffix(table_name, "ses", "s")

      String.ends_with?(table_name, "s") and not String.ends_with?(table_name, "ss") ->
        String.replace_suffix(table_name, "s", "")

      true ->
        table_name
    end
  end
end
