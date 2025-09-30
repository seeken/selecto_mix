defmodule Mix.Tasks.Selecto.Gen.SavedViewsDisplay do
  use Mix.Task

  @shortdoc "Insert Saved Views list next to the Toggle View Controller button"

  def run(_args) do
    target = "lib/selecto_test_web/live/pagila_live.html.heex"

    case File.read(target) do
      {:ok, content} ->
        if String.contains?(content, "flex items-center") do
          Mix.shell().info("Saved Views display already appears to be inline. No changes made.")
        else
          old = "<.button phx-click=\"toggle_show_view_configurator\">Toggle View Controller</.button>\n\n\nSaved Views:\n<.intersperse :let={v} enum={@available_saved_views}>\n  <:separator>,\n  </:separator>\n  <.link href={\"#\{@path\}?saved_view=\#{v}\"} > [<%= v %>] </.link>\n</.intersperse>\n\n"

          replacement = "<div class=\"flex items-center space-x-4\">\n  <.button phx-click=\"toggle_show_view_configurator\">Toggle View Controller</.button>\n  <div class=\"ml-4\">Saved Views:\n    <.intersperse :let={v} enum={@available_saved_views}>\n      <:separator>,\n      </:separator>\n      <.link href={\"#\{@path\}?saved_view=\#{v}\"} > [<%= v %>] </.link>\n    </.intersperse>\n  </div>\n</div>\n\n"

          if String.contains?(content, old) do
            new_content = String.replace(content, old, replacement)
            File.write!(target, new_content)
            Mix.shell().info("Inserted inline Saved Views display into #{target}")
          else
            Mix.shell().info("Target pattern not found in #{target}. No changes made.")
          end
        end

      {:error, reason} ->
        Mix.shell().error("Failed to read #{target}: #{inspect(reason)}")
    end
  end
end
