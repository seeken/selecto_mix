defmodule Mix.Tasks.Selecto.Views.Integrate do
  @shortdoc "Integrate SelectoViews hooks into your Phoenix app"
  @moduledoc """
  Configures the SelectoViews colocated JavaScript hooks in your Phoenix
  application.

  ## Usage

      mix selecto.views.integrate

  ## What it does

  1. **Updates assets/js/app.js**:
     - Adds the import for the SelectoViews hooks
     - Merges the hooks into your LiveSocket
     - Exposes Chart.js as `window.Chart` for the graph view

  2. **Updates assets/package.json**:
     - Adds Chart.js when it is missing

  SelectoViews ships its own stylesheet, so no Tailwind configuration is
  needed. The task prints the `Plug.Static` snippet that serves it from your
  endpoint.

  The task is idempotent - running it multiple times is safe.

  ## Options

    * `--check` - Check if integration is needed without making changes
    * `--force` - Force re-integration even if already configured
  """

  use Mix.Task

  alias SelectoMix.ViewsIntegrate

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [check: :boolean, force: :boolean])
    ViewsIntegrate.run(opts)
  end
end
