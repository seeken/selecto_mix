defmodule SelectoMix.LiveViewGenerator.Postgrex do
  @moduledoc """
  Generates Phoenix LiveView for Postgrex-based Selecto domains.
  """

  def generate_liveview(table_info, app_module, module_name, opts) do
    path = opts[:path] || "/#{table_info.table_name}"
    has_saved_views = opts[:saved_views] || false
    saved_views_code = if has_saved_views, do: saved_views_assigns(path), else: ""
    capitalized_module = String.capitalize(module_name)

    "defmodule #{app_module}Web.#{module_name}PostgrexLive do\n" <>
    "  use #{app_module}Web, :live_view\n" <>
    "  use SelectoComponents.Form,\n" <>
    "    domain: #{app_module}.SelectoDomains.#{module_name}PostgrexDomain.domain()\n" <>
    "\n" <>
    "  @impl true\n" <>
    "  def mount(_params, _session, socket) do\n" <>
    "    # Initialize Selecto and view configuration\n" <>
    "    domain = #{app_module}.SelectoDomains.#{module_name}PostgrexDomain.domain()\n" <>
    "    selecto = Selecto.configure(domain, #{app_module}.Database)\n" <>
    "\n" <>
    "    # Define available views\n" <>
    "    views = [\n" <>
    "      {:aggregate, SelectoComponents.Views.Aggregate, \"Aggregate View\", %{drill_down: :detail}},\n" <>
    "      {:detail, SelectoComponents.Views.Detail, \"Detail View\", %{}}\n" <>
    "    ]\n" <>
    "\n" <>
    "    # Get initial state from views (returns keyword list of assigns)\n" <>
    "    state = get_initial_state(views, selecto)\n" <>
    "\n" <>
    "    # Apply all state assigns plus additional ones\n" <>
    "    socket =\n" <>
    "      socket\n" <>
    "      |> assign(id: \"#{table_info.table_name}_postgrex\")\n" <>
    "      |> assign(page_title: \"#{capitalized_module} (Postgrex)\")\n" <>
    "      |> assign(my_path: \"#{path}\")\n" <>
    "      |> assign(views: views)\n" <>
    "      |> assign(state)\n" <>
    "      |> assign(active_tab: \"view\")\n" <>
    "      |> assign(query_results: nil)\n" <>
    "      |> assign(execution_error: nil)#{saved_views_code}\n" <>
    "\n" <>
    "    {:ok, socket}\n" <>
    "  end\n" <>
    "\n" <>
    "  @impl true\n" <>
    "  def render(assigns) do\n" <>
    "    ~H\"\"\"\n" <>
    "    <header class=\"bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700\">\n" <>
    "      <div class=\"mx-auto max-w-7xl px-4 sm:px-6 lg:px-8\">\n" <>
    "        <div class=\"flex justify-between items-center py-4\">\n" <>
    "          <h1 class=\"text-xl font-semibold text-gray-900 dark:text-white\">\n" <>
    "            Selecto Northwind Demo\n" <>
    "          </h1>\n" <>
    "          <div class=\"flex items-center gap-4\">\n" <>
    "            <a\n" <>
    "              href=\"/dev/dashboard\"\n" <>
    "              class=\"px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors\"\n" <>
    "            >\n" <>
    "              Live Dashboard\n" <>
    "            </a>\n" <>
    "          </div>\n" <>
    "        </div>\n" <>
    "      </div>\n" <>
    "    </header>\n" <>
    "\n" <>
    "    <main class=\"px-4 py-8\">\n" <>
    "      <div class=\"max-w-full\">\n" <>
    "        {SelectoComponents.Form.render(assigns)}\n" <>
    "      </div>\n" <>
    "    </main>\n" <>
    "    \"\"\"\n" <>
    "  end\n" <>
    "\n" <>
    "  # Provide the Postgrex connection to SelectoComponents\n" <>
    "  def get_connection do\n" <>
    "    #{app_module}.Database\n" <>
    "  end\n" <>
    "end\n"
  end

  defp saved_views_assigns(path) do
    "\n          |> assign(saved_view_module: __MODULE__)" <>
    "\n          |> assign(saved_view_context: \"#{path}\")" <>
    "\n          |> assign(available_saved_views: [])"
  end
end
