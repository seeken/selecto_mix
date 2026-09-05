defmodule Mix.Tasks.Selecto.Document.Check do
  @shortdoc "Check local document schema artifacts"
  @moduledoc """
  Check local document JSON artifacts through the host Selecto runtime.

  See `SelectoMix.DocumentCLI` for bounds and the complete local artifact lifecycle.
  This task never starts the host application or opens a database connection.
  """
  use Mix.Task

  @requirements ["compile"]

  @impl Mix.Task
  def run(args), do: SelectoMix.DocumentCLI.run(:check, args)
end
