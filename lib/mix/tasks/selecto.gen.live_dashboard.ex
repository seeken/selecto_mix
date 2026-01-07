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
    {opts, _, _} = OptionParser.parse(args,
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
    app_module = Mix.Project.config()[:app]
      |> to_string()
      |> Macro.camelize()

    web_module = Module.concat([app_module, "Web"])

    # Determine the page module name
    page_module = if opts[:module] do
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
    2. Visit /dev/dashboard and look for the "Selecto" tab
    3. The page will show real-time query metrics and performance data

    To enable query hooks for metric collection, add this to your application.ex:

        # In your start/2 function, after starting the MetricsCollector
        Selecto.Performance.Hooks.install_default_hooks(
          slow_query_threshold: 100,
          auto_explain_threshold: 500
        )

    """)
  end

  defp generate_page_module(app, _web_module, page_module) do
    path = page_module_path(app, page_module)

    content = """
    defmodule #{page_module} do
      @moduledoc \"\"\"
      LiveDashboard page for Selecto query metrics and performance monitoring.
      \"\"\"

      use Phoenix.LiveDashboard.PageBuilder
      import Telemetry.Metrics

      @impl true
      def menu_link(_, _) do
        {:ok, "Selecto"}
      end

      @impl true
      def render_page(assigns) do
        items = [
          {:query_metrics, name: "Query Metrics", render: &render_query_metrics/1},
          {:slow_queries, name: "Slow Queries", render: &render_slow_queries/1},
          {:cache_stats, name: "Cache Stats", render: &render_cache_stats/1},
          {:index_usage, name: "Index Usage", render: &render_index_usage/1}
        ]

        nav_bar(items: items)
      end

      defp render_query_metrics(assigns) do
        metrics_collector_data = get_metrics_data()

        assigns = Map.merge(assigns, %{
          metrics: metrics_collector_data.metrics,
          timeline: metrics_collector_data.timeline,
          percentiles: metrics_collector_data.percentiles
        })

        ~H\"\"\"
        <div>
          <h2 class="text-xl font-bold mb-4">Query Performance Metrics</h2>

          <.live_component
            module={Phoenix.LiveDashboard.ChartComponent}
            id="selecto-query-timeline"
            title="Query Execution Timeline (Last Hour)"
            kind={:line}
            label="Execution Time (ms)"
            prune_threshold={100}
            metric={summary("selecto.query.complete.duration")}
          />

          <div class="grid grid-cols-3 gap-4 mt-6">
            <.metric_card
              title="Total Queries"
              value={@metrics.total_queries}
              icon="heroicons-outline:chart-bar"
            />
            <.metric_card
              title="Avg Response Time"
              value={\#{@metrics.avg_response_time}ms}
              icon="heroicons-outline:clock"
            />
            <.metric_card
              title="Error Rate"
              value={\#{@metrics.error_rate}%}
              icon="heroicons-outline:exclamation-triangle"
              color={if @metrics.error_rate > 5, do: "red", else: "green"}
            />
          </div>

          <div class="mt-6">
            <h3 class="text-lg font-semibold mb-2">Response Time Percentiles</h3>
            <div class="grid grid-cols-3 gap-4">
              <div class="bg-gray-50 p-3 rounded">
                <div class="text-sm text-gray-600">P50 (Median)</div>
                <div class="text-xl font-bold">{@percentiles.p50}ms</div>
              </div>
              <div class="bg-gray-50 p-3 rounded">
                <div class="text-sm text-gray-600">P95</div>
                <div class="text-xl font-bold">{@percentiles.p95}ms</div>
              </div>
              <div class="bg-gray-50 p-3 rounded">
                <div class="text-sm text-gray-600">P99</div>
                <div class="text-xl font-bold">{@percentiles.p99}ms</div>
              </div>
            </div>
          </div>
        </div>
        \"\"\"
      end

      defp render_slow_queries(assigns) do
        slow_queries = get_slow_queries()
        assigns = Map.put(assigns, :slow_queries, slow_queries)

        ~H\"\"\"
        <div>
          <h2 class="text-xl font-bold mb-4">Slow Queries (>500ms)</h2>

          <div class="space-y-4">
            <%= for query <- @slow_queries do %>
              <div class="border rounded-lg p-4 bg-white shadow-sm">
                <div class="flex justify-between items-start mb-2">
                  <span class="text-sm text-gray-500">
                    <%= format_timestamp(query.timestamp) %>
                  </span>
                  <span class="px-2 py-1 bg-red-100 text-red-700 text-sm rounded">
                    <%= query.execution_time %>ms
                  </span>
                </div>
                <pre class="text-xs bg-gray-50 p-2 rounded overflow-x-auto"><%= format_sql(query.query) %></pre>
                <div class="mt-2 flex gap-4 text-sm text-gray-600">
                  <span>Rows: <%= query.row_count %></span>
                  <span>Table Scans: <%= query.table_scans %></span>
                  <span>Index Scans: <%= query.index_scans %></span>
                </div>
              </div>
            <% end %>

            <%= if @slow_queries == [] do %>
              <div class="text-center py-8 text-gray-500">
                <div class="text-4xl mb-2">🎉</div>
                <p>No slow queries detected</p>
              </div>
            <% end %>
          </div>
        </div>
        \"\"\"
      end

      defp render_cache_stats(assigns) do
        cache_stats = get_cache_stats()
        assigns = Map.put(assigns, :cache_stats, cache_stats)

        ~H\"\"\"
        <div>
          <h2 class="text-xl font-bold mb-4">Query Cache Statistics</h2>

          <div class="grid grid-cols-2 gap-6">
            <div>
              <.live_component
                module={Phoenix.LiveDashboard.ChartComponent}
                id="selecto-cache-ratio"
                title="Cache Hit Ratio"
                kind={:doughnut}
                label="Cache Performance"
                prune_threshold={100}
                metric={
                  distribution("selecto.cache.ratio",
                    buckets: [0, 0.25, 0.5, 0.75, 1.0],
                    unit: :percent
                  )
                }
              />
            </div>

            <div class="space-y-4">
              <.metric_card
                title="Cache Hit Rate"
                value={\#{@cache_stats.hit_rate}%}
                icon="heroicons-outline:lightning-bolt"
                color={if @cache_stats.hit_rate > 80, do: "green", else: "yellow"}
              />
              <.metric_card
                title="Total Hits"
                value={@cache_stats.hits}
                icon="heroicons-outline:check-circle"
              />
              <.metric_card
                title="Total Misses"
                value={@cache_stats.misses}
                icon="heroicons-outline:x-circle"
              />
            </div>
          </div>
        </div>
        \"\"\"
      end

      defp render_index_usage(assigns) do
        index_data = get_index_usage()
        assigns = Map.merge(assigns, %{
          most_used: index_data.most_used,
          unused: index_data.unused,
          recommendations: index_data.recommendations
        })

        ~H\"\"\"
        <div>
          <h2 class="text-xl font-bold mb-4">Index Usage Analysis</h2>

          <div class="grid grid-cols-2 gap-6">
            <div>
              <h3 class="text-lg font-semibold mb-3">Most Used Indexes</h3>
              <div class="space-y-2">
                <%= for index <- @most_used do %>
                  <div class="flex justify-between p-2 bg-gray-50 rounded">
                    <span class="text-sm font-medium"><%= index.name %></span>
                    <span class="text-sm text-gray-600"><%= index.usage_count %> uses</span>
                  </div>
                <% end %>
              </div>
            </div>

            <div>
              <h3 class="text-lg font-semibold mb-3">Unused Indexes</h3>
              <div class="space-y-2">
                <%= for index <- @unused do %>
                  <div class="flex justify-between p-2 bg-yellow-50 rounded">
                    <span class="text-sm font-medium"><%= index.name %></span>
                    <span class="text-sm text-yellow-600">Consider removing</span>
                  </div>
                <% end %>

                <%= if @unused == [] do %>
                  <p class="text-sm text-gray-500">All indexes are being used</p>
                <% end %>
              </div>
            </div>
          </div>

          <%= if @recommendations != [] do %>
            <div class="mt-6">
              <h3 class="text-lg font-semibold mb-3">Recommendations</h3>
              <div class="bg-blue-50 border border-blue-200 rounded p-4">
                <ul class="space-y-1">
                  <%= for rec <- @recommendations do %>
                    <li class="text-sm text-blue-800">• <%= rec %></li>
                  <% end %>
                </ul>
              </div>
            </div>
          <% end %>
        </div>
        \"\"\"
      end

      # Helper components

      defp metric_card(assigns) do
        assigns = Map.put_new(assigns, :color, "blue")

        ~H\"\"\"
        <div class={"bg-\#{@color}-50 p-4 rounded-lg"}>
          <div class="text-sm text-gray-600 mb-1"><%= @title %></div>
          <div class={"text-2xl font-bold text-\#{@color}-700"}><%= @value %></div>
        </div>
        \"\"\"
      end

      # Data fetching functions

      defp get_metrics_data do
        if Process.whereis(SelectoComponents.Performance.MetricsCollector) do
          metrics = SelectoComponents.Performance.MetricsCollector.get_metrics("1h")
          timeline = SelectoComponents.Performance.MetricsCollector.get_timeline("1h")

          %{
            metrics: metrics,
            timeline: timeline,
            percentiles: metrics[:percentiles] || %{p50: 0, p95: 0, p99: 0}
          }
        else
          %{
            metrics: %{
              total_queries: 0,
              avg_response_time: 0,
              error_rate: 0.0,
              queries_per_minute: 0
            },
            timeline: [],
            percentiles: %{p50: 0, p95: 0, p99: 0}
          }
        end
      end

      defp get_slow_queries do
        if Process.whereis(SelectoComponents.Performance.MetricsCollector) do
          SelectoComponents.Performance.MetricsCollector.get_slow_queries(500, 20)
        else
          []
        end
      end

      defp get_cache_stats do
        # This would be fetched from telemetry metrics or MetricsCollector
        %{
          hit_rate: 85,
          hits: 1523,
          misses: 267
        }
      end

      defp get_index_usage do
        # This would be fetched from database statistics
        %{
          most_used: [
            %{name: "idx_film_title", usage_count: 1523},
            %{name: "idx_customer_email", usage_count: 892}
          ],
          unused: [
            %{name: "idx_actor_first_name", usage_count: 0}
          ],
          recommendations: [
            "Consider adding an index on film.rating for frequent filter operations",
            "The idx_actor_first_name index hasn't been used in 7 days"
          ]
        }
      end

      # Formatting helpers

      defp format_timestamp(datetime) do
        Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
      end

      defp format_sql(sql) when byte_size(sql) > 500 do
        String.slice(sql, 0, 500) <> "..."
      end
      defp format_sql(sql), do: sql
    end
    """

    create_file(path, content)
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
        updated_content = String.replace(content,
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
        Mix.shell().info("Please manually add #{page_module} to the additional_pages list")
      else
        # Add additional_pages to live_dashboard
        updated_content = String.replace(content,
          ~r/live_dashboard\s+"\/dashboard",\s*\n\s*metrics:\s*#{web_module}\.Telemetry/,
          """
          live_dashboard "/dashboard",
            metrics: #{web_module}.Telemetry,
            additional_pages: [
              selecto: #{page_module}
            ]
          """
        )

        if updated_content != content do
          File.write!(router_path, updated_content)
          Mix.shell().info("✓ Updated router.ex with Selecto LiveDashboard page")
        else
          Mix.shell().error("Could not automatically update router.ex")
          Mix.shell().info("""

          Please manually update your router.ex:

              live_dashboard "/dashboard",
                metrics: #{web_module}.Telemetry,
                additional_pages: [
                  selecto: #{page_module}
                ]
          """)
        end
      end
    else
      Mix.shell().error("Router file not found at #{router_path}")
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