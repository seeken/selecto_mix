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

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [check: :boolean, force: :boolean])

    Mix.shell().info("🔧 SelectoComponents Asset Integration")
    Mix.shell().info("=====================================\n")

    # Check if Chart.js is configured in package.json
    check_chart_js_installation(opts)

    app_js_status = integrate_app_js(opts)
    app_css_status = integrate_app_css(opts)

    if opts[:check] do
      report_check_status(app_js_status, app_css_status)
    else
      report_integration_status(app_js_status, app_css_status)

      if app_js_status == :updated || app_css_status == :updated do
        Mix.shell().info("\n✅ Integration complete!")
      end

      print_next_steps()
    end
  end

  defp print_next_steps do
    Mix.shell().info("""

    Next steps:
      1. Run `cd assets && npm install`
      2. Run `mix assets.build`
    """)
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
              if needs_chart, do: Mix.shell().info("⚠ Chart.js missing from package.json")
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
    Mix.shell().info("  Run `cd assets && npm install` to install dependencies")
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

            Mix.shell().info("  Run `cd assets && npm install` to install dependencies")

          _ ->
            Mix.shell().info("""
            ⚠️  Could not automatically add dependencies to package.json.

            Please add manually to your package.json dependencies:
                "chart.js": "^4.4.0"

            Then run:
                cd assets && npm install
            """)
        end

      _ ->
        Mix.shell().info("""
        ⚠️  Could not parse package.json.

        Please add these to your package.json dependencies:
            "chart.js": "^4.4.0"

        Then run:
            cd assets && npm install
        """)
    end
  end

  defp integrate_app_js(opts) do
    app_js_path = "assets/js/app.js"

    case File.read(app_js_path) do
      {:ok, content} ->
        has_legacy_hook_setup = stale_selecto_hook_setup?(content)

        cond do
          String.contains?(content, "phoenix-colocated/selecto_components") &&
            String.contains?(content, "...selectoComponentsHooks") &&
            !has_legacy_hook_setup &&
              !opts[:force] ->
            if opts[:check] do
              :already_configured
            else
              Mix.shell().info("✓ app.js: SelectoComponents hooks already configured")
              :already_configured
            end

          opts[:check] ->
            :needs_update

          true ->
            updated_content = patch_app_js(content)

            if updated_content != content do
              File.write!(app_js_path, updated_content)
              Mix.shell().info("✓ app.js: Added SelectoComponents colocated hooks")
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

  defp integrate_app_css(opts) do
    app_css_path = "assets/css/app.css"

    case File.read(app_css_path) do
      {:ok, content} ->
        cond do
          String.contains?(content, "selecto_components/lib") && !opts[:force] ->
            if opts[:check] do
              :already_configured
            else
              Mix.shell().info("✓ app.css: SelectoComponents styles already configured")
              :already_configured
            end

          opts[:check] ->
            :needs_update

          true ->
            updated_content = patch_app_css(content)

            if updated_content != content do
              File.write!(app_css_path, updated_content)
              Mix.shell().info("✓ app.css: Added SelectoComponents styles")
              :updated
            else
              Mix.shell().error(
                "✗ app.css: Could not automatically add styles (manual configuration needed)"
              )

              :failed
            end
        end

      {:error, :enoent} ->
        Mix.shell().error("✗ app.css: File not found at #{app_css_path}")
        :not_found

      {:error, reason} ->
        Mix.shell().error("✗ app.css: Error reading file - #{inspect(reason)}")
        :error
    end
  end

  defp patch_app_js(content) do
    content
    |> normalize_legacy_selecto_hooks_import()
    |> remove_local_selecto_hooks_import()
    |> remove_tree_builder_hook_import()
    |> add_import_to_js()
    |> add_hooks_to_livesocket()
  end

  defp normalize_legacy_selecto_hooks_import(content) do
    String.replace(
      content,
      ~r/import\s+selectoHooks\s+from\s+["']\.\.\/\.\.\/(?:vendor|deps)\/selecto_components\/assets\/js\/hooks["'];?/,
      "import {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\""
    )
  end

  defp add_import_to_js(content) do
    selecto_components_imports = missing_selecto_components_js_imports(content)

    # Check if Chart.js is imported
    content_with_chart =
      if String.contains?(content, "window.Chart") || String.contains?(content, "import Chart") do
        content
      else
        add_chart_js_import(content)
      end

    if selecto_components_imports == "" do
      content_with_chart
    else
      # Add SelectoComponents hook imports if needed
      cond do
        String.contains?(content_with_chart, "import {LiveSocket}") ->
          # Add import after LiveSocket import
          String.replace(
            content_with_chart,
            ~r/(import {LiveSocket} from "phoenix_live_view")/,
            "\\1\n#{selecto_components_imports}"
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
              last_import <> "\n" <> selecto_components_imports
            )
          else
            # Add at the beginning
            selecto_components_imports <> "\n" <> content_with_chart
          end

        true ->
          # Add at the beginning
          selecto_components_imports <> "\n" <> content_with_chart
      end
    end
  end

  defp missing_selecto_components_js_imports(content) do
    []
    |> maybe_add_selecto_components_hooks_import(content)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp maybe_add_selecto_components_hooks_import(imports, content) do
    if String.contains?(content, "selectoComponentsHooks") do
      imports
    else
      [
        "import {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\""
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
          "\\1\n\n// Import Chart.js for SelectoComponents graph visualization\nimport Chart from \"chart.js/auto\"\nwindow.Chart = Chart"
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
              "\n\n// Import Chart.js for SelectoComponents graph visualization\nimport Chart from \"chart.js/auto\"\nwindow.Chart = Chart"
          )
        else
          content
        end

      true ->
        content
    end
  end

  defp remove_local_selecto_hooks_import(content) do
    Regex.replace(
      ~r/^\s*import\s+selectoHooks\s+from\s+["']\.\/selecto_hooks["'];?\s*\n/m,
      content,
      ""
    )
  end

  defp remove_tree_builder_hook_import(content) do
    Regex.replace(~r/^\s*import\s+TreeBuilderHook\s+from\s+[^\n]+\n/m, content, "")
  end

  defp add_hooks_to_livesocket(content) do
    cond do
      String.contains?(content, "hooks:") &&
        String.contains?(content, "...selectoComponentsHooks") &&
          !stale_selecto_hook_setup?(content) ->
        # Already fully configured
        content

      String.contains?(content, "hooks:") ->
        ensure_livesocket_hooks(content)

      String.contains?(content, "new LiveSocket") ->
        # No hooks object, add one
        String.replace(
          content,
          ~r/(const liveSocket = new LiveSocket\([^,]+,\s*Socket,\s*{)([^}]*)(})/,
          "\\1\\2,\n  hooks: { ...selectoComponentsHooks }\\3"
        )

      true ->
        content
    end
  end

  defp ensure_livesocket_hooks(content) do
    Regex.replace(~r/hooks:\s*{([^}]*)}/, content, fn _full, hooks_body ->
      existing_hooks = sanitize_livesocket_hooks(hooks_body)

      additions =
        ""
        |> maybe_add_hook_entry(existing_hooks, "...selectoComponentsHooks")

      merged_hooks =
        case {existing_hooks, additions} do
          {"", ""} -> ""
          {"", extra} -> extra
          {existing, ""} -> existing
          {existing, extra} -> "#{existing}, #{extra}"
        end

      "hooks: {#{merged_hooks}}"
    end)
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
    |> String.replace(~r/\bTreeBuilder\s*:\s*TreeBuilderHook\s*,?\s*/, "")
    |> String.replace(~r/\.\.\.selectoHooks\s*,?\s*/, "")
    |> String.replace(~r/\s+,/, ",")
    |> String.replace(~r/,\s*,+/, ", ")
    |> String.trim()
    |> String.trim_leading(",")
    |> String.trim_trailing(",")
    |> String.trim()
  end

  defp stale_selecto_hook_setup?(content) do
    String.contains?(content, "/selecto_components/assets/js/hooks") ||
      String.contains?(content, "./selecto_hooks") ||
      String.contains?(content, "...selectoHooks") ||
      String.contains?(content, "TreeBuilderHook") ||
      String.contains?(content, "TreeBuilder: TreeBuilderHook")
  end

  defp get_selecto_components_path() do
    vendor_path = Path.join([File.cwd!(), "vendor", "selecto_components"])
    deps_path = Path.join([File.cwd!(), "deps", "selecto_components"])

    cond do
      File.dir?(vendor_path) -> "../../vendor/selecto_components/lib/**/*.{ex,heex}"
      File.dir?(deps_path) -> "../../deps/selecto_components/lib/**/*.{ex,heex}"
      # default to deps
      true -> "../../deps/selecto_components/lib/**/*.{ex,heex}"
    end
  end

  defp patch_app_css(content) do
    selecto_path = get_selecto_components_path()

    cond do
      # If there are already @source directives, add after the last one
      String.contains?(content, "@source") ->
        lines = String.split(content, "\n")

        source_indices =
          lines
          |> Enum.with_index()
          |> Enum.filter(fn {line, _} -> String.contains?(line, "@source") end)
          |> Enum.map(fn {_, index} -> index end)

        if length(source_indices) > 0 do
          last_index = List.last(source_indices)

          List.insert_at(lines, last_index + 1, "@source \"#{selecto_path}\";")
          |> Enum.join("\n")
        else
          content <> "\n@source \"#{selecto_path}\";\n"
        end

      # If there's @import "tailwindcss/utilities", add after it
      String.contains?(content, "@import \"tailwindcss/utilities\"") ->
        String.replace(
          content,
          ~r/(@import "tailwindcss\/utilities";)/,
          "\\1\n\n/* SelectoComponents styles */\n@source \"#{selecto_path}\";"
        )

      # Otherwise, append at the end
      true ->
        content <> "\n\n/* SelectoComponents styles */\n@source \"#{selecto_path}\";\n"
    end
  end

  defp report_check_status(js_status, css_status) do
    Mix.shell().info("\nIntegration Status Check:")
    Mix.shell().info("-------------------------")

    report_file_status("app.js", js_status)
    report_file_status("app.css", css_status)

    if js_status == :needs_update || css_status == :needs_update do
      Mix.shell().info("\nRun `mix selecto.components.integrate` to apply changes.")
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

  defp report_integration_status(js_status, css_status) do
    if js_status == :failed || css_status == :failed do
      Mix.shell().info("""

      ⚠️  Manual configuration needed:

      1. In assets/js/app.js, add:
         import {hooks as selectoComponentsHooks} from "phoenix-colocated/selecto_components"

          // In your LiveSocket configuration:
          hooks: { ...selectoComponentsHooks }

      2. In assets/css/app.css, add:
         @source "#{get_selecto_components_path()}";
      """)
    end
  end
end
