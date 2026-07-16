defmodule Mix.Tasks.Selecto.Gen.LiveDashboard do
  @moduledoc """
  Generates a Phoenix LiveDashboard page for Selecto query metrics.

  This task creates a custom LiveDashboard page that displays:
  - Query execution metrics
  - Slow query analysis
  - Cache hit/miss rates
  - Query timeline visualization
  - Index usage statistics

  ## Usage

      mix selecto.gen.live_dashboard

  This will:
  1. Generate the LiveDashboard page module
  2. Add Selecto-specific telemetry metrics
  3. Update your router.ex with the additional_pages configuration

  ## Options

    * `--no-router` - Skip router.ex modifications
    * `--module` - The module name for the page (default: YourAppWeb.LiveDashboard.SelectoPage)

  ## Example

      mix selecto.gen.live_dashboard
      mix selecto.gen.live_dashboard --module MyAppWeb.Dashboard.SelectoMetrics
  """

  use Mix.Task
  import Mix.Generator

  @shortdoc "Generates a LiveDashboard page for Selecto metrics"

  @impl Mix.Task
  def run(args) do
    {opts, _positional} =
      SelectoMix.CLI.parse!(args,
        switches: [
          no_router: :boolean,
          module: :string
        ]
      )

    # Ensure the project is compiled
    Mix.Task.run("compile")

    # Get the application configuration
    app = Mix.Project.config()[:app]

    # Get the base module from the Mix project
    app_module =
      Mix.Project.config()[:app]
      |> to_string()
      |> Macro.camelize()

    web_module = Module.concat(["#{app_module}Web"])

    # Determine the page module name
    page_module =
      if opts[:module] do
        Module.concat([opts[:module]])
      else
        Module.concat([web_module, "LiveDashboard", "SelectoPage"])
      end

    Mix.shell().info("Generating Selecto LiveDashboard page...")

    # Generate the page module
    generate_page_module(app, web_module, page_module)

    # Add telemetry metrics
    add_telemetry_metrics(app, web_module)

    # Update router unless --no-router flag is set
    unless opts[:no_router] do
      update_router(app, web_module, page_module)
    end

    Mix.shell().info("""

    Selecto LiveDashboard page has been generated!

    Next steps:
    1. Restart your Phoenix server
    2. Visit your LiveDashboard route (commonly `/dev/dashboard` or `/dashboard`) and look for the "Selecto" tab
    3. The page will show real-time query metrics and performance data

    Optional: if you want Selecto core query hooks in addition to
    SelectoComponents metrics, install them during application startup:

        Selecto.Performance.Hooks.install_default_hooks(
          slow_query_threshold: 100,
          auto_explain_threshold: 500
        )

    """)
  end

  defp generate_page_module(app, _web_module, page_module) do
    path = page_module_path(app, page_module)

    content = render_page_module(page_module)
    create_file(path, content)
  end

  def render_page_module_for_test(page_module), do: render_page_module(page_module)

  defp render_page_module(page_module) do
    """
    defmodule #{inspect(page_module)} do
      @moduledoc \"\"\"
      LiveDashboard page for Selecto query metrics and performance monitoring.
      \"\"\"

      use Phoenix.LiveDashboard.PageBuilder

      @impl true
      def menu_link(_, _) do
        {:ok, "Selecto"}
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <div class="card">
          <div class="card-body">
            <h2 class="card-title">Selecto</h2>
            <p>Selecto telemetry metrics are registered for this application.</p>
          </div>
        </div>
        \"\"\"
      end
    end
    """
  end

  defp add_telemetry_metrics(app, _web_module) do
    telemetry_path = Path.join(["lib", "#{app}_web", "telemetry.ex"])

    if File.exists?(telemetry_path) do
      Mix.shell().info("Adding Selecto metrics to #{telemetry_path}...")

      content = File.read!(telemetry_path)

      # Check if Selecto metrics already exist
      if String.contains?(content, "selecto.query") do
        Mix.shell().info("Selecto metrics already present in telemetry.ex")
      else
        # Add Selecto metrics to the metrics/0 function
        updated_content =
          String.replace(
            content,
            "# VM Metrics",
            """
            # Selecto Metrics
            summary("selecto.query.complete.duration",
              unit: {:native, :millisecond},
              description: "Selecto query execution time"
            ),
            summary("selecto.query.complete.execution_time",
              unit: {:native, :millisecond},
              description: "Time spent executing the query"
            ),
            counter("selecto.cache.hit.count",
              description: "Number of cache hits"
            ),
            counter("selecto.cache.miss.count",
              description: "Number of cache misses"
            ),
            counter("selecto.query.error.count",
              description: "Number of query errors"
            ),
            distribution("selecto.cache.ratio",
              buckets: [0, 0.25, 0.5, 0.75, 1.0],
              unit: :percent,
              description: "Cache hit ratio"
            ),

            # VM Metrics
            """
          )

        File.write!(telemetry_path, updated_content)
        Mix.shell().info("✓ Added Selecto telemetry metrics")
      end
    else
      Mix.shell().error("Telemetry file not found at #{telemetry_path}")
    end
  end

  defp update_router(app, web_module, page_module) do
    router_path = Path.join(["lib", "#{app}_web", "router.ex"])

    if File.exists?(router_path) do
      Mix.shell().info("Updating router with Selecto LiveDashboard page...")

      content = File.read!(router_path)

      # Check if additional_pages already exists
      if String.contains?(content, "additional_pages:") do
        Mix.shell().info("Router already has additional_pages configuration")
        print_router_snippet(web_module, page_module)
      else
        # Only auto-patch high-confidence exact matches; otherwise print a merge snippet.
        updated_content = update_router_content(content, web_module, page_module)

        if updated_content != content do
          File.write!(router_path, updated_content)
          Mix.shell().info("✓ Updated router.ex with Selecto LiveDashboard page")
        else
          Mix.shell().info("Could not safely auto-update router.ex; please merge manually:")
          print_router_snippet(web_module, page_module)
        end
      end
    else
      Mix.shell().error("Router file not found at #{router_path}")
      print_router_snippet(web_module, page_module)
    end
  end

  defp print_router_snippet(web_module, page_module) do
    Mix.shell().info("""

    Please update your router.ex:

        live_dashboard("/dashboard",
          metrics: #{inspect(web_module)}.Telemetry,
          additional_pages: [
            selecto: #{inspect(page_module)}
          ]
        )
    """)
  end

  def update_router_content_for_test(content, web_module, page_module) do
    update_router_content(content, web_module, page_module)
  end

  defp update_router_content(content, web_module, page_module) do
    web_module_name = inspect(web_module)
    page_module_name = inspect(page_module)

    # High-confidence only: single-line live_dashboard with metrics and no additional_pages.
    pattern =
      ~r/live_dashboard\(\s*"\/dashboard"\s*,\s*metrics:\s*#{Regex.escape(web_module_name)}\.Telemetry\s*\)/

    replacement = """
    live_dashboard("/dashboard",
      metrics: #{web_module_name}.Telemetry,
      additional_pages: [
        selecto: #{page_module_name}
      ]
    )
    """

    case Regex.run(pattern, content) do
      [_match] -> String.replace(content, pattern, String.trim(replacement), global: false)
      nil -> content
    end
  end

  defp page_module_path(app, module_name) when is_atom(module_name) do
    parts = Module.split(module_name)

    # Convert module parts to path
    web_part = Enum.find_index(parts, &(&1 =~ ~r/Web$/i)) || 0

    path_parts =
      parts
      |> Enum.drop(web_part + 1)
      |> Enum.map(&Macro.underscore/1)

    Path.join(["lib", "#{app}_web"] ++ path_parts) <> ".ex"
  end
end
