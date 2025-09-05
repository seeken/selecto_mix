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
    cond do
      String.contains?(content, "import {LiveSocket}") ->
        # Add import after LiveSocket import
        String.replace(
          content,
          ~r/(import {LiveSocket} from "phoenix_live_view")/,
          "\\1\nimport {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\""
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
            last_import <> "\nimport {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\""
          )
        else
          # Add at the beginning
          "import {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\"\n" <> content
        end
        
      true ->
        # Add at the beginning
        "import {hooks as selectoComponentsHooks} from \"phoenix-colocated/selecto_components\"\n" <> content
    end
  end
  
  defp add_hooks_to_livesocket(content) do
    cond do
      String.contains?(content, "hooks:") && String.contains?(content, "selectoComponentsHooks") ->
        # Already configured
        content
        
      String.contains?(content, "hooks:") ->
        # Hooks object exists, add to it
        String.replace(
          content,
          ~r/hooks:\s*{([^}]*)}/,
          "hooks: {\n    ...selectoComponentsHooks,\\1}"
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

  defp patch_app_css(content) do
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
          List.insert_at(lines, last_index + 1, "@source \"../../deps/selecto_components/lib/**/*.{ex,heex}\";")
          |> Enum.join("\n")
        else
          content <> "\n@source \"../../deps/selecto_components/lib/**/*.{ex,heex}\";\n"
        end
        
      # If there's @import "tailwindcss/utilities", add after it
      String.contains?(content, "@import \"tailwindcss/utilities\"") ->
        String.replace(
          content,
          ~r/(@import "tailwindcss\/utilities";)/,
          "\\1\n\n/* SelectoComponents styles */\n@source \"../../deps/selecto_components/lib/**/*.{ex,heex}\";"
        )
        
      # Otherwise, append at the end
      true ->
        content <> "\n\n/* SelectoComponents styles */\n@source \"../../deps/selecto_components/lib/**/*.{ex,heex}\";\n"
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
         @source "../../deps/selecto_components/lib/**/*.{ex,heex}";
      """)
    end
  end
end