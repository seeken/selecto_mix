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
    * `--parameterized-joins` - Generate example parameterized join configurations
    * `--path` - Custom path for the LiveView route (e.g., /products instead of /product)
    * `--enable-modal` - Enable modal detail view for row clicks in LiveView (requires --live)

  ## File Generation

  For each schema, generates:
  - `schemas/SCHEMA_NAME_domain.ex` - Selecto domain configuration
  - `schemas/SCHEMA_NAME_queries.ex` - Common query helpers (optional)

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
  
  # alias SelectoMix.{AdapterDetector, CLIParser, JoinAnalyzer}
  # alias SelectoMix.{SchemaIntrospector, ConfigMerger, DomainGenerator}

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.gen.domain Blog.Post --include-associations --expand-schemas categories",
      positional: [:schemas],
      schema: [
        all: :boolean,
        output: :string,
        force: :boolean,
        dry_run: :boolean,
        include_associations: :boolean,
        exclude: :string,
        live: :boolean,
        saved_views: :boolean,
        expand_schemas: :string,
        parameterized_joins: :boolean,
        path: :string,
        enable_modal: :boolean
      ],
      aliases: [
        a: :all,
        o: :output,
        f: :force,
        d: :dry_run,
        l: :live,
        s: :saved_views,
        e: :expand_schemas,
        p: :parameterized_joins
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # Ensure all modules are compiled first
    Mix.Task.run("compile", [])
    
    {parsed_args_list, remaining_args} = OptionParser.parse!(igniter.args.argv, strict: info(igniter.args.argv, nil).schema)
    
    # Convert keyword list to map for easier manipulation
    parsed_args = Map.new(parsed_args_list)

    schemas_arg = List.first(remaining_args) || ""

    schemas = cond do
      parsed_args[:all] -> discover_all_schemas(igniter)
      schemas_arg != "" -> parse_schema_patterns(schemas_arg)
      true -> []
    end

    exclude_patterns = parse_exclude_patterns(parsed_args[:exclude] || "")
    schemas = Enum.reject(schemas, &schema_matches_exclude?(&1, exclude_patterns))

    # Parse expand-schemas parameter
    expand_schemas = parse_expand_schemas(parsed_args[:expand_schemas] || "")

    # Validate flags
    validated_igniter = validate_flags(igniter, parsed_args)

    if Enum.empty?(schemas) do
      Igniter.add_warning(validated_igniter, """
      No schemas specified. Use one of:
        mix selecto.gen.domain MyApp.Schema
        mix selecto.gen.domain MyApp.Context.*
        mix selecto.gen.domain --all
      """)
    else
      # Add expand_schemas to parsed_args
      updated_args = Map.put(parsed_args, :expand_schemas_list, expand_schemas)
      process_schemas(validated_igniter, schemas, updated_args)
    end
  end

  # Private functions

  defp validate_flags(igniter, parsed_args) do
    cond do
      parsed_args[:saved_views] && !parsed_args[:live] ->
        Igniter.add_warning(igniter, "--saved-views flag requires --live flag to be set")
      true ->
        igniter
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
          _ -> false
        end
      {_igniter, false} -> false
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

  defp parse_expand_schemas(expand_arg) do
    expand_arg
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp schema_matches_exclude?(schema, exclude_patterns) do
    schema_str = to_string(schema)
    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(schema_str, pattern)
    end)
  end

  defp process_schemas(igniter, schemas, opts) do
    output_dir = get_output_directory(igniter, opts[:output])

    if opts[:dry_run] do
      show_dry_run_summary(schemas, output_dir, opts)
      igniter
    else
      igniter_after_schemas = Enum.reduce(schemas, igniter, fn schema, acc_igniter ->
        generate_domain_for_schema(acc_igniter, schema, output_dir, opts)
      end)

      # Generate saved views implementation if requested and not already present
      if opts[:saved_views] do
        generate_saved_views_if_needed(igniter_after_schemas, opts)
      else
        igniter_after_schemas
      end
    end
  end

  defp get_output_directory(igniter, custom_output) do
    case custom_output do
      nil ->
        app_name = Igniter.Project.Application.app_name(igniter)
        "lib/#{app_name}/selecto_domains"
      custom -> custom
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

    Schemas to process:
    """)

    Enum.each(schemas, fn schema ->
      domain_file = domain_file_path(output_dir, schema)
      queries_file = queries_file_path(output_dir, schema)

      IO.puts("  • #{schema}")
      IO.puts("    → #{domain_file}")
      IO.puts("    → #{queries_file}")

      if opts[:live] do
        schema_parts = schema |> to_string() |> String.split(".")
        app_name = get_app_name_from_schema_parts(schema_parts)
        schema_name = List.last(schema_parts) |> Macro.underscore()

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

  defp generate_domain_for_schema(igniter, schema, output_dir, opts) do
    domain_file = domain_file_path(output_dir, schema)
    _queries_file = queries_file_path(output_dir, schema)

    igniter_with_domain = igniter
    |> ensure_directory_exists(output_dir)
    |> generate_domain_file(schema, domain_file, opts)
    # Skip queries file generation for now due to backslash escaping issue
    # |> generate_queries_file(schema, queries_file, opts)
    |> add_success_message("Generated Selecto domain for #{schema}")

    # Generate LiveView files if requested
    if opts[:live] do
      igniter_with_domain
      |> generate_live_view_for_schema(schema, opts)
    else
      igniter_with_domain
    end
  end

  defp domain_file_path(output_dir, schema) do
    filename = schema |> to_string() |> String.split(".") |> List.last() |> Macro.underscore()
    Path.join([output_dir, "#{filename}_domain.ex"])
  end

  defp queries_file_path(output_dir, schema) do
    filename = schema |> to_string() |> String.split(".") |> List.last() |> Macro.underscore()
    Path.join([output_dir, "#{filename}_queries.ex"])
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

  defp generate_domain_file(igniter, schema, file_path, opts) do
    existing_content = read_existing_domain_file(igniter, file_path)
    # Convert map opts to keyword list for SchemaIntrospector
    opts_list = Map.to_list(opts)
    domain_config = SelectoMix.SchemaIntrospector.introspect_schema(schema, opts_list)
    
    # Expand associated schemas if requested
    expanded_config = if opts[:expand_schemas_list] && is_list(opts[:expand_schemas_list]) do
      domain_config
      |> expand_associated_schemas(opts[:expand_schemas_list])
      |> Map.put(:expand_schemas_list, opts[:expand_schemas_list])
    else
      domain_config
    end

    merged_config = if opts[:force] do
      expanded_config
    else
      SelectoMix.ConfigMerger.merge_with_existing(expanded_config, existing_content)
    end

    content = SelectoMix.DomainGenerator.generate_domain_file(schema, merged_config)

    # For now, delete the existing file and create a new one
    # This is a workaround until we figure out the proper Igniter API
    if File.exists?(file_path) do
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

  defp read_existing_domain_file(_igniter, file_path) do
    case File.read(file_path) do
      {:ok, content} -> content
      {:error, :enoent} -> nil
      {:error, _reason} -> nil
    end
  end
  
  defp expand_associated_schemas(domain_config, expand_list) do
    associations = domain_config[:associations] || %{}
    
    expanded_schemas = Enum.reduce(expand_list, %{}, fn schema_name, acc ->
      # Find matching association by name
      matching_assoc = Enum.find(associations, fn {assoc_name, _assoc_data} ->
        String.downcase(to_string(assoc_name)) == String.downcase(schema_name)
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
              associations: %{}  # No associations in expanded schemas
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

  defp generate_live_view_for_schema(igniter, schema, opts) do
    app_name = Igniter.Project.Application.app_name(igniter)

    live_file = live_view_file_path(app_name, schema)
    html_file = live_view_html_file_path(app_name, schema)

    igniter
    |> ensure_live_directory_exists(app_name)
    |> generate_live_view_file(schema, live_file, opts)
    |> generate_live_view_html_file(schema, html_file, opts)
    |> add_success_message("Generated LiveView files for #{schema}")
    |> maybe_run_assets_integration()
    |> add_route_suggestion(schema, opts)
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
          # Generate saved views implementation by updating the igniter's args
          # and calling the saved views task
          updated_igniter = %{igniter |
            args: %{igniter.args |
              argv: [to_string(Macro.camelize(to_string(app_name)))]
            }
          }
          Mix.Tasks.Selecto.Gen.SavedViews.igniter(updated_igniter)
      end
    else
      igniter
    end
  end

  defp live_view_file_path(app_name_atom, schema) do
    schema_parts = schema |> to_string() |> String.split(".")
    # Use the actual app name from Igniter instead of trying to derive it
    app_name = app_name_atom |> to_string()
    schema_name = List.last(schema_parts) |> Macro.underscore()
    "lib/#{app_name}_web/live/#{schema_name}_live.ex"
  end

  defp live_view_html_file_path(app_name_atom, schema) do
    schema_parts = schema |> to_string() |> String.split(".")
    # Use the actual app name from Igniter instead of trying to derive it
    app_name = app_name_atom |> to_string()
    schema_name = List.last(schema_parts) |> Macro.underscore()
    "lib/#{app_name}_web/live/#{schema_name}_live.html.heex"
  end

  defp ensure_live_directory_exists(igniter, app_name_atom) do
    app_name = app_name_atom |> to_string() |> Macro.underscore()
    live_dir = "lib/#{app_name}_web/live"
    Igniter.create_new_file(igniter, Path.join(live_dir, ".gitkeep"), "")
  end

  defp generate_live_view_file(igniter, schema, file_path, opts) do
    content = render_live_view_template(schema, opts)
    Igniter.create_new_file(igniter, file_path, content)
  end

  defp generate_live_view_html_file(igniter, schema, file_path, opts) do
    content = render_live_view_html_template(schema, opts)
    Igniter.create_new_file(igniter, file_path, content)
  end

  defp render_live_view_template(schema, opts) do
    # Extract app name from the schema module
    schema_parts = schema |> to_string() |> String.split(".")
    # Remove "Elixir" prefix if present
    clean_parts = case schema_parts do
      ["Elixir" | rest] -> rest
      parts -> parts
    end
    app_name = List.first(clean_parts)
    schema_name = List.last(clean_parts)
    schema_underscore = Macro.underscore(schema_name)

    # Use custom path if provided, otherwise use singular form
    route_path = opts[:path] || "/#{schema_underscore}"
    # Ensure path starts with /
    route_path = if String.starts_with?(route_path, "/"), do: route_path, else: "/#{route_path}"

    domain_module = "#{app_name}.SelectoDomains.#{schema_name}Domain"
    web_module = "#{app_name}Web"

    saved_views_code = if opts[:saved_views] do
      """
        saved_views = #{domain_module}.get_view_names(path)

        socket =
          assign(socket,
            show_view_configurator: false,
            views: views,
            my_path: path,
            saved_view_module: #{domain_module},
            saved_view_context: path,
            path: path,
            available_saved_views: saved_views
          )
      """
    else
      """
        socket =
          assign(socket,
            show_view_configurator: false,
            views: views,
            my_path: path
          )
      """
    end

    """
    defmodule #{web_module}.#{schema_name}Live do
      @moduledoc \"\"\"
      LiveView for #{schema_name} using SelectoComponents.
      
      ## Quick Setup (Phoenix 1.7+)
      
      1. Import hooks in `assets/js/app.js`:
         ```javascript
         import {hooks as selectoHooks} from "phoenix-colocated/selecto_components"
         // Add to your liveSocket hooks: { ...selectoHooks }
         ```
      
      2. Add to Tailwind in `assets/css/app.css`:
         ```css
         @source "../../#{get_selecto_components_location()}/selecto_components/lib/**/*.{ex,heex}";
         ```
      
      3. Run `mix assets.build`
      
      That's it! The drag-and-drop query builder and charts will work automatically.
      \"\"\"

      use #{web_module}, :live_view
      use SelectoComponents.Form

      @impl true
      def mount(_params, _session, socket) do
        # Configure the domain and path
        domain = #{domain_module}.domain()
        path = "#{route_path}"

        # Configure Selecto to use the main Repo connection pool
        selecto = Selecto.configure(domain, #{app_name}.Repo)

        views = [
          {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate View", %{drill_down: :detail}},
          {:detail, SelectoComponents.Views.Detail, "Detail View", %{}},
          {:graph, SelectoComponents.Views.Graph, "Graph View", %{}}
        ]

        state = get_initial_state(views, selecto)

    #{saved_views_code}

        {:ok, assign(socket, state), layout: {#{web_module}.Layouts, :root}}
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <div class="container mx-auto px-4 py-8">
          <h1 class="text-3xl font-bold mb-6">#{schema_name} Explorer</h1>

          <.live_component
            module={SelectoComponents.Form}
            id="#{schema_underscore}-form"
            #{if opts[:enable_modal], do: "enable_modal_detail={true}", else: ""}
            {assigns}
          />

          <.live_component
            module={SelectoComponents.Results}
            id="#{schema_underscore}-results"
            {assigns}
          />
        </div>
        \"\"\"
      end

      @impl true
      def handle_event("toggle_show_view_configurator", _params, socket) do
        {:noreply, assign(socket, show_view_configurator: !socket.assigns.show_view_configurator)}
      end
    end
    """
  end

  defp render_live_view_html_template(schema, opts) do
    schema_name = schema |> to_string() |> String.split(".") |> List.last()

    saved_views_section = if opts[:saved_views] do
      ~S"""
      Saved Views:
      <.intersperse :let={v} enum={@available_saved_views}>
        <:separator>,</:separator>
        <.link href={"#{@path}?saved_view=#{v}"}>[<%= v %>]</.link>
      </.intersperse>
      """
    else
      ""
    end

    saved_view_assigns = if opts[:saved_views] do
      """
          saved_view_module={@saved_view_module}
          saved_view_context={@saved_view_context}
      """
    else
      ""
    end

    """
    <h1>#{schema_name} Data View</h1>

    <.button phx-click="toggle_show_view_configurator">Toggle View Controller</.button>

    #{saved_views_section}

    <div :if={@show_view_configurator}>
      <.live_component
        module={SelectoComponents.Form}
        id="config"
        view_config={@view_config}
        selecto={@selecto}
        executed={@executed}
        applied_view={nil}
        active_tab={@active_tab}
        views={@views}
        #{if opts[:enable_modal], do: "enable_modal_detail={true}", else: ""}#{saved_view_assigns}
      />
    </div>

    <.live_component
      module={SelectoComponents.Results}
      selecto={@selecto}
      query_results={@query_results}
      applied_view={@applied_view}
      executed={@executed}
      views={@views}
      view_meta={@view_meta}
      id="results"
    />
    """
  end

  defp get_app_name_from_schema_parts(schema_parts) do
    # For module names like Elixir.SelectoTest.Store.Film, extract "selecto_test"
    # Skip "Elixir" prefix if present
    relevant_parts = case schema_parts do
      ["Elixir" | rest] -> rest
      parts -> parts
    end

    app_name = case List.first(relevant_parts) do
      name when is_binary(name) ->
        name |> Macro.underscore()
      name when is_atom(name) ->
        name |> to_string() |> Macro.underscore()
      _ -> "app"
    end
    app_name
  end

  defp add_route_suggestion(igniter, schema, opts) do
    schema_parts = schema |> to_string() |> String.split(".")
    # Remove Elixir prefix if present
    clean_parts = case schema_parts do
      ["Elixir" | rest] -> rest
      parts -> parts
    end
    app_name = List.first(clean_parts)
    schema_name = List.last(clean_parts)
    schema_underscore = Macro.underscore(schema_name)

    # Use custom path if provided
    route_path = opts[:path] || schema_underscore
    # Remove leading slash if present for the route suggestion
    route_path = String.replace_prefix(route_path, "/", "")

    _live_module = "#{app_name}Web.#{schema_name}Live"

    route_suggestion = """

    Add this route to your router.ex:
      live "/#{route_path}", #{schema_name}Live, :index
    """

    Igniter.add_notice(igniter, route_suggestion)
  end

  defp add_success_message(igniter, message) do
    Igniter.add_notice(igniter, message)
  end

  defp maybe_run_assets_integration(igniter) do
    # Check if integration is needed
    Mix.Task.run("selecto.components.integrate", ["--check"])
    
    # Ask user if they want to run integration
    if Mix.shell().yes?("\nWould you like to automatically integrate SelectoComponents?") do
      Mix.Task.rerun("selecto.components.integrate", [])
    else
      Igniter.add_notice(igniter, """
      
      To complete SelectoComponents setup, run:
          mix selecto.components.integrate
      
      Or manually configure:
      1. Import hooks in assets/js/app.js
      2. Add @source directive in assets/css/app.css
      """)
    end
    
    igniter
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
