defmodule Mix.Tasks.Selecto.Gen.UpdatoApi do
  @moduledoc """
  Wrapper task for `mix selecto_api.gen.api`.

  This keeps Updato API scaffolding under the `selecto.gen.*` namespace for
  app projects that already use `selecto_mix` tasks.

  ## Usage

      mix selecto.gen.updato_api orders --domain MyApp.OrdersDomain

  All args/options are forwarded to `mix selecto_api.gen.api`.

  ## Requirements

  Your project must include `:selecto_api` in `mix.exs` deps so the
  delegated task is available.
  """

  use Mix.Task

  @shortdoc "Delegates to selecto_api API generator"
  @delegate_task "selecto_api.gen.api"

  @impl Mix.Task
  def run(args) do
    Mix.Task.load_all()

    if task_available?(@delegate_task) do
      Mix.Task.reenable(@delegate_task)
      Mix.Task.run(@delegate_task, args)
    else
      Mix.raise(missing_task_message())
    end
  end

  defp task_available?(task_name) when is_binary(task_name) do
    not is_nil(Mix.Task.get(task_name))
  end

  defp missing_task_message do
    """
    Could not find `mix #{@delegate_task}`.

    Add `:selecto_api` to your dependencies and fetch deps, for example:

        {:selecto_api, "~> 0.1"}

    Then run:

        mix deps.get
        mix selecto.gen.updato_api orders --domain MyApp.OrdersDomain
    """
  end
end
