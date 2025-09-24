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
    
    # Check if Chart.js is installed
    check_chart_js_installation()

    app_js_status = integrate_app_js(opts)
    app_css_status = integrate_app_css(opts)

    if opts[:check] do
      report_check_status(app_js_status, app_css_status)
    else
      report_integration_status(app_js_status, app_css_status)
      
      if app_js_status == :updated || app_css_status == :updated do
        Mix.shell().info("""
        
        ✅ Integration complete!
        
        Run `mix assets.build` to compile your assets.
        """)
      end
    end
  end

  defp check_chart_js_installation do
    package_json_path = "assets/package.json"
    
    if File.exists?(package_json_path) do
      case File.read(package_json_path) do
        {:ok, content} ->
          # Check if Chart.js and Alpine.js are already in dependencies
          needs_chart = !String.contains?(content, "\"chart.js\"")
          needs_alpine = !String.contains?(content, "\"alpinejs\"")
          
          if needs_chart || needs_alpine do
            # Add missing dependencies to existing package.json
            add_dependencies_to_package_json(package_json_path, content, needs_chart, needs_alpine)
          else
            Mix.shell().info("✓ Chart.js: Already configured in package.json")
            Mix.shell().info("✓ Alpine.js: Already configured in package.json")
          end
        _ -> :ok
      end
    else
      # Create a minimal package.json with Chart.js and Alpine.js
      create_package_json_with_dependencies(package_json_path)
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
        updated_deps = if needs_chart, do: Map.put(updated_deps, "chart.js", "^4.4.0"), else: updated_deps
        updated_deps = if needs_alpine, do: Map.put(updated_deps, "alpinejs", "^3.13.0"), else: updated_deps
        
        updated_json = Map.put(json, "dependencies", updated_deps)
        
        case Jason.encode(updated_json, pretty: true) do
          {:ok, new_content} ->
            File.write!(path, new_content)
            if needs_chart, do: Mix.shell().info("✓ Added Chart.js to package.json dependencies")
            if needs_alpine, do: Mix.shell().info("✓ Added Alpine.js to package.json dependencies")
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
        cond do
          String.contains?(content, "phoenix-colocated/selecto_components") && !opts[:force] ->
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
              Mix.shell().info("✓ app.js: Added SelectoComponents hooks")
              :updated
            else
              Mix.shell().error("✗ app.js: Could not automatically add hooks (manual configuration needed)")
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
              Mix.shell().error("✗ app.css: Could not automatically add styles (manual configuration needed)")
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
      if String.contains?(content, "selectoComponentsHooks") do
        content
      else
        add_import_to_js(content)
      end
    
    # Now add hooks to the LiveSocket configuration
    add_hooks_to_livesocket(content_with_import)
  end
  
  defp add_import_to_js(content) do
    # First check if Chart.js is imported
    content_with_chart = 
      if String.contains?(content, "window.Chart") || String.contains?(content, "import Chart") do
        content
      else
        add_chart_js_import(content)
      end
    
    # Then check if Alpine.js is imported
    content_with_alpine =
      if String.contains?(content_with_chart, "window.Alpine") || String.contains?(content_with_chart, "import Alpine") do
        content_with_chart
      else
        add_alpine_js_import(content_with_chart)
      end
    
    # Finally add selectoComponentsHooks if needed
    cond do
      String.contains?(content_with_alpine, "import {LiveSocket}") ->
        # Add import after LiveSocket import
        String.replace(
          content_with_alpine,
          ~r/(import {LiveSocket} from "phoenix_live_view")/,
          "\\1\nimport {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\""
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
            last_import <> "\nimport {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\""
          )
        else
          # Add at the beginning
          "import {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\"\n" <> content_with_alpine
        end
        
      true ->
        # Add at the beginning
        "import {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\"\n" <> content_with_alpine
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
            last_import <> "\n\n// Import Chart.js for SelectoComponents graph visualization\nimport Chart from \"chart.js/auto\"\nwindow.Chart = Chart"
          )
        else
          content
        end
        
      true ->
        content
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
            last_import <> "\n\n// Import Alpine.js for enhanced interactivity\nimport Alpine from \"alpinejs\"\nwindow.Alpine = Alpine\nAlpine.start()"
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
      # Check if selectoComponentsHooks is actually IN the hooks object, not just imported
      String.contains?(content, "hooks:") && String.contains?(content, "...selectoComponentsHooks") ->
        # Already configured
        content
        
      String.contains?(content, "hooks:") && String.contains?(content, "...") ->
        # Hooks object exists with spread operator, add our hooks
        # This handles cases like: hooks: {...colocatedHooks}
        String.replace(
          content,
          ~r/hooks:\s*{\s*([^}]+)}/,
          "hooks: {\\1, ...selectoComponentsHooks}"
        )
        
      String.contains?(content, "hooks:") ->
        # Hooks object exists without spread, add with spread to preserve existing
        String.replace(
          content,
          ~r/hooks:\s*{([^}]*)}/,
          "hooks: {...selectoComponentsHooks,\\1}"
        )
        
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

  defp get_selecto_components_path() do
    vendor_path = Path.join([File.cwd!(), "vendor", "selecto_components"])
    deps_path = Path.join([File.cwd!(), "deps", "selecto_components"])

    cond do
      File.dir?(vendor_path) -> "../../vendor/selecto_components/lib/**/*.{ex,heex}"
      File.dir?(deps_path) -> "../../deps/selecto_components/lib/**/*.{ex,heex}"
      true -> "../../deps/selecto_components/lib/**/*.{ex,heex}"  # default to deps
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