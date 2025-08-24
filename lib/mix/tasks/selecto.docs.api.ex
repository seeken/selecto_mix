defmodule Mix.Tasks.Selecto.Docs.Api do
  @shortdoc "Generate comprehensive API reference documentation for Selecto"
  @moduledoc """
  Generate comprehensive API reference documentation for the Selecto ecosystem.

  This task creates detailed API documentation including function references,
  type specifications, examples, and integration guides.

  ## Examples

      # Generate API documentation for all modules
      mix selecto.docs.api --all

      # Generate API documentation for specific modules
      mix selecto.docs.api --modules=Selecto,SelectoComponents

      # Include private functions
      mix selecto.docs.api --include-private

      # Generate with examples for each function
      mix selecto.docs.api --with-examples

      # Specify output directory
      mix selecto.docs.api --output docs/api

  ## Options

    * `--all` - Generate API docs for all Selecto modules
    * `--modules` - Comma-separated list of specific modules
    * `--output` - Specify output directory (default: docs/api)
    * `--format` - Output formats: markdown, html, or both (default: markdown)
    * `--include-private` - Include private functions in documentation
    * `--with-examples` - Generate code examples for each function
    * `--with-types` - Include detailed type specifications
    * `--dry-run` - Show what would be generated without creating files

  ## Generated Documentation

  Creates comprehensive API reference including:
  - Module overviews and purposes
  - Function signatures with type specifications
  - Parameter descriptions and examples
  - Return value documentation
  - Usage examples and patterns
  - Related function cross-references
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.docs.api --all --with-examples",
      schema: [
        all: :boolean,
        modules: :string,
        output: :string,
        format: :string,
        include_private: :boolean,
        with_examples: :boolean,
        with_types: :boolean,
        dry_run: :boolean
      ],
      aliases: [
        a: :all,
        m: :modules,
        o: :output,
        f: :format
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    {parsed_args, _remaining_args} = OptionParser.parse!(igniter.args.argv, strict: info(igniter.args.argv, nil).schema)
    
    modules = cond do
      parsed_args[:all] -> discover_selecto_modules(igniter)
      parsed_args[:modules] -> parse_module_list(parsed_args[:modules])
      true -> []
    end

    if Enum.empty?(modules) do
      Igniter.add_warning(igniter, """
      No modules specified. Use one of:
        mix selecto.docs.api --all
        mix selecto.docs.api --modules=Selecto,SelectoComponents
      """)
    else
      process_modules(igniter, modules, parsed_args)
    end
  end

  # Private functions

  defp discover_selecto_modules(igniter) do
    # Find all Selecto-related modules
    igniter
    |> Igniter.Project.Module.find_all_matching_modules(fn module_name ->
      module_str = to_string(module_name)
      String.starts_with?(module_str, "Selecto") or 
      String.starts_with?(module_str, "Mix.Tasks.Selecto")
    end)
    |> Enum.filter(&is_public_api_module/1)
  end

  defp parse_module_list(modules_str) do
    modules_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&Module.concat([&1]))
  end

  defp is_public_api_module(module_name) do
    # Filter out internal/private modules
    module_str = to_string(module_name)
    not (String.contains?(module_str, "Test") or 
         String.contains?(module_str, "Private") or
         String.ends_with?(module_str, "Helpers"))
  end

  defp process_modules(igniter, modules, opts) do
    output_dir = get_output_directory(igniter, opts[:output])
    formats = parse_formats(opts[:format])
    
    if opts[:dry_run] do
      show_dry_run_summary(modules, output_dir, opts)
      igniter
    else
      Enum.reduce(modules, igniter, fn module, acc_igniter ->
        generate_api_docs_for_module(acc_igniter, module, output_dir, formats, opts)
      end)
      |> generate_api_index(modules, output_dir, formats, opts)
    end
  end

  defp get_output_directory(_igniter, custom_output) do
    custom_output || "docs/api"
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

  defp show_dry_run_summary(modules, output_dir, opts) do
    IO.puts("""
    
    Selecto API Documentation Generation (DRY RUN)
    ==============================================
    
    Output directory: #{output_dir}
    Formats: #{inspect(parse_formats(opts[:format]))}
    Include private: #{opts[:include_private] || false}
    With examples: #{opts[:with_examples] || false}
    With types: #{opts[:with_types] || false}
    
    Modules to document:
    """)
    
    Enum.each(modules, fn module ->
      files = get_api_doc_files(module, output_dir, parse_formats(opts[:format]))
      
      IO.puts("  • #{module}")
      Enum.each(files, fn file ->
        IO.puts("    → #{file}")
      end)
    end)
    
    IO.puts("""
    
    Additional files:
      → #{output_dir}/index.md (API index)
      → #{output_dir}/types.md (Type reference)
    
    Run without --dry-run to generate API documentation.
    """)
  end

  defp get_api_doc_files(module, output_dir, formats) do
    module_name = module |> to_string() |> String.replace("Elixir.", "") |> Macro.underscore()
    
    Enum.map(formats, fn format ->
      extension = if format == :markdown, do: ".md", else: ".html"
      Path.join(output_dir, "#{module_name}#{extension}")
    end)
  end

  defp generate_api_docs_for_module(igniter, module, output_dir, formats, opts) do
    igniter
    |> ensure_directory_exists(output_dir)
    |> generate_module_documentation(module, output_dir, formats, opts)
    |> add_success_message("Generated API documentation for #{module}")
  end

  defp generate_api_index(igniter, modules, output_dir, formats, _opts) do
    Enum.reduce(formats, igniter, fn format, acc_igniter ->
      extension = if format == :markdown, do: ".md", else: ".html"
      file_path = Path.join(output_dir, "index#{extension}")
      content = SelectoMix.ApiDocsGenerator.generate_api_index(modules, format)
      Igniter.create_new_file(acc_igniter, file_path, content)
    end)
  end

  defp ensure_directory_exists(igniter, dir_path) do
    Igniter.create_new_file(igniter, Path.join(dir_path, ".gitkeep"), "")
  end

  defp generate_module_documentation(igniter, module, output_dir, formats, opts) do
    Enum.reduce(formats, igniter, fn format, acc_igniter ->
      extension = if format == :markdown, do: ".md", else: ".html"
      module_name = module |> to_string() |> String.replace("Elixir.", "") |> Macro.underscore()
      file_path = Path.join(output_dir, "#{module_name}#{extension}")
      content = SelectoMix.ApiDocsGenerator.generate_module_docs(module, format, opts)
      Igniter.create_new_file(acc_igniter, file_path, content)
    end)
  end

  defp add_success_message(igniter, message) do
    Igniter.add_notice(igniter, message)
  end
end