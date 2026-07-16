defmodule Mix.Tasks.Selecto.Domain.Contract.Snapshot do
  @shortdoc "Write a published domain contract snapshot"
  @moduledoc """
  Write a published domain contract snapshot from a normalized domain JSON artifact.

  ## Examples

      mix selecto.domain.contract.snapshot priv/selecto/billing.normalized.json --output priv/selecto_contracts/billing.snapshot.json
  """

  use Mix.Task

  alias SelectoMix.DomainContractVerification

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = SelectoMix.CLI.parse!(args, strict: [output: :string])

    cond do
      length(positional) != 1 ->
        Mix.raise(
          "Usage: mix selecto.domain.contract.snapshot provider.normalized.json --output provider.snapshot.json"
        )

      is_nil(opts[:output]) ->
        Mix.raise("Missing required --output provider.snapshot.json")

      true ->
        write_snapshot(List.first(positional), opts[:output])
    end
  end

  defp write_snapshot(provider_path, output_path) do
    case DomainContractVerification.write_snapshot_file(provider_path, output_path) do
      {:ok, snapshot} ->
        Mix.shell().info("Wrote domain contract snapshot: #{output_path}")
        Mix.shell().info("Provider: #{get_in(snapshot, ["provider", "name"]) || "(unnamed)"}")
        Mix.shell().info("Surfaces: #{length(Map.get(snapshot, "surfaces", []))}")

      {:error, reason} ->
        Mix.raise(DomainContractVerification.format_error(reason))
    end
  end
end
