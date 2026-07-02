defmodule Mix.Tasks.Selecto.Domain.Verify do
  @shortdoc "Verify consumer domain dependencies against a provider artifact"
  @moduledoc """
  Verify consumer domain dependencies against a provider normalized domain JSON artifact.

  ## Examples

      mix selecto.domain.verify priv/selecto/billing.normalized.json priv/selecto/registration.normalized.json
  """

  use Mix.Task

  alias SelectoMix.DomainContractVerification

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: [])

    cond do
      invalid != [] ->
        Mix.raise("Invalid option(s): #{format_invalid_options(invalid)}")

      opts != [] ->
        Mix.raise("Invalid option(s): #{format_invalid_options(opts)}")

      length(positional) != 2 ->
        Mix.raise(
          "Usage: mix selecto.domain.verify provider.normalized.json consumer.normalized.json"
        )

      true ->
        [provider_path, consumer_path] = positional
        verify(provider_path, consumer_path)
    end
  end

  defp verify(provider_path, consumer_path) do
    case DomainContractVerification.verify_files(provider_path, consumer_path) do
      {:ok, report} ->
        print_report(report)

      {:error, %{errors: _errors} = report} ->
        print_report(report)
        Mix.raise(DomainContractVerification.format_error(report))

      {:error, reason} ->
        Mix.raise(DomainContractVerification.format_error(reason))
    end
  end

  defp print_report(report) do
    Mix.shell().info("Domain contract verification")
    Mix.shell().info("Provider: #{identity_name(Map.fetch!(report, :provider))}")
    Mix.shell().info("Consumer: #{identity_name(Map.fetch!(report, :consumer))}")

    dependencies = Map.get(report, :dependencies, [])
    Mix.shell().info("Dependencies: #{length(dependencies)}")

    Enum.each(dependencies, fn dependency ->
      errors = Map.get(dependency, :errors, [])
      status = if errors == [], do: "ok", else: "#{length(errors)} error(s)"
      Mix.shell().info("  #{Map.get(dependency, :contract) || "(missing contract)"}: #{status}")

      Enum.each(errors, fn error ->
        Mix.shell().info("    - #{Map.get(error, :code)}: #{Map.get(error, :message)}")
      end)
    end)

    Mix.shell().info("Errors: #{length(Map.get(report, :errors, []))}")
    Mix.shell().info("Warnings: #{length(Map.get(report, :warnings, []))}")
  end

  defp identity_name(identity) do
    Map.get(identity, :name) || Map.get(identity, "name") || "(unnamed)"
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
