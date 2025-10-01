defmodule Mix.Tasks.Selecto.Gen.Domain.Postgrex do
  @shortdoc "Generate Selecto domain from PostgreSQL database via introspection"

  @moduledoc """
  Generate Selecto domain configuration by introspecting a PostgreSQL database directly.

  This task connects to PostgreSQL using Postgrex and introspects the database schema
  to generate Selecto domain configurations without requiring Ecto schemas.

  ## Examples

      # Using DATABASE_URL environment variable
      DATABASE_URL="postgres://user:pass@localhost/db" \\
        mix selecto.gen.domain.postgrex --table products

      # Using explicit connection parameters
      mix selecto.gen.domain.postgrex --table products \\
        --host localhost --port 5432 --database mydb \\
        --username postgres --password postgres

      # With LiveView and saved views
      mix selecto.gen.domain.postgrex --table products \\
        --live --saved-views --path products_postgrex

      # With expanded associations (introspect related tables)
      mix selecto.gen.domain.postgrex --table products --expand

  ## Options

    * `--table` - Table name to introspect (required)
    * `--host` - Database host (default: localhost)
    * `--port` - Database port (default: 5432)
    * `--database` - Database name (required if no DATABASE_URL)
    * `--username` - Database username (required if no DATABASE_URL)
    * `--password` - Database password
    * `--schema` - PostgreSQL schema (default: public)
    * `--live` - Generate LiveView files for the domain
    * `--saved-views` - Generate saved views implementation (requires --live)
    * `--path` - Custom path for the LiveView route
    * `--output` - Specify output directory (default: lib/APP_NAME/selecto_domains)
    * `--expand` - Introspect related tables and include as nested schemas

  ## Connection

  The task can connect using either:
  1. DATABASE_URL environment variable
  2. Explicit connection parameters (--host, --database, etc.)

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Mix.Task.run("loadpaths")

    {opts, _remaining, _invalid} = OptionParser.parse(args,
      strict: [
        table: :string,
        host: :string,
        port: :integer,
        database: :string,
        username: :string,
        password: :string,
        schema: :string,
        live: :boolean,
        saved_views: :boolean,
        path: :string,
        output: :string,
        expand: :boolean
      ]
    )

    # Validate required options
    unless opts[:table] do
      Mix.raise("--table option is required")
    end

    table_name = opts[:table]
    schema_name = opts[:schema] || "public"

    # Get connection config
    conn_config = get_connection_config(opts)

    Mix.shell().info("Connecting to PostgreSQL database...")
    Mix.shell().info("Introspecting table: #{schema_name}.#{table_name}")

    # Connect and introspect
    {:ok, conn} = Postgrex.start_link(conn_config)

    try do
      table_info = introspect_table(conn, schema_name, table_name)

      # If expand flag is set, introspect related tables
      expanded_tables = if opts[:expand] do
        expand_related_tables(conn, schema_name, table_info)
      else
        %{}
      end

      # Generate domain file
      generate_domain_file(table_info, Keyword.put(opts, :expanded_tables, expanded_tables))

      # Generate LiveView if requested
      if opts[:live] do
        generate_liveview_file(table_info, opts)

        # Integrate SelectoComponents assets
        integrate_assets()

        # Generate saved views if requested
        if opts[:saved_views] do
          generate_saved_views(table_info, opts)
        end
      end

      Mix.shell().info("✓ Successfully generated Selecto domain for #{table_name}")

      if opts[:live] do
        Mix.shell().info("")
        Mix.shell().info("Next steps:")
        Mix.shell().info("  1. Add route to router.ex:")
        path = opts[:path] || "/#{table_name}"
        module_name = Macro.camelize(table_name)
        Mix.shell().info("     live \"#{path}\", #{module_name}PostgrexLive, :index")

        if opts[:saved_views] do
          Mix.shell().info("  2. Run migrations: mix ecto.migrate")
        end

        Mix.shell().info("  #{if opts[:saved_views], do: "3", else: "2"}. Build assets: mix assets.build")
        Mix.shell().info("  #{if opts[:saved_views], do: "4", else: "3"}. Restart server: mix phx.server")
      end

    after
      GenServer.stop(conn)
    end
  end

  defp get_connection_config(opts) do
    # Try DATABASE_URL first
    case System.get_env("DATABASE_URL") do
      nil ->
        # Use explicit parameters
        unless opts[:database] && opts[:username] do
          Mix.raise("Either DATABASE_URL environment variable or --database and --username options are required")
        end

        [
          hostname: opts[:host] || "localhost",
          port: opts[:port] || 5432,
          database: opts[:database],
          username: opts[:username],
          password: opts[:password] || ""
        ]

      database_url ->
        # Parse DATABASE_URL (format: postgres://user:pass@host:port/database)
        uri = URI.parse(database_url)

        [
          hostname: uri.host || "localhost",
          port: uri.port || 5432,
          database: String.trim_leading(uri.path || "", "/"),
          username: uri.userinfo && String.split(uri.userinfo, ":") |> hd() || "postgres",
          password: uri.userinfo && String.split(uri.userinfo, ":") |> Enum.at(1, "") || ""
        ]
    end
  end

  defp introspect_table(conn, schema, table) do
    # Get columns
    {:ok, columns} = SelectoMix.Introspector.Postgres.get_columns(conn, table, schema)

    # Get primary key
    {:ok, primary_key} = SelectoMix.Introspector.Postgres.get_primary_key(conn, table, schema)

    # Get foreign keys
    {:ok, foreign_keys} = SelectoMix.Introspector.Postgres.get_foreign_keys(conn, table, schema)

    %{
      table_name: table,
      schema_name: schema,
      columns: columns,
      primary_key: primary_key,
      foreign_keys: foreign_keys
    }
  end

  defp generate_domain_file(table_info, opts) do
    app_name = Mix.Project.config()[:app]
    app_module = app_name |> to_string() |> Macro.camelize()
    table_name = table_info.table_name
    module_name = Macro.camelize(table_name)

    output_dir = opts[:output] || "lib/#{app_name}/selecto_domains"
    File.mkdir_p!(output_dir)

    file_path = Path.join(output_dir, "#{table_name}_postgrex_domain.ex")

    content = SelectoMix.DomainGenerator.Postgrex.generate_domain(
      table_info,
      app_module,
      module_name,
      opts
    )

    File.write!(file_path, content)
    Mix.shell().info("✓ Generated #{file_path}")
  end

  defp expand_related_tables(conn, schema, table_info) do
    Mix.shell().info("Expanding related tables...")

    # Get unique list of foreign table names
    foreign_table_names =
      table_info.foreign_keys
      |> Enum.map(& &1.foreign_table_name)
      |> Enum.uniq()

    # Introspect each foreign table
    Enum.reduce(foreign_table_names, %{}, fn foreign_table, acc ->
      Mix.shell().info("  - Introspecting #{foreign_table}...")
      foreign_table_info = introspect_table(conn, schema, foreign_table)
      Map.put(acc, foreign_table, foreign_table_info)
    end)
  end

  defp generate_liveview_file(table_info, opts) do
    app_name = Mix.Project.config()[:app]
    app_module = app_name |> to_string() |> Macro.camelize()
    table_name = table_info.table_name
    module_name = Macro.camelize(table_name)

    live_dir = "lib/#{app_name}_web/live"
    File.mkdir_p!(live_dir)

    file_path = Path.join(live_dir, "#{table_name}_postgrex_live.ex")

    content = SelectoMix.LiveViewGenerator.Postgrex.generate_liveview(
      table_info,
      app_module,
      module_name,
      opts
    )

    File.write!(file_path, content)
    Mix.shell().info("✓ Generated #{file_path}")
  end

  defp integrate_assets do
    # Run the SelectoComponents integration task
    case Mix.Task.run("selecto.components.integrate", ["--yes"]) do
      :ok -> Mix.shell().info("✓ Integrated SelectoComponents assets")
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp generate_saved_views(_table_info, _opts) do
    # Run the saved views generator
    case Mix.Task.run("selecto.gen.saved_views", []) do
      :ok -> Mix.shell().info("✓ Generated saved views infrastructure")
      _ -> :ok
    end
  rescue
    _ -> :ok
  end
end
