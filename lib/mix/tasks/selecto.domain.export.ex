defmodule Mix.Tasks.Selecto.Domain.Export do
  @shortdoc "Export a normalized Selecto domain JSON artifact"
  @moduledoc """
  Export a normalized Selecto domain JSON artifact.

  The task loads a domain module, calls `domain/0`, normalizes the map through
  `Selecto.Domain.normalize/1`, and writes a JSON artifact containing the
  canonical normalized domain plus diagnostics. Runtime-only terms such as
  function captures are represented as explicit placeholder metadata so the
  artifact remains JSON-safe.

  ## Examples

      mix selecto.domain.export MyApp.SelectoDomains.ProductDomain

      mix selecto.domain.export MyApp.SelectoDomains.ProductDomain --output priv/selecto/product.normalized.json
  """

  use Mix.Task

  alias SelectoMix.DomainExport

  @requirements ["app.start"]
  @switches [output: :string, pretty: :boolean]
  @aliases [o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = SelectoMix.CLI.parse!(args, strict: @switches, aliases: @aliases)

    if positional == [] do
      Mix.raise("Usage: mix selecto.domain.export MyApp.SelectoDomains.ProductDomain")
    else
      export_domain(List.first(positional), opts)
    end
  end

  defp export_domain(domain_module, opts) do
    case DomainExport.export(domain_module) do
      {:ok, artifact} ->
        write_artifact(artifact, opts)

      {:error, reason} ->
        Mix.raise(DomainExport.format_error(reason))
    end
  end

  defp write_artifact(artifact, opts) do
    json = DomainExport.encode!(artifact, pretty: Keyword.get(opts, :pretty, true))

    case Keyword.get(opts, :output) do
      nil ->
        IO.write(json <> "\n")

      output_path ->
        output_path
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(output_path, json <> "\n")
        Mix.shell().info("Wrote normalized domain JSON: #{output_path}")
    end
  end
end
