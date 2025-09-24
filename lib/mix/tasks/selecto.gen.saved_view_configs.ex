defmodule Mix.Tasks.Selecto.Gen.SavedViewConfigs do
  @shortdoc "Generate SavedViewConfigs implementation for view type separation"
  @moduledoc """
  Generate SavedViewConfigs implementation for separate view type configurations.

  This task generates the necessary files to implement saved view configurations
  that are separate by view type (detail, aggregate, graph) in your SelectoComponents application.

  ## Examples

      # Generate for MyApp with default naming
      mix selecto.gen.saved_view_configs MyApp

      # Generate with custom context module name
      mix selecto.gen.saved_view_configs MyApp --context-module MyApp.ViewConfigs.Context

      # Generate with custom schema module name
      mix selecto.gen.saved_view_configs MyApp --schema-module MyApp.ViewConfigs.SavedConfig

      # Generate with custom table name
      mix selecto.gen.saved_view_configs MyApp --table-name view_configurations

      # Show what would be generated without creating files
      mix selecto.gen.saved_view_configs MyApp --dry-run

  ## Options

    * `--context-module` - Name for the context module (default: APP.SavedViewConfigContext)
    * `--schema-module` - Name for the schema module (default: APP.SavedViewConfig)
    * `--table-name` - Database table name (default: saved_view_configs)
    * `--repo-module` - Repository module name (default: APP.Repo)
    * `--dry-run` - Show what would be generated without creating files

  ## Generated Files

  This task generates:
  - Migration file for the saved_view_configs table with view_type separation
  - Ecto schema module for SavedViewConfig
  - Context module with view_type filtering support

  ## Usage in Domains

  After running the generator, use the context in your domains:

      defmodule MyApp.Domains.UserDomain do
        use MyApp.SavedViewConfigContext

        # ... rest of domain configuration
      end

  Then in your LiveView, use the new saved view configurations:

      def handle_event("save_view_config", params, socket) do
        view_type = socket.assigns.view_config.view_mode

        MyApp.Domains.UserDomain.save_view_config(
          params["name"],
          socket.assigns.saved_view_context,
          view_type,
          view_config_to_params(socket.assigns.view_config),
          user_id: socket.assigns.current_user.id,
          description: params["description"]
        )

        {:noreply, socket}
      end
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.gen.saved_view_configs MyApp --context-module MyApp.SavedViewConfigContext",
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
    {parsed_args, remaining_args} = OptionParser.parse!(igniter.args.argv, strict: info(igniter.args.argv, nil).schema)

    app_name_arg = List.first(remaining_args)

    if is_nil(app_name_arg) or app_name_arg == "" do
      Igniter.add_warning(igniter, """
      App name is required. Usage:
        mix selecto.gen.saved_view_configs MyApp
      """)
    else
      generate_saved_view_configs_implementation(igniter, app_name_arg, parsed_args)
    end
  end

  # Private functions

  defp generate_saved_view_configs_implementation(igniter, app_name, opts) do
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
      context_module: parse_module_name(opts[:context_module] || "#{app_name}.SavedViewConfigContext"),
      schema_module: parse_module_name(opts[:schema_module] || "#{app_name}.SavedViewConfig"),
      table_name: opts[:table_name] || "saved_view_configs",
      repo_module: parse_module_name(opts[:repo_module] || "#{app_name}.Repo"),
      migration_name: "create_#{opts[:table_name] || "saved_view_configs"}",
      timestamp: timestamp()
    }
  end

  defp parse_module_name(module_string) when is_binary(module_string) do
    Module.concat([module_string])
  end
  defp parse_module_name(module) when is_atom(module), do: module

  defp show_dry_run_summary(config) do
    IO.puts("""

    Selecto SavedViewConfigs Generation (DRY RUN)
    =============================================

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
      • #{inspect(config.schema_module)} (Ecto schema with view_type)
      • #{inspect(config.context_module)} (Context with view type filtering)

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
    schema_name = config.schema_module |> to_string() |> String.split(".") |> List.last() |> Macro.underscore()
    "lib/#{app_name}/#{schema_name}.ex"
  end

  defp context_file_path(config) do
    app_name = config.app_name |> to_string() |> Macro.underscore()
    context_name = config.context_module |> to_string() |> String.split(".") |> List.last() |> Macro.underscore()
    "lib/#{app_name}/#{context_name}.ex"
  end

  defp render_migration_template(config) do
    migration_module_name = "#{config.repo_module}.Migrations.#{Macro.camelize(config.migration_name)}"
    migration_module = Module.concat([migration_module_name])

    """
    defmodule #{inspect(migration_module)} do
      use Ecto.Migration

      def change do
        create table(:#{config.table_name}) do
          add :name, :string, null: false
          add :context, :string, null: false
          add :view_type, :string, null: false  # "detail", "aggregate", "graph"
          add :params, :map, null: false
          add :user_id, :string
          add :description, :text
          add :is_public, :boolean, default: false
          add :version, :integer, default: 1

          timestamps()
        end

        # Unique constraint for each view type per user
        create(
          unique_index(
            :#{config.table_name},
            ~w(name context view_type user_id)a,
            name: :#{config.table_name}_unique_name_per_view_type
          )
        )

        # Index for querying by view type and context
        create(
          index(
            :#{config.table_name},
            ~w(view_type context)a,
            name: :#{config.table_name}_view_type_context_idx
          )
        )

        # Index for user queries
        create(
          index(
            :#{config.table_name},
            [:user_id],
            name: :#{config.table_name}_user_id_idx
          )
        )

        # Index for public views
        create(
          index(
            :#{config.table_name},
            [:is_public],
            name: :#{config.table_name}_public_idx
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
      Ecto schema for saved view configurations with view type separation.

      Generated by mix selecto.gen.saved_view_configs
      \"\"\"

      use Ecto.Schema
      import Ecto.Changeset

      @view_types ~w(detail aggregate graph)

      schema "#{config.table_name}" do
        field :name, :string
        field :context, :string
        field :view_type, :string
        field :params, :map
        field :user_id, :string
        field :description, :string
        field :is_public, :boolean, default: false
        field :version, :integer, default: 1

        timestamps()
      end

      @doc false
      def changeset(saved_view_config, attrs) do
        saved_view_config
        |> cast(attrs, [:name, :context, :view_type, :params, :user_id, :description, :is_public, :version])
        |> validate_required([:name, :context, :view_type, :params])
        |> validate_inclusion(:view_type, @view_types)
        |> validate_length(:name, min: 1, max: 255)
        |> validate_length(:description, max: 1000)
        |> unique_constraint([:name, :context, :view_type, :user_id],
             name: :#{config.table_name}_unique_name_per_view_type)
      end

      @doc "Returns the list of valid view types"
      def view_types, do: @view_types
    end
    """
  end

  defp render_context_template(config) do
    """
    defmodule #{inspect(config.context_module)} do
      @moduledoc \"\"\"
      Context module for saved view configurations with view type separation.

      This module provides a `use` macro that adds saved view configuration
      functionality to your domain modules, with support for different view types.

      Generated by mix selecto.gen.saved_view_configs

      ## Usage

          defmodule MyApp.Domains.UserDomain do
            use #{inspect(config.context_module)}

            # ... rest of domain configuration
          end
      \"\"\"

      defmacro __using__(_opts \\\\ []) do
        quote do
          import Ecto.Query

          @doc \"\"\"
          Get a saved view configuration by name, context, and view type.
          \"\"\"
          def get_view_config(name, context, view_type, opts \\\\ []) do
            user_id = Keyword.get(opts, :user_id)

            query =
              from v in #{inspect(config.schema_module)},
                where: v.name == ^name,
                where: v.context == ^context,
                where: v.view_type == ^view_type

            query =
              if user_id do
                from v in query,
                  where: v.user_id == ^user_id or v.is_public == true
              else
                from v in query,
                  where: v.is_public == true
              end

            #{inspect(config.repo_module)}.one(query)
          end

          @doc \"\"\"
          Save or update a view configuration.
          \"\"\"
          def save_view_config(name, context, view_type, params, opts \\\\ []) do
            user_id = Keyword.get(opts, :user_id)
            description = Keyword.get(opts, :description)
            is_public = Keyword.get(opts, :is_public, false)

            case get_view_config(name, context, view_type, user_id: user_id) do
              nil ->
                %#{inspect(config.schema_module)}{}
                |> #{inspect(config.schema_module)}.changeset(%{
                  name: name,
                  context: context,
                  view_type: view_type,
                  params: params,
                  user_id: user_id,
                  description: description,
                  is_public: is_public
                })
                |> #{inspect(config.repo_module)}.insert()

              existing ->
                existing
                |> #{inspect(config.schema_module)}.changeset(%{
                  params: params,
                  description: description,
                  is_public: is_public
                })
                |> #{inspect(config.repo_module)}.update()
            end
          end

          @doc \"\"\"
          List view configurations for a context and view type.
          \"\"\"
          def list_view_configs(context, view_type, opts \\\\ []) do
            user_id = Keyword.get(opts, :user_id)
            include_public = Keyword.get(opts, :include_public, true)

            query =
              from v in #{inspect(config.schema_module)},
                where: v.context == ^context,
                where: v.view_type == ^view_type,
                order_by: [desc: v.updated_at]

            query =
              cond do
                user_id && include_public ->
                  from v in query,
                    where: v.user_id == ^user_id or v.is_public == true

                user_id ->
                  from v in query,
                    where: v.user_id == ^user_id

                include_public ->
                  from v in query,
                    where: v.is_public == true

                true ->
                  from v in query,
                    where: false
              end

            #{inspect(config.repo_module)}.all(query)
          end

          @doc \"\"\"
          Delete a view configuration.
          \"\"\"
          def delete_view_config(name, context, view_type, opts \\\\ []) do
            user_id = Keyword.get(opts, :user_id)

            case get_view_config(name, context, view_type, user_id: user_id) do
              nil -> {:error, :not_found}
              config ->
                if config.user_id == user_id do
                  #{inspect(config.repo_module)}.delete(config)
                else
                  {:error, :unauthorized}
                end
            end
          end

          @doc \"\"\"
          Update a view configuration.
          \"\"\"
          def update_view_config(name, context, view_type, params, opts \\\\ []) do
            user_id = Keyword.get(opts, :user_id)
            description = Keyword.get(opts, :description)
            is_public = Keyword.get(opts, :is_public)

            case get_view_config(name, context, view_type, user_id: user_id) do
              nil ->
                {:error, :not_found}

              config ->
                if config.user_id == user_id do
                  config
                  |> #{inspect(config.schema_module)}.changeset(%{
                    params: params,
                    description: description,
                    is_public: is_public
                  })
                  |> #{inspect(config.repo_module)}.update()
                else
                  {:error, :unauthorized}
                end
            end
          end

          @doc \"\"\"
          Get just the names of saved view configs for a context and view type.
          \"\"\"
          def get_view_config_names(context, view_type, opts \\\\ []) do
            configs = list_view_configs(context, view_type, opts)
            Enum.map(configs, fn config -> config.name end)
          end

          @doc \"\"\"
          Decode a view configuration to get its params.
          \"\"\"
          def decode_view_config(view_config) do
            view_config.params
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
    3. Update your LiveView to use view_type when saving/loading configs
    """)
  end
end