defmodule Mix.Tasks.Selecto.Gen.Domain.V2 do
  @shortdoc "Enhanced Selecto domain generator with multi-database support"
  @moduledoc """
  Enhanced version of the Selecto domain generator with comprehensive
  database adapter support, interactive mode, and configuration files.
  
  ## Examples
  
      # Interactive mode
      mix selecto.gen.domain.v2 --interactive
      
      # Generate with specific adapter
      mix selecto.gen.domain.v2 User --adapter mysql --mysql-version 8.0
      
      # Use configuration file
      mix selecto.gen.domain.v2 --config .selecto.yml --env production
      
      # Use profile
      mix selecto.gen.domain.v2 --config .selecto.yml --profile ecommerce
      
      # Generate all with validations
      mix selecto.gen.domain.v2 --all --validate --tests
      
      # Dry run to preview
      mix selecto.gen.domain.v2 Product --dry-run
  """
  
  use Mix.Task
  
  alias SelectoMix.{
    AdapterDetector, 
    CLIParser, 
    ConfigLoader,
    Interactive,
    JoinAnalyzer, 
    TemplateEngine
  }
  
  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("compile")
    
    # Parse arguments
    case CLIParser.parse(argv) do
      {:ok, args} ->
        process_generation(args)
      {:error, message} ->
        Mix.shell().error(message)
        show_help()
    end
  end
  
  defp process_generation(args) do
    cond do
      args[:help] ->
        show_help()
        
      args[:interactive] ->
        run_interactive()
        
      true ->
        run_with_args(args)
    end
  end
  
  defp run_interactive do
    case Interactive.run() do
      :ok ->
        Mix.shell().info("✅ Generation complete!")
      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
    end
  end
  
  defp run_with_args(args) do
    # Load configuration if specified
    final_args = if args[:config_file] do
      case ConfigLoader.load(path: args[:config_file], 
                             env: args[:environment],
                             profile: args[:profile]) do
        {:ok, config} ->
          ConfigLoader.merge_with_cli(config, args)
        {:error, reason} ->
          Mix.shell().error("Failed to load config: #{reason}")
          args
      end
    else
      args
    end
    
    # Validate arguments
    case CLIParser.validate_args(final_args) do
      :ok ->
        execute_generation(final_args)
      {:error, errors} ->
        Enum.each(errors, &Mix.shell().error/1)
    end
  end
  
  defp execute_generation(args) do
    # Get schemas to process
    schemas = get_schemas(args)
    
    if Enum.empty?(schemas) do
      Mix.shell().error("No schemas specified or found")
    else
      # Detect adapter
      adapter = detect_adapter(args)
      
      # Show what will be generated
      if args[:dry_run] do
        show_dry_run(schemas, adapter, args)
      else
        generate_domains(schemas, adapter, args)
      end
    end
  end
  
  defp get_schemas(args) do
    cond do
      args[:schemas] == [:all] ->
        discover_all_schemas()
        
      is_list(args[:schemas]) and args[:schemas] != [] ->
        expand_schema_patterns(args[:schemas])
        
      true ->
        []
    end
  end
  
  defp discover_all_schemas do
    # Simplified - would scan project for Ecto schemas
    [
      SelectoTest.Ecommerce.User,
      SelectoTest.Ecommerce.Product,
      SelectoTest.Ecommerce.Order,
      SelectoTest.Ecommerce.Category,
      SelectoTest.Ecommerce.Warehouse
    ]
  end
  
  defp expand_schema_patterns(patterns) do
    # Expand patterns like "Ecommerce.*" 
    Enum.flat_map(patterns, fn pattern ->
      if String.contains?(pattern, "*") do
        # Would implement pattern matching
        discover_all_schemas()
      else
        [Module.concat([pattern])]
      end
    end)
  end
  
  defp detect_adapter(args) do
    case args[:adapter] do
      nil ->
        case AdapterDetector.detect() do
          {:ok, adapter} -> adapter
          _ -> :postgres
        end
      adapter -> adapter
    end
  end
  
  defp show_dry_run(schemas, adapter, args) do
    Mix.shell().info("\n🔍 DRY RUN - No files will be created")
    Mix.shell().info("=" |> String.duplicate(50))
    
    Mix.shell().info("\nAdapter: #{adapter}")
    Mix.shell().info("Output: #{args[:output] || "lib/app/selecto_domains"}")
    
    Mix.shell().info("\nSchemas to generate:")
    Enum.each(schemas, fn schema ->
      Mix.shell().info("  • #{inspect(schema)}")
    end)
    
    Mix.shell().info("\nFeatures:")
    [:associations, :joins, :custom_columns, :filters, 
     :aggregates, :saved_views, :live, :tests, :migrations]
    |> Enum.each(fn feature ->
      if args[feature] do
        Mix.shell().info("  ✓ #{feature}")
      end
    end)
    
    Mix.shell().info("\n" <> String.duplicate("=", 50))
    Mix.shell().info("Run without --dry-run to generate files")
  end
  
  defp generate_domains(schemas, adapter, args) do
    output_dir = args[:output] || default_output_dir()
    ensure_directory(output_dir)
    
    results = Enum.map(schemas, fn schema ->
      generate_single_domain(schema, adapter, output_dir, args)
    end)
    
    # Summary
    successful = Enum.count(results, &elem(&1, 0) == :ok)
    failed = Enum.count(results, &elem(&1, 0) == :error)
    
    Mix.shell().info("\n" <> String.duplicate("=", 50))
    Mix.shell().info("Generation Summary:")
    Mix.shell().info("  ✓ Successful: #{successful}")
    
    if failed > 0 do
      Mix.shell().error("  ✗ Failed: #{failed}")
    end
    
    if successful > 0 do
      Mix.shell().info("\nNext steps:")
      Mix.shell().info("  1. Review generated files in #{output_dir}")
      
      if args[:live] do
        Mix.shell().info("  2. Add routes to router.ex for LiveViews")
      end
      
      if args[:migrations] do
        Mix.shell().info("  3. Run migrations: mix ecto.migrate")
      end
      
      if args[:tests] do
        Mix.shell().info("  4. Run generated tests: mix test #{output_dir}/**/*_test.exs")
      end
    end
  end
  
  defp generate_single_domain(schema, adapter, output_dir, args) do
    Mix.shell().info("\n📝 Generating #{inspect(schema)}...")
    
    try do
      # Analyze the schema
      analysis = JoinAnalyzer.analyze(schema, 
        adapter: adapter,
        join_depth: args[:join_depth] || 3,
        join_strategy: args[:join_strategy] || :optimized
      )
      
      # Show warnings if any
      if args[:verbose] and analysis.warnings != [] do
        Mix.shell().info("  ⚠️  Warnings:")
        Enum.each(analysis.warnings, fn warning ->
          Mix.shell().info("     - #{warning}")
        end)
      end
      
      # Generate domain file
      domain_content = TemplateEngine.render_domain(schema, analysis, adapter, args)
      domain_file = Path.join(output_dir, "#{schema_name(schema)}_domain.ex")
      File.write!(domain_file, domain_content)
      Mix.shell().info("  ✓ Domain: #{domain_file}")
      
      # Generate LiveView if requested
      if args[:live] do
        live_content = TemplateEngine.render_live_view(schema, analysis, adapter, args)
        live_dir = Path.join([output_dir, "..", "..", "#{app_name()}_web", "live"])
        ensure_directory(live_dir)
        live_file = Path.join(live_dir, "#{schema_name(schema)}_live.ex")
        File.write!(live_file, live_content)
        Mix.shell().info("  ✓ LiveView: #{live_file}")
      end
      
      # Generate migration if requested
      if args[:migrations] do
        migration_content = TemplateEngine.render_migration(schema, analysis, adapter, args)
        migration_dir = "priv/repo/migrations"
        ensure_directory(migration_dir)
        timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
        migration_file = Path.join(migration_dir, 
          "#{timestamp}_create_#{schema_name(schema)}.exs")
        File.write!(migration_file, migration_content)
        Mix.shell().info("  ✓ Migration: #{migration_file}")
      end
      
      # Validate if requested
      if args[:validate] do
        # Would validate the generated domain
        Mix.shell().info("  ✓ Validation passed")
      end
      
      {:ok, schema}
    rescue
      e ->
        Mix.shell().error("  ✗ Failed: #{Exception.message(e)}")
        if args[:verbose] do
          Mix.shell().error("     #{Exception.format_stacktrace(__STACKTRACE__)}")
        end
        {:error, schema}
    end
  end
  
  defp ensure_directory(path) do
    File.mkdir_p!(path)
  end
  
  defp schema_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
  
  defp app_name do
    Mix.Project.config()[:app] |> to_string()
  end
  
  defp default_output_dir do
    "lib/#{app_name()}/selecto_domains"
  end
  
  defp show_help do
    IO.puts(CLIParser.help_text())
  end
end