defmodule Mix.Tasks.Selecto.Domain.Describe do
  @shortdoc "Generate Studio inspection JSON from a normalized Selecto domain artifact"
  @moduledoc """
  Generate Studio inspection JSON from a normalized Selecto domain artifact.

  The task reads an artifact produced by `mix selecto.domain.export`, verifies
  it the same way `mix selecto.domain.check` does, and delegates to
  `Selecto.Domain.describe/1` to produce a compact, deterministic inspection
  artifact for Studio and other tools.

  ## Examples

      mix selecto.domain.describe priv/selecto/product.normalized.json

      mix selecto.domain.describe priv/selecto/product.normalized.json --output priv/selecto/product.inspection.json
  """

  use Mix.Task

  alias SelectoMix.DomainInspection

  @requirements ["app.start"]
  @switches [output: :string, pretty: :boolean]
  @aliases [o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = SelectoMix.CLI.parse!(args, strict: @switches, aliases: @aliases)

    cond do
      positional == [] ->
        Mix.raise("Usage: mix selecto.domain.describe priv/selecto/product.normalized.json")

      length(positional) > 1 ->
        Mix.raise("Usage: mix selecto.domain.describe priv/selecto/product.normalized.json")

      true ->
        describe_artifact(List.first(positional), opts)
    end
  end

  defp describe_artifact(path, opts) do
    case DomainInspection.describe_file(path) do
      {:ok, inspection_artifact} ->
        write_inspection(inspection_artifact, opts)

      {:error, reason} ->
        Mix.raise(DomainInspection.format_error(reason))
    end
  end

  defp write_inspection(inspection_artifact, opts) do
    json = DomainInspection.encode!(inspection_artifact, pretty: Keyword.get(opts, :pretty, true))

    case Keyword.get(opts, :output) do
      nil ->
        IO.write(json <> "\n")

      output_path ->
        output_path
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(output_path, json <> "\n")
        Mix.shell().info("Wrote normalized domain inspection JSON: #{output_path}")
    end
  end
end
