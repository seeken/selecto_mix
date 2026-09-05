defmodule Mix.Tasks.Selecto.Document.Approve do
  @shortdoc "Approve local document schema artifacts"
  @moduledoc """
  Approve local document JSON artifacts through the host Selecto runtime.

  See `SelectoMix.DocumentCLI` for bounds and the complete local artifact lifecycle.
  This task never starts the host application or opens a database connection.
  """
  use Mix.Task

  @requirements ["compile"]

  @impl Mix.Task
  def run(args), do: SelectoMix.DocumentCLI.run(:approve, args)
end
