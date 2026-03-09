defmodule Mix.Tasks.Selecto.Gen.UpdatoApi do
  @moduledoc """
  Compatibility alias for `mix selecto.gen.api`.

  This keeps the legacy command available for existing scripts and docs.

  ## Usage

      mix selecto.gen.updato_api orders --domain MyApp.OrdersDomain

  All args/options are forwarded to `mix selecto.gen.api`.
  """

  use Mix.Task

  @shortdoc "Deprecated alias for selecto.gen.api"
  @delegate_task "selecto.gen.api"

  @impl Mix.Task
  def run(args) do
    Mix.Task.load_all()
    Mix.shell().info("`mix selecto.gen.updato_api` is deprecated; use `mix selecto.gen.api`.")
    Mix.Task.reenable(@delegate_task)
    Mix.Task.run(@delegate_task, args)
  end
end
