defmodule Mix.Tasks.Selecto.Gen.Domain do
  @shortdoc "Generate Selecto domain configuration from Ecto schemas"
  @moduledoc """
  Generate Selecto domain configuration from Ecto schemas with Igniter support.

  This task automatically discovers Ecto schemas in your project and generates
  corresponding Selecto domain configurations. It preserves user customizations
  when re-run and supports incremental updates when database schemas change.

  ## Examples

      # Generate domain for a single schema
      mix selecto.gen.domain Blog.Post

      # Generate domains for all schemas in a context
      mix selecto.gen.domain Blog.*

      # Generate domains for all schemas in the project
      mix selecto.gen.domain --all

      # Generate with specific output directory
      mix selecto.gen.domain Blog.Post --output lib/blog/selecto_domains

      # Force regenerate (overwrites customizations)
      mix selecto.gen.domain Blog.Post --force

      # Expand associated schemas with full columns/associations
      mix selecto.gen.domain Blog.Post --expand-schemas categories,tags,authors

      # Use special join modes for optimized queries
      mix selecto.gen.domain Product --expand-tag Tags:name --expand-star Category:category_name

  ## Options

    * `--all` - Generate domains for all discovered Ecto schemas
    * `--output` - Specify output directory (default: lib/APP_NAME/selecto_domains)
    * `--force` - Overwrite existing domain files without merging customizations
    * `--dry-run` - Show what would be generated without creating files
    * `--include-associations` - Include associations as joins (default: true)
    * `--exclude` - Comma-separated list of schemas to exclude
    * `--live` - Generate LiveView files for the domain
    * `--saved-views` - Generate saved views implementation (requires --live)
    * `--expand-schemas` - Comma-separated list of associated schemas to fully expand with columns and associations
    * `--expand-tag` - Many-to-many tag mode: TableName:display_field (uses IDs, prevents denormalization)
    * `--expand-star` - Star schema mode: TableName:display_field (lookup table with ID-based filtering)
    * `--expand-lookup` - Lookup table mode: TableName:display_field (small reference tables)
    * `--expand-polymorphic` - Polymorphic association: field_name:type_field,id_field:Type1,Type2,Type3
    * `--parameterized-joins` - Generate example parameterized join configurations
    * `--path` - Custom path for the LiveView route (e.g., /products instead of /product)
    * `--enable-modal` - Enable modal detail view for row clicks in LiveView (requires --live)

  ## File Generation

  For each schema, generates:
  - `schemas/SCHEMA_NAME_domain.ex` - Selecto domain configuration

  With `--live` flag, additionally generates:
  - `live/SCHEMA_NAME_live.ex` - LiveView module
  - `live/SCHEMA_NAME_live.html.heex` - LiveView template

  With `--saved-views` flag, additionally generates:
  - SavedView schema and context modules (if not already present)
  - Saved views integration in the LiveView

  ## Customization Preservation

  When re-running the task, user customizations are preserved by:
  - Detecting custom fields, filters, and joins
  - Merging new schema fields with existing customizations
  - Preserving custom domain metadata and configuration
  - Backing up original files before major changes

  The generated files include special markers that help identify
  generated vs. customized sections.
  """

  use Igniter.Mix.Task

  alias SelectoMix.{AdapterResolver, Connection, ConnectionOpts, LiveViewGenerator}

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
    expand_schemas = parse_expand_schemas(parsed_args[:expand_schemas] || "")

    # Parse special join mode parameters
    expand_modes = parse_expand_modes(parsed_args)

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
          updated_args[:all] -> discover_all_schemas(igniter)
          schemas_arg != "" -> parse_schema_patterns(schemas_arg)
          true -> []
        end

      exclude_patterns = parse_exclude_patterns(updated_args[:exclude] || "")
      schemas = Enum.reject(schemas, &schema_matches_exclude?(&1, exclude_patterns))

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

  # Private functions

  defp validate_flags(igniter, parsed_args) do
    cond do
      parsed_args[:saved_views] && !parsed_args[:live] ->
        igniter
        |> Igniter.add_warning("--saved-views flag requires --live flag to be set")

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
          "Failed to generate from database source: #{inspect(reason)}"
        )
    end
  end

  defp with_db_connection(adapter, conn_opts, igniter, opts) do
    Connection.with_connection(adapter, conn_opts, fn conn ->
      db_schema = opts[:schema] || "public"
      exclude_patterns = parse_exclude_patterns(opts[:exclude] || "")

      tables =
        cond do
          opts[:all] -> discover_all_tables(adapter, conn, db_schema)
          table = opts[:table] -> [table]
          true -> []
        end

      tables = Enum.reject(tables, &table_matches_exclude?(&1, exclude_patterns))

      if Enum.empty?(tables) do
        Igniter.add_warning(
          igniter,
          "No tables specified. Use one of: mix selecto.gen.domain --adapter postgresql --table TABLE_NAME or --all"
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

  defp discover_all_tables(adapter, conn, db_schema) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        []

      not function_exported?(adapter, :list_tables, 2) ->
        []

      true ->
        case adapter.list_tables(conn, schema: db_schema) do
          {:ok, tables} -> Enum.reject(tables, &(&1 in ConnectionOpts.system_tables()))
          {:error, _reason} -> []
        end
    end
  end

  defp process_db_tables(igniter, adapter, conn, tables, opts) do
    output_dir = get_output_directory(igniter, opts[:output])
    opts = Map.put_new(opts, :app_name, Igniter.Project.Application.app_name(igniter))

    if opts[:dry_run] do
      show_dry_run_summary(tables, output_dir, opts)
      igniter
    else
      Enum.reduce(tables, igniter, fn table, acc_igniter ->
        source =
          {:db, adapter, conn, table, schema: opts[:db_schema], expand: opts[:expand] || false}

        generate_domain_for_source(acc_igniter, source, output_dir, opts)
      end)
    end
  end

  defp discover_all_schemas(igniter) do
    # Use Igniter to find all Ecto schema modules in the project
    igniter
    |> Igniter.Project.Module.find_all_matching_modules(fn module_name ->
      String.contains?(to_string(module_name), ["Schema", "Store"]) or
        module_uses_ecto_schema?(igniter, module_name)
    end)
  end

  defp module_uses_ecto_schema?(igniter, module_name) do
    case Igniter.Project.Module.module_exists(igniter, module_name) do
      {_igniter, true} ->
        # Check if the module uses Ecto.Schema
        case Igniter.Project.Module.find_module(igniter, module_name) do
          {_igniter, {:ok, {_zipper, _module_zipper}}} ->
            # This is simplified - in real implementation would parse AST
            # to check for `use Ecto.Schema`
            true

          _ ->
            false
        end

      {_igniter, false} ->
        false
    end
  end

  defp parse_schema_patterns(schemas_arg) do
    schemas_arg
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> expand_patterns()
  end

  defp expand_patterns(patterns) do
    # For now, just return the patterns as module names
    # In full implementation, would expand wildcards like "Blog.*"
    Enum.map(patterns, &Module.concat([&1]))
  end

  defp parse_exclude_patterns(exclude_arg) do
    exclude_arg
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp parse_expand_schemas(expand_arg) when is_list(expand_arg) do
    # Already a list from :keep option - just return it
    expand_arg
    |> Enum.flat_map(fn item ->
      # Each item might still be comma-separated
      item
      |> String.split(",")
      |> Enum.map(&String.trim/1)
    end)
    |> Enum.filter(&(&1 != ""))
  end

  defp parse_expand_schemas(expand_arg) when is_binary(expand_arg) do
    # Single string - split by comma
    expand_arg
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp parse_expand_schemas(_), do: []

  # Parse expand mode parameters like --expand-tag Tags:name --expand-star Category:category_name
  # Returns a map like: %{"Tags" => {:tag, "name"}, "Category" => {:star, "category_name"}}
  defp parse_expand_modes(parsed_args) do
    modes = [:expand_tag, :expand_star, :expand_lookup, :expand_polymorphic]

    Enum.reduce(modes, %{}, fn mode, acc ->
      mode_type = mode |> to_string() |> String.replace("expand_", "") |> String.to_atom()

      case Map.get(parsed_args, mode) do
        nil ->
          acc

        specs when is_list(specs) ->
          # :keep option returns a list of all occurrences
          Enum.reduce(specs, acc, fn spec, mode_acc ->
            parse_expand_mode_spec(spec, mode_type, mode_acc)
          end)

        spec when is_binary(spec) ->
          parse_expand_mode_spec(spec, mode_type, acc)

        _ ->
          acc
      end
    end)
  end

  defp parse_expand_mode_spec(spec, mode_type, acc) do
    cond do
      # Polymorphic format: field_name:type_field,id_field:Type1,Type2,Type3
      mode_type == :polymorphic ->
        case String.split(spec, ":") do
          [field_name, fields, types] ->
            case String.split(fields, ",") do
              [type_field, id_field] ->
                entity_types = String.split(types, ",") |> Enum.map(&String.trim/1)

                poly_config = %{
                  field_name: String.trim(field_name),
                  type_field: String.trim(type_field),
                  id_field: String.trim(id_field),
                  entity_types: entity_types
                }

                # Use field_name as the key
                Map.put(acc, String.trim(field_name), {:polymorphic, poly_config})

              _ ->
                acc
            end

          _ ->
            acc
        end

      # Standard format for tag/star/lookup: TableName:display_field
      true ->
        case String.split(spec, ":") do
          [table_name, display_field] ->
            # Store both singular and plural forms to match flexibly
            table_key = String.trim(table_name)
            Map.put(acc, table_key, {mode_type, String.trim(display_field)})

          _ ->
            # Invalid format, skip
            acc
        end
    end
  end

  defp schema_matches_exclude?(schema, exclude_patterns) do
    schema_str = to_string(schema)

    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(schema_str, pattern)
    end)
  end

  defp table_matches_exclude?(table, exclude_patterns) do
    table_name = table |> to_string() |> String.downcase()

    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(table_name, String.downcase(pattern))
    end)
  end

  defp process_schemas(igniter, schemas, opts) do
    output_dir = get_output_directory(igniter, opts[:output])

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

  defp get_output_directory(igniter, custom_output) do
    case custom_output do
      nil ->
        app_name = Igniter.Project.Application.app_name(igniter)
        "lib/#{app_name}/selecto_domains"

      custom ->
        custom
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
    Generate Saved Views: #{opts[:saved_views] || false}

    Sources to process:
    """)

    Enum.each(schemas, fn schema ->
      domain_file = domain_file_path(output_dir, schema)

      IO.puts("  • #{display_source(schema)}")
      IO.puts("    → #{domain_file}")

      if opts[:live] do
        app_name = output_app_name(opts)
        schema_name = LiveViewGenerator.source_live_name(schema) |> Macro.underscore()

        live_file = "lib/#{app_name}_web/live/#{schema_name}_live.ex"
        html_file = "lib/#{app_name}_web/live/#{schema_name}_live.html.heex"

        IO.puts("    → #{live_file}")
        IO.puts("    → #{html_file}")
      end
    end)

    if opts[:saved_views] do
      IO.puts("\nSaved Views implementation will be generated if not already present.")
    end

    IO.puts("\nRun without --dry-run to generate files.")
  end

  defp generate_domain_for_source(igniter, source, output_dir, opts) do
    domain_file = domain_file_path(output_dir, source)

    igniter_with_domain =
      igniter
      |> ensure_directory_exists(output_dir)
      |> generate_domain_file(source, domain_file, opts)
      |> generate_overlay_file(source, domain_file, opts)
      |> add_success_message("Generated Selecto domain for #{display_source(source)}")

    # Generate LiveView files if requested
    if opts[:live] && ecto_source?(source) do
      igniter_with_domain
      |> generate_live_view_for_schema(source, opts)
    else
      if opts[:live] && !ecto_source?(source) do
        Igniter.add_warning(
          igniter_with_domain,
          "LiveView generation is still Ecto-only in selecto_mix; domain generation completed for #{display_source(source)}"
        )
      else
        igniter_with_domain
      end
    end
  end

  defp ecto_source?(source) when is_atom(source), do: true
  defp ecto_source?(_source), do: false

  defp display_source({:db, _adapter, _conn, table, _opts}), do: table
  defp display_source({:db, _adapter, _conn, table}), do: table
  defp display_source(source) when is_binary(source), do: source
  defp display_source(source), do: inspect(source)

  defp source_basename({:db, _adapter, _conn, table, _opts}), do: Macro.underscore(table)
  defp source_basename({:db, _adapter, _conn, table}), do: Macro.underscore(table)
  defp source_basename(source) when is_binary(source), do: Macro.underscore(source)

  defp source_basename(source) do
    source
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
  end

  defp domain_file_path(output_dir, source) do
    Path.join([output_dir, "#{source_basename(source)}_domain.ex"])
  end

  defp ensure_directory_exists(igniter, dir_path) do
    # Use Igniter to ensure directory exists
    gitkeep_path = Path.join(dir_path, ".gitkeep")

    if File.exists?(gitkeep_path) do
      igniter
    else
      Igniter.create_new_file(igniter, gitkeep_path, "")
    end
  end

  defp generate_domain_file(igniter, source, file_path, opts) do
    existing_content = read_existing_domain_file(igniter, file_path)
    # Convert map opts to keyword list for SchemaIntrospector
    opts_list = Map.to_list(opts)
    domain_config = SelectoMix.SchemaIntrospector.introspect_schema(source, opts_list)

    # Expand associated schemas if requested
    expanded_config =
      if opts[:expand_schemas_list] && is_list(opts[:expand_schemas_list]) do
        domain_config
        |> expand_associated_schemas(source, opts[:expand_schemas_list], opts_list)
        |> Map.put(:expand_schemas_list, opts[:expand_schemas_list])
      else
        domain_config
      end

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

    merged_config =
      if opts[:force] do
        config_with_poly
      else
        SelectoMix.ConfigMerger.merge_with_existing(config_with_poly, existing_content)
      end

    merged_config = Map.put(merged_config, :adapter, domain_config[:adapter])

    # Add schema_module to opts for saved views context inference
    app_name = Igniter.Project.Application.app_name(igniter) |> to_string() |> Macro.camelize()

    opts_with_schema =
      opts
      |> Map.put(:schema_module, source)
      |> Map.put(:app_name, app_name)

    content =
      SelectoMix.DomainGenerator.generate_domain_file(source, merged_config, opts_with_schema)

    # For now, delete the existing file and create a new one
    # This is a workaround until we figure out the proper Igniter API
    if opts[:force] && File.exists?(file_path) do
      File.rm!(file_path)
    end

    Igniter.create_new_file(igniter, file_path, content)
  end

  # defp generate_queries_file(igniter, schema, file_path, opts) do
  #   # Only generate queries file if it doesn't exist or if forced
  #   if opts[:force] || not File.exists?(file_path) do
  #     content = SelectoMix.QueriesGenerator.generate_queries_file(schema, opts)
  #     Igniter.create_new_file(igniter, file_path, content)
  #   else
  #     igniter
  #   end
  # end

  defp generate_overlay_file(igniter, source, domain_file_path, opts) do
    # Only generate overlay file if it doesn't already exist
    # Never overwrite an existing overlay file
    overlay_path = SelectoMix.OverlayGenerator.overlay_file_path(domain_file_path)

    if File.exists?(overlay_path) do
      # Overlay already exists, don't overwrite it
      igniter
    else
      # Generate overlay template
      opts_list = Map.to_list(opts)
      domain_config = SelectoMix.SchemaIntrospector.introspect_schema(source, opts_list)

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

  defp read_existing_domain_file(_igniter, file_path) do
    case File.read(file_path) do
      {:ok, content} -> content
      {:error, :enoent} -> nil
      {:error, _reason} -> nil
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

    expanded_schemas =
      Enum.reduce(expand_list, %{}, fn schema_name, acc ->
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
              related_config = SelectoMix.SchemaIntrospector.introspect_schema(related_schema, [])

              # Build expanded schema config
              # We don't include associations in expanded schemas to avoid complexity
              # and circular reference issues
              Map.put(acc, assoc_name, %{
                source_table: related_config[:table_name],
                primary_key: related_config[:primary_key],
                fields: related_config[:fields],
                redact_fields: [],
                columns: related_config[:field_types] || %{},
                # No associations in expanded schemas
                associations: %{}
              })
            else
              acc
            end

          nil ->
            acc
        end
      end)

    # Add expanded schemas to the domain config
    Map.put(domain_config, :expanded_schemas, expanded_schemas)
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

    expanded_schemas =
      Enum.reduce(associations, %{}, fn {assoc_name, assoc_data}, acc ->
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
              Map.put(acc, schema_key, %{
                source_table: related_config.table_name,
                table_name: related_config.table_name,
                primary_key: related_config.primary_key,
                fields: related_config.fields,
                field_types: related_config.field_types,
                associations: %{}
              })

            {:error, _reason} ->
              acc
          end
        else
          acc
        end
      end)

    Map.put(domain_config, :expanded_schemas, expanded_schemas)
  end

  defp related_schema_key(assoc_name, assoc_data) do
    cond do
      module_name = assoc_data[:related_module_name] ->
        module_name
        |> to_string()
        |> Macro.underscore()
        |> String.to_atom()

      related_schema = assoc_data[:related_schema] ->
        related_schema
        |> to_string()
        |> String.split(".")
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()

      related_table = assoc_data[:related_table] ->
        related_table
        |> singularize_table_name()
        |> String.to_atom()

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

  defp singularize_table_name(table_name) do
    cond do
      String.ends_with?(table_name, "ies") ->
        String.replace_suffix(table_name, "ies", "y")

      String.ends_with?(table_name, "sses") ->
        String.replace_suffix(table_name, "sses", "ss")

      String.ends_with?(table_name, "ses") ->
        String.replace_suffix(table_name, "ses", "s")

      String.ends_with?(table_name, "s") and not String.ends_with?(table_name, "ss") ->
        String.replace_suffix(table_name, "s", "")

      true ->
        table_name
    end
  end

  defp generate_live_view_for_schema(igniter, source, opts) do
    app_name = Igniter.Project.Application.app_name(igniter)

    live_file = LiveViewGenerator.live_view_file_path(app_name, source)
    html_file = LiveViewGenerator.live_view_html_file_path(app_name, source)

    igniter
    |> ensure_live_directory_exists(app_name)
    |> generate_live_view_file(source, live_file, opts)
    |> generate_live_view_html_file(source, html_file, opts)
    |> add_success_message("Generated LiveView files for #{display_source(source)}")
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
          # Generate saved views implementation before the domain
          # This must happen in a separate Mix task to avoid circular compilation issues
          app_name_string = to_string(Macro.camelize(to_string(app_name)))

          IO.puts("\nGenerating SavedViews implementation...")

          case System.cmd("mix", ["selecto.gen.saved_views", app_name_string],
                 stderr_to_stdout: true
               ) do
            {output, 0} ->
              IO.puts(output)
              igniter

            {output, _exit_code} ->
              IO.puts(output)

              igniter
              |> Igniter.add_warning("""
              Failed to auto-generate saved views. Please run manually:

                  mix selecto.gen.saved_views #{app_name_string}
              """)
          end
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

    domain_config = SelectoMix.SchemaIntrospector.introspect_schema(source, Map.to_list(opts))

    domain_module =
      SelectoMix.DomainGenerator.domain_module_name(source, domain_config, app_name: app_name)

    LiveViewGenerator.render_live_view_template(
      app_name,
      source,
      domain_module,
      opts,
      get_selecto_components_location()
    )
  end

  defp output_app_name(opts) do
    (opts[:app_name] || Application.get_env(:selecto_mix, :app_name, "my_app"))
    |> to_string()
    |> Macro.underscore()
  end

  defp add_route_suggestion(igniter, source, opts) do
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

  defp get_selecto_components_location() do
    vendor_path = Path.join([File.cwd!(), "vendor", "selecto_components"])

    if File.dir?(vendor_path) do
      "vendor"
    else
      "deps"
    end
  end
end
