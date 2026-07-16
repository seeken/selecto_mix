defmodule SelectoMix do
  @moduledoc """
  Mix tasks and tooling for automatic Selecto configuration generation.

  SelectoMix provides utilities to automatically generate Selecto domain
  configurations from Ecto schemas, create overlay modules for app-specific
  customizations, and scaffold related SelectoComponents persistence helpers.

  ## Key Features

  - **Automatic Schema Discovery**: Finds and introspects all Ecto schemas in your project
  - **Intelligent Configuration Generation**: Creates comprehensive Selecto domains with suggested defaults
  - **Overlay Customization**: Keeps app-specific modifications outside generated base files
  - **Igniter Integration**: Uses modern Elixir project modification tools
  - **Persistence Scaffolds**: Generates saved views, saved view configs,
    exported views, and filter set persistence modules
  - **Domain Artifacts**: Exports normalized domain JSON artifacts for tools
    and round-trip checks
  - **Domain Import Plans**: Checks import/readback plans and can write
    validated, placeholder-free domain previews from normalized artifacts
  - **Domain Inspection**: Generates Studio/tooling inspection JSON from
    normalized domain artifacts
  - **Domain Diagrams**: Generates Mermaid diagrams from domain inspection
    artifacts
  - **Domain Docs**: Generates Markdown references from normalized domain
    artifacts
  - **Domain Contract Verification**: Verifies consumer domain dependencies
    against provider published surfaces and snapshots published contracts
  - **Studio Host Artifacts**: Can generate trusted host-app inspection
    providers for `SelectoStudio.DomainArtifacts`

  ## Main Mix Tasks

  - `mix selecto.gen.domain` - Generate Selecto domain configurations from Ecto schemas
  - `mix selecto.install` - Install Selecto dependencies and setup project structure
  - `mix selecto.gen.saved_views` - Generate persistent saved views support
  - `mix selecto.gen.saved_view_configs` - Generate per-view-type saved config persistence
  - `mix selecto.gen.exported_views` - Generate exported iframe view persistence
  - `mix selecto.gen.filter_sets` - Generate filter set persistence
  - `mix selecto.domain.export` - Export normalized domain JSON artifacts
  - `mix selecto.domain.check` - Check normalized domain JSON artifacts
  - `mix selecto.domain.import` - Check import plans or write validated previews for normalized artifacts
  - `mix selecto.domain.inspect` - Inspect normalized domain JSON artifacts
  - `mix selecto.domain.describe` - Generate Studio/tooling inspection JSON from normalized artifacts
  - `mix selecto.domain.diagram` - Generate Mermaid diagrams from domain inspection artifacts
  - `mix selecto.domain.diff` - Diff normalized domain JSON artifacts
  - `mix selecto.domain.docs` - Generate Markdown docs from normalized domain JSON artifacts
  - `mix selecto.domain.verify` - Verify consumer dependencies against a provider artifact
  - `mix selecto.domain.contract.snapshot` - Write published domain contract snapshots
  - `mix selecto.domain.contract.diff` - Diff published domain contract snapshots

  ## Getting Started

  1. Add SelectoMix to your project dependencies
  2. Run `mix selecto.install` to setup basic structure
  3. Generate domains with `mix selecto.gen.domain --all`
  4. Put app-specific changes in the generated overlay modules
  5. Re-run `mix selecto.gen.domain --force` after schema changes to refresh generated base files

  ## Configuration

  You can configure SelectoMix in your `config/config.exs`:

      config :selecto_mix,
        output_dir: "lib/my_app/selecto_domains",
        default_associations: true

  ## Example Usage

      # Generate domain for a single schema
      mix selecto.gen.domain Blog.Post
      
      # Generate for all schemas in a context
      mix selecto.gen.domain Blog.*
      
      # Generate for all schemas with associations
      mix selecto.gen.domain --all --include-associations
      
      # Force regeneration of the generated base file
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

      dir ->
        dir
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
  List all available Ecto schemas in the current (host) Mix project.

  Uses `Mix.Project.config()[:app]` to resolve the current host application
  and inspects its compiled module list. Returns `[]` if there is no Mix
  project loaded (e.g. when called outside of a Mix task/session) or if the
  host application has no modules key available yet.
  """
  def discover_schemas do
    with app when not is_nil(app) <- host_app(),
         {:ok, modules} <- :application.get_key(app, :modules) do
      modules
      |> Enum.filter(&is_ecto_schema?/1)
    else
      _ -> []
    end
  end

  defp host_app do
    if Code.ensure_loaded?(Mix.Project) and function_exported?(Mix.Project, :config, 0) do
      Mix.Project.config()[:app]
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
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
