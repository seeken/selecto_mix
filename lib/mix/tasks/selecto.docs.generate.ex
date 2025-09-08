defmodule Mix.Tasks.Selecto.Docs.Generate do
  @shortdoc "Generate comprehensive documentation for Selecto domains and configurations"
  @moduledoc """
  Generate comprehensive documentation for Selecto domains and configurations.

  This task creates detailed documentation including domain overviews, field references,
  join relationships, performance considerations, and interactive examples.

  ## Examples

      # Generate documentation for a specific domain
      mix selecto.docs.generate --domain=posts

      # Generate documentation for all domains
      mix selecto.docs.generate --all

      # Generate with performance benchmarks
      mix selecto.docs.generate --with-benchmarks

      # Generate with interactive examples
      mix selecto.docs.generate --interactive

      # Specify output directory
      mix selecto.docs.generate --output docs/selecto

      # Generate in different formats
      mix selecto.docs.generate --format=markdown,html

  ## Options

    * `--domain` - Generate documentation for a specific domain
    * `--all` - Generate documentation for all discovered domains
    * `--output` - Specify output directory (default: docs/selecto)
    * `--format` - Output formats: markdown, html, or both (default: markdown)
    * `--with-benchmarks` - Include performance benchmarking guides
    * `--interactive` - Generate interactive examples with live data
    * `--api-reference` - Include complete API reference
    * `--include-examples` - Include code examples for common operations
    * `--dry-run` - Show what would be generated without creating files

  ## Generated Documentation

  For each domain, generates:
  - `DOMAIN_overview.md` - Domain overview and structure
  - `DOMAIN_fields.md` - Complete field reference with types and descriptions
  - `DOMAIN_joins.md` - Join relationships and optimization guides
  - `DOMAIN_examples.md` - Code examples and common patterns
  - `DOMAIN_performance.md` - Performance considerations and benchmarks (if --with-benchmarks)
  - `DOMAIN_interactive.livemd` - Interactive Livebook examples (if --interactive)

  ## Interactive Features

  When `--interactive` is used, generates Livebook files with:
  - Live domain exploration
  - Interactive query building
  - Real-time performance monitoring
  - Data visualization examples
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.docs.generate --domain=posts --interactive",
      schema: [
        domain: :string,
        all: :boolean,
        output: :string,
        format: :string,
        with_benchmarks: :boolean,
        interactive: :boolean,
        api_reference: :boolean,
        include_examples: :boolean,
        dry_run: :boolean
      ],
      aliases: [
        d: :domain,
        a: :all,
        o: :output,
        f: :format,
        b: :with_benchmarks,
        i: :interactive
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    {parsed_args, _remaining_args} = OptionParser.parse!(igniter.args.argv, strict: info(igniter.args.argv, nil).schema)
    
    domains = cond do
      parsed_args[:all] -> discover_all_domains(igniter)
      parsed_args[:domain] -> [parsed_args[:domain]]
      true -> []
    end

    if Enum.empty?(domains) do
      Igniter.add_warning(igniter, """
      No domains specified. Use one of:
        mix selecto.docs.generate --domain=posts
        mix selecto.docs.generate --all
      """)
    else
      process_domains(igniter, domains, parsed_args)
    end
  end

  # Private functions

  defp discover_all_domains(igniter) do
    # Find all domain modules in the project
    app_name = Igniter.Project.Application.app_name(igniter)
    
    {_igniter, modules} = 
      igniter
      |> Igniter.Project.Module.find_all_matching_modules(fn module_name, _zipper ->
        module_str = to_string(module_name)
        String.contains?(module_str, "Domain") and String.starts_with?(module_str, to_string(app_name))
      end)
    
    modules
    |> Enum.map(&extract_domain_name/1)
    |> Enum.filter(&(&1 != nil))
  end

  defp extract_domain_name(module_name) do
    module_str = to_string(module_name)
    case Regex.run(~r/(\w+)Domain$/, module_str) do
      [_, domain_name] -> Macro.underscore(domain_name)
      _ -> nil
    end
  end

  defp process_domains(igniter, domains, opts) do
    output_dir = get_output_directory(igniter, opts[:output])
    formats = parse_formats(opts[:format])
    
    if opts[:dry_run] do
      show_dry_run_summary(domains, output_dir, opts)
      igniter
    else
      Enum.reduce(domains, igniter, fn domain, acc_igniter ->
        generate_documentation_for_domain(acc_igniter, domain, output_dir, formats, opts)
      end)
    end
  end

  defp get_output_directory(_igniter, custom_output) do
    custom_output || "docs/selecto"
  end

  defp parse_formats(format_arg) do
    case format_arg do
      nil -> [:exs]  # Default to executable format
      formats_str ->
        formats_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)
        |> Enum.filter(&(&1 in [:markdown, :html, :exs]))
    end
  end

  defp show_dry_run_summary(domains, output_dir, opts) do
    IO.puts("""
    
    Selecto Documentation Generation (DRY RUN)
    ==========================================
    
    Output directory: #{output_dir}
    Formats: #{inspect(parse_formats(opts[:format]))}
    With benchmarks: #{opts[:with_benchmarks] || false}
    Interactive examples: #{opts[:interactive] || false}
    API reference: #{opts[:api_reference] || false}
    
    Domains to document:
    """)
    
    Enum.each(domains, fn domain ->
      files = get_documentation_files(domain, output_dir, parse_formats(opts[:format]), opts)
      
      IO.puts("  • #{domain}")
      Enum.each(files, fn file ->
        IO.puts("    → #{file}")
      end)
    end)
    
    IO.puts("\nRun without --dry-run to generate documentation.")
  end

  defp get_documentation_files(domain, output_dir, formats, opts) do
    # For .exs format, only generate examples file
    if formats == [:exs] do
      [Path.join(output_dir, "#{domain}_examples.exs")]
    else
      base_files = [
        "#{domain}_overview",
        "#{domain}_fields", 
        "#{domain}_joins",
        "#{domain}_examples"
      ]
      
      optional_files = []
      optional_files = if opts[:with_benchmarks], do: optional_files ++ ["#{domain}_performance"], else: optional_files
      optional_files = if opts[:interactive], do: optional_files ++ ["#{domain}_interactive"], else: optional_files
      
      all_files = base_files ++ optional_files
      
      Enum.flat_map(all_files, fn base_name ->
        Enum.map(formats, fn format ->
          extension = case format do
            :markdown -> if String.ends_with?(base_name, "interactive"), do: ".livemd", else: ".md"
            :html -> ".html"
            :exs -> ".exs"
          end
          Path.join(output_dir, "#{base_name}#{extension}")
        end)
      end)
    end
  end

  defp generate_documentation_for_domain(igniter, domain, output_dir, formats, opts) do
    # For .exs format, only generate the examples file
    if formats == [:exs] do
      igniter
      |> ensure_directory_exists(output_dir)
      |> generate_examples_documentation(domain, output_dir, formats, opts)
      |> add_success_message("Generated executable examples for #{domain} domain")
    else
      igniter
      |> ensure_directory_exists(output_dir)
      |> generate_overview_documentation(domain, output_dir, formats, opts)
      |> generate_fields_documentation(domain, output_dir, formats, opts)
      |> generate_joins_documentation(domain, output_dir, formats, opts)
      |> generate_examples_documentation(domain, output_dir, formats, opts)
      |> maybe_generate_performance_documentation(domain, output_dir, formats, opts)
      |> maybe_generate_interactive_documentation(domain, output_dir, formats, opts)
      |> add_success_message("Generated documentation for #{domain} domain")
    end
  end

  defp ensure_directory_exists(igniter, dir_path) do
    Igniter.create_new_file(igniter, Path.join(dir_path, ".gitkeep"), "")
  end

  defp generate_overview_documentation(igniter, domain, output_dir, formats, _opts) do
    Enum.reduce(formats, igniter, fn format, acc_igniter ->
      extension = if format == :markdown, do: ".md", else: ".html"
      file_path = Path.join(output_dir, "#{domain}_overview#{extension}")
      content = SelectoMix.DocsGenerator.generate_overview(domain, format)
      Igniter.create_new_file(acc_igniter, file_path, content)
    end)
  end

  defp generate_fields_documentation(igniter, domain, output_dir, formats, _opts) do
    Enum.reduce(formats, igniter, fn format, acc_igniter ->
      extension = if format == :markdown, do: ".md", else: ".html"
      file_path = Path.join(output_dir, "#{domain}_fields#{extension}")
      content = SelectoMix.DocsGenerator.generate_fields_reference(domain, format)
      Igniter.create_new_file(acc_igniter, file_path, content)
    end)
  end

  defp generate_joins_documentation(igniter, domain, output_dir, formats, _opts) do
    Enum.reduce(formats, igniter, fn format, acc_igniter ->
      extension = if format == :markdown, do: ".md", else: ".html"
      file_path = Path.join(output_dir, "#{domain}_joins#{extension}")
      content = SelectoMix.DocsGenerator.generate_joins_guide(domain, format)
      Igniter.create_new_file(acc_igniter, file_path, content)
    end)
  end

  defp generate_examples_documentation(igniter, domain, output_dir, formats, opts) do
    Enum.reduce(formats, igniter, fn format, acc_igniter ->
      extension = case format do
        :markdown -> ".md"
        :html -> ".html"
        :exs -> ".exs"
      end
      file_path = Path.join(output_dir, "#{domain}_examples#{extension}")
      content = SelectoMix.DocsGenerator.generate_examples(domain, format, opts)
      
      # Create the file first
      acc_igniter = Igniter.create_new_file(acc_igniter, file_path, content)
      
      # Note: File permissions will need to be set after Igniter writes the files
      # For now, we'll just create the file and users can chmod it manually if needed
      
      acc_igniter
    end)
  end

  defp maybe_generate_performance_documentation(igniter, domain, output_dir, formats, opts) do
    if opts[:with_benchmarks] do
      Enum.reduce(formats, igniter, fn format, acc_igniter ->
        extension = if format == :markdown, do: ".md", else: ".html"
        file_path = Path.join(output_dir, "#{domain}_performance#{extension}")
        content = SelectoMix.DocsGenerator.generate_performance_guide(domain, format)
        Igniter.create_new_file(acc_igniter, file_path, content)
      end)
    else
      igniter
    end
  end

  defp maybe_generate_interactive_documentation(igniter, domain, output_dir, formats, opts) do
    if opts[:interactive] do
      Enum.reduce(formats, igniter, fn format, acc_igniter ->
        case format do
          :markdown ->
            file_path = Path.join(output_dir, "#{domain}_interactive.livemd")
            content = SelectoMix.DocsGenerator.generate_interactive_livebook(domain)
            Igniter.create_new_file(acc_igniter, file_path, content)
          :html ->
            file_path = Path.join(output_dir, "#{domain}_interactive.html")
            content = SelectoMix.DocsGenerator.generate_interactive_html(domain)
            Igniter.create_new_file(acc_igniter, file_path, content)
        end
      end)
    else
      igniter
    end
  end

  defp add_success_message(igniter, message) do
    Igniter.add_notice(igniter, message)
  end
end