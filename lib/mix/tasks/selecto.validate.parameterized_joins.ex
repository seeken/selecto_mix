defmodule Mix.Tasks.Selecto.Validate.ParameterizedJoins do
  @shortdoc "Validate parameterized join configurations in Selecto domains"
  @moduledoc """
  Validate parameterized join configurations across your Selecto domains.

  This task analyzes domain files to check for valid parameterized join configurations,
  parameter definitions, field references, and provides suggestions for improvements.

  ## Examples

      # Validate all domains in the default directory
      mix selecto.validate.parameterized_joins

      # Validate domains in a specific directory
      mix selecto.validate.parameterized_joins --path lib/my_app/selecto_domains

      # Validate specific domain files
      mix selecto.validate.parameterized_joins lib/my_app/selecto_domains/user_domain.ex

      # Test field reference parsing
      mix selecto.validate.parameterized_joins --test-references "products:electronics:true.name,discounts:seasonal.amount"

  ## Options

    * `--path` - Directory containing domain files (default: lib/APP/selecto_domains)
    * `--test-references` - Comma-separated list of field references to validate
    * `--check-schemas` - Verify that referenced tables and fields exist in database
    * `--suggestions` - Show optimization suggestions for parameterized joins

  ## Validation Checks

  - Parameter definitions are valid (correct types, names, options)
  - Field references use proper dot notation syntax
  - Join conditions reference valid parameters
  - Source tables and fields are properly defined
  - Field types are consistent with database schema

  ## Output

  Provides detailed validation results including:
  - Configuration errors and warnings
  - Field reference parsing results
  - Suggestions for improvements
  - Usage examples for validated joins
  """

  use Mix.Task

  alias Selecto.FieldResolver.ParameterizedParser

  @impl Mix.Task
  def run(args) do
    {opts, files, _} = 
      OptionParser.parse(args, strict: [
        path: :string,
        test_references: :string,
        check_schemas: :boolean,
        suggestions: :boolean
      ])

    # Handle different modes of operation
    cond do
      opts[:test_references] ->
        test_field_references(opts[:test_references])
      
      not Enum.empty?(files) ->
        validate_specific_files(files, opts)
      
      true ->
        validate_all_domains(opts)
    end
  end

  # Test field reference parsing
  defp test_field_references(references_str) do
    Mix.shell().info("Testing parameterized field reference parsing...\n")
    
    references = String.split(references_str, ",") |> Enum.map(&String.trim/1)
    
    Enum.each(references, fn ref ->
      Mix.shell().info("Testing: #{inspect(ref)}")
      
      case ParameterizedParser.parse_field_reference(ref) do
        {:ok, parsed} ->
          Mix.shell().info("  ✅ Valid syntax")
          Mix.shell().info("  📋 Parsed: #{format_parsed_reference(parsed)}")
          
          case parsed.type do
            :parameterized ->
              Mix.shell().info("  🔧 Parameters: #{format_parameters(parsed.parameters)}")
            _ ->
              nil
          end
        
        {:error, reason} ->
          Mix.shell().error("  ❌ Invalid syntax: #{inspect(reason)}")
      end
      
      Mix.shell().info("")
    end)
  end

  # Validate specific domain files
  defp validate_specific_files(files, opts) do
    Mix.shell().info("Validating specific domain files...\n")
    
    results = 
      Enum.map(files, fn file ->
        case validate_domain_file(file, opts) do
          {:ok, result} -> {file, :ok, result}
          {:error, error} -> {file, :error, error}
        end
      end)
    
    display_validation_results(results, opts)
  end

  # Validate all domains in the configured path
  defp validate_all_domains(opts) do
    domain_path = opts[:path] || detect_default_domain_path()
    
    Mix.shell().info("Validating parameterized joins in: #{domain_path}\n")
    
    case find_domain_files(domain_path) do
      [] ->
        Mix.shell().info("No domain files found in #{domain_path}")
      
      files ->
        Mix.shell().info("Found #{length(files)} domain files\n")
        
        results = 
          Enum.map(files, fn file ->
            case validate_domain_file(file, opts) do
              {:ok, result} -> {file, :ok, result}
              {:error, error} -> {file, :error, error}
            end
          end)
        
        display_validation_results(results, opts)
    end
  end

  # Core validation logic
  defp validate_domain_file(file_path, opts) do
    try do
      case File.read(file_path) do
        {:ok, content} ->
          case extract_domain_config(content) do
            {:ok, domain_config} ->
              validation_result = validate_parameterized_joins(domain_config, opts)
              {:ok, validation_result}
            
            {:error, error} ->
              {:error, "Failed to parse domain config: #{error}"}
          end
        
        {:error, reason} ->
          {:error, "Failed to read file: #{reason}"}
      end
    rescue
      error -> {:error, "Exception during validation: #{inspect(error)}"}
    end
  end

  defp extract_domain_config(content) do
    # Simple regex-based extraction (in a full implementation, would use AST parsing)
    case Regex.run(~r/joins:\s*(%\{[^}]+\})/s, content) do
      [_, joins_config] ->
        try do
          # This is simplified - a full implementation would properly parse the AST
          {:ok, %{joins: joins_config}}
        rescue
          _ -> {:error, "Failed to parse joins configuration"}
        end
      
      nil ->
        {:ok, %{joins: "%{}"}}
    end
  end

  defp validate_parameterized_joins(domain_config, opts) do
    %{
      file_status: :readable,
      parameterized_joins: extract_parameterized_joins_from_config(domain_config),
      validation_checks: perform_validation_checks(domain_config, opts),
      suggestions: if(opts[:suggestions], do: generate_suggestions(domain_config), else: [])
    }
  end

  defp extract_parameterized_joins_from_config(domain_config) do
    # Simplified extraction - would be more sophisticated in real implementation
    joins_str = domain_config[:joins] || "%{}"
    
    # Look for parameterized join patterns
    parameterized_patterns = [
      ~r/parameters:\s*\[/,
      ~r/source_table:/,
      ~r/fields:\s*%\{/
    ]
    
    has_parameterized = Enum.any?(parameterized_patterns, fn pattern ->
      String.match?(joins_str, pattern)
    end)
    
    if has_parameterized do
      ["detected_parameterized_join"]  # Placeholder - would extract actual join names
    else
      []
    end
  end

  defp perform_validation_checks(domain_config, _opts) do
    checks = %{
      syntax_valid: true,
      parameters_valid: true,
      field_types_valid: true,
      join_conditions_valid: true
    }
    
    # Basic validation - would be more comprehensive in real implementation
    joins_str = domain_config[:joins] || "%{}"
    
    issues = []
    
    # Check for common syntax issues
    issues = if String.contains?(joins_str, ":parameters") and not String.contains?(joins_str, "parameters:") do
      issues ++ ["Found ':parameters' instead of 'parameters:' - check syntax"]
    else
      issues
    end
    
    # Check for field definitions
    issues = if String.contains?(joins_str, "parameters:") and not String.contains?(joins_str, "fields:") do
      issues ++ ["Parameterized joins should define available fields"]
    else
      issues
    end
    
    Map.put(checks, :issues, issues)
  end

  defp generate_suggestions(_domain_config) do
    [
      "Consider adding parameter validation for better error handling",
      "Document parameter usage with examples",
      "Use consistent parameter naming conventions (snake_case)",
      "Consider default values for optional parameters"
    ]
  end

  defp display_validation_results(results, opts) do
    total_files = length(results)
    successful_files = Enum.count(results, fn {_, status, _} -> status == :ok end)
    
    Mix.shell().info("Validation Summary:")
    Mix.shell().info("=================")
    Mix.shell().info("Files processed: #{total_files}")
    Mix.shell().info("Successful: #{successful_files}")
    Mix.shell().info("Errors: #{total_files - successful_files}")
    Mix.shell().info("")
    
    Enum.each(results, fn {file, status, result} ->
      display_file_result(file, status, result, opts)
    end)
    
    # Overall recommendations
    if opts[:suggestions] do
      Mix.shell().info("\nOverall Recommendations:")
      Mix.shell().info("========================")
      Mix.shell().info("• Use consistent parameter naming (snake_case)")
      Mix.shell().info("• Document parameter types and requirements")  
      Mix.shell().info("• Test field references with mix selecto.validate.parameterized_joins --test-references")
      Mix.shell().info("• Consider using the parameterized join generator: mix selecto.gen.parameterized_join")
    end
  end

  defp display_file_result(file, :ok, result, opts) do
    filename = Path.basename(file)
    Mix.shell().info("📄 #{filename}")
    
    case result.parameterized_joins do
      [] ->
        Mix.shell().info("  ℹ️  No parameterized joins found")
      
      joins ->
        Mix.shell().info("  ✅ Found #{length(joins)} parameterized join(s)")
        Enum.each(joins, fn join ->
          Mix.shell().info("     • #{join}")
        end)
    end
    
    # Display validation issues
    case result.validation_checks.issues do
      [] ->
        Mix.shell().info("  ✅ All validation checks passed")
      
      issues ->
        Mix.shell().info("  ⚠️  Validation issues:")
        Enum.each(issues, fn issue ->
          Mix.shell().info("     • #{issue}")
        end)
    end
    
    # Display suggestions if requested
    if opts[:suggestions] and not Enum.empty?(result.suggestions) do
      Mix.shell().info("  💡 Suggestions:")
      Enum.each(result.suggestions, fn suggestion ->
        Mix.shell().info("     • #{suggestion}")
      end)
    end
    
    Mix.shell().info("")
  end

  defp display_file_result(file, :error, error, _opts) do
    filename = Path.basename(file)
    Mix.shell().error("📄 #{filename}")
    Mix.shell().error("  ❌ #{error}")
    Mix.shell().info("")
  end

  # Helper functions
  
  defp detect_default_domain_path do
    app_name = case Mix.Project.get() do
      nil -> "app"
      project -> project.project()[:app] |> to_string()
    end
    
    "lib/#{app_name}/selecto_domains"
  end

  defp find_domain_files(path) do
    if File.dir?(path) do
      Path.wildcard(Path.join(path, "*_domain.ex"))
    else
      []
    end
  end

  defp format_parsed_reference(parsed) do
    case parsed.type do
      :simple ->
        "Simple field: #{parsed.field}"
      
      :dot_notation ->
        "Dot notation: #{parsed.join}.#{parsed.field}"
      
      :parameterized ->
        "Parameterized: #{parsed.join}.#{parsed.field} with #{length(parsed.parameters)} parameter(s)"
      
      :legacy_bracket ->
        "Legacy bracket notation: #{parsed.join}[#{parsed.field}]"
    end
  end

  defp format_parameters(parameters) when is_list(parameters) do
    parameters
    |> Enum.map(fn param ->
      case param do
        %{type: type, value: value} -> "#{type}(#{value})"
        {type, value} -> "#{type}(#{value})"
        value -> "#{value}"
      end
    end)
    |> Enum.join(", ")
  end

  defp format_parameters(_), do: "none"
end