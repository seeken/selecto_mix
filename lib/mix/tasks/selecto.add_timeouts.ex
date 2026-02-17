defmodule Mix.Tasks.Selecto.AddTimeouts do
  @shortdoc "Add query timeout defense system to your Phoenix application"
  @moduledoc """
  Adds a multi-layer query timeout defense system to protect your database from overload.

  This task implements a comprehensive defense strategy including:
  - PostgreSQL statement_timeout configuration
  - Ecto connection pool timeout configuration
  - QueryTimeoutMonitor with circuit breaker pattern
  - Application supervision tree integration

  ## Examples

      # Add with default settings (30s timeout, 90% circuit breaker threshold)
      mix selecto.add_timeouts

      # Add with custom timeout
      mix selecto.add_timeouts --timeout 60000

      # Add with custom circuit breaker threshold
      mix selecto.add_timeouts --circuit-threshold 0.8

      # Preview changes without applying
      mix selecto.add_timeouts --dry-run

  ## Options

    * `--timeout` - Default query timeout in milliseconds (default: 30000)
    * `--test-timeout` - Test query timeout in milliseconds (default: 15000)
    * `--circuit-threshold` - Pool utilization threshold to open circuit (default: 0.9)
    * `--check-interval` - Health check interval in milliseconds (default: 5000)
    * `--dry-run` - Show what would be changed without applying
    * `--force` - Overwrite existing QueryTimeoutMonitor module
    * `--skip-config` - Skip config file modifications
    * `--skip-monitor` - Skip QueryTimeoutMonitor generation
    * `--skip-supervision` - Skip adding monitor to supervision tree

  ## What Gets Modified

  ### Configuration Files:
  - `config/dev.exs` - Adds database timeouts and PostgreSQL parameters
  - `config/test.exs` - Adds shorter timeouts for tests
  - `config/runtime.exs` - Adds production timeout configuration with env vars

  ### Generated Files:
  - `lib/APP_NAME/query_timeout_monitor.ex` - Circuit breaker GenServer

  ### Modified Files:
  - `lib/APP_NAME/application.ex` - Adds QueryTimeoutMonitor to supervision tree

  ## Defense Layers

  The system implements multiple defense layers:

  1. **PostgreSQL Level**: `statement_timeout` kills queries at database
  2. **Ecto Level**: Connection pool timeouts (query, connect, queue)
  3. **Application Level**: Task-based timeout wrapper (if using Selecto.Executor)
  4. **Circuit Breaker**: Blocks queries when pool saturated
  5. **Complexity Analysis**: Pre-execution query validation (if enabled)

  ## Usage After Installation

  Check circuit breaker status:

      YourApp.QueryTimeoutMonitor.allow_query?()
      YourApp.QueryTimeoutMonitor.circuit_state()
      YourApp.QueryTimeoutMonitor.stats()

  Record query metrics:

      YourApp.QueryTimeoutMonitor.record_timeout()
      YourApp.QueryTimeoutMonitor.record_slow_query(duration_ms)
      YourApp.QueryTimeoutMonitor.record_query(duration_ms)

  ## Environment Variables (Production)

  Set these in your production environment:

      QUERY_TIMEOUT=30000          # Query execution timeout
      STATEMENT_TIMEOUT=30000      # PostgreSQL statement timeout
      POOL_SIZE=10                 # Connection pool size
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.add_timeouts --timeout 60000",
      positional: [],
      schema: [
        timeout: :integer,
        test_timeout: :integer,
        circuit_threshold: :float,
        check_interval: :integer,
        dry_run: :boolean,
        force: :boolean,
        skip_config: :boolean,
        skip_monitor: :boolean,
        skip_supervision: :boolean
      ],
      aliases: [
        t: :timeout,
        d: :dry_run,
        f: :force
      ],
      defaults: [
        timeout: 30_000,
        test_timeout: 15_000,
        circuit_threshold: 0.9,
        check_interval: 5_000,
        dry_run: false,
        force: false,
        skip_config: false,
        skip_monitor: false,
        skip_supervision: false
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    options =
      info([], nil).defaults
      |> Keyword.merge(igniter.args.options)

    app_name = Igniter.Project.Application.app_name(igniter)
    app_module = Igniter.Project.Module.module_name(igniter, app_name)

    igniter
    |> maybe_update_dev_config(options, app_name)
    |> maybe_update_test_config(options, app_name)
    |> maybe_update_runtime_config(options, app_name)
    |> maybe_generate_monitor(options, app_module)
    |> maybe_add_to_supervision_tree(options, app_module)
    |> display_instructions(options, app_module)
  end

  defp maybe_update_dev_config(igniter, options, app_name) do
    if options[:skip_config] do
      igniter
    else
      timeout = options[:timeout]
      config_path = "config/dev.exs"

      Mix.shell().info("📝 Updating #{config_path} with database timeouts...")

      repo_config = """
        timeout: #{timeout},              # Query execution timeout: #{div(timeout, 1000)}s
        connect_timeout: 5_000,       # Connection establishment: 5 seconds
        queue_timeout: 10_000,        # Pool checkout timeout: 10 seconds
        # PostgreSQL-level timeout enforcement
        parameters: [
          statement_timeout: "#{timeout}",                      # Kill queries > #{div(timeout, 1000)}s
          idle_in_transaction_session_timeout: "300000"   # Kill idle txns > 5min
        ]
      """

      Igniter.Project.Config.configure(
        igniter,
        config_path,
        app_name,
        [:"Elixir.#{Macro.camelize(to_string(app_name))}.Repo"],
        {:code, repo_config},
        updater: fn zipper ->
          # Try to find and update existing timeout config
          zipper
        end
      )
    end
  end

  defp maybe_update_test_config(igniter, options, app_name) do
    if options[:skip_config] do
      igniter
    else
      timeout = options[:test_timeout]
      config_path = "config/test.exs"

      Mix.shell().info("📝 Updating #{config_path} with test timeouts...")

      repo_config = """
        timeout: #{timeout},              # Query timeout: #{div(timeout, 1000)} seconds
        connect_timeout: 5_000,
        queue_timeout: 5_000,
        # PostgreSQL-level timeout enforcement
        parameters: [
          statement_timeout: "#{timeout}",                      # Kill queries > #{div(timeout, 1000)}s in tests
          idle_in_transaction_session_timeout: "60000"    # Kill idle txns > 1min in tests
        ]
      """

      Igniter.Project.Config.configure(
        igniter,
        config_path,
        app_name,
        [:"Elixir.#{Macro.camelize(to_string(app_name))}.Repo"],
        {:code, repo_config}
      )
    end
  end

  defp maybe_update_runtime_config(igniter, options, app_name) do
    if options[:skip_config] do
      igniter
    else
      config_path = "config/runtime.exs"

      Mix.shell().info("📝 Updating #{config_path} with production timeout configuration...")

      repo_config = """
        # Production timeout configuration
        timeout: String.to_integer(System.get_env("QUERY_TIMEOUT") || "#{options[:timeout]}"),
        connect_timeout: 5_000,
        queue_timeout: 10_000,
        # PostgreSQL-level safety parameters
        parameters: [
          statement_timeout: System.get_env("STATEMENT_TIMEOUT") || "#{options[:timeout]}",
          idle_in_transaction_session_timeout: "300000",
          lock_timeout: "10000",                    # Don't wait > 10s for locks
          maintenance_work_mem: "256MB"             # Limit work memory
        ]
      """

      Igniter.Project.Config.configure(
        igniter,
        config_path,
        app_name,
        [:"Elixir.#{Macro.camelize(to_string(app_name))}.Repo"],
        {:code, repo_config}
      )
    end
  end

  defp maybe_generate_monitor(igniter, options, app_module) do
    if options[:skip_monitor] do
      igniter
    else
      Mix.shell().info("🔧 Generating QueryTimeoutMonitor module...")

      monitor_module = Module.concat(app_module, QueryTimeoutMonitor)
      monitor_code = generate_monitor_code(options, app_module)

      Igniter.Project.Module.create_module(
        igniter,
        monitor_module,
        monitor_code,
        force?: options[:force]
      )
    end
  end

  defp maybe_add_to_supervision_tree(igniter, options, app_module) do
    if options[:skip_supervision] do
      igniter
    else
      Mix.shell().info("🌳 Adding QueryTimeoutMonitor to supervision tree...")

      _app_module_path = Module.concat(app_module, Application)
      monitor_module = Module.concat(app_module, QueryTimeoutMonitor)

      Igniter.Project.Application.add_new_child(
        igniter,
        monitor_module,
        after: [Module.concat(app_module, Repo)]
      )
    end
  end

  defp display_instructions(igniter, options, app_module) do
    if not options[:dry_run] do
      Mix.shell().info("""

      ✅ Query timeout defense system has been added to your application!

      ## What was added:

      - PostgreSQL statement_timeout: #{options[:timeout]}ms
      - Ecto connection pool timeouts
      - #{inspect(Module.concat(app_module, QueryTimeoutMonitor))} with circuit breaker
      - Integration with application supervision tree

      ## Circuit Breaker Configuration:

      - Threshold: #{Float.round(options[:circuit_threshold] * 100, 1)}% pool utilization
      - Check interval: #{div(options[:check_interval], 1000)}s
      - States: :closed (normal) → :open (blocked) → :half_open (testing)

      ## Usage:

      Check if queries are allowed:
          #{inspect(Module.concat(app_module, QueryTimeoutMonitor))}.allow_query?()

      Get current statistics:
          #{inspect(Module.concat(app_module, QueryTimeoutMonitor))}.stats()

      Get circuit breaker state:
          #{inspect(Module.concat(app_module, QueryTimeoutMonitor))}.circuit_state()

      ## Environment Variables (Production):

      Set these in your production environment:

          export QUERY_TIMEOUT=#{options[:timeout]}
          export STATEMENT_TIMEOUT=#{options[:timeout]}
          export POOL_SIZE=10

      ## Next Steps:

      1. Review generated files and adjust thresholds if needed
      2. Test with: `mix test`
      3. Start server: `mix phx.server`
      4. Monitor logs for timeout warnings
      5. Adjust timeouts based on your application's needs

      For more information, see the SelectoMix documentation.
      """)
    end

    igniter
  end

  defp generate_monitor_code(options, app_module) do
    repo_module = Module.concat(app_module, Repo)

    """
    defmodule #{inspect(Module.concat(app_module, QueryTimeoutMonitor))} do
      @moduledoc \"\"\"
      Monitors database query performance and implements circuit breaker pattern.

      Uses Selecto.QueryTimeoutMonitor with #{inspect(repo_module)}.

      Circuit breaker states:
      - `:closed` - Normal operation, queries allowed
      - `:open` - System overloaded, queries blocked
      - `:half_open` - Testing if system has recovered

      Generated by: mix selecto.add_timeouts
      \"\"\"

      use Selecto.QueryTimeoutMonitor,
        repo: #{inspect(repo_module)},
        check_interval: #{options[:check_interval]},
        circuit_open_threshold: #{options[:circuit_threshold]},
        circuit_half_open_timeout: 30_000,
        slow_query_threshold: 10_000,
        very_slow_query_threshold: 30_000
    end
    """
  end
end
