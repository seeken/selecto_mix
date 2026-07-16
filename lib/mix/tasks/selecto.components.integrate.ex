defmodule Mix.Tasks.Selecto.Components.Integrate do
  @shortdoc "Integrate SelectoComponents hooks and styles into your Phoenix app"
  @moduledoc """
  Automatically configures SelectoComponents JavaScript hooks and Tailwind styles in your Phoenix application.

  This task patches your `app.js` and `app.css` files to include:
  - SelectoComponents colocated JavaScript hooks
  - Tailwind CSS @source directive for SelectoComponents styles

  ## Usage

      mix selecto.components.integrate

  ## What it does

  1. **Updates assets/js/app.js**:
     - Adds import for SelectoComponents hooks
     - Configures hooks in your LiveSocket

  2. **Updates assets/css/app.css**:
     - Adds @source directive for SelectoComponents styles

  The task is idempotent - running it multiple times is safe.

  ## Options

    * `--check` - Check if integration is needed without making changes
    * `--force` - Force re-integration even if already configured

  ## Examples

      # Integrate SelectoComponents
      mix selecto.components.integrate

      # Check if integration is needed
      mix selecto.components.integrate --check

      # Force re-integration
      mix selecto.components.integrate --force
  """

  use Mix.Task

  alias SelectoMix.ComponentsIntegrate

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [check: :boolean, force: :boolean])
    ComponentsIntegrate.run(opts)
  end

  @doc false
  def selecto_components_source_path(cwd \\ File.cwd!(), deps \\ nil) do
    ComponentsIntegrate.selecto_components_source_path(cwd, deps)
  end

  @doc false
  def patch_app_css(content, selecto_path \\ ComponentsIntegrate.selecto_components_source_path()) do
    ComponentsIntegrate.patch_app_css(content, selecto_path)
  end
end
