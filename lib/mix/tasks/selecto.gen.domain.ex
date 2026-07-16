defmodule Mix.Tasks.Selecto.Gen.Domain do
  @shortdoc "Generate Selecto domain configuration from Ecto schemas"
  @moduledoc """
  Generate Selecto domain configuration from Ecto schemas or database relations with Igniter support.

  This task automatically discovers Ecto schemas in your project and generates
  corresponding Selecto domain configurations. Generated base files are
  regenerated intentionally; app-specific customizations belong in overlays.

  ## Examples

      # Generate domain for a single schema
      mix selecto.gen.domain Blog.Post

      # Generate domains for all schemas in a context
      mix selecto.gen.domain Blog.*

      # Generate domains for all schemas in the project
      mix selecto.gen.domain --all

      # Generate with specific output directory
      mix selecto.gen.domain Blog.Post --output lib/blog/selecto_domains

      # Force regenerate the generated base file
      mix selecto.gen.domain Blog.Post --force

      # Expand associated schemas with full columns/associations
      mix selecto.gen.domain Blog.Post --expand-schemas categories,tags,authors

      # Generate a read-only domain from an existing database view
      mix selecto.gen.domain --adapter postgresql --view reporting.active_customers --primary-key customer_id

      # Generate from a materialized view
      mix selecto.gen.domain --adapter postgresql --materialized-view reporting.daily_rollup --primary-key customer_id

      # Use special join modes for optimized queries
      mix selecto.gen.domain Product --expand-tag Tags:name --expand-star Category:category_name

  ## Options

     * `--all` - Generate domains for all discovered Ecto schemas
     * `--output` - Specify output directory (default: lib/APP_NAME/selecto_domains)
     * `--force` - Overwrite existing generated domain files
     * `--dry-run` - Show what would be generated without creating files
     * `--include-associations` - Include associations as joins (default: true)
     * `--exclude` - Comma-separated list of schemas to exclude
     * `--live` - Generate LiveView files for the domain
     * `--studio-artifacts` - Generate a host-app Studio inspection provider module
     * `--saved-views` - Generate saved views implementation (requires --live)
     * `--expand-schemas` - Comma-separated list of associated schemas to fully expand with columns and associations
    * `--expand-tag` - Many-to-many tag mode: TableName:display_field (uses IDs, prevents denormalization)
    * `--expand-star` - Star schema mode: TableName:display_field (lookup table with ID-based filtering)
    * `--expand-lookup` - Lookup table mode: TableName:display_field (small reference tables)
    * `--expand-polymorphic` - Polymorphic association: field_name:type_field,id_field:Type1,Type2,Type3
     * `--parameterized-joins` - Generate example parameterized join configurations
     * `--path` - Custom path for the LiveView route (e.g., /products instead of /product)
     * `--enable-modal` - Enable modal detail view for row clicks in LiveView (requires --live)
     * `--view` - Introspect an existing database view as a read-only domain source
     * `--materialized-view` - Introspect an existing materialized view as a read-only domain source
     * `--primary-key` - Explicit primary key column for DB views/materialized views
     * `--include-views` - Include views and materialized views when generating DB-backed domains with `--all`

  ## File Generation

  For each schema, generates:
  - `schemas/SCHEMA_NAME_domain.ex` - Selecto domain configuration

  With `--live` flag, additionally generates:
  - `live/SCHEMA_NAME_live.ex` - LiveView module
  - `live/SCHEMA_NAME_live.html.heex` - LiveView template

  With `--studio-artifacts` flag, additionally generates:
  - `schemas/SCHEMA_NAME_domain_artifacts.ex` - trusted inspection provider
    module for `SelectoStudio.DomainArtifacts` host-app registration

  With `--saved-views` flag, additionally generates:
  - SavedView schema and context modules (if not already present)
  - Saved views integration in the LiveView

  ## Customization

  Generated domain files are treated as generated code. Put app-specific
  customizations in the generated overlay module so schema refreshes can
  replace the base domain intentionally.
  """

  use Igniter.Mix.Task

  alias SelectoMix.{
    AdapterResolver,
    Connection,
    ConnectionOpts,
    LiveViewGenerator,
    SchemaDiscovery,
    StudioArtifactsGenerator
  }

  alias SelectoMix.Gen.DomainPaths

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example:
        "mix selecto.gen.domain Blog.Post --include-associations --expand-schemas categories",
      positional: [:schemas],
      schema:
        [
          all: :boolean,
          output: :string,
          force: :boolean,
          dry_run: :boolean,
          include_associations: :boolean,
          exclude: :string,
          live: :boolean,
          studio_artifacts: :boolean,
          saved_views: :boolean,
          expand_schemas: :string,
          expand_tag: :keep,
          expand_star: :keep,
          expand_lookup: :keep,
          expand_polymorphic: :keep,
          parameterized_joins: :boolean,
          path: :string,
          enable_modal: :boolean
        ] ++ ConnectionOpts.connection_schema(),
      aliases:
        [
          a: :all,
          o: :output,
          f: :force,
          d: :dry_run,
          l: :live,
          s: :saved_views,
          e: :expand_schemas,
          p: :parameterized_joins
        ] ++ ConnectionOpts.connection_aliases()
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # Note: Don't call Mix.Task.run from within Igniter tasks (causes conflicts in Igniter 0.6.x)
    # Compilation will happen automatically before the task runs

    # Get parsed options and positional args from Igniter
    options = igniter.args.options
    positional = igniter.args.positional

    # Convert keyword list to map for easier manipulation
    parsed_args = Map.new(options) |> Map.put_new(:include_associations, true)

    # Get the schemas positional argument
    schemas_arg = Map.get(positional, :schemas, "")

    # Parse expand-schemas parameter
    expand_schemas = SchemaDiscovery.parse_expand_schemas(parsed_args[:expand_schemas] || "")

    # Parse special join mode parameters
    expand_modes = SchemaDiscovery.parse_expand_modes(parsed_args)

    # Auto-add schemas with join modes to expand list
    schemas_from_modes = Map.keys(expand_modes)
    expand_schemas = Enum.uniq(expand_schemas ++ schemas_from_modes)

    # Validate flags
    validated_igniter = validate_flags(igniter, parsed_args)

    updated_args =
      parsed_args
      |> Map.put(:expand_schemas_list, expand_schemas)
      |> Map.put(:expand_modes, expand_modes)

    if db_mode?(updated_args, schemas_arg) do
      process_db_sources(validated_igniter, updated_args)
    else
      schemas =
        cond do
          updated_args[:all] -> SchemaDiscovery.discover_all_schemas(igniter)
          schemas_arg != "" -> SchemaDiscovery.parse_schema_patterns(igniter, schemas_arg)
          true -> []
        end

      exclude_patterns = SchemaDiscovery.parse_exclude_patterns(updated_args[:exclude] || "")

      schemas =
        Enum.reject(schemas, &SchemaDiscovery.schema_matches_exclude?(&1, exclude_patterns))

      if Enum.empty?(schemas) do
        validated_igniter
        |> Igniter.add_warning("""
        No schemas specified. Use one of:
          mix selecto.gen.domain MyApp.Schema
          mix selecto.gen.domain MyApp.Context.*
          mix selecto.gen.domain --all
          mix selecto.gen.domain --adapter postgresql --table users
        """)
      else
        process_schemas(validated_igniter, schemas, updated_args)
      end
    end
  end

  @doc false
  def artifact_guidance(
        domain_module,
        artifact_path,
        docs_path \\ nil,
        inspection_path \\ nil,
        diagram_path \\ nil
      ) do
    docs_path = docs_path || DomainPaths.default_docs_path(artifact_path)
    inspection_path = inspection_path || DomainPaths.default_inspection_path(artifact_path)
    diagram_path = diagram_path || DomainPaths.default_diagram_path(artifact_path)

    """

    Domain artifact follow-up:
      mix selecto.domain.export #{domain_module} --output #{artifact_path}
      mix selecto.domain.check #{artifact_path}
      mix selecto.domain.import #{artifact_path} --check
      mix selecto.domain.inspect #{artifact_path}
      mix selecto.domain.describe #{artifact_path} --output #{inspection_path}
      mix selecto.domain.diagram #{inspection_path} --output #{diagram_path}
      mix selecto.domain.docs #{artifact_path} --output #{docs_path}
    """
  end

  # Private functions

  defp validate_flags(igniter, parsed_args) do
    cond do
      parsed_args[:saved_views] && !parsed_args[:live] ->
        igniter
        |> Igniter.add_warning("--saved-views flag requires --live flag to be set")

      parsed_args[:view] && parsed_args[:materialized_view] ->
        igniter
        |> Igniter.add_warning("Specify only one of --view or --materialized-view")

      (parsed_args[:view] || parsed_args[:materialized_view]) && is_nil(parsed_args[:primary_key]) ->
        igniter
        |> Igniter.add_warning(
          "View-backed generation requires --primary-key because views often do not expose a detectable key"
        )

      parsed_args[:table] && is_nil(parsed_args[:adapter]) ->
        igniter
        |> Igniter.add_warning(
          "DB-backed generation requires --adapter (for example: --adapter postgresql)"
        )

      true ->
        igniter
    end
  end

  defp db_mode?(parsed_args, schemas_arg) do
    parsed_args[:adapter] ||
      parsed_args[:table] ||
      parsed_args[:view] ||
      parsed_args[:materialized_view] ||
      parsed_args[:database_url] ||
      parsed_args[:database] ||
      (parsed_args[:host] && schemas_arg == "")
  end

  defp process_db_sources(igniter, opts) do
    with {:ok, adapter} <- resolve_adapter(opts[:adapter]),
         {:ok, conn_opts} <- resolve_db_connection_opts(opts),
         {:ok, updated_igniter} <- with_db_connection(adapter, conn_opts, igniter, opts) do
      updated_igniter
    else
      {:error, :missing_adapter} ->
        Igniter.add_warning(
          igniter,
          "DB-backed generation requires --adapter. Known adapters: #{Enum.join(AdapterResolver.known_adapter_names(), ", ")}"
        )

      {:error, reason} ->
        Igniter.add_warning(
          igniter,
          "Failed to generate from database source: #{AdapterResolver.format_adapter_error(reason)}"
        )
    end
  end

  defp with_db_connection(adapter, conn_opts, igniter, opts) do
    Connection.with_connection(adapter, conn_opts, fn conn ->
      db_schema = opts[:schema] || "public"
      exclude_patterns = SchemaDiscovery.parse_exclude_patterns(opts[:exclude] || "")

      tables =
        cond do
          opts[:all] -> SchemaDiscovery.discover_all_relations(adapter, conn, db_schema, opts)
          view = opts[:view] -> [view]
          materialized_view = opts[:materialized_view] -> [materialized_view]
          table = opts[:table] -> [table]
          true -> []
        end

      tables = Enum.reject(tables, &SchemaDiscovery.table_matches_exclude?(&1, exclude_patterns))

      if Enum.empty?(tables) do
        Igniter.add_warning(
          igniter,
          "No DB source specified. Use one of: mix selecto.gen.domain --adapter postgresql --table TABLE_NAME, --view VIEW_NAME, --materialized-view VIEW_NAME, or --all"
        )
      else
        process_db_tables(igniter, adapter, conn, tables, Map.put(opts, :db_schema, db_schema))
      end
    end)
  end

  defp resolve_adapter(nil), do: {:error, :missing_adapter}
  defp resolve_adapter(adapter), do: AdapterResolver.resolve(adapter)

  defp resolve_db_connection_opts(opts) do
    conn_opts = ConnectionOpts.from_parsed_args(opts)

    if conn_opts == [] do
      {:error, :missing_connection_opts}
    else
      {:ok, conn_opts}
    end
  end

  defp process_db_tables(igniter, adapter, conn, relations, opts) do
    output_dir = DomainPaths.get_output_directory(igniter, opts[:output])
    opts = Map.put_new(opts, :app_name, Igniter.Project.Application.app_name(igniter))

    if opts[:dry_run] do
      show_dry_run_summary(Enum.map(relations, & &1.name), output_dir, opts)
      igniter
    else
      Enum.reduce(relations, igniter, fn relation, acc_igniter ->
        source_kind = relation_source_kind(opts, relation)

        source =
          {:db, adapter, conn, relation.name,
           [
             schema: opts[:db_schema],
             expand: opts[:expand] || false,
             source_kind: source_kind,
             primary_key: parse_primary_key_override(opts[:primary_key])
           ]}

        generate_domain_for_source(acc_igniter, source, output_dir, opts)
      end)
    end
  end

  defp relation_source_kind(opts, relation) do
    cond do
      opts[:materialized_view] -> :materialized_view
      opts[:view] -> :view
      true -> relation[:source_kind] || :table
    end
  end

  defp parse_primary_key_override(nil), do: nil
  defp parse_primary_key_override(value) when is_atom(value), do: value

  defp parse_primary_key_override(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> SelectoMix.Identifier.to_atom!(trimmed)
    end
  end

  defp process_schemas(igniter, schemas, opts) do
    output_dir = DomainPaths.get_output_directory(igniter, opts[:output])

    if opts[:dry_run] do
      show_dry_run_summary(schemas, output_dir, opts)
      igniter
    else
      # Generate saved views implementation FIRST if requested and not already present
      # This must happen before domain generation to avoid circular compilation dependencies
      igniter_with_saved_views =
        if opts[:saved_views] do
          generate_saved_views_if_needed(igniter, opts)
        else
          igniter
        end

      # Now generate domain files
      Enum.reduce(schemas, igniter_with_saved_views, fn schema, acc_igniter ->
        generate_domain_for_source(acc_igniter, schema, output_dir, opts)
      end)
    end
  end

  defp show_dry_run_summary(schemas, output_dir, opts) do
    IO.puts("""

    Selecto Domain Generation (DRY RUN)
    ===================================

    Output directory: #{output_dir}
    Include associations: #{opts[:include_associations]}
    Force overwrite: #{opts[:force] || false}
    Generate LiveView: #{opts[:live] || false}
    Generate Studio artifacts provider: #{opts[:studio_artifacts] || false}
    Generate Saved Views: #{opts[:saved_views] || false}

    Sources to process:
    """)

    Enum.each(schemas, fn schema ->
      domain_file = DomainPaths.domain_file_path(output_dir, schema)

      IO.puts("  • #{DomainPaths.display_source(schema)}")
      IO.puts("    → #{domain_file}")

      if opts[:live] do
        app_name = output_app_name(opts)
        schema_name = LiveViewGenerator.source_live_name(schema) |> Macro.underscore()

        live_file = "lib/#{app_name}_web/#{schema_name}_live.ex"
        html_file = "lib/#{app_name}_web/#{schema_name}_live.html.heex"

        IO.puts("    → #{live_file}")
        IO.puts("    → #{html_file}")
      end

      if opts[:studio_artifacts] do
        IO.puts("    → #{DomainPaths.studio_artifacts_file_path(output_dir, schema)}")
      end
    end)

    if opts[:saved_views] do
      IO.puts("\nSaved Views implementation will be generated if not already present.")
    end

    IO.puts("\nRun without --dry-run to generate files.")
  end

  defp generate_domain_for_source(igniter, source, output_dir, opts) do
    domain_file = DomainPaths.domain_file_path(output_dir, source)
    opts_list = Map.to_list(opts)

    case SelectoMix.SchemaIntrospector.introspect_schema_result(source, opts_list) do
      {:error, reason} ->
        Igniter.add_issue(
          igniter,
          "Failed to introspect #{DomainPaths.display_source(source)}: #{reason}"
        )

      {:ok, domain_config} ->
        igniter_with_domain =
          igniter
          |> ensure_directory_exists(output_dir)
          |> generate_domain_file(source, domain_config, domain_file, opts)
          |> generate_overlay_file(source, domain_config, domain_file, opts)
          |> maybe_generate_studio_artifacts_file(source, output_dir, opts)
          |> add_success_message(
            "Generated Selecto domain for #{DomainPaths.display_source(source)}"
          )
          |> add_artifact_guidance(source, opts)

        # Generate LiveView files if requested
        if opts[:live] && ecto_source?(source) do
          igniter_with_domain
          |> generate_live_view_for_schema(source, opts)
        else
          if opts[:live] && !ecto_source?(source) do
            Igniter.add_warning(
              igniter_with_domain,
              "LiveView generation is still Ecto-only in selecto_mix; domain generation completed for #{DomainPaths.display_source(source)}"
            )
          else
            igniter_with_domain
          end
        end
    end
  end

  defp ecto_source?(source) when is_atom(source), do: true
  defp ecto_source?(_source), do: false

  defp ensure_directory_exists(igniter, dir_path) do
    # Use Igniter to ensure directory exists
    gitkeep_path = Path.join(dir_path, ".gitkeep")

    if File.exists?(gitkeep_path) do
      igniter
    else
      Igniter.create_new_file(igniter, gitkeep_path, "")
    end
  end

  defp generate_domain_file(igniter, source, domain_config, file_path, opts) do
    # Convert map opts to keyword list for SchemaIntrospector
    opts_list = Map.to_list(opts)

    # Expand associated schemas if requested
    {expanded_config, expansion_warnings} =
      if opts[:expand_schemas_list] && is_list(opts[:expand_schemas_list]) do
        {config, warnings} =
          expand_associated_schemas(domain_config, source, opts[:expand_schemas_list], opts_list)

        {Map.put(config, :expand_schemas_list, opts[:expand_schemas_list]), warnings}
      else
        {domain_config, []}
      end

    igniter =
      Enum.reduce(expansion_warnings, igniter, fn warning, acc ->
        Igniter.add_warning(acc, warning)
      end)

    # Add expand_modes to config if present
    config_with_modes =
      if opts[:expand_modes] && map_size(opts[:expand_modes]) > 0 do
        Map.put(expanded_config, :expand_modes, opts[:expand_modes])
      else
        expanded_config
      end

    # Extract polymorphic config if present (for direct schema generation, not associations)
    config_with_poly =
      if opts[:expand_modes] do
        poly_config =
          Enum.find_value(opts[:expand_modes], fn
            {_key, {:polymorphic, config}} -> config
            _ -> nil
          end)

        if poly_config do
          Map.put(config_with_modes, :polymorphic_config, poly_config)
        else
          config_with_modes
        end
      else
        config_with_modes
      end

    generated_config = Map.put(config_with_poly, :adapter, domain_config[:adapter])

    # Add schema_module to opts for saved views context inference
    app_name = Igniter.Project.Application.app_name(igniter) |> to_string() |> Macro.camelize()

    opts_with_schema =
      opts
      |> Map.put(:schema_module, source)
      |> Map.put(:app_name, app_name)

    content =
      SelectoMix.DomainGenerator.generate_domain_file(source, generated_config, opts_with_schema)

    cond do
      File.exists?(file_path) && !opts[:force] ->
        Igniter.add_warning(
          igniter,
          "Domain file already exists at #{file_path}; not overwriting. Move customizations to the overlay and rerun with --force to regenerate the base domain."
        )

      true ->
        if opts[:force] && File.exists?(file_path) do
          File.rm!(file_path)
        end

        Igniter.create_new_file(igniter, file_path, content)
    end
  end

  defp generate_overlay_file(igniter, source, domain_config, domain_file_path, opts) do
    # Only generate overlay file if it doesn't already exist
    # Never overwrite an existing overlay file
    overlay_path = SelectoMix.OverlayGenerator.overlay_file_path(domain_file_path)

    if File.exists?(overlay_path) do
      # Overlay already exists, don't overwrite it
      igniter
    else
      # Get the domain module name
      app_name = Igniter.Project.Application.app_name(igniter) |> to_string() |> Macro.camelize()

      domain_module_name =
        SelectoMix.DomainGenerator.domain_module_name(source, domain_config, app_name: app_name)

      # Generate overlay content
      content =
        SelectoMix.OverlayGenerator.generate_overlay_file(
          domain_module_name,
          domain_config,
          opts
        )

      # Ensure overlays directory exists
      overlay_dir = Path.dirname(overlay_path)

      igniter
      |> ensure_directory_exists(overlay_dir)
      |> Igniter.create_new_file(overlay_path, content)
      |> add_success_message("Generated overlay template at #{overlay_path}")
    end
  end

  defp maybe_generate_studio_artifacts_file(igniter, _source, _output_dir, opts)
       when not is_map_key(opts, :studio_artifacts),
       do: igniter

  defp maybe_generate_studio_artifacts_file(igniter, _source, _output_dir, %{
         studio_artifacts: false
       }),
       do: igniter

  defp maybe_generate_studio_artifacts_file(igniter, source, output_dir, opts) do
    file_path = DomainPaths.studio_artifacts_file_path(output_dir, source)

    cond do
      File.exists?(file_path) and not opts[:force] ->
        igniter
        |> add_success_message("Studio artifacts provider already exists at #{file_path}")
        |> add_studio_artifacts_guidance(source, opts)

      true ->
        if opts[:force] && File.exists?(file_path), do: File.rm!(file_path)

        domain_module = domain_module_for_source(igniter, source, opts)
        content = StudioArtifactsGenerator.provider_module(domain_module)

        igniter
        |> Igniter.create_new_file(file_path, content)
        |> add_success_message("Generated Studio artifacts provider at #{file_path}")
        |> add_studio_artifacts_guidance(source, opts)
    end
  end

  defp expand_associated_schemas(domain_config, source, expand_list, opts_list) do
    case source do
      {:db, adapter, conn, _table, source_opts} ->
        expand_db_associated_schemas(
          domain_config,
          adapter,
          conn,
          source_opts,
          expand_list,
          opts_list
        )

      {:db, adapter, conn, _table} ->
        expand_db_associated_schemas(domain_config, adapter, conn, [], expand_list, opts_list)

      _ ->
        expand_ecto_associated_schemas(domain_config, expand_list)
    end
  end

  defp expand_ecto_associated_schemas(domain_config, expand_list) do
    associations = domain_config[:associations] || %{}

    {expanded_schemas, warnings} =
      Enum.reduce(expand_list, {%{}, []}, fn schema_name, {acc, warnings} ->
        # Find matching association by name or by related schema module
        matching_assoc =
          Enum.find(associations, fn {assoc_name, assoc_data} ->
            # Match by association name (e.g., "tags", "category")
            assoc_name_match =
              String.downcase(to_string(assoc_name)) == String.downcase(schema_name)

            # Match by related schema module (e.g., "SelectoNorthwind.Catalog.Tag")
            related_schema = assoc_data[:related_schema]

            schema_module_match =
              related_schema &&
                (to_string(related_schema) == schema_name ||
                   String.ends_with?(to_string(related_schema), ".#{schema_name}"))

            assoc_name_match || schema_module_match
          end)

        case matching_assoc do
          {assoc_name, assoc_data} ->
            # Get the related schema module
            related_schema = assoc_data[:related_schema]

            if related_schema && Code.ensure_loaded?(related_schema) do
              # Introspect the related schema
              case SelectoMix.SchemaIntrospector.introspect_schema_result(related_schema, []) do
                {:ok, related_config} ->
                  # Build expanded schema config
                  # We don't include associations in expanded schemas to avoid complexity
                  # and circular reference issues
                  {Map.put(acc, assoc_name, %{
                     source_table: related_config[:table_name],
                     primary_key: related_config[:primary_key],
                     fields: related_config[:fields],
                     redact_fields: [],
                     columns: related_config[:field_types] || %{},
                     # No associations in expanded schemas
                     associations: %{}
                   }), warnings}

                {:error, reason} ->
                  warning =
                    "Skipping expansion of #{inspect(related_schema)}: #{inspect(reason)}"

                  {acc, [warning | warnings]}
              end
            else
              warning =
                "Skipping expansion of #{schema_name}: related schema #{inspect(related_schema)} is not loaded"

              {acc, [warning | warnings]}
            end

          nil ->
            warning =
              "Skipping expansion of #{schema_name}: no matching association found"

            {acc, [warning | warnings]}
        end
      end)

    {Map.put(domain_config, :expanded_schemas, expanded_schemas), Enum.reverse(warnings)}
  end

  defp expand_db_associated_schemas(
         domain_config,
         adapter,
         conn,
         source_opts,
         expand_list,
         opts_list
       ) do
    associations = domain_config[:associations] || %{}
    merged_opts = Keyword.merge(source_opts, opts_list)

    {expanded_schemas, warnings} =
      Enum.reduce(associations, {%{}, []}, fn {assoc_name, assoc_data}, {acc, warnings} ->
        related_table = assoc_data[:related_table]
        schema_key = related_schema_key(assoc_name, assoc_data)

        if should_expand_related_table?(schema_key, related_table, expand_list) and related_table do
          introspection_opts =
            merged_opts
            |> Keyword.put(:include_associations, false)
            |> Keyword.put(:expand, false)

          case SelectoMix.Introspector.introspect(
                 {:db, adapter, conn, related_table, introspection_opts},
                 introspection_opts
               ) do
            {:ok, related_config} ->
              {Map.put(acc, schema_key, %{
                 source_table: related_config.table_name,
                 table_name: related_config.table_name,
                 primary_key: related_config.primary_key,
                 fields: related_config.fields,
                 field_types: related_config.field_types,
                 associations: %{}
               }), warnings}

            {:error, reason} ->
              warning =
                "Skipping expansion of related table #{inspect(related_table)}: #{inspect(reason)}"

              {acc, [warning | warnings]}
          end
        else
          {acc, warnings}
        end
      end)

    {Map.put(domain_config, :expanded_schemas, expanded_schemas), Enum.reverse(warnings)}
  end

  defp related_schema_key(assoc_name, assoc_data) do
    cond do
      module_name = assoc_data[:related_module_name] ->
        module_name
        |> to_string()
        |> Macro.underscore()
        |> SelectoMix.Identifier.to_atom!()

      related_schema = assoc_data[:related_schema] ->
        related_schema
        |> to_string()
        |> String.split(".")
        |> List.last()
        |> Macro.underscore()
        |> SelectoMix.Identifier.to_atom!()

      related_table = assoc_data[:related_table] ->
        related_table
        |> SelectoMix.Inflect.singularize()
        |> SelectoMix.Identifier.to_atom!()

      true ->
        assoc_name
    end
  end

  defp should_expand_related_table?(schema_key, related_table, expand_list) do
    schema_name = schema_key |> to_string() |> String.downcase()
    table_name = related_table |> to_string() |> String.downcase()

    Enum.any?(expand_list || [], fn expand_name ->
      expand_name = String.downcase(expand_name)

      expand_name == schema_name ||
        expand_name == table_name ||
        String.contains?(expand_name, schema_name) ||
        String.contains?(table_name, expand_name)
    end)
  end

  defp generate_live_view_for_schema(igniter, source, opts) do
    app_name = Igniter.Project.Application.app_name(igniter)

    live_file = LiveViewGenerator.live_view_file_path(app_name, source)
    html_file = LiveViewGenerator.live_view_html_file_path(app_name, source)

    igniter
    |> ensure_live_directory_exists(app_name)
    |> generate_live_view_file(source, live_file, opts)
    |> generate_live_view_html_file(source, html_file, opts)
    |> add_success_message("Generated LiveView files for #{DomainPaths.display_source(source)}")
    |> maybe_run_assets_integration()
    |> add_route_suggestion(source, opts)
  end

  defp generate_saved_views_if_needed(igniter, opts) do
    if opts[:saved_views] do
      app_name = Igniter.Project.Application.app_name(igniter)
      saved_view_context_path = "lib/#{app_name}/saved_view_context.ex"

      # Check if saved views implementation already exists
      case File.exists?(saved_view_context_path) do
        true ->
          igniter

        false ->
          app_name_string = to_string(Macro.camelize(to_string(app_name)))

          Igniter.compose_task(igniter, "selecto.gen.saved_views", [app_name_string])
      end
    else
      igniter
    end
  end

  defp ensure_live_directory_exists(igniter, app_name_atom) do
    app_name = app_name_atom |> to_string() |> Macro.underscore()
    live_dir = "lib/#{app_name}_web/live"
    Igniter.create_new_file(igniter, Path.join(live_dir, ".gitkeep"), "")
  end

  defp generate_live_view_file(igniter, source, file_path, opts) do
    content = render_live_view_template(igniter, source, opts)

    if opts[:force] && File.exists?(file_path) do
      File.rm!(file_path)
    end

    Igniter.create_new_file(igniter, file_path, content)
  end

  defp generate_live_view_html_file(igniter, source, file_path, opts) do
    content = LiveViewGenerator.render_live_view_html_template(source, opts)

    if opts[:force] && File.exists?(file_path) do
      File.rm!(file_path)
    end

    Igniter.create_new_file(igniter, file_path, content)
  end

  defp render_live_view_template(igniter, source, opts) do
    app_name = Igniter.Project.Application.app_name(igniter) |> to_string() |> Macro.camelize()
    domain_module = domain_module_for_source(igniter, source, opts)

    LiveViewGenerator.render_live_view_template(
      app_name,
      source,
      domain_module,
      opts,
      SelectoMix.ComponentsIntegrate.selecto_components_source_path()
    )
  end

  defp output_app_name(opts) do
    (opts[:app_name] || Application.get_env(:selecto_mix, :app_name, "my_app"))
    |> to_string()
    |> Macro.underscore()
  end

  defp domain_module_for_source(igniter, source, opts) do
    app_name = Igniter.Project.Application.app_name(igniter) |> to_string() |> Macro.camelize()
    domain_config = SelectoMix.SchemaIntrospector.introspect_schema!(source, Map.to_list(opts))

    SelectoMix.DomainGenerator.domain_module_name(source, domain_config, app_name: app_name)
  end

  defp add_artifact_guidance(igniter, source, opts) do
    domain_module = domain_module_for_source(igniter, source, opts)
    artifact_path = DomainPaths.domain_artifact_path(source)
    docs_path = DomainPaths.domain_docs_path(source)
    inspection_path = DomainPaths.domain_inspection_path(source)
    diagram_path = DomainPaths.domain_diagram_path(source)

    Igniter.add_notice(
      igniter,
      artifact_guidance(domain_module, artifact_path, docs_path, inspection_path, diagram_path)
    )
  end

  defp add_studio_artifacts_guidance(igniter, source, opts) do
    domain_module = domain_module_for_source(igniter, source, opts)
    artifact_module = StudioArtifactsGenerator.artifact_module_name(domain_module)

    Igniter.add_notice(
      igniter,
      StudioArtifactsGenerator.integration_guidance(
        domain_id: DomainPaths.source_basename(source),
        domain_name: DomainPaths.source_display_name(source),
        artifact_module: artifact_module
      )
    )
  end

  defp add_route_suggestion(igniter, source, opts) do
    domain_module = domain_module_for_source(igniter, source, opts)

    opts = Map.put(opts, :domain_module, domain_module)

    Igniter.add_notice(igniter, LiveViewGenerator.route_suggestion(source, opts))
  end

  defp add_success_message(igniter, message) do
    Igniter.add_notice(igniter, message)
  end

  defp maybe_run_assets_integration(igniter) do
    # Don't call Mix tasks from within Igniter tasks (causes conflicts in Igniter 0.6.x)
    # Instead, just add a notice for the user to run it manually if needed
    igniter
    |> Igniter.add_notice("""

    To integrate SelectoComponents assets (if not already done), run:
      mix selecto.components.integrate

    Or manually configure:
      1. Import hooks in assets/js/app.js
      2. Add @source directive in assets/css/app.css
    """)
  end
end
