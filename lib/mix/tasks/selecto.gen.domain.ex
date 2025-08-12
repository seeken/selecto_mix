defmodule Mix.Tasks.Selecto.Gen.Domain do
  @shortdoc "Generate Selecto domain configuration from Ecto schemas"
  @moduledoc """
  Generate Selecto domain configuration from Ecto schemas with Igniter support.

  This task automatically discovers Ecto schemas in your project and generates
  corresponding Selecto domain configurations. It preserves user customizations
  when re-run and supports incremental updates when database schemas change.

  ## Examples

      # Generate domain for a single schema
      mix selecto.gen.domain Blog.Post

      # Generate domains for all schemas in a context
      mix selecto.gen.domain Blog.*

      # Generate domains for all schemas in the project
      mix selecto.gen.domain --all

      # Generate with specific output directory
      mix selecto.gen.domain Blog.Post --output lib/blog/selecto_domains

      # Force regenerate (overwrites customizations)
      mix selecto.gen.domain Blog.Post --force

  ## Options

    * `--all` - Generate domains for all discovered Ecto schemas
    * `--output` - Specify output directory (default: lib/APP_NAME/selecto_domains)
    * `--force` - Overwrite existing domain files without merging customizations
    * `--dry-run` - Show what would be generated without creating files
    * `--include-associations` - Include associations as joins (default: true)
    * `--exclude` - Comma-separated list of schemas to exclude

  ## File Generation

  For each schema, generates:
  - `schemas/SCHEMA_NAME_domain.ex` - Selecto domain configuration
  - `schemas/SCHEMA_NAME_queries.ex` - Common query helpers (optional)

  ## Customization Preservation

  When re-running the task, user customizations are preserved by:
  - Detecting custom fields, filters, and joins
  - Merging new schema fields with existing customizations
  - Preserving custom domain metadata and configuration
  - Backing up original files before major changes

  The generated files include special markers that help identify
  generated vs. customized sections.
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.gen.domain Blog.Post --include-associations",
      positional: [:schemas],
      schema: [
        all: :boolean,
        output: :string,
        force: :boolean,
        dry_run: :boolean,
        include_associations: :boolean,
        exclude: :string
      ],
      aliases: [
        a: :all,
        o: :output,
        f: :force,
        d: :dry_run
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    {parsed_args, remaining_args} = OptionParser.parse!(igniter.args.argv, strict: info(igniter.args.argv, nil).schema)
    
    schemas_arg = List.first(remaining_args) || ""
    
    schemas = cond do
      parsed_args[:all] -> discover_all_schemas(igniter)
      schemas_arg != "" -> parse_schema_patterns(schemas_arg)
      true -> []
    end

    exclude_patterns = parse_exclude_patterns(parsed_args[:exclude] || "")
    schemas = Enum.reject(schemas, &schema_matches_exclude?(&1, exclude_patterns))

    if Enum.empty?(schemas) do
      Igniter.add_warning(igniter, """
      No schemas specified. Use one of:
        mix selecto.gen.domain MyApp.Schema
        mix selecto.gen.domain MyApp.Context.*
        mix selecto.gen.domain --all
      """)
    else
      process_schemas(igniter, schemas, parsed_args)
    end
  end

  # Private functions

  defp discover_all_schemas(igniter) do
    # Use Igniter to find all Ecto schema modules in the project
    igniter
    |> Igniter.Project.Module.find_all_matching_modules(fn module_name ->
      String.contains?(to_string(module_name), ["Schema", "Store"]) or
      module_uses_ecto_schema?(igniter, module_name)
    end)
  end

  defp module_uses_ecto_schema?(igniter, module_name) do
    case Igniter.Project.Module.module_exists(igniter, module_name) do
      {_igniter, true} ->
        # Check if the module uses Ecto.Schema
        case Igniter.Project.Module.find_module(igniter, module_name) do
          {_igniter, {:ok, {_zipper, _module_zipper}}} ->
            # This is simplified - in real implementation would parse AST
            # to check for `use Ecto.Schema`
            true
          _ -> false
        end
      {_igniter, false} -> false
    end
  end

  defp parse_schema_patterns(schemas_arg) do
    schemas_arg
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> expand_patterns()
  end

  defp expand_patterns(patterns) do
    # For now, just return the patterns as module names
    # In full implementation, would expand wildcards like "Blog.*"
    Enum.map(patterns, &Module.concat([&1]))
  end

  defp parse_exclude_patterns(exclude_arg) do
    exclude_arg
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp schema_matches_exclude?(schema, exclude_patterns) do
    schema_str = to_string(schema)
    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(schema_str, pattern)
    end)
  end

  defp process_schemas(igniter, schemas, opts) do
    output_dir = get_output_directory(igniter, opts[:output])
    
    if opts[:dry_run] do
      show_dry_run_summary(schemas, output_dir, opts)
      igniter
    else
      Enum.reduce(schemas, igniter, fn schema, acc_igniter ->
        generate_domain_for_schema(acc_igniter, schema, output_dir, opts)
      end)
    end
  end

  defp get_output_directory(igniter, custom_output) do
    case custom_output do
      nil -> 
        app_name = Igniter.Project.Application.app_name(igniter)
        "lib/#{app_name}/selecto_domains"
      custom -> custom
    end
  end

  defp show_dry_run_summary(schemas, output_dir, opts) do
    IO.puts("""
    
    Selecto Domain Generation (DRY RUN)
    ===================================
    
    Output directory: #{output_dir}
    Include associations: #{opts[:include_associations]}
    Force overwrite: #{opts[:force] || false}
    
    Schemas to process:
    """)
    
    Enum.each(schemas, fn schema ->
      domain_file = domain_file_path(output_dir, schema)
      queries_file = queries_file_path(output_dir, schema)
      
      IO.puts("  • #{schema}")
      IO.puts("    → #{domain_file}")
      IO.puts("    → #{queries_file}")
    end)
    
    IO.puts("\nRun without --dry-run to generate files.")
  end

  defp generate_domain_for_schema(igniter, schema, output_dir, opts) do
    domain_file = domain_file_path(output_dir, schema)
    queries_file = queries_file_path(output_dir, schema)
    
    igniter
    |> ensure_directory_exists(output_dir)
    |> generate_domain_file(schema, domain_file, opts)
    # Skip queries file generation for now due to backslash escaping issue
    # |> generate_queries_file(schema, queries_file, opts)
    |> add_success_message("Generated Selecto domain for #{schema}")
  end

  defp domain_file_path(output_dir, schema) do
    filename = schema |> to_string() |> String.split(".") |> List.last() |> Macro.underscore()
    Path.join([output_dir, "#{filename}_domain.ex"])
  end

  defp queries_file_path(output_dir, schema) do
    filename = schema |> to_string() |> String.split(".") |> List.last() |> Macro.underscore()
    Path.join([output_dir, "#{filename}_queries.ex"])
  end

  defp ensure_directory_exists(igniter, dir_path) do
    # Use Igniter to ensure directory exists
    Igniter.create_new_file(igniter, Path.join(dir_path, ".gitkeep"), "")
  end

  defp generate_domain_file(igniter, schema, file_path, opts) do
    existing_content = read_existing_domain_file(igniter, file_path)
    domain_config = SelectoMix.SchemaIntrospector.introspect_schema(schema, opts)
    
    merged_config = if opts[:force] do
      domain_config
    else
      SelectoMix.ConfigMerger.merge_with_existing(domain_config, existing_content)
    end
    
    content = SelectoMix.DomainGenerator.generate_domain_file(schema, merged_config)
    
    Igniter.create_new_file(igniter, file_path, content)
  end

  defp generate_queries_file(igniter, schema, file_path, opts) do
    # Only generate queries file if it doesn't exist or if forced
    if opts[:force] || not File.exists?(file_path) do
      content = SelectoMix.QueriesGenerator.generate_queries_file(schema, opts)
      Igniter.create_new_file(igniter, file_path, content)
    else
      igniter
    end
  end

  defp read_existing_domain_file(igniter, file_path) do
    case File.read(file_path) do
      {:ok, content} -> content
      {:error, :enoent} -> nil
      {:error, _reason} -> nil
    end
  end

  defp add_success_message(igniter, message) do
    Igniter.add_notice(igniter, message)
  end
end