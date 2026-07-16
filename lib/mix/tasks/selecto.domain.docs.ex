defmodule Mix.Tasks.Selecto.Domain.Docs do
  @shortdoc "Generate Markdown docs from a normalized Selecto domain JSON artifact"
  @moduledoc """
  Generate Markdown docs from a normalized Selecto domain JSON artifact.

  The task reads an artifact produced by `mix selecto.domain.export`, verifies
  it the same way `mix selecto.domain.check` does, and renders a compact
  Markdown reference for sections, counts, source fields, schemas, registries,
  query members, capability usage, and diagnostics.

  ## Examples

      mix selecto.domain.docs priv/selecto/product.normalized.json

      mix selecto.domain.docs priv/selecto/product.normalized.json --output docs/selecto/product.md
  """

  use Mix.Task

  alias SelectoMix.{DomainDocs, DomainExport}

  @requirements ["app.start"]
  @switches [output: :string]
  @aliases [o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = SelectoMix.CLI.parse!(args, strict: @switches, aliases: @aliases)

    cond do
      positional == [] ->
        Mix.raise("Usage: mix selecto.domain.docs priv/selecto/product.normalized.json")

      length(positional) > 1 ->
        Mix.raise("Usage: mix selecto.domain.docs priv/selecto/product.normalized.json")

      true ->
        docs_from_artifact(List.first(positional), opts)
    end
  end

  defp docs_from_artifact(path, opts) do
    case DomainDocs.render_file(path) do
      {:ok, markdown} ->
        write_docs(markdown, opts)

      {:error, reason} ->
        Mix.raise(DomainExport.format_error(reason))
    end
  end

  defp write_docs(markdown, opts) do
    case Keyword.get(opts, :output) do
      nil ->
        IO.write(markdown)

      output_path ->
        output_path
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(output_path, markdown)
        Mix.shell().info("Wrote normalized domain Markdown docs: #{output_path}")
    end
  end
end
