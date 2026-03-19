defmodule Mix.Tasks.Selecto.Gen.ExportedViews do
  @shortdoc "Generate ExportedViews implementation for iframe embeds"
  @moduledoc """
  Generate ExportedViews persistence for SelectoComponents iframe embeds.

  This task creates the schema, context, and migration needed to back
  SelectoComponents exported views with signed iframe access, cache metadata,
  and optional IP allowlists.

  Generated exports persist the currently active view mode. The generated schema
  accepts the current built-in and extension-contributed view modes used by
  SelectoComponents, including `detail`, `aggregate`, `graph`, `timeseries`,
  `chart`, `table`, and `map`.

  ## Examples

      mix selecto.gen.exported_views MyApp
      mix selecto.gen.exported_views MyApp --context-module MyApp.ExportedViewContext
      mix selecto.gen.exported_views MyApp --schema-module MyApp.ExportedView
      mix selecto.gen.exported_views MyApp --table-name exported_views
      mix selecto.gen.exported_views MyApp --dry-run

  ## Options

    * `--context-module` - Name for the context module (default: APP.ExportedViewContext)
    * `--schema-module` - Name for the schema module (default: APP.ExportedView)
    * `--table-name` - Database table name (default: exported_views)
    * `--repo-module` - Repository module name (default: APP.Repo)
    * `--dry-run` - Show what would be generated without creating files
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.gen.exported_views MyApp --context-module MyApp.ExportedViewContext",
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
    opts = igniter.args.options
    app_name = Map.get(igniter.args.positional, :app_name)

    if is_nil(app_name) or app_name == "" do
      Igniter.add_warning(
        igniter,
        "App name is required. Usage: mix selecto.gen.exported_views MyApp"
      )
    else
      generate_exported_views(igniter, app_name, opts)
    end
  end

  defp generate_exported_views(igniter, app_name, opts) do
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
    %{
      app_name: app_name,
      context_module:
        parse_module_name(opts[:context_module] || "#{app_name}.ExportedViewContext"),
      schema_module: parse_module_name(opts[:schema_module] || "#{app_name}.ExportedView"),
      table_name: opts[:table_name] || "exported_views",
      repo_module: parse_module_name(opts[:repo_module] || "#{app_name}.Repo"),
      migration_name: "create_#{opts[:table_name] || "exported_views"}",
      timestamp: timestamp()
    }
  end

  defp parse_module_name(module_string) when is_binary(module_string),
    do: Module.concat([module_string])

  defp parse_module_name(module) when is_atom(module), do: module

  defp show_dry_run_summary(config) do
    IO.puts("""

    Selecto ExportedViews Generation (DRY RUN)
    ==========================================

    App Name: #{config.app_name}
    Table Name: #{config.table_name}

    Files to be generated:
      - #{migration_file_path(config)}
      - #{schema_file_path(config)}
      - #{context_file_path(config)}

    Modules to be created:
      - #{inspect(config.schema_module)}
      - #{inspect(config.context_module)}
    """)
  end

  defp generate_migration_file(igniter, config) do
    Igniter.create_new_file(
      igniter,
      migration_file_path(config),
      render_migration_template(config)
    )
  end

  defp generate_schema_file(igniter, config) do
    Igniter.create_new_file(igniter, schema_file_path(config), render_schema_template(config))
  end

  defp generate_context_file(igniter, config) do
    Igniter.create_new_file(igniter, context_file_path(config), render_context_template(config))
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
    migration_module =
      Module.concat([
        "#{config.repo_module}.Migrations.#{Macro.camelize(config.migration_name)}"
      ])

    """
    defmodule #{inspect(migration_module)} do
      use Ecto.Migration

      def change do
        create table(:#{config.table_name}) do
          add :name, :string, null: false
          add :context, :string, null: false
          add :path, :string
          add :view_type, :string, null: false
          add :public_id, :string, null: false
          add :signature_version, :integer, null: false, default: 1
          add :cache_ttl_hours, :integer, null: false, default: 3
          add :ip_allowlist_text, :text
          add :snapshot_blob, :binary, null: false
          add :cache_blob, :binary
          add :cache_generated_at, :utc_datetime_usec
          add :cache_expires_at, :utc_datetime_usec
          add :last_execution_time_ms, :float
          add :last_row_count, :integer
          add :last_payload_bytes, :integer
          add :access_count, :integer, null: false, default: 0
          add :last_accessed_at, :utc_datetime_usec
          add :last_error, :text
          add :disabled_at, :utc_datetime_usec
          add :user_id, :string

          timestamps(type: :utc_datetime_usec)
        end

        create unique_index(:#{config.table_name}, [:public_id])
        create index(:#{config.table_name}, [:context])
        create index(:#{config.table_name}, [:context, :user_id])
        create index(:#{config.table_name}, [:cache_expires_at])
      end
    end
    """
  end

  defp render_schema_template(config) do
    """
    defmodule #{inspect(config.schema_module)} do
      @moduledoc \"\"\"
      Ecto schema for SelectoComponents exported iframe views.

      Generated by mix selecto.gen.exported_views
      \"\"\"

      use Ecto.Schema
      import Ecto.Changeset

      @view_types ~w(detail aggregate graph timeseries chart table map)
      @ttl_hours [3, 6, 12]

      schema "#{config.table_name}" do
        field :name, :string
        field :context, :string
        field :path, :string
        field :view_type, :string
        field :public_id, :string
        field :signature_version, :integer, default: 1
        field :cache_ttl_hours, :integer, default: 3
        field :ip_allowlist_text, :string
        field :snapshot_blob, :binary
        field :cache_blob, :binary
        field :cache_generated_at, :utc_datetime_usec
        field :cache_expires_at, :utc_datetime_usec
        field :last_execution_time_ms, :float
        field :last_row_count, :integer
        field :last_payload_bytes, :integer
        field :access_count, :integer, default: 0
        field :last_accessed_at, :utc_datetime_usec
        field :last_error, :string
        field :disabled_at, :utc_datetime_usec
        field :user_id, :string

        timestamps(type: :utc_datetime_usec)
      end

      @doc false
      def changeset(exported_view, attrs) do
        exported_view
        |> cast(attrs, [
          :name,
          :context,
          :path,
          :view_type,
          :public_id,
          :signature_version,
          :cache_ttl_hours,
          :ip_allowlist_text,
          :snapshot_blob,
          :cache_blob,
          :cache_generated_at,
          :cache_expires_at,
          :last_execution_time_ms,
          :last_row_count,
          :last_payload_bytes,
          :access_count,
          :last_accessed_at,
          :last_error,
          :disabled_at,
          :user_id
        ])
        |> validate_required([:name, :context, :view_type, :public_id, :snapshot_blob, :cache_ttl_hours])
        |> validate_length(:name, min: 1, max: 255)
        |> validate_inclusion(:view_type, @view_types)
        |> validate_inclusion(:cache_ttl_hours, @ttl_hours)
        |> unique_constraint(:public_id)
      end
    end
    """
  end

  defp render_context_template(config) do
    """
    defmodule #{inspect(config.context_module)} do
      @moduledoc \"\"\"
      Persistence adapter for SelectoComponents exported iframe views.

      Generated by mix selecto.gen.exported_views
      \"\"\"

      @behaviour SelectoComponents.ExportedViews

      import Ecto.Query

      alias #{inspect(config.repo_module)}
      alias #{inspect(config.schema_module)}

      @impl true
      def list_exported_views(context, opts \\ []) do
        user_id = Keyword.get(opts, :user_id)

        #{inspect(config.schema_module)}
        |> where([view], view.context == ^context)
        |> maybe_scope_user(user_id)
        |> order_by([view], desc: view.updated_at, asc: view.name)
        |> Repo.all()
      end

      @impl true
      def get_exported_view_by_public_id(public_id, _opts \\ []) do
        Repo.get_by(#{inspect(config.schema_module)}, public_id: public_id)
      end

      @impl true
      def create_exported_view(attrs, opts \\ []) do
        attrs = maybe_put_user_id(attrs, Keyword.get(opts, :user_id))

        %#{inspect(config.schema_module)}{}
        |> #{inspect(config.schema_module)}.changeset(attrs)
        |> Repo.insert()
      end

      @impl true
      def update_exported_view(%#{inspect(config.schema_module)}{} = exported_view, attrs, _opts \\ []) do
        exported_view
        |> #{inspect(config.schema_module)}.changeset(attrs)
        |> Repo.update()
      end

      @impl true
      def delete_exported_view(%#{inspect(config.schema_module)}{} = exported_view, _opts \\ []) do
        Repo.delete(exported_view)
      end

      defp maybe_scope_user(query, nil), do: query

      defp maybe_scope_user(query, user_id) do
        where(query, [view], view.user_id == ^user_id)
      end

      defp maybe_put_user_id(attrs, nil), do: attrs
      defp maybe_put_user_id(attrs, user_id), do: Map.put_new(attrs, :user_id, user_id)
    end
    """
  end

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()
    "#{year}#{pad(month)}#{pad(day)}#{pad(hour)}#{pad(minute)}#{pad(second)}"
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
    2. Assign `exported_view_module`, `exported_view_context`, and `exported_view_endpoint` in your LiveView
    3. Add a wrapper LiveView that delegates to `SelectoComponents.ExportedViews.EmbedLive`
    4. Wire a public route like `/selecto/exported/:public_id`
    5. If you use `SelectoComponents.Form`, the exported views manager renders automatically once `exported_view_module` is assigned
    """)
  end
end
