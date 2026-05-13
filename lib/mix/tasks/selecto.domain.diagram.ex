defmodule Mix.Tasks.Selecto.Domain.Diagram do
  @shortdoc "Generate a Mermaid diagram from a Selecto domain inspection artifact"
  @moduledoc """
  Generate a Mermaid diagram from a Selecto domain inspection artifact.

  The task reads an inspection JSON artifact produced by
  `mix selecto.domain.describe` and renders a Mermaid flowchart focused on
  source fields, source relationships, choice sources, and picker field
  bindings.

  ## Examples

      mix selecto.domain.diagram priv/selecto/product.inspection.json

      mix selecto.domain.diagram priv/selecto/product.inspection.json --output docs/selecto/product.diagram.mmd
  """

  use Mix.Task

  alias SelectoMix.DomainDiagram

  @requirements ["app.start"]
  @switches [output: :string]
  @aliases [o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    cond do
      invalid != [] ->
        Mix.raise("Invalid option(s): #{format_invalid_options(invalid)}")

      positional == [] ->
        Mix.raise("Usage: mix selecto.domain.diagram priv/selecto/product.inspection.json")

      length(positional) > 1 ->
        Mix.raise("Usage: mix selecto.domain.diagram priv/selecto/product.inspection.json")

      true ->
        diagram_from_inspection(List.first(positional), opts)
    end
  end

  defp diagram_from_inspection(path, opts) do
    case DomainDiagram.render_file(path) do
      {:ok, diagram} ->
        write_diagram(diagram, opts)

      {:error, reason} ->
        Mix.raise(DomainDiagram.format_error(reason))
    end
  end

  defp write_diagram(diagram, opts) do
    case Keyword.get(opts, :output) do
      nil ->
        IO.write(diagram)

      output_path ->
        output_path
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(output_path, diagram)
        Mix.shell().info("Wrote normalized domain Mermaid diagram: #{output_path}")
    end
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
