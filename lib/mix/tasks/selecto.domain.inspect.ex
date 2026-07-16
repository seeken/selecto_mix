defmodule Mix.Tasks.Selecto.Domain.Inspect do
  @shortdoc "Inspect a normalized Selecto domain JSON artifact"
  @moduledoc """
  Inspect a normalized Selecto domain JSON artifact.

  The task reads an artifact produced by `mix selecto.domain.export`, verifies
  it the same way `mix selecto.domain.check` does, and prints a compact summary
  of sections, counts, diagnostics, and registry names across query and
  operational domain sections.

  ## Examples

      mix selecto.domain.inspect priv/selecto/product.normalized.json
  """

  use Mix.Task

  alias SelectoMix.DomainExport

  @requirements ["app.start"]
  @count_order [
    :source_fields,
    :source_columns,
    :schemas,
    :joins,
    :filters,
    :functions,
    :query_members,
    :published_views,
    :detail_actions,
    :write_operations,
    :write_fields,
    :write_relationships,
    :write_transitions,
    :write_validations,
    :write_constraints,
    :write_scope,
    :write_hooks,
    :actions,
    :capabilities,
    :source_relationships,
    :choice_sources
  ]
  @registry_order [
    :joins,
    :filters,
    :functions,
    :query_members,
    :published_views,
    :detail_actions,
    :write_operations,
    :write_fields,
    :write_relationships,
    :write_transitions,
    :write_scope,
    :write_hooks,
    :actions,
    :capabilities,
    :source_relationships,
    :choice_sources
  ]

  @impl Mix.Task
  def run(args) do
    {_opts, positional} = SelectoMix.CLI.parse!(args, strict: [])

    if positional == [] do
      Mix.raise("Usage: mix selecto.domain.inspect priv/selecto/product.normalized.json")
    else
      inspect_artifact(List.first(positional))
    end
  end

  defp inspect_artifact(path) do
    case DomainExport.summary_file(path) do
      {:ok, summary} ->
        print_summary(summary)

      {:error, reason} ->
        Mix.raise(DomainExport.format_error(reason))
    end
  end

  defp print_summary(summary) do
    Mix.shell().info("Normalized domain artifact: #{Map.get(summary, :path)}")
    Mix.shell().info("Format: #{Map.get(summary, :format)} v#{Map.get(summary, :format_version)}")
    Mix.shell().info("Domain module: #{Map.get(summary, :domain_module) || "(unknown)"}")
    Mix.shell().info("Schema version: #{Map.get(summary, :schema_version) || "(unknown)"}")
    Mix.shell().info("Domain version: #{Map.get(summary, :domain_version) || "(unversioned)"}")

    Mix.shell().info(
      "Domain fingerprint: #{Map.get(summary, :domain_fingerprint) || "(unfingerprinted)"}"
    )

    Mix.shell().info("Name: #{Map.get(summary, :name) || "(unnamed)"}")

    print_sections(Map.fetch!(summary, :sections))
    print_counts(Map.fetch!(summary, :counts))
    print_registries(Map.fetch!(summary, :registries))
    print_security_review(Map.get(summary, :security_review, []))
    print_diagnostics(Map.fetch!(summary, :diagnostics))
  end

  defp print_sections(sections) do
    Mix.shell().info("")
    Mix.shell().info("Sections:")
    Mix.shell().info("  canonical: #{format_list(Map.get(sections, :canonical, []))}")
    Mix.shell().info("  projection: #{format_list(Map.get(sections, :projection, []))}")
    Mix.shell().info("  proposed: #{format_list(Map.get(sections, :proposed, []))}")
    Mix.shell().info("  unknown: #{format_list(Map.get(sections, :unknown, []))}")
  end

  defp print_counts(counts) do
    Mix.shell().info("")
    Mix.shell().info("Counts:")

    Enum.each(@count_order, fn key ->
      Mix.shell().info("  #{format_key(key)}: #{Map.get(counts, key, 0)}")
    end)
  end

  defp print_registries(registries) do
    Mix.shell().info("")
    Mix.shell().info("Registries:")

    Enum.each(@registry_order, fn key ->
      Mix.shell().info("  #{format_key(key)}: #{format_list(Map.get(registries, key, []))}")
    end)
  end

  defp print_security_review([]) do
    Mix.shell().info("")
    Mix.shell().info("Security Review:")
    Mix.shell().info("  (none)")
  end

  defp print_security_review(sections) do
    Mix.shell().info("")
    Mix.shell().info("Security Review:")

    Enum.each(sections, fn section ->
      Mix.shell().info(
        "  #{Map.fetch!(section, :section)}: #{Map.fetch!(section, :count)} (#{format_security_items(Map.fetch!(section, :items))})"
      )

      Mix.shell().info("    #{Map.fetch!(section, :reason)}")
    end)
  end

  defp print_diagnostics(diagnostics) do
    Mix.shell().info("")
    Mix.shell().info("Diagnostics:")
    print_diagnostic_summary("artifact", Map.fetch!(diagnostics, :artifact))
    print_diagnostic_summary("current", Map.fetch!(diagnostics, :current))
  end

  defp print_diagnostic_summary(label, diagnostics) do
    Mix.shell().info(
      "  #{label}: #{Map.get(diagnostics, :errors, 0)} errors, #{Map.get(diagnostics, :warnings, 0)} warnings"
    )

    Mix.shell().info(
      "    warning codes: #{format_list(Map.get(diagnostics, :warning_codes, []))}"
    )

    Mix.shell().info("    error codes: #{format_list(Map.get(diagnostics, :error_codes, []))}")
  end

  defp format_list([]), do: "(none)"

  defp format_list(values) when is_list(values) do
    values
    |> Enum.map(&format_value/1)
    |> Enum.join(", ")
  end

  defp format_list(%{} = value) when map_size(value) == 0, do: "(none)"
  defp format_list(%{} = value), do: value |> Map.keys() |> format_list()
  defp format_list(value), do: format_value(value)

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value), do: inspect(value)

  defp format_security_items(items) when is_map(items) do
    [
      {"operations", format_list(Map.get(items, "operations", []))},
      {"fields", format_list(Map.get(items, "fields", []))},
      {"relationships", format_list(Map.get(items, "relationships", []))},
      {"transitions", format_list(Map.get(items, "transitions", []))},
      {"validations", Map.get(items, "validations_count", 0)},
      {"constraints", Map.get(items, "constraints_count", 0)},
      {"scope", format_list(Map.get(items, "scope", []))},
      {"hooks", format_list(Map.get(items, "hooks", []))}
    ]
    |> Enum.reject(fn {_label, value} -> value in ["(none)", 0] end)
    |> Enum.map(fn {label, value} -> "#{label}: #{value}" end)
    |> Enum.join("; ")
  end

  defp format_security_items(items), do: format_list(items)

  defp format_key(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
