defmodule Mix.Tasks.SelectoMix.Install do
  @shortdoc "Install Selecto dependencies"
  @moduledoc """
  Install Selecto ecosystem dependencies (including `:selecto` and
  `:selecto_components`) and run SelectoComponents integration.

  This task is a package-scoped alias of `mix selecto.install` and supports
  `mix igniter.install selecto_mix` installer execution.

  ## Usage

      mix selecto_mix.install
      mix selecto_mix.install --development-mode --source your-fork
      mix selecto_mix.install --postgis
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    Mix.Tasks.Selecto.Install.info([], nil)
  end

  def supports_umbrella?, do: true

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    Mix.Tasks.Selecto.Install.igniter(igniter)
  end
end
