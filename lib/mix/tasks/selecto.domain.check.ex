defmodule Mix.Tasks.Selecto.Domain.Check do
  @shortdoc "Check a normalized Selecto domain JSON artifact"
  @moduledoc """
  Check a normalized Selecto domain JSON artifact.

  The task reads a JSON artifact produced by `mix selecto.domain.export`,
  verifies the artifact envelope, decodes the embedded normalized domain, and
  runs it back through `Selecto.Domain.normalize/1`.

  ## Examples

      mix selecto.domain.check priv/selecto/product.normalized.json
  """

  use Mix.Task

  alias SelectoMix.DomainExport

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: [])

    cond do
      invalid != [] ->
        Mix.raise("Invalid option(s): #{format_invalid_options(invalid)}")

      opts != [] ->
        Mix.raise("Invalid option(s): #{format_invalid_options(opts)}")

      positional == [] ->
        Mix.raise("Usage: mix selecto.domain.check priv/selecto/product.normalized.json")

      true ->
        check_artifact(List.first(positional))
    end
  end

  defp check_artifact(path) do
    case DomainExport.check_file(path) do
      {:ok, check} ->
        print_check(path, check)

      {:error, reason} ->
        Mix.raise(DomainExport.format_error(reason))
    end
  end

  defp print_check(path, check) do
    diagnostics = Map.fetch!(check, :diagnostics)
    errors = diagnostics |> diagnostic_items(:errors) |> length()
    warnings = diagnostics |> diagnostic_items(:warnings) |> length()

    Mix.shell().info("Checked normalized domain JSON: #{path}")
    Mix.shell().info("Format: selecto.normalized_domain v1")
    Mix.shell().info("Domain module: #{Map.get(check, :domain_module) || "(unknown)"}")
    Mix.shell().info("Schema version: #{Map.get(check, :schema_version) || "(unknown)"}")
    Mix.shell().info("Domain version: #{Map.get(check, :domain_version) || "(unversioned)"}")

    Mix.shell().info(
      "Domain fingerprint: #{Map.get(check, :domain_fingerprint) || "(unfingerprinted)"}"
    )

    Mix.shell().info("Diagnostics: #{errors} errors, #{warnings} warnings")
  end

  defp diagnostic_items(diagnostics, key) when is_map(diagnostics) do
    Map.get(diagnostics, key) || Map.get(diagnostics, Atom.to_string(key)) || []
  end

  defp diagnostic_items(_diagnostics, _key), do: []

  defp format_invalid_options(invalid) do
    invalid
    |> Enum.map(fn
      {switch, nil} -> switch
      {switch, value} -> "#{switch} #{value}"
    end)
    |> Enum.join(", ")
  end
end
