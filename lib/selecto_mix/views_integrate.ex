defmodule SelectoMix.ViewsIntegrate do
  @moduledoc """
  Integrates the SelectoViews colocated JavaScript hooks into a host Phoenix
  application's `assets/js/app.js`.

  SelectoViews ships its own stylesheet (`priv/static/selecto-views.css`), so
  there is no Tailwind `@source` to add. The host serves that file with
  `Plug.Static`; `run/1` prints the endpoint snippet.

  This module holds the actual integration logic so it can be called
  directly (e.g. from `mix selecto.install`) without going through
  `Mix.Task.run/2`. `Mix.Tasks.Selecto.Views.Integrate` is a thin CLI
  wrapper around `run/1`.
  """

  @doc """
  Runs the app.js integration (and the Chart.js package.json check).

  ## Options

    * `:check` - report what would change without writing files
    * `:force` - re-patch even if already configured
  """
  def run(opts \\ []) do
    Mix.shell().info("🔧 SelectoViews Asset Integration")
    Mix.shell().info("================================\n")

    check_chart_js_installation(opts)

    app_js_status = integrate_app_js(opts)

    if opts[:check] do
      report_check_status(app_js_status)
    else
      report_integration_status(app_js_status)

      if app_js_status == :updated do
        Mix.shell().info("\n✅ Integration complete!")
      end

      print_next_steps()
    end

    :ok
  end

  @doc """
  Endpoint snippet that serves the packaged SelectoViews stylesheet.
  """
  def stylesheet_plug_snippet do
    """
    plug Plug.Static,
      at: "/selecto-views",
      from: :selecto_views,
      gzip: false,
      only: ~w(selecto-views.css)
    """
  end

  defp print_next_steps do
    Mix.shell().info("""

    Next steps:
      1. Serve the packaged stylesheet from your endpoint, before the router:

    #{indent(stylesheet_plug_snippet(), 9)}
      2. Run `(cd assets && npm install)`
      3. Run `mix assets.build`
    """)
  end

  defp indent(text, width) do
    pad = String.duplicate(" ", width)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> pad <> line
    end)
  end

  defp check_chart_js_installation(opts) do
    package_json_path = "assets/package.json"
    check_only? = opts[:check] == true

    if File.exists?(package_json_path) do
      case File.read(package_json_path) do
        {:ok, content} ->
          # Check if Chart.js is already in dependencies
          needs_chart = !String.contains?(content, "\"chart.js\"")

          if needs_chart do
            # Add missing dependency to existing package.json
            if check_only? do
              Mix.shell().info("⚠ Chart.js missing from package.json")
            else
              add_dependencies_to_package_json(package_json_path, content, needs_chart)
            end
          else
            Mix.shell().info("✓ Chart.js: Already configured in package.json")
          end

        _ ->
          :ok
      end
    else
      if check_only? do
        Mix.shell().info("⚠ assets/package.json missing (would create with Chart.js)")
      else
        # Create a minimal package.json with Chart.js
        create_package_json_with_dependencies(package_json_path)
      end
    end
  end

  defp create_package_json_with_dependencies(path) do
    content = """
    {
      "name": "assets",
      "version": "1.0.0",
      "private": true,
      "dependencies": {
        "chart.js": "^4.4.0"
      }
    }
    """

    File.write!(path, content)
    Mix.shell().info("✓ Created package.json with Chart.js dependency")
    Mix.shell().info("  Run `(cd assets && npm install)` to install dependencies")
  end

  defp add_dependencies_to_package_json(path, content, needs_chart) do
    # Parse JSON and add missing dependencies
    case Jason.decode(content) do
      {:ok, json} ->
        dependencies = Map.get(json, "dependencies", %{})

        updated_deps = dependencies

        updated_deps =
          if needs_chart, do: Map.put(updated_deps, "chart.js", "^4.4.0"), else: updated_deps

        updated_json = Map.put(json, "dependencies", updated_deps)

        case Jason.encode(updated_json, pretty: true) do
          {:ok, new_content} ->
            File.write!(path, new_content)
            if needs_chart, do: Mix.shell().info("✓ Added Chart.js to package.json dependencies")

            Mix.shell().info("  Run `(cd assets && npm install)` to install dependencies")

          _ ->
            Mix.shell().info("""
            ⚠️  Could not automatically add dependencies to package.json.

            Please add manually to your package.json dependencies:
                "chart.js": "^4.4.0"

            Then run:
                (cd assets && npm install)
            """)
        end

      _ ->
        Mix.shell().info("""
        ⚠️  Could not parse package.json.

        Please add these to your package.json dependencies:
            "chart.js": "^4.4.0"

        Then run:
            (cd assets && npm install)
        """)
    end
  end

  defp integrate_app_js(opts) do
    app_js_path = "assets/js/app.js"

    case File.read(app_js_path) do
      {:ok, content} ->
        cond do
          String.contains?(content, "phoenix-colocated/selecto_views") &&
            String.contains?(content, "...selectoViewsHooks") &&
              !opts[:force] ->
            if opts[:check] do
              :already_configured
            else
              Mix.shell().info("✓ app.js: SelectoViews hooks already configured")
              :already_configured
            end

          opts[:check] ->
            :needs_update

          true ->
            updated_content = patch_app_js(content)

            if updated_content != content do
              File.write!(app_js_path, updated_content)
              Mix.shell().info("✓ app.js: Added SelectoViews colocated hooks")
              :updated
            else
              Mix.shell().error(
                "✗ app.js: Could not automatically add hooks (manual configuration needed)"
              )

              :failed
            end
        end

      {:error, :enoent} ->
        Mix.shell().error("✗ app.js: File not found at #{app_js_path}")
        :not_found

      {:error, reason} ->
        Mix.shell().error("✗ app.js: Error reading file - #{inspect(reason)}")
        :error
    end
  end

  @doc false
  def patch_app_js(content) do
    content
    |> add_import_to_js()
    |> add_hooks_to_livesocket()
  end

  defp add_import_to_js(content) do
    selecto_views_imports = missing_selecto_views_js_imports(content)

    # Check if Chart.js is imported
    content_with_chart =
      if String.contains?(content, "window.Chart") || String.contains?(content, "import Chart") do
        content
      else
        add_chart_js_import(content)
      end

    if selecto_views_imports == "" do
      content_with_chart
    else
      # Add SelectoViews hook imports if needed
      cond do
        String.contains?(content_with_chart, "import {LiveSocket}") ->
          # Add import after LiveSocket import
          String.replace(
            content_with_chart,
            ~r/(import {LiveSocket} from "phoenix_live_view")/,
            "\\1\n#{selecto_views_imports}"
          )

        String.contains?(content_with_chart, "import") ->
          # Find last import and add after it
          lines = String.split(content_with_chart, "\n")
          import_lines = Enum.filter(lines, &String.starts_with?(&1, "import"))

          if length(import_lines) > 0 do
            last_import = List.last(import_lines)

            String.replace(
              content_with_chart,
              last_import,
              last_import <> "\n" <> selecto_views_imports
            )
          else
            # Add at the beginning
            selecto_views_imports <> "\n" <> content_with_chart
          end

        true ->
          # Add at the beginning
          selecto_views_imports <> "\n" <> content_with_chart
      end
    end
  end

  defp missing_selecto_views_js_imports(content) do
    []
    |> maybe_add_selecto_views_hooks_import(content)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp maybe_add_selecto_views_hooks_import(imports, content) do
    if String.contains?(content, "selectoViewsHooks") do
      imports
    else
      [
        "import {hooks as selectoViewsHooks} from \"phoenix-colocated/selecto_views\""
        | imports
      ]
    end
  end

  defp add_chart_js_import(content) do
    # Find a good place to add Chart.js import
    cond do
      String.contains?(content, "import topbar") ->
        # Add after topbar import
        String.replace(
          content,
          ~r/(import topbar from[^\n]+)/,
          "\\1\n\n// Import Chart.js for SelectoViews graph visualization\nimport Chart from \"chart.js/auto\"\nwindow.Chart = Chart"
        )

      String.contains?(content, "import") ->
        # Find last import and add after it
        lines = String.split(content, "\n")
        import_lines = Enum.filter(lines, &String.starts_with?(&1, "import"))

        if length(import_lines) > 0 do
          last_import = List.last(import_lines)

          String.replace(
            content,
            last_import,
            last_import <>
              "\n\n// Import Chart.js for SelectoViews graph visualization\nimport Chart from \"chart.js/auto\"\nwindow.Chart = Chart"
          )
        else
          content
        end

      true ->
        content
    end
  end

  defp add_hooks_to_livesocket(content) do
    cond do
      String.contains?(content, "hooks:") &&
          String.contains?(content, "...selectoViewsHooks") ->
        # Already fully configured
        content

      String.contains?(content, "hooks:") ->
        ensure_livesocket_hooks(content)

      String.contains?(content, "new LiveSocket") ->
        # No hooks object, add one
        String.replace(
          content,
          ~r/(const liveSocket = new LiveSocket\([^,]+,\s*Socket,\s*{)([^}]*)(})/,
          "\\1\\2,\n  hooks: { ...selectoViewsHooks }\\3"
        )

      true ->
        content
    end
  end

  defp ensure_livesocket_hooks(content) do
    case Regex.run(~r/hooks:\s*{([^}]*)}/, content) do
      [full_match, hooks_body] ->
        if simple_hooks_body?(hooks_body) do
          replacement = "hooks: {#{merge_hooks_body(hooks_body)}}"
          String.replace(content, full_match, replacement, global: false)
        else
          # `[^}]*` only matches up to the first closing brace, so a non-empty
          # `{` inside `hooks_body` means the real `hooks: { ... }` object has
          # nested braces (e.g. per-hook definitions) that this shallow regex
          # can't safely locate the true end of. Patching here would truncate
          # the object and corrupt the nested structure, so we leave the file
          # untouched and print a manual merge snippet instead.
          print_manual_hooks_merge_notice()
          content
        end

      nil ->
        content
    end
  end

  defp simple_hooks_body?(hooks_body), do: not String.contains?(hooks_body, "{")

  defp merge_hooks_body(hooks_body) do
    existing_hooks = sanitize_livesocket_hooks(hooks_body)

    additions =
      ""
      |> maybe_add_hook_entry(existing_hooks, "...selectoViewsHooks")

    case {existing_hooks, additions} do
      {"", ""} -> ""
      {"", extra} -> extra
      {existing, ""} -> existing
      {existing, extra} -> "#{existing}, #{extra}"
    end
  end

  defp print_manual_hooks_merge_notice do
    Mix.shell().info("""
    ⚠ app.js: Found an existing `hooks: { ... }` object with nested braces
      (e.g. per-hook definitions). To avoid corrupting it, this was left
      untouched - please merge manually:

        hooks: {
          ...selectoViewsHooks,
          // ...your existing hooks
        }
    """)
  end

  defp maybe_add_hook_entry(entries, hooks_body, entry) do
    if String.contains?(hooks_body, entry) do
      entries
    else
      append_entry(entries, entry)
    end
  end

  defp append_entry("", entry), do: entry
  defp append_entry(entries, entry), do: entries <> ", " <> entry

  defp sanitize_livesocket_hooks(hooks_body) do
    hooks_body
    |> String.replace(~r/\s+,/, ",")
    |> String.replace(~r/,\s*,+/, ", ")
    |> String.trim()
    |> String.trim_leading(",")
    |> String.trim_trailing(",")
    |> String.trim()
  end

  defp report_check_status(js_status) do
    Mix.shell().info("\nIntegration Status Check:")
    Mix.shell().info("-------------------------")

    report_file_status("app.js", js_status)

    if js_status == :needs_update do
      Mix.shell().info("\nRun `mix selecto.views.integrate` to apply changes.")
    end
  end

  defp report_file_status(filename, status) do
    case status do
      :already_configured ->
        Mix.shell().info("✓ #{filename}: Already configured")

      :needs_update ->
        Mix.shell().info("⚠ #{filename}: Needs integration")

      :not_found ->
        Mix.shell().error("✗ #{filename}: File not found")

      _ ->
        Mix.shell().error("✗ #{filename}: Error")
    end
  end

  defp report_integration_status(js_status) do
    if js_status == :failed do
      Mix.shell().info("""

      ⚠️  Manual configuration needed in assets/js/app.js:

         import {hooks as selectoViewsHooks} from "phoenix-colocated/selecto_views"

         // In your LiveSocket configuration:
         hooks: { ...selectoViewsHooks }
      """)
    end
  end
end
