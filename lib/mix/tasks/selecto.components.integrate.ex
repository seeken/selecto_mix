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

    # Check if Chart.js/Alpine.js are configured in package.json
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
          # Check if Chart.js and Alpine.js are already in dependencies
          needs_chart = !String.contains?(content, "\"chart.js\"")
          needs_alpine = !String.contains?(content, "\"alpinejs\"")

          if needs_chart || needs_alpine do
            # Add missing dependencies to existing package.json
            if check_only? do
              if needs_chart, do: Mix.shell().info("⚠ Chart.js missing from package.json")
              if needs_alpine, do: Mix.shell().info("⚠ Alpine.js missing from package.json")
            else
              add_dependencies_to_package_json(
                package_json_path,
                content,
                needs_chart,
                needs_alpine
              )
            end
          else
            Mix.shell().info("✓ Chart.js: Already configured in package.json")
            Mix.shell().info("✓ Alpine.js: Already configured in package.json")
          end

        _ ->
          :ok
      end
    else
      if check_only? do
        Mix.shell().info("⚠ assets/package.json missing (would create with Chart.js + Alpine.js)")
      else
        # Create a minimal package.json with Chart.js and Alpine.js
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
        "chart.js": "^4.4.0",
        "alpinejs": "^3.13.0"
      }
    }
    """

    File.write!(path, content)
    Mix.shell().info("✓ Created package.json with Chart.js and Alpine.js dependencies")
    Mix.shell().info("  Run `cd assets && npm install` to install dependencies")
  end

  defp add_dependencies_to_package_json(path, content, needs_chart, needs_alpine) do
    # Parse JSON and add missing dependencies
    case Jason.decode(content) do
      {:ok, json} ->
        dependencies = Map.get(json, "dependencies", %{})

        updated_deps = dependencies

        updated_deps =
          if needs_chart, do: Map.put(updated_deps, "chart.js", "^4.4.0"), else: updated_deps

        updated_deps =
          if needs_alpine, do: Map.put(updated_deps, "alpinejs", "^3.13.0"), else: updated_deps

        updated_json = Map.put(json, "dependencies", updated_deps)

        case Jason.encode(updated_json, pretty: true) do
          {:ok, new_content} ->
            File.write!(path, new_content)
            if needs_chart, do: Mix.shell().info("✓ Added Chart.js to package.json dependencies")

            if needs_alpine,
              do: Mix.shell().info("✓ Added Alpine.js to package.json dependencies")

            Mix.shell().info("  Run `cd assets && npm install` to install dependencies")

          _ ->
            Mix.shell().info("""
            ⚠️  Could not automatically add dependencies to package.json.

            Please add manually to your package.json dependencies:
                "chart.js": "^4.4.0"
                "alpinejs": "^3.13.0"

            Then run:
                cd assets && npm install
            """)
        end

      _ ->
        Mix.shell().info("""
        ⚠️  Could not parse package.json.

        Please add these to your package.json dependencies:
            "chart.js": "^4.4.0"
            "alpinejs": "^3.13.0"

        Then run:
            cd assets && npm install
        """)
    end
  end

  defp integrate_app_js(opts) do
    app_js_path = "assets/js/app.js"

    case File.read(app_js_path) do
      {:ok, content} ->
        has_legacy_selecto_hooks_import =
          String.contains?(content, "/selecto_components/assets/js/hooks")

        has_local_selecto_hooks_import =
          String.contains?(content, "import selectoHooks from \"./selecto_hooks\"")

        cond do
          String.contains?(content, "phoenix-colocated/selecto_components") &&
            has_local_selecto_hooks_import &&
            !has_legacy_selecto_hooks_import &&
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
              Mix.shell().info("✓ app.js: Added SelectoComponents hooks and selecto_hooks")
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
    # First, add the import statement if not present
    content_with_import =
      if String.contains?(content, "TreeBuilderHook") &&
           String.contains?(content, "selectoComponentsHooks") do
        content
      else
        add_import_to_js(content)
      end

    content_with_normalized_hooks_import =
      normalize_legacy_selecto_hooks_import(content_with_import)

    # Add selecto_hooks import if needed
    content_with_selecto_hooks = add_selecto_hooks_import(content_with_normalized_hooks_import)

    # Now add hooks to the LiveSocket configuration
    add_hooks_to_livesocket(content_with_selecto_hooks)
  end

  defp normalize_legacy_selecto_hooks_import(content) do
    normalized =
      String.replace(
        content,
        ~r/import\s+selectoHooks\s+from\s+["']\.\.\/\.\.\/(?:vendor|deps)\/selecto_components\/assets\/js\/hooks["'];?/,
        "import selectoHooks from \"./selecto_hooks\""
      )

    if normalized != content do
      create_selecto_hooks_file()
    end

    normalized
  end

  defp add_import_to_js(content) do
    selecto_components_imports = missing_selecto_components_js_imports(content)

    # First check if Chart.js is imported
    content_with_chart =
      if String.contains?(content, "window.Chart") || String.contains?(content, "import Chart") do
        content
      else
        add_chart_js_import(content)
      end

    # Then check if Alpine.js is imported
    content_with_alpine =
      if String.contains?(content_with_chart, "window.Alpine") ||
           String.contains?(content_with_chart, "import Alpine") do
        content_with_chart
      else
        add_alpine_js_import(content_with_chart)
      end

    if selecto_components_imports == "" do
      content_with_alpine
    else
      # Finally add TreeBuilder and selecto component hooks imports if needed
      cond do
        String.contains?(content_with_alpine, "import {LiveSocket}") ->
          # Add import after LiveSocket import
          String.replace(
            content_with_alpine,
            ~r/(import {LiveSocket} from "phoenix_live_view")/,
            "\\1\n#{selecto_components_imports}"
          )

        String.contains?(content_with_alpine, "import") ->
          # Find last import and add after it
          lines = String.split(content_with_alpine, "\n")
          import_lines = Enum.filter(lines, &String.starts_with?(&1, "import"))

          if length(import_lines) > 0 do
            last_import = List.last(import_lines)

            String.replace(
              content_with_alpine,
              last_import,
              last_import <> "\n" <> selecto_components_imports
            )
          else
            # Add at the beginning
            selecto_components_imports <> "\n" <> content_with_alpine
          end

        true ->
          # Add at the beginning
          selecto_components_imports <> "\n" <> content_with_alpine
      end
    end
  end

  defp missing_selecto_components_js_imports(content) do
    base_path = get_selecto_components_js_base_path()

    []
    |> maybe_add_selecto_components_hooks_import(content)
    |> maybe_add_tree_builder_import(content, base_path)
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

  defp maybe_add_tree_builder_import(imports, content, base_path) do
    if String.contains?(content, "TreeBuilderHook") do
      imports
    else
      [
        "import TreeBuilderHook from \"#{base_path}/lib/selecto_components/components/tree_builder.hooks\""
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

  defp add_selecto_hooks_import(content) do
    # Check if selecto_hooks is already imported
    if String.contains?(content, "selectoHooks") do
      content
    else
      # Create selecto_hooks.js if it doesn't exist
      create_selecto_hooks_file()

      # Find where to add the import
      cond do
        String.contains?(content, "selectoComponentsHooks") ->
          # Add after selectoComponentsHooks import
          String.replace(
            content,
            ~r/(import {hooks as selectoComponentsHooks} from[^\n]+)/,
            "\\1\nimport selectoHooks from \"./selecto_hooks\""
          )

        String.contains?(content, "import topbar") ->
          # Add after topbar import
          String.replace(
            content,
            ~r/(import topbar from[^\n]+)/,
            "\\1\nimport selectoHooks from \"./selecto_hooks\""
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
              last_import <> "\nimport selectoHooks from \"./selecto_hooks\""
            )
          else
            content
          end

        true ->
          content
      end
    end
  end

  defp create_selecto_hooks_file() do
    hooks_path = "assets/js/selecto_hooks.js"

    if !File.exists?(hooks_path) do
      hooks_content = """
      // Custom Phoenix LiveView hooks for Selecto Components

      export const DebugClipboard = {
        mounted() {
          this.handleCopyEvent = (e) => {
            const button = e.target.closest('button[phx-click="copy_sql"]');
            if (button) {
              const sqlQuery = this.el.querySelector('[data-sql-query]')?.textContent ||
                              this.el.querySelector('pre')?.textContent || '';

              if (sqlQuery) {
                navigator.clipboard.writeText(sqlQuery).then(() => {
                  const originalText = button.innerHTML;
                  button.innerHTML = '✓ Copied!';
                  button.classList.add('bg-green-500');
                  button.classList.remove('bg-blue-500');

                  setTimeout(() => {
                    button.innerHTML = originalText;
                    button.classList.remove('bg-green-500');
                    button.classList.add('bg-blue-500');
                  }, 2000);
                });
              }
            }
          };

          this.el.addEventListener('click', this.handleCopyEvent);
        },

        destroyed() {
          if (this.handleCopyEvent) {
            this.el.removeEventListener('click', this.handleCopyEvent);
          }
        }
      };

      export const RowClickable = {
        mounted() {
          this.handleRowClick = (e) => {
            const row = e.target.closest('tr[data-row-id]');
            if (row && !e.target.closest('a, button, input, select, textarea')) {
              const rowId = row.dataset.rowId;
              const action = row.dataset.clickAction || 'row_clicked';

              this.pushEvent(action, { row_id: rowId });
            }
          };

          this.el.addEventListener('click', this.handleRowClick);

          // Add hover effect
          const rows = this.el.querySelectorAll('tr[data-row-id]');
          rows.forEach(row => {
            row.style.cursor = 'pointer';
            row.addEventListener('mouseenter', () => {
              row.classList.add('bg-gray-50', 'transition-colors');
            });
            row.addEventListener('mouseleave', () => {
              row.classList.remove('bg-gray-50');
            });
          });
        },

        destroyed() {
          if (this.handleRowClick) {
            this.el.removeEventListener('click', this.handleRowClick);
          }
        }
      };

      export const ColumnResize = {
        mounted() {
          const columnId = this.el.dataset.columnId;
          let startX = 0;
          let startWidth = 0;
          let currentTable = null;
          let currentColumn = null;

          const handleMouseDown = (e) => {
            e.preventDefault();
            e.stopPropagation();

            currentTable = this.el.closest('table');
            if (!currentTable) return;

            // Find the column header
            currentColumn = currentTable.querySelector(`th[data-column-id="${columnId}"]`) ||
                           this.el.closest('th');

            if (!currentColumn) return;

            startX = e.pageX;
            startWidth = currentColumn.offsetWidth;

            document.body.style.cursor = 'col-resize';
            document.body.style.userSelect = 'none';

            // Add active state
            this.el.classList.add('bg-blue-500');

            document.addEventListener('mousemove', handleMouseMove);
            document.addEventListener('mouseup', handleMouseUp);
          };

          const handleMouseMove = (e) => {
            if (!currentColumn) return;

            const diff = e.pageX - startX;
            const newWidth = Math.max(50, Math.min(500, startWidth + diff));

            currentColumn.style.width = `${newWidth}px`;
            currentColumn.style.minWidth = `${newWidth}px`;
            currentColumn.style.maxWidth = `${newWidth}px`;

            // Update all cells in this column
            const columnIndex = Array.from(currentColumn.parentElement.children).indexOf(currentColumn);
            const rows = currentTable.querySelectorAll('tbody tr');
            rows.forEach(row => {
              const cell = row.children[columnIndex];
              if (cell) {
                cell.style.width = `${newWidth}px`;
                cell.style.minWidth = `${newWidth}px`;
                cell.style.maxWidth = `${newWidth}px`;
              }
            });
          };

          const handleMouseUp = (e) => {
            if (currentColumn) {
              const newWidth = currentColumn.offsetWidth;

              // Send the new width to the server
              this.pushEvent('column_resized', {
                column_id: columnId,
                width: newWidth
              });
            }

            // Reset
            document.body.style.cursor = '';
            document.body.style.userSelect = '';
            this.el.classList.remove('bg-blue-500');

            document.removeEventListener('mousemove', handleMouseMove);
            document.removeEventListener('mouseup', handleMouseUp);

            currentColumn = null;
            currentTable = null;
          };

          this.el.addEventListener('mousedown', handleMouseDown);

          // Store for cleanup
          this.handleMouseDown = handleMouseDown;
        },

        destroyed() {
          if (this.handleMouseDown) {
            this.el.removeEventListener('mousedown', this.handleMouseDown);
          }
        }
      };

      export default {
        DebugClipboard,
        RowClickable,
        ColumnResize
      };
      """

      File.write!(hooks_path, hooks_content)
      Mix.shell().info("✓ Created selecto_hooks.js with required LiveView hooks")
    end
  end

  defp add_alpine_js_import(content) do
    # Find a good place to add Alpine.js import
    cond do
      String.contains?(content, "window.Chart = Chart") ->
        # Add after Chart.js if it exists
        String.replace(
          content,
          ~r/(window\.Chart = Chart)/,
          "\\1\n\n// Import Alpine.js for enhanced interactivity\nimport Alpine from \"alpinejs\"\nwindow.Alpine = Alpine\nAlpine.start()"
        )

      String.contains?(content, "import topbar") ->
        # Add after topbar import
        String.replace(
          content,
          ~r/(import topbar from[^\n]+)/,
          "\\1\n\n// Import Alpine.js for enhanced interactivity\nimport Alpine from \"alpinejs\"\nwindow.Alpine = Alpine\nAlpine.start()"
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
              "\n\n// Import Alpine.js for enhanced interactivity\nimport Alpine from \"alpinejs\"\nwindow.Alpine = Alpine\nAlpine.start()"
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
      # Check if all hooks are already configured in the hooks object
      String.contains?(content, "hooks:") &&
        String.contains?(content, "TreeBuilder: TreeBuilderHook") &&
        String.contains?(content, "...selectoComponentsHooks") &&
          String.contains?(content, "...selectoHooks") ->
        # Already fully configured
        content

      String.contains?(content, "hooks:") ->
        ensure_livesocket_hooks(content)

      String.contains?(content, "new LiveSocket") ->
        # No hooks object, add one
        String.replace(
          content,
          ~r/(const liveSocket = new LiveSocket\([^,]+,\s*Socket,\s*{)([^}]*)(})/,
          "\\1\\2,\n  hooks: { TreeBuilder: TreeBuilderHook, ...selectoComponentsHooks, ...selectoHooks }\\3"
        )

      true ->
        content
    end
  end

  defp ensure_livesocket_hooks(content) do
    Regex.replace(~r/hooks:\s*{([^}]*)}/, content, fn _full, hooks_body ->
      existing_hooks = hooks_body |> String.trim() |> String.trim_trailing(",")

      additions =
        ""
        |> maybe_add_hook_entry(existing_hooks, "TreeBuilder: TreeBuilderHook")
        |> maybe_add_hook_entry(existing_hooks, "...selectoComponentsHooks")
        |> maybe_add_hook_entry(existing_hooks, "...selectoHooks")

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

  defp get_selecto_components_js_base_path() do
    vendor_path = Path.join([File.cwd!(), "vendor", "selecto_components"])
    deps_path = Path.join([File.cwd!(), "deps", "selecto_components"])

    cond do
      File.dir?(vendor_path) -> "../../vendor/selecto_components"
      File.dir?(deps_path) -> "../../deps/selecto_components"
      true -> "../../deps/selecto_components"
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
         import TreeBuilderHook from "#{get_selecto_components_js_base_path()}/lib/selecto_components/components/tree_builder.hooks"
         import {hooks as selectoComponentsHooks} from "phoenix-colocated/selecto_components"
         import selectoHooks from "./selecto_hooks"

          // In your LiveSocket configuration:
          hooks: { TreeBuilder: TreeBuilderHook, ...selectoComponentsHooks, ...selectoHooks }

      2. In assets/css/app.css, add:
         @source "#{get_selecto_components_path()}";

      3. Make sure assets/js/selecto_hooks.js exists with the required hooks
      """)
    end
  end
end
