defmodule Mix.Tasks.Selecto.Domain.Diff do
  @shortdoc "Diff two normalized Selecto domain JSON artifacts"
  @moduledoc """
  Diff two normalized Selecto domain JSON artifacts.

  The task reads two artifacts produced by `mix selecto.domain.export`, verifies
  them, and compares section classifications, counts, registry names, and
  diagnostic counts/codes across query and operational domain sections. It also
  reports changed constraint policies for existing choice sources.

  ## Examples

      mix selecto.domain.diff priv/selecto/old.normalized.json priv/selecto/new.normalized.json
  """

  use Mix.Task

  alias SelectoMix.DomainExport

  @requirements ["app.start"]
  @section_order [:canonical, :projection, :proposed, :unknown]
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
    {opts, positional, invalid} = OptionParser.parse(args, strict: [])

    cond do
      invalid != [] ->
        Mix.raise("Invalid option(s): #{format_invalid_options(invalid)}")

      opts != [] ->
        Mix.raise("Invalid option(s): #{format_invalid_options(opts)}")

      length(positional) != 2 ->
        Mix.raise("Usage: mix selecto.domain.diff old.normalized.json new.normalized.json")

      true ->
        [left_path, right_path] = positional
        diff_artifacts(left_path, right_path)
    end
  end

  defp diff_artifacts(left_path, right_path) do
    case DomainExport.diff_files(left_path, right_path) do
      {:ok, diff} ->
        print_diff(diff)

      {:error, reason} ->
        Mix.raise(DomainExport.format_error(reason))
    end
  end

  defp print_diff(diff) do
    Mix.shell().info("Normalized domain artifact diff")
    Mix.shell().info("Left: #{get_in(diff, [:left, :path])}")
    Mix.shell().info("Right: #{get_in(diff, [:right, :path])}")

    if Map.get(diff, :changed?) do
      print_identity(diff)
      print_sections(Map.fetch!(diff, :sections))
      print_counts(Map.fetch!(diff, :counts))
      print_registries(Map.fetch!(diff, :registries))
      print_choice_source_policies(Map.fetch!(diff, :choice_source_policies))
      print_diagnostics(Map.fetch!(diff, :diagnostics))
    else
      Mix.shell().info("No differences found.")
    end
  end

  defp print_identity(diff) do
    Mix.shell().info("")
    Mix.shell().info("Identity:")
    print_value_change("name", get_in(diff, [:left, :name]), get_in(diff, [:right, :name]))

    print_value_change(
      "domain module",
      get_in(diff, [:left, :domain_module]),
      get_in(diff, [:right, :domain_module])
    )

    print_value_change(
      "schema version",
      get_in(diff, [:left, :schema_version]),
      get_in(diff, [:right, :schema_version])
    )

    print_value_change(
      "domain version",
      get_in(diff, [:left, :domain_version]),
      get_in(diff, [:right, :domain_version])
    )

    print_value_change(
      "domain fingerprint",
      get_in(diff, [:left, :domain_fingerprint]),
      get_in(diff, [:right, :domain_fingerprint])
    )
  end

  defp print_sections(sections) do
    Mix.shell().info("")
    Mix.shell().info("Sections:")
    print_list_diffs(sections, @section_order)
  end

  defp print_counts(counts) do
    Mix.shell().info("")
    Mix.shell().info("Counts:")

    changed =
      @count_order
      |> Enum.map(&{&1, Map.get(counts, &1, %{left: 0, right: 0, delta: 0})})
      |> Enum.filter(fn {_key, diff} -> Map.get(diff, :delta, 0) != 0 end)

    case changed do
      [] ->
        Mix.shell().info("  (none)")

      changed ->
        Enum.each(changed, fn {key, diff} ->
          Mix.shell().info(
            "  #{format_key(key)}: #{diff.left} -> #{diff.right} (#{format_delta(diff.delta)})"
          )
        end)
    end
  end

  defp print_registries(registries) do
    Mix.shell().info("")
    Mix.shell().info("Registries:")
    print_list_diffs(registries, @registry_order)
  end

  defp print_diagnostics(diagnostics) do
    Mix.shell().info("")
    Mix.shell().info("Diagnostics:")
    print_diagnostic_diff("artifact", Map.fetch!(diagnostics, :artifact))
    print_diagnostic_diff("current", Map.fetch!(diagnostics, :current))
  end

  defp print_choice_source_policies(%{changed: []}) do
    Mix.shell().info("")
    Mix.shell().info("Choice Source Policies:")
    Mix.shell().info("  (none)")
  end

  defp print_choice_source_policies(%{changed: changed}) do
    Mix.shell().info("")
    Mix.shell().info("Choice Source Policies:")

    Enum.each(changed, fn change ->
      Mix.shell().info(
        "  #{Map.fetch!(change, :id)}: #{policy_value(Map.fetch!(change, :left))} -> #{policy_value(Map.fetch!(change, :right))}"
      )
    end)
  end

  defp print_diagnostic_diff(label, diagnostics) do
    Mix.shell().info("  #{label}:")
    print_count_change("errors", Map.fetch!(diagnostics, :errors))
    print_count_change("warnings", Map.fetch!(diagnostics, :warnings))
    print_named_list_diff("error codes", Map.fetch!(diagnostics, :error_codes))
    print_named_list_diff("warning codes", Map.fetch!(diagnostics, :warning_codes))
  end

  defp print_list_diffs(diff_group, keys) do
    changed =
      keys
      |> Enum.map(&{&1, Map.get(diff_group, &1, %{added: [], removed: []})})
      |> Enum.filter(fn {_key, diff} -> diff.added != [] or diff.removed != [] end)

    case changed do
      [] ->
        Mix.shell().info("  (none)")

      changed ->
        Enum.each(changed, fn {key, diff} ->
          print_named_list_diff(format_key(key), diff)
        end)
    end
  end

  defp print_named_list_diff(label, %{added: [], removed: []}) do
    Mix.shell().info("    #{label}: (none)")
  end

  defp print_named_list_diff(label, diff) do
    Mix.shell().info("    #{label}:")
    Enum.each(diff.added, &Mix.shell().info("      + #{&1}"))
    Enum.each(diff.removed, &Mix.shell().info("      - #{&1}"))
  end

  defp print_count_change(label, %{left: left, right: right, delta: delta}) do
    if delta == 0 do
      Mix.shell().info("    #{label}: (none)")
    else
      Mix.shell().info("    #{label}: #{left} -> #{right} (#{format_delta(delta)})")
    end
  end

  defp print_value_change(label, left, right) do
    if left == right do
      Mix.shell().info("  #{label}: (none)")
    else
      Mix.shell().info("  #{label}: #{left || "(none)"} -> #{right || "(none)"}")
    end
  end

  defp format_delta(delta) when delta > 0, do: "+#{delta}"
  defp format_delta(delta), do: to_string(delta)

  defp policy_value(""), do: "(none)"
  defp policy_value(nil), do: "(none)"
  defp policy_value(value), do: value

  defp format_key(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp format_invalid_options(invalid) do
    invalid
    |> Enum.map(fn
      {switch, nil} -> switch
      {switch, value} -> "#{switch} #{value}"
    end)
    |> Enum.join(", ")
  end
end
