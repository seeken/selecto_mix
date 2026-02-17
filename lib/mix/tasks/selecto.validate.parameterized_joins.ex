defmodule Mix.Tasks.Selecto.Validate.ParameterizedJoins do
  @shortdoc "Validate parameterized join configurations in Selecto domains"
  @moduledoc """
  Validate parameterized join configurations across Selecto domain files.

  ## Examples

      mix selecto.validate.parameterized_joins
      mix selecto.validate.parameterized_joins --path lib/my_app/selecto_domains
      mix selecto.validate.parameterized_joins lib/my_app/selecto_domains/user_domain.ex
      mix selecto.validate.parameterized_joins --test-references "products:electronics:true.name,discounts:seasonal.amount"
  """

  use Mix.Task

  alias SelectoMix.ParameterizedJoinsValidator

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          path: :string,
          test_references: :string,
          check_schemas: :boolean,
          suggestions: :boolean
        ]
      )

    cond do
      opts[:test_references] ->
        test_field_references(opts[:test_references])

      files != [] ->
        validate_specific_files(files, opts)

      true ->
        validate_all_domains(opts)
    end
  end

  defp test_field_references(references_str) do
    Mix.shell().info("Testing parameterized field reference parsing...\n")

    references = references_str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    Enum.each(references, fn ref ->
      Mix.shell().info("Testing: #{inspect(ref)}")

      case ParameterizedJoinsValidator.parse_field_reference(ref) do
        {:ok, parsed} ->
          Mix.shell().info("  ✅ Valid syntax")
          Mix.shell().info("  📋 Parsed: #{format_parsed_reference(parsed)}")

          if parsed.parameters != [] do
            Mix.shell().info("  🔧 Parameters: #{format_parameters(parsed.parameters)}")
          end

        {:error, reason} ->
          Mix.shell().error("  ❌ Invalid syntax: #{reason}")
      end

      Mix.shell().info("")
    end)
  end

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

  defp validate_domain_file(file_path, opts) do
    with {:ok, content} <- File.read(file_path),
         {:ok, validation_result} <- ParameterizedJoinsValidator.validate_domain_content(content) do
      {:ok,
       %{
         file_status: :readable,
         parameterized_joins: validation_result.parameterized_joins,
         validation_checks: validation_result.validation_checks,
         suggestions: if(opts[:suggestions], do: generate_suggestions(validation_result), else: [])
       }}
    else
      {:error, reason} ->
        {:error, format_validation_error(reason)}
    end
  rescue
    error ->
      {:error, "Exception during validation: #{inspect(error)}"}
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

    if opts[:suggestions] do
      Mix.shell().info("\nOverall Recommendations:")
      Mix.shell().info("========================")
      Mix.shell().info("• Use explicit parameter types and required flags")
      Mix.shell().info("• Keep join_condition placeholders aligned to declared parameters")
      Mix.shell().info("• Define :fields maps for each parameterized join")
      Mix.shell().info("• Validate references with --test-references before release")
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

    case result.validation_checks.issues do
      [] ->
        Mix.shell().info("  ✅ All validation checks passed")

      issues ->
        Mix.shell().info("  ⚠️  Validation issues:")
        Enum.each(issues, fn issue ->
          Mix.shell().info("     • #{issue}")
        end)
    end

    if opts[:suggestions] == true and result.suggestions != [] do
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

  defp generate_suggestions(validation_result) do
    suggestions = []
    checks = validation_result.validation_checks

    suggestions =
      if !checks.parameters_valid do
        ["Normalize parameter definitions to `%{name: atom, type: atom, required: boolean}`" | suggestions]
      else
        suggestions
      end

    suggestions =
      if !checks.field_types_valid do
        ["Define each join field as `%{type: atom}` with supported Selecto-compatible types" | suggestions]
      else
        suggestions
      end

    suggestions =
      if !checks.join_conditions_valid do
        ["Ensure every `:param_name` in join_condition is declared in `parameters`" | suggestions]
      else
        suggestions
      end

    Enum.reverse(suggestions)
  end

  defp format_validation_error(:joins_not_found), do: "No joins map found in domain file"
  defp format_validation_error(:joins_parse_failed), do: "Failed to parse joins configuration"
  defp format_validation_error(reason), do: inspect(reason)

  defp format_parsed_reference(parsed) do
    case parsed.type do
      :dot_notation ->
        "Dot notation: #{parsed.join}.#{parsed.field}"

      :parameterized ->
        "Parameterized: #{parsed.join}.#{parsed.field} (#{length(parsed.parameters)} parameter(s))"
    end
  end

  defp format_parameters(parameters) when is_list(parameters) do
    parameters
    |> Enum.map(&inspect/1)
    |> Enum.join(", ")
  end

  defp detect_default_domain_path do
    app_name =
      case Mix.Project.get() do
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
end
