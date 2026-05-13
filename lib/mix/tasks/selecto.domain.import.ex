defmodule Mix.Tasks.Selecto.Domain.Import do
  @shortdoc "Check or write a normalized Selecto domain import preview"
  @moduledoc """
  Check or write a normalized Selecto domain import preview.

  `--check` verifies the artifact and reports what SelectoMix can reconstruct.
  `--write` writes the generated module only when the source preview parses,
  defines the expected target module, exposes `domain/0`, and contains no
  runtime placeholders.

  ## Examples

      mix selecto.domain.import priv/selecto/product.normalized.json --check

      mix selecto.domain.import priv/selecto/product.normalized.json --check --target-module MyApp.SelectoDomains.ProductDomain

      mix selecto.domain.import priv/selecto/product.normalized.json --check --source

      mix selecto.domain.import priv/selecto/product.normalized.json --write --target-file lib/my_app/selecto_domains/product_domain.ex
  """

  use Mix.Task

  alias SelectoMix.DomainImport

  @requirements ["app.start"]
  @switches [
    check: :boolean,
    force: :boolean,
    format: :string,
    output_dir: :string,
    source: :boolean,
    target_file: :string,
    target_module: :string,
    write: :boolean
  ]
  @aliases [c: :check, f: :force, w: :write]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)
    check? = Keyword.get(opts, :check, false)
    write? = Keyword.get(opts, :write, false)

    cond do
      invalid != [] ->
        Mix.raise("Invalid option(s): #{format_invalid_options(invalid)}")

      positional == [] ->
        Mix.raise(import_usage())

      length(positional) > 1 ->
        Mix.raise(import_usage())

      check? and write? ->
        Mix.raise("Choose either --check or --write, not both.")

      not check? and not write? ->
        Mix.raise(import_usage())

      check? ->
        check_import(List.first(positional), opts)

      true ->
        write_import(List.first(positional), opts)
    end
  end

  defp check_import(path, opts) do
    case DomainImport.plan_file(path, opts) do
      {:ok, plan} ->
        print_plan(plan, opts)

      {:error, reason} ->
        Mix.raise(DomainImport.format_error(reason))
    end
  end

  defp write_import(path, opts) do
    case DomainImport.write_file(path, opts) do
      {:ok, plan} ->
        print_write(plan, opts)

      {:error, reason} ->
        Mix.raise(DomainImport.format_error(reason))
    end
  end

  defp print_plan(plan, opts) do
    case Keyword.get(opts, :format, "text") do
      "text" ->
        print_text_plan(plan, opts)

      "json" ->
        IO.write(DomainImport.encode!(plan) <> "\n")

      format ->
        Mix.raise("Unsupported import plan format #{inspect(format)}; expected text or json")
    end
  end

  defp print_write(plan, opts) do
    case Keyword.get(opts, :format, "text") do
      "text" ->
        print_text_write(plan)

      "json" ->
        IO.write(DomainImport.encode!(plan) <> "\n")

      format ->
        Mix.raise("Unsupported import write format #{inspect(format)}; expected text or json")
    end
  end

  defp print_text_plan(plan, opts) do
    source = Map.fetch!(plan, "source")
    runtime_placeholders = Map.fetch!(plan, "runtime_placeholders")
    diagnostics = Map.fetch!(plan, "diagnostics")

    Mix.shell().info("Checked normalized domain import plan: #{Map.get(source, "path")}")
    Mix.shell().info("Mode: check (no files written)")
    Mix.shell().info("Domain module: #{Map.get(source, "domain_module") || "(unknown)"}")
    Mix.shell().info("Schema version: #{Map.get(source, "schema_version") || "(unknown)"}")
    Mix.shell().info("Domain version: #{Map.get(source, "domain_version") || "(unversioned)"}")

    Mix.shell().info(
      "Domain fingerprint: #{Map.get(source, "domain_fingerprint") || "(unfingerprinted)"}"
    )

    Mix.shell().info("Name: #{Map.get(source, "name") || "(unnamed)"}")

    print_preview(Map.fetch!(plan, "preview"), Map.fetch!(plan, "source_preview"))
    print_source_validation(Map.fetch!(plan, "source_validation"))
    print_sections(Map.fetch!(plan, "sections"))
    print_runtime_placeholders(runtime_placeholders)
    print_diagnostics(diagnostics)

    Mix.shell().info("")
    Mix.shell().info("Write status: #{get_in(plan, ["write", "status"])}")
    Mix.shell().info("  #{get_in(plan, ["write", "message"])}")

    if Keyword.get(opts, :source, false) do
      print_source_preview(Map.fetch!(plan, "source_preview"))
    end
  end

  defp print_text_write(plan) do
    write = Map.fetch!(plan, "write")
    validation = Map.fetch!(write, "source_validation")

    Mix.shell().info(
      "Wrote normalized domain import preview: #{Map.fetch!(write, "target_file")}"
    )

    Mix.shell().info("Target module: #{Map.fetch!(write, "target_module")}")
    Mix.shell().info("Source validation: #{Map.get(validation, "syntax")}")
    Mix.shell().info("domain/0 present: #{Map.get(validation, "domain_function_present")}")
    Mix.shell().info("Runtime placeholders: #{Map.get(validation, "runtime_placeholder_count")}")
    Mix.shell().info("Bytes: #{Map.fetch!(write, "bytes")}")
    Mix.shell().info("Overwrote: #{Map.fetch!(write, "overwrote")}")
  end

  defp print_preview(preview, source_preview) do
    Mix.shell().info("")
    Mix.shell().info("Generated-domain preview:")
    Mix.shell().info("  status: #{Map.get(preview, "status")}")
    Mix.shell().info("  target module: #{Map.get(preview, "target_module")}")
    Mix.shell().info("  target file: #{Map.get(preview, "target_file")}")
    Mix.shell().info("  domain function: #{Map.get(preview, "domain_function")}")
    Mix.shell().info("  render strategy: #{Map.get(preview, "render_strategy")}")
    Mix.shell().info("  write enabled: #{Map.get(preview, "write_enabled")}")

    Mix.shell().info(
      "  reconstructable sections: #{format_list(Map.get(preview, "reconstructable_sections", []))}"
    )

    Mix.shell().info(
      "  partial sections: #{format_list(Map.get(preview, "partial_sections", []))}"
    )

    Mix.shell().info(
      "  preserved unmodeled sections: #{format_list(Map.get(preview, "preserved_unmodeled_sections", []))}"
    )

    Mix.shell().info(
      "  security review sections: #{format_security_sections(Map.get(preview, "security_sensitive_sections", []))}"
    )

    Mix.shell().info(
      "  source preview: #{Map.get(source_preview, "line_count")} lines (use --source to print)"
    )
  end

  defp print_source_preview(source_preview) do
    Mix.shell().info("")
    Mix.shell().info("Elixir source preview:")
    IO.write(Map.fetch!(source_preview, "content"))
  end

  defp print_source_validation(validation) do
    Mix.shell().info("")
    Mix.shell().info("Source preview validation:")
    Mix.shell().info("  syntax: #{Map.get(validation, "syntax")}")
    Mix.shell().info("  module: #{Map.get(validation, "module") || "(unknown)"}")
    Mix.shell().info("  target module match: #{Map.get(validation, "target_module_match")}")
    Mix.shell().info("  domain/0 present: #{Map.get(validation, "domain_function_present")}")

    Mix.shell().info(
      "  runtime placeholders blocking: #{Map.get(validation, "runtime_placeholders_blocking")} (#{Map.get(validation, "runtime_placeholder_count")})"
    )

    Mix.shell().info("  write ready: #{Map.get(validation, "write_ready")}")
  end

  defp print_sections(sections) do
    Mix.shell().info("")
    Mix.shell().info("Sections to reconstruct:")

    sections
    |> Enum.group_by(&Map.get(&1, "class", "unclassified"))
    |> Enum.sort_by(fn {class, _items} -> class_order(class) end)
    |> Enum.each(fn {class, items} ->
      Mix.shell().info("  #{class}:")

      items
      |> Enum.sort_by(&Map.get(&1, "name"))
      |> Enum.each(fn section ->
        Mix.shell().info(
          "    #{Map.get(section, "name")}: #{Map.get(section, "count")} (#{Map.get(section, "status")})"
        )
      end)
    end)
  end

  defp print_runtime_placeholders(runtime_placeholders) do
    Mix.shell().info("")
    Mix.shell().info("Runtime placeholders: #{Map.get(runtime_placeholders, "count", 0)}")

    runtime_placeholders
    |> Map.get("by_type", %{})
    |> Enum.sort_by(fn {type, _count} -> type end)
    |> Enum.each(fn {type, count} ->
      Mix.shell().info("  #{type}: #{count}")
    end)

    runtime_placeholders
    |> Map.get("paths", [])
    |> Enum.take(10)
    |> Enum.each(fn placeholder ->
      Mix.shell().info("  #{Map.get(placeholder, "path")} (#{Map.get(placeholder, "type")})")
    end)
  end

  defp print_diagnostics(diagnostics) do
    Mix.shell().info("")
    Mix.shell().info("Diagnostics:")
    print_diagnostic_summary("artifact", Map.fetch!(diagnostics, "artifact"))
    print_diagnostic_summary("current", Map.fetch!(diagnostics, "current"))
  end

  defp print_diagnostic_summary(label, diagnostics) do
    Mix.shell().info(
      "  #{label}: #{Map.get(diagnostics, "errors", 0)} errors, #{Map.get(diagnostics, "warnings", 0)} warnings"
    )
  end

  defp class_order("canonical"), do: 0
  defp class_order("projection"), do: 1
  defp class_order("proposed"), do: 2
  defp class_order("unknown"), do: 3
  defp class_order(_class), do: 4

  defp format_list([]), do: "(none)"
  defp format_list(values), do: Enum.join(values, ", ")

  defp format_security_sections([]), do: "(none)"

  defp format_security_sections(sections) do
    sections
    |> Enum.map(fn section ->
      "#{Map.fetch!(section, "name")} (#{Map.fetch!(section, "status")})"
    end)
    |> Enum.join(", ")
  end

  defp format_invalid_options(invalid) do
    invalid
    |> Enum.map(fn
      {switch, nil} -> switch
      {switch, value} -> "#{switch} #{value}"
    end)
    |> Enum.join(", ")
  end

  defp import_usage do
    "Usage: mix selecto.domain.import priv/selecto/product.normalized.json --check or --write"
  end
end
