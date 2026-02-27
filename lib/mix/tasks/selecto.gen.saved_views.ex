defmodule Mix.Tasks.Selecto.Gen.SavedViews do
  @shortdoc "Generate SavedViews implementation for SelectoComponents"
  @moduledoc """
  Generate SavedViews behavior implementation for SelectoComponents.

  This task generates the necessary files to implement persistent saved views
  functionality in your SelectoComponents application.

  ## Examples

      # Generate for MyApp with default naming
      mix selecto.gen.saved_views MyApp

      # Generate with custom context module name  
      mix selecto.gen.saved_views MyApp --context-module MyApp.CustomSavedViewContext

      # Generate with custom schema module name
      mix selecto.gen.saved_views MyApp --schema-module MyApp.CustomSavedView

      # Generate with custom table name
      mix selecto.gen.saved_views MyApp --table-name custom_saved_views

      # Show what would be generated without creating files
      mix selecto.gen.saved_views MyApp --dry-run

  ## Options

    * `--context-module` - Name for the context module (default: APP.SavedViewContext)
    * `--schema-module` - Name for the schema module (default: APP.SavedView)  
    * `--table-name` - Database table name (default: saved_views)
    * `--repo-module` - Repository module name (default: APP.Repo)
    * `--dry-run` - Show what would be generated without creating files

  ## Generated Files

  This task generates:
  - Migration file for the saved_views table
  - Ecto schema module for SavedView
  - Context module implementing SelectoComponents.SavedViews behavior

  ## Usage in Domains

  After running the generator, use the context in your domains:

      defmodule MyApp.Domains.UserDomain do
        use MyApp.SavedViewContext
        
        # ... rest of domain configuration
      end

  Then in your LiveView, set the saved_view_context assign:

      def mount(_params, _session, socket) do
        socket = assign(socket, saved_view_context: MyApp.Domains.UserDomain)
        # ... rest of mount logic
      end
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.gen.saved_views MyApp --context-module MyApp.SavedViewContext",
      positional: [:app_name],
      schema: [
        context_module: :string,
        schema_module: :string,
        table_name: :string,
        repo_module: :string,
        dry_run: :boolean
      ],
      aliases: [
        c: :context_module,
        s: :schema_module,
        t: :table_name,
        r: :repo_module,
        d: :dry_run
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # Get parsed options and positional args from Igniter
    parsed_args = igniter.args.options
    positional = igniter.args.positional

    # Get the app_name positional argument
    app_name_arg = Map.get(positional, :app_name)

    if is_nil(app_name_arg) or app_name_arg == "" do
      igniter
      |> Igniter.add_warning("""
      App name is required. Usage:
        mix selecto.gen.saved_views MyApp
      """)
    else
      generate_saved_views_implementation(igniter, app_name_arg, parsed_args)
    end
  end

  # Private functions

  defp generate_saved_views_implementation(igniter, app_name, opts) do
    config = build_generation_config(app_name, opts)

    if opts[:dry_run] do
      show_dry_run_summary(config)
      igniter
    else
      igniter
      |> generate_migration_file(config)
      |> generate_schema_file(config)
      |> generate_context_file(config)
      |> add_success_messages(config)
    end
  end

  defp build_generation_config(app_name, opts) do
    app_module = Module.concat([app_name])

    %{
      app_name: app_name,
      app_module: app_module,
      context_module: parse_module_name(opts[:context_module] || "#{app_name}.SavedViewContext"),
      schema_module: parse_module_name(opts[:schema_module] || "#{app_name}.SavedView"),
      table_name: opts[:table_name] || "saved_views",
      repo_module: parse_module_name(opts[:repo_module] || "#{app_name}.Repo"),
      migration_name: "create_#{opts[:table_name] || "saved_views"}",
      timestamp: timestamp()
    }
  end

  defp parse_module_name(module_string) when is_binary(module_string) do
    Module.concat([module_string])
  end

  defp parse_module_name(module) when is_atom(module), do: module

  defp show_dry_run_summary(config) do
    IO.puts("""

    Selecto SavedViews Generation (DRY RUN)
    =======================================

    App Name: #{config.app_name}
    Table Name: #{config.table_name}

    Files to be generated:
    """)

    migration_file = migration_file_path(config)
    schema_file = schema_file_path(config)
    context_file = context_file_path(config)

    IO.puts("  • Migration: #{migration_file}")
    IO.puts("  • Schema:    #{schema_file}")
    IO.puts("  • Context:   #{context_file}")

    IO.puts("""

    Modules to be created:
      • #{inspect(config.schema_module)} (Ecto schema)
      • #{inspect(config.context_module)} (SavedViews behavior)

    Run without --dry-run to generate files.
    """)
  end

  defp generate_migration_file(igniter, config) do
    file_path = migration_file_path(config)
    content = render_migration_template(config)

    Igniter.create_new_file(igniter, file_path, content)
  end

  defp generate_schema_file(igniter, config) do
    file_path = schema_file_path(config)
    content = render_schema_template(config)

    Igniter.create_new_file(igniter, file_path, content)
  end

  defp generate_context_file(igniter, config) do
    file_path = context_file_path(config)
    content = render_context_template(config)

    Igniter.create_new_file(igniter, file_path, content)
  end

  defp migration_file_path(config) do
    "priv/repo/migrations/#{config.timestamp}_#{config.migration_name}.exs"
  end

  defp schema_file_path(config) do
    app_name = config.app_name |> to_string() |> Macro.underscore()

    schema_name =
      config.schema_module
      |> to_string()
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    "lib/#{app_name}/#{schema_name}.ex"
  end

  defp context_file_path(config) do
    app_name = config.app_name |> to_string() |> Macro.underscore()

    context_name =
      config.context_module
      |> to_string()
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    "lib/#{app_name}/#{context_name}.ex"
  end

  defp render_migration_template(config) do
    migration_module_name =
      "#{config.repo_module}.Migrations.#{Macro.camelize(config.migration_name)}"

    migration_module = Module.concat([migration_module_name])

    """
    defmodule #{inspect(migration_module)} do
      use Ecto.Migration

      def change do
        create table(:#{config.table_name}) do
          add :name, :string
          add :context, :string
          add :params, :map

          timestamps()
        end

        create(
          unique_index(
            :#{config.table_name},
            ~w(name context)a,
            name: :index_for_#{config.table_name}_name_context
          )
        )
      end
    end
    """
  end

  defp render_schema_template(config) do
    """
    defmodule #{inspect(config.schema_module)} do
      @moduledoc \"\"\"
      Ecto schema for saved views.
      
      Generated by mix selecto.gen.saved_views
      \"\"\"

      use Ecto.Schema
      import Ecto.Changeset

      schema "#{config.table_name}" do
        field :context, :string
        field :name, :string
        field :params, :map

        timestamps()
      end

      @doc false
      def changeset(saved_view, attrs) do
        saved_view
        |> cast(attrs, [:name, :context, :params])
        |> validate_required([:name, :context, :params])
        |> unique_constraint([:name, :context], name: :index_for_#{config.table_name}_name_context)
      end
    end
    """
  end

  defp render_context_template(config) do
    """
    defmodule #{inspect(config.context_module)} do
      @moduledoc \"\"\"
      Context module implementing SelectoComponents.SavedViews behavior.
      
      This module provides a `use` macro that adds saved views functionality
      to your domain modules.
      
      Generated by mix selecto.gen.saved_views
      
      ## Usage
      
          defmodule MyApp.Domains.UserDomain do
            use #{inspect(config.context_module)}
            
            # ... rest of domain configuration
          end
      \"\"\"

      defmacro __using__(_opts \\\\ []) do
        quote do
          @behaviour SelectoComponents.SavedViews

          import Ecto.Query

          def get_view(name, context) do
            q = from v in #{inspect(config.schema_module)},
              where: ^context == v.context,
              where: ^name == v.name
            #{inspect(config.repo_module)}.one(q)
          end

          def save_view(name, context, params) do
            case get_view(name, context) do
              nil -> #{inspect(config.repo_module)}.insert!(%#{inspect(config.schema_module)}{name: name, context: context, params: params})
              view -> update_view(view, params)
            end
          end

          defp update_view(view, params) do
            {:ok, view} = #{inspect(config.schema_module)}.changeset(view, %{params: params})
              |> #{inspect(config.repo_module)}.update()
            view
          end

          def get_view_names(context) do
            q = from v in #{inspect(config.schema_module)},
              select: v.name,
              where: ^context == v.context,
              order_by: v.name

            #{inspect(config.repo_module)}.all(q)
          end

          def list_views(context) do
            q =
              from v in #{inspect(config.schema_module)},
                where: ^context == v.context,
                order_by: [desc: v.updated_at, asc: v.name]

            #{inspect(config.repo_module)}.all(q)
          end

          def delete_view(name, context) do
            case get_view(name, context) do
              nil ->
                {:error, :not_found}

              view ->
                #{inspect(config.repo_module)}.delete(view)
            end
          end

          def rename_view(old_name, new_name, context) do
            trimmed_name = String.trim(new_name || "")

            cond do
              trimmed_name == "" ->
                {:error, :invalid_name}

              old_name == trimmed_name ->
                case get_view(old_name, context) do
                  nil -> {:error, :not_found}
                  view -> {:ok, view}
                end

              true ->
                case get_view(old_name, context) do
                  nil ->
                    {:error, :not_found}

                  view ->
                    if get_view(trimmed_name, context) do
                      {:error, :already_exists}
                    else
                      view
                      |> #{inspect(config.schema_module)}.changeset(%{name: trimmed_name})
                      |> #{inspect(config.repo_module)}.update()
                    end
                end
            end
          end

          def decode_view(view) do
            # Return params to use for view restoration
            view.params
          end
        end
      end
    end
    """
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  defp add_success_messages(igniter, config) do
    igniter
    |> Igniter.add_notice("Generated migration: #{migration_file_path(config)}")
    |> Igniter.add_notice("Generated schema: #{inspect(config.schema_module)}")
    |> Igniter.add_notice("Generated context: #{inspect(config.context_module)}")
    |> Igniter.add_notice("""

    Next steps:
    1. Run: mix ecto.migrate
    2. Add 'use #{inspect(config.context_module)}' to your domain modules
    3. Set saved_view_context assign in your LiveViews
    """)
  end
end
