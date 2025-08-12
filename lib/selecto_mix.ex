defmodule SelectoMix do
  @moduledoc """
  Mix tasks and tooling for automatic Selecto configuration generation.
  
  SelectoMix provides utilities to automatically generate Selecto domain
  configurations from Ecto schemas, preserving user customizations across
  regenerations and supporting incremental updates when schemas change.
  
  ## Key Features
  
  - **Automatic Schema Discovery**: Finds and introspects all Ecto schemas in your project
  - **Intelligent Configuration Generation**: Creates comprehensive Selecto domains with suggested defaults
  - **Customization Preservation**: Maintains user modifications when regenerating files
  - **Incremental Updates**: Detects schema changes and updates only what's necessary
  - **Igniter Integration**: Uses modern Elixir project modification tools
  
  ## Main Mix Tasks
  
  - `mix selecto.gen.domain` - Generate Selecto domain configurations from Ecto schemas
  - `mix selecto.install` - Install Selecto dependencies and setup project structure
  - `mix selecto.update` - Update existing domain configurations after schema changes
  
  ## Getting Started
  
  1. Add SelectoMix to your project dependencies
  2. Run `mix selecto.install` to setup basic structure
  3. Generate domains with `mix selecto.gen.domain --all`
  4. Customize the generated domains as needed
  5. Re-run generation after schema changes - customizations will be preserved
  
  ## Configuration
  
  You can configure SelectoMix in your `config/config.exs`:
  
      config :selecto_mix,
        output_dir: "lib/my_app/selecto_domains",
        default_associations: true,
        preserve_customizations: true
  
  ## Example Usage
  
      # Generate domain for a single schema
      mix selecto.gen.domain Blog.Post
      
      # Generate for all schemas in a context
      mix selecto.gen.domain Blog.*
      
      # Generate for all schemas with associations
      mix selecto.gen.domain --all --include-associations
      
      # Force regeneration (overwrites customizations)
      mix selecto.gen.domain Blog.Post --force
  """

  @doc """
  Get the version of SelectoMix.
  """
  def version do
    Application.spec(:selecto_mix, :vsn) |> to_string()
  end

  @doc """
  Get configuration for SelectoMix.
  """
  def config do
    Application.get_all_env(:selecto_mix)
  end

  @doc """
  Check if Selecto dependencies are available.
  """
  def dependencies_available? do
    Code.ensure_loaded?(Selecto) and 
    Code.ensure_loaded?(Ecto.Schema)
  end

  @doc """
  Get the default output directory for generated domains.
  """
  def default_output_dir do
    case Application.get_env(:selecto_mix, :output_dir) do
      nil -> 
        app_name = Application.get_env(:selecto_mix, :app_name, "my_app")
        "lib/#{app_name}/selecto_domains"
      dir -> dir
    end
  end

  @doc """
  Validate a schema module exists and is an Ecto schema.
  """
  def validate_schema_module(module_name) when is_atom(module_name) do
    try do
      Code.ensure_loaded!(module_name)
      
      if function_exported?(module_name, :__schema__, 1) do
        {:ok, module_name}
      else
        {:error, "#{module_name} is not an Ecto schema"}
      end
    rescue
      error -> {:error, "Could not load #{module_name}: #{inspect(error)}"}
    end
  end
  
  def validate_schema_module(module_string) when is_binary(module_string) do
    try do
      module_atom = String.to_existing_atom("Elixir.#{module_string}")
      validate_schema_module(module_atom)
    rescue
      ArgumentError -> {:error, "Module #{module_string} does not exist"}
    end
  end

  @doc """
  List all available Ecto schemas in the current project.
  """
  def discover_schemas do
    # This is a simplified version - the full implementation would use more sophisticated discovery
    with {:ok, modules} <- :application.get_key(:selecto_mix, :modules) do
      modules
      |> Enum.filter(&is_ecto_schema?/1)
    else
      _ -> []
    end
  end

  # Private helper functions

  defp is_ecto_schema?(module) do
    try do
      Code.ensure_loaded!(module)
      function_exported?(module, :__schema__, 1)
    rescue
      _ -> false
    end
  end
end
