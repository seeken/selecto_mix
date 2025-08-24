defmodule Mix.Tasks.Selecto.Docs.Guide do
  @shortdoc "Generate comprehensive guides for Selecto development and usage"
  @moduledoc """
  Generate comprehensive guides for Selecto development, migration, and best practices.

  This task creates detailed guides including getting started tutorials, migration guides,
  best practices documentation, troubleshooting guides, and advanced usage patterns.

  ## Examples

      # Generate all guides
      mix selecto.docs.guide --all

      # Generate specific guide types
      mix selecto.docs.guide --type=migration,best-practices

      # Include advanced examples
      mix selecto.docs.guide --advanced

      # Generate for specific versions
      mix selecto.docs.guide --from-version=0.1.0 --to-version=0.2.0

      # Specify output directory
      mix selecto.docs.guide --output docs/guides

  ## Options

    * `--all` - Generate all available guide types
    * `--type` - Comma-separated list of guide types to generate
    * `--output` - Specify output directory (default: docs/guides)
    * `--format` - Output formats: markdown, html, or both (default: markdown)
    * `--advanced` - Include advanced usage patterns and examples
    * `--from-version` - Source version for migration guides
    * `--to-version` - Target version for migration guides
    * `--dry-run` - Show what would be generated without creating files

  ## Guide Types

    * `getting-started` - Comprehensive getting started tutorial
    * `migration` - Version migration guides and breaking changes
    * `best-practices` - Development best practices and patterns
    * `troubleshooting` - Common issues and solutions
    * `performance` - Performance optimization strategies
    * `testing` - Testing strategies and examples
    * `deployment` - Production deployment guides
    * `advanced` - Advanced usage patterns and techniques

  ## Generated Guides

  Creates comprehensive guides including:
  - Step-by-step tutorials with code examples
  - Migration paths between versions
  - Best practice recommendations
  - Performance optimization techniques
  - Testing strategies and examples
  - Troubleshooting common issues
  """

  use Igniter.Mix.Task

  @guide_types ~w[getting-started migration best-practices troubleshooting performance testing deployment advanced]

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.docs.guide --all --advanced",
      schema: [
        all: :boolean,
        type: :string,
        output: :string,
        format: :string,
        advanced: :boolean,
        from_version: :string,
        to_version: :string,
        dry_run: :boolean
      ],
      aliases: [
        a: :all,
        t: :type,
        o: :output,
        f: :format
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    {parsed_args, _remaining_args} = OptionParser.parse!(igniter.args.argv, strict: info(igniter.args.argv, nil).schema)
    
    guide_types = cond do
      parsed_args[:all] -> @guide_types
      parsed_args[:type] -> parse_guide_types(parsed_args[:type])
      true -> []
    end

    if Enum.empty?(guide_types) do
      Igniter.add_warning(igniter, """
      No guide types specified. Use one of:
        mix selecto.docs.guide --all
        mix selecto.docs.guide --type=getting-started,migration
      
      Available guide types: #{Enum.join(@guide_types, ", ")}
      """)
    else
      process_guides(igniter, guide_types, parsed_args)
    end
  end

  # Private functions

  defp parse_guide_types(types_str) do
    types_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @guide_types))
  end

  defp process_guides(igniter, guide_types, opts) do
    output_dir = get_output_directory(igniter, opts[:output])
    formats = parse_formats(opts[:format])
    
    if opts[:dry_run] do
      show_dry_run_summary(guide_types, output_dir, opts)
      igniter
    else
      Enum.reduce(guide_types, igniter, fn guide_type, acc_igniter ->
        generate_guide(acc_igniter, guide_type, output_dir, formats, opts)
      end)
      |> generate_guides_index(guide_types, output_dir, formats, opts)
    end
  end

  defp get_output_directory(_igniter, custom_output) do
    custom_output || "docs/guides"
  end

  defp parse_formats(format_arg) do
    case format_arg do
      nil -> [:markdown]
      formats_str ->
        formats_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)
        |> Enum.filter(&(&1 in [:markdown, :html]))
    end
  end

  defp show_dry_run_summary(guide_types, output_dir, opts) do
    IO.puts("""
    
    Selecto Guides Generation (DRY RUN)
    ===================================
    
    Output directory: #{output_dir}
    Formats: #{inspect(parse_formats(opts[:format]))}
    Advanced examples: #{opts[:advanced] || false}
    Migration: #{opts[:from_version]} → #{opts[:to_version]}
    
    Guides to generate:
    """)
    
    Enum.each(guide_types, fn guide_type ->
      files = get_guide_files(guide_type, output_dir, parse_formats(opts[:format]))
      
      IO.puts("  • #{guide_type}")
      Enum.each(files, fn file ->
        IO.puts("    → #{file}")
      end)
    end)
    
    IO.puts("""
    
    Additional files:
      → #{output_dir}/index.md (Guides index)
    
    Run without --dry-run to generate guides.
    """)
  end

  defp get_guide_files(guide_type, output_dir, formats) do
    Enum.map(formats, fn format ->
      extension = if format == :markdown, do: ".md", else: ".html"
      Path.join(output_dir, "#{guide_type}#{extension}")
    end)
  end

  defp generate_guide(igniter, guide_type, output_dir, formats, opts) do
    igniter
    |> ensure_directory_exists(output_dir)
    |> generate_guide_content(guide_type, output_dir, formats, opts)
    |> add_success_message("Generated #{guide_type} guide")
  end

  defp generate_guides_index(igniter, guide_types, output_dir, formats, _opts) do
    Enum.reduce(formats, igniter, fn format, acc_igniter ->
      extension = if format == :markdown, do: ".md", else: ".html"
      file_path = Path.join(output_dir, "index#{extension}")
      content = SelectoMix.GuideGenerator.generate_guides_index(guide_types, format)
      Igniter.create_new_file(acc_igniter, file_path, content)
    end)
  end

  defp ensure_directory_exists(igniter, dir_path) do
    Igniter.create_new_file(igniter, Path.join(dir_path, ".gitkeep"), "")
  end

  defp generate_guide_content(igniter, guide_type, output_dir, formats, opts) do
    Enum.reduce(formats, igniter, fn format, acc_igniter ->
      extension = if format == :markdown, do: ".md", else: ".html"
      file_path = Path.join(output_dir, "#{guide_type}#{extension}")
      content = SelectoMix.GuideGenerator.generate_guide(guide_type, format, opts)
      Igniter.create_new_file(acc_igniter, file_path, content)
    end)
  end

  defp add_success_message(igniter, message) do
    Igniter.add_notice(igniter, message)
  end
end