defmodule SelectoMix.Gen.Api.Paths do
  @moduledoc false

  def for(config, :api_module) do
    "lib/#{config.app}/updato_api/#{config.name_snake}_api.ex"
  end

  def for(config, :controller) do
    "lib/#{config.app}_web/controllers/#{config.name_snake}_api_controller.ex"
  end

  def for(config, :control_panel_live) do
    "lib/#{config.app}_web/live/#{config.name_snake}_api_control_panel_live.ex"
  end
end
