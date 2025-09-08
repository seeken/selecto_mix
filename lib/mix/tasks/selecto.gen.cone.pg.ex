defmodule Mix.Tasks.Selecto.Gen.Cone.Pg do
  @moduledoc """
  Generates a SelectoCone LiveView .exs file using Phoenix Playground.

  The SelectoCone pattern manages nested data through a single apex entity,
  ensuring all operations flow through the root to maintain consistency.

  ## Usage

      mix selecto.gen.cone.pg Customer Rental Payment [options]

  This creates a three-level hierarchy:
  - Customer (apex/root) - all operations flow through here
  - Rental (middle layer) - customer's rentals
  - Payment (base layer) - rental payments

  ## Options

    * `--output` - Output file path (default: selecto_cone_[apex]_pg.exs)
    * `--port` - Port for the Phoenix server (default: 4090)
    * `--no-stats` - Skip stats dashboard
    * `--no-forms` - Skip form modals (read-only view)

  ## Examples

      # Basic three-level hierarchy
      mix selecto.gen.cone.pg Customer Rental Payment

      # Two-level hierarchy
      mix selecto.gen.cone.pg Order OrderItem

      # Custom output and port
      mix selecto.gen.cone.pg Customer Rental Payment --output my_cone.exs --port 5000

      # Read-only view without forms
      mix selecto.gen.cone.pg Customer Rental Payment --no-forms
  """

  use Mix.Task
  import Mix.Generator

  @shortdoc "Generates a SelectoCone LiveView .exs file using Phoenix Playground"

  def run(args) do
    Mix.Task.run("compile")
    
    case parse_args(args) do
      {:ok, config} ->
        generate_cone(config)
        
      {:error, message} ->
        Mix.shell().error(message)
        Mix.shell().info("\n" <> @moduledoc)
    end
  end

  defp parse_args(args) do
    {opts, schemas, _} = OptionParser.parse(args,
      strict: [
        output: :string,
        port: :integer,
        no_stats: :boolean,
        no_forms: :boolean
      ]
    )

    case schemas do
      [] ->
        {:error, "At least two schemas are required (apex and one nested level)"}
      
      [_] ->
        {:error, "At least two schemas are required (apex and one nested level)"}
      
      schemas when length(schemas) > 3 ->
        {:error, "Maximum 3 levels supported (apex, middle, base)"}
      
      schemas ->
        config = build_config(schemas, opts)
        validate_schemas(config)
    end
  end

  defp build_config(schema_names, opts) do
    [apex | rest] = schema_names
    
    %{
      apex: parse_schema(apex),
      middle: if(Enum.at(rest, 0), do: parse_schema(Enum.at(rest, 0)), else: nil),
      base: if(Enum.at(rest, 1), do: parse_schema(Enum.at(rest, 1)), else: nil),
      output: Keyword.get(opts, :output, "selecto_cone_#{Macro.underscore(apex)}_pg.exs"),
      port: Keyword.get(opts, :port, 4090),
      include_stats: !Keyword.get(opts, :no_stats, false),
      include_forms: !Keyword.get(opts, :no_forms, false)
    }
  end

  defp parse_schema(name) do
    parts = String.split(name, ".")
    
    {module_parts, [schema_name]} = Enum.split(parts, -1)
    
    app_module = 
      if module_parts == [] do
        # Default to SelectoTest.Store for simple names
        SelectoTest.Store
      else
        Module.concat(module_parts)
      end
    
    schema_module = Module.concat([app_module, schema_name])
    
    %{
      module: schema_module,
      name: schema_name,
      singular: Macro.underscore(schema_name),
      plural: pluralize(Macro.underscore(schema_name)),
      human: humanize(schema_name)
    }
  end

  defp validate_schemas(config) do
    schemas_to_check = [config.apex, config.middle, config.base] |> Enum.filter(& &1)
    
    missing = Enum.filter(schemas_to_check, fn schema ->
      !Code.ensure_loaded?(schema.module)
    end)
    
    case missing do
      [] ->
        analyze_relationships(config)
      
      missing_schemas ->
        names = Enum.map(missing_schemas, & &1.module)
        {:error, "Schema modules not found: #{inspect(names)}"}
    end
  end

  defp analyze_relationships(config) do
    # Analyze the Ecto schemas to understand relationships
    config = Map.put(config, :relationships, %{})
    
    # Try to detect foreign keys and associations
    config = 
      if config.middle do
        detect_relationship(config, :apex_to_middle, config.apex, config.middle)
      else
        config
      end
    
    config = 
      if config.base && config.middle do
        detect_relationship(config, :middle_to_base, config.middle, config.base)
      else
        config
      end
    
    {:ok, config}
  end

  defp detect_relationship(config, key, parent_schema, child_schema) do
    # Look for has_many in parent
    parent_assocs = parent_schema.module.__schema__(:associations)
    child_assocs = child_schema.module.__schema__(:associations)
    
    # Find the association from parent to child
    parent_to_child = Enum.find(parent_assocs, fn assoc ->
      assoc_info = parent_schema.module.__schema__(:association, assoc)
      assoc_info.queryable == child_schema.module
    end)
    
    # Find the association from child to parent  
    child_to_parent = Enum.find(child_assocs, fn assoc ->
      assoc_info = child_schema.module.__schema__(:association, assoc)
      assoc_info.queryable == parent_schema.module
    end)
    
    # Get primary key field
    [parent_pk] = parent_schema.module.__schema__(:primary_key)
    [child_pk] = child_schema.module.__schema__(:primary_key)
    
    relationship = %{
      parent_pk: parent_pk,
      child_pk: child_pk,
      parent_assoc: parent_to_child,
      child_assoc: child_to_parent,
      foreign_key: if(child_to_parent, do: child_schema.module.__schema__(:association, child_to_parent).owner_key)
    }
    
    put_in(config, [:relationships, key], relationship)
  end

  defp generate_cone(config) do
    Mix.shell().info("Generating SelectoCone LiveView with Phoenix Playground...")
    
    template = build_template(config)
    
    create_file(config.output, template)
    
    Mix.shell().info("""
    
    SelectoCone LiveView generated successfully!
    
    To run:
        mix run #{config.output}
    
    Then visit:
        http://localhost:#{config.port}/
    
    The generated file includes:
    #{if config.include_stats, do: "  ✓ Stats dashboard", else: "  ✗ Stats dashboard (disabled)"}
    #{if config.include_forms, do: "  ✓ Create/Edit forms", else: "  ✗ Create/Edit forms (disabled)"}
    #{if config.base, do: "  ✓ Three-level hierarchy", else: "  ✓ Two-level hierarchy"}
    """)
  end

  defp build_template(config) do
    """
    #!/usr/bin/env elixir
    
    # SelectoCone LiveView with Phoenix Playground
    # Generated #{Date.to_string(Date.utc_today())}
    # 
    # Hierarchical data management pattern:
    # - #{config.apex.human} (Apex/Root)
    #{if config.middle, do: "# - #{config.middle.human} (Middle Layer)", else: ""}
    #{if config.base, do: "# - #{config.base.human} (Base Layer)", else: ""}
    #
    # Usage: mix run #{config.output}
    
    # Check if we're in a Mix project
    in_mix_project = File.exists?("mix.exs")
    
    unless in_mix_project do
      Mix.install([
        {:phoenix_playground, "~> 0.1.7"},
        {:ecto_sql, "~> 3.10"},
        {:postgrex, "~> 0.17"}
      ])
    end
    
    # Configure database connection
    Application.put_env(:selecto_cone, SelectoCone.Repo,
      database: System.get_env("DB_NAME", "selecto_test_dev"),
      username: System.get_env("DB_USER", "postgres"),
      password: System.get_env("DB_PASS", "postgres"),
      hostname: System.get_env("DB_HOST", "localhost"),
      pool_size: 10
    )
    
    defmodule SelectoCone.Repo do
      use Ecto.Repo,
        otp_app: :selecto_cone,
        adapter: Ecto.Adapters.Postgres
    end
    
    #{generate_schema_imports(config)}
    
    defmodule #{config.apex.name}Cone.ConeLive do
      use Phoenix.LiveView
      use Phoenix.Component
      import Phoenix.HTML.Form
      import Ecto.Query
      
      @impl true
      def mount(_params, _session, socket) do
        #{config.apex.plural} = list_#{config.apex.plural}()
        
        socket =
          socket
          |> assign(:#{config.apex.plural}, #{config.apex.plural})
          |> assign(:selected_#{config.apex.singular}, nil)
          #{if config.middle, do: "|> assign(:#{config.middle.plural}, [])", else: ""}
          #{if config.middle, do: "|> assign(:selected_#{config.middle.singular}, nil)", else: ""}
          #{if config.base, do: "|> assign(:#{config.base.plural}, [])", else: ""}
          #{if config.include_forms, do: "|> assign(:form_mode, nil)\n          |> assign(:changeset, nil)", else: ""}
          #{if config.include_stats, do: "|> assign(:stats, calculate_stats(#{config.apex.plural}))", else: ""}
        
        {:ok, socket}
      end
      
      @impl true
      def handle_params(params, _url, socket) do
        #{generate_handle_params(config)}
        {:noreply, socket}
      end
      
      @impl true
      def render(assigns) do
        ~H\"""
        <div style="font-family: system-ui, -apple-system, sans-serif; max-width: 1400px; margin: 0 auto; padding: 2rem;">
          <h1 style="font-size: 2rem; font-weight: bold; margin-bottom: 2rem;">
            SelectoCone - #{config.apex.human} Management
          </h1>
          
          #{if config.include_stats, do: generate_stats_template(config), else: ""}
          
          <div style="display: grid; grid-template-columns: #{grid_columns(config)}; gap: 1.5rem;">
            #{generate_apex_column(config)}
            #{if config.middle, do: generate_middle_column(config), else: ""}
            #{if config.base, do: generate_base_column(config), else: ""}
          </div>
          
          #{if config.include_forms, do: generate_form_modal(config), else: ""}
        </div>
        \"""
      end
      
      #{generate_event_handlers(config)}
      
      # Private Functions
      
      #{generate_private_functions(config)}
    end
    
    # Start the application
    {:ok, _} = SelectoCone.Repo.start_link()
    
    # Start Phoenix Playground
    port = #{config.port}
    
    PhoenixPlayground.start(
      live: #{config.apex.name}Cone.ConeLive,
      port: port
    )
    
    IO.puts \"""
    
    🚀 SelectoCone Server Started!
    📍 Visit: http://localhost:#{config.port}/
    ⏹  Press Ctrl+C twice to stop
    
    Hierarchy:
    • #{config.apex.human} (Apex - all operations flow through here)
    #{if config.middle, do: "• #{config.middle.human} (Middle layer)", else: ""}
    #{if config.base, do: "• #{config.base.human} (Base layer)", else: ""}
    
    \"""
    """
  end

  # Template generation helpers
  
  defp generate_schema_imports(config) do
    """
    # Import your schema modules
    # Update these aliases to match your application structure
    alias #{config.apex.module}
    #{if config.middle, do: "alias #{config.middle.module}", else: ""}
    #{if config.base, do: "alias #{config.base.module}", else: ""}
    """
  end

  defp grid_columns(config) do
    cond do
      config.base -> "repeat(3, 1fr)"
      config.middle -> "repeat(2, 1fr)"
      true -> "1fr"
    end
  end

  defp generate_handle_params(config) do
    """
        #{config.apex.singular}_id = params["#{config.apex.singular}_id"]
        #{if config.middle, do: "#{config.middle.singular}_id = params[\"#{config.middle.singular}_id\"]", else: ""}
        
        socket =
          socket
          |> load_#{config.apex.singular}(#{config.apex.singular}_id)
          #{if config.middle, do: "|> load_#{config.middle.singular}(#{config.middle.singular}_id)", else: ""}
    """
  end

  defp generate_stats_template(config) do
    """
    <!-- Stats Dashboard -->
          <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; margin-bottom: 2rem;">
            <div style="background: #EBF8FF; padding: 1rem; border-radius: 0.5rem;">
              <div style="color: #718096; font-size: 0.875rem;">Total #{config.apex.human}s</div>
              <div style="font-size: 1.5rem; font-weight: bold;"><%= @stats.total_#{config.apex.plural} %></div>
            </div>
            #{if config.middle, do: generate_middle_stats(config), else: ""}
          </div>
    """
  end

  defp generate_middle_stats(config) do
    """
    <div style="background: #F0FDF4; padding: 1rem; border-radius: 0.5rem;">
              <div style="color: #718096; font-size: 0.875rem;">Active #{config.middle.human}s</div>
              <div style="font-size: 1.5rem; font-weight: bold;"><%= @stats.active_#{config.middle.plural} %></div>
            </div>
    """
  end

  defp generate_apex_column(config) do
    """
    <!-- #{config.apex.human}s (Apex) -->
            <div style="background: white; border-radius: 0.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); padding: 1.5rem;">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                <h2 style="font-size: 1.25rem; font-weight: 600;">#{config.apex.human}s (Apex)</h2>
                #{if config.include_forms, do: """
                <button phx-click="new_#{config.apex.singular}" style="background: #3B82F6; color: white; padding: 0.25rem 0.75rem; border-radius: 0.25rem; border: none; cursor: pointer;">
                  + New
                </button>
                """, else: ""}
              </div>
              
              <div style="max-height: 24rem; overflow-y: auto;">
                <%= for #{config.apex.singular} <- @#{config.apex.plural} do %>
                  <div
                    phx-click="select_#{config.apex.singular}"
                    phx-value-id={#{config.apex.singular}.#{get_primary_key(config.apex)}}
                    style={"padding: 0.75rem; margin-bottom: 0.5rem; border: 1px solid #E5E7EB; border-radius: 0.25rem; cursor: pointer; \#{if @selected_#{config.apex.singular} && @selected_#{config.apex.singular}.#{get_primary_key(config.apex)} == #{config.apex.singular}.#{get_primary_key(config.apex)}, do: \"background: #DBEAFE; border-color: #3B82F6;\", else: \"background: white;\"}"}
                  >
                    <div style="font-weight: 500;">
                      #{config.apex.human} #<%= #{config.apex.singular}.#{get_primary_key(config.apex)} %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
    """
  end

  defp generate_middle_column(config) do
    """
    <!-- #{config.middle.human}s (Middle) -->
            <div style="background: white; border-radius: 0.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); padding: 1.5rem;">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                <h2 style="font-size: 1.25rem; font-weight: 600;">#{config.middle.human}s (Middle)</h2>
                <%= if @selected_#{config.apex.singular} do %>
                  #{if config.include_forms, do: """
                  <button phx-click="new_#{config.middle.singular}" style="background: #10B981; color: white; padding: 0.25rem 0.75rem; border-radius: 0.25rem; border: none; cursor: pointer;">
                    + New
                  </button>
                  """, else: ""}
                <% end %>
              </div>
              
              <%= if @selected_#{config.apex.singular} do %>
                <div style="max-height: 24rem; overflow-y: auto;">
                  <%= for #{config.middle.singular} <- @#{config.middle.plural} do %>
                    <div
                      phx-click="select_#{config.middle.singular}"
                      phx-value-id={#{config.middle.singular}.#{get_primary_key(config.middle)}}
                      style={"padding: 0.75rem; margin-bottom: 0.5rem; border: 1px solid #E5E7EB; border-radius: 0.25rem; cursor: pointer; \#{if @selected_#{config.middle.singular} && @selected_#{config.middle.singular}.#{get_primary_key(config.middle)} == #{config.middle.singular}.#{get_primary_key(config.middle)}, do: \"background: #D1FAE5; border-color: #10B981;\", else: \"background: white;\"}"}
                    >
                      <div style="font-weight: 500;">
                        #{config.middle.human} #<%= #{config.middle.singular}.#{get_primary_key(config.middle)} %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div style="text-align: center; color: #9CA3AF; padding: 4rem 0;">
                  Select a #{config.apex.singular} to view #{config.middle.plural}
                </div>
              <% end %>
            </div>
    """
  end

  defp generate_base_column(config) do
    """
    <!-- #{config.base.human}s (Base) -->
            <div style="background: white; border-radius: 0.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); padding: 1.5rem;">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                <h2 style="font-size: 1.25rem; font-weight: 600;">#{config.base.human}s (Base)</h2>
                <%= if @selected_#{config.middle.singular} do %>
                  #{if config.include_forms, do: """
                  <button phx-click="new_#{config.base.singular}" style="background: #8B5CF6; color: white; padding: 0.25rem 0.75rem; border-radius: 0.25rem; border: none; cursor: pointer;">
                    + New
                  </button>
                  """, else: ""}
                <% end %>
              </div>
              
              <%= if @selected_#{config.middle.singular} do %>
                <div style="max-height: 24rem; overflow-y: auto;">
                  <%= for #{config.base.singular} <- @#{config.base.plural} do %>
                    <div style="padding: 0.75rem; margin-bottom: 0.5rem; border: 1px solid #E5E7EB; border-radius: 0.25rem; background: white;">
                      <div style="font-weight: 500;">
                        #{config.base.human} #<%= #{config.base.singular}.#{get_primary_key(config.base)} %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div style="text-align: center; color: #9CA3AF; padding: 4rem 0;">
                  Select a #{config.middle.singular} to view #{config.base.plural}
                </div>
              <% end %>
            </div>
    """
  end

  defp generate_form_modal(_config) do
    """
    <!-- Form Modal Placeholder -->
          <%= if @form_mode do %>
            <div style="position: fixed; inset: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 50;">
              <div style="background: white; border-radius: 0.5rem; padding: 1.5rem; width: 24rem;">
                <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">
                  Form Modal
                </h3>
                <p>Form implementation goes here</p>
                <button phx-click="cancel_form" style="background: #9CA3AF; color: white; padding: 0.5rem 1rem; border-radius: 0.25rem; border: none; cursor: pointer;">
                  Cancel
                </button>
              </div>
            </div>
          <% end %>
    """
  end

  defp generate_event_handlers(config) do
    """
    # Event Handlers
      
      @impl true
      def handle_event("select_#{config.apex.singular}", %{"id" => id}, socket) do
        socket = load_#{config.apex.singular}(socket, id)
        {:noreply, push_patch(socket, to: "/?#{config.apex.singular}_id=\#{id}")}
      end
      
      #{if config.middle, do: generate_middle_handlers(config), else: ""}
      
      #{if config.include_forms, do: generate_form_handlers(config), else: ""}
    """
  end

  defp generate_middle_handlers(config) do
    """
    @impl true
      def handle_event("select_#{config.middle.singular}", %{"id" => id}, socket) do
        socket = load_#{config.middle.singular}(socket, id)
        #{config.apex.singular}_id = socket.assigns.selected_#{config.apex.singular}.#{get_primary_key(config.apex)}
        {:noreply, push_patch(socket, to: "/?#{config.apex.singular}_id=\#{#{config.apex.singular}_id}&#{config.middle.singular}_id=\#{id}")}
      end
    """
  end

  defp generate_form_handlers(config) do
    """
    @impl true
      def handle_event("new_#{config.apex.singular}", _params, socket) do
        socket = assign(socket, :form_mode, :new_#{config.apex.singular})
        {:noreply, socket}
      end
      
      @impl true
      def handle_event("cancel_form", _params, socket) do
        socket = 
          socket
          |> assign(:form_mode, nil)
          |> assign(:changeset, nil)
        
        {:noreply, socket}
      end
    """
  end

  defp generate_private_functions(config) do
    """
    defp list_#{config.apex.plural} do
        #{config.apex.module}
        |> order_by([t], t.#{get_primary_key(config.apex)})
        |> limit(100)
        |> SelectoCone.Repo.all()
      end
      
      defp load_#{config.apex.singular}(socket, nil), do: socket
      defp load_#{config.apex.singular}(socket, #{config.apex.singular}_id) do
        #{config.apex.singular} = SelectoCone.Repo.get!(#{config.apex.module}, #{config.apex.singular}_id)
        #{if config.middle, do: "#{config.middle.plural} = list_#{config.middle.plural}(#{config.apex.singular}.#{get_primary_key(config.apex)})", else: ""}
        
        socket
        |> assign(:selected_#{config.apex.singular}, #{config.apex.singular})
        #{if config.middle, do: "|> assign(:#{config.middle.plural}, #{config.middle.plural})\n        |> assign(:selected_#{config.middle.singular}, nil)", else: ""}
        #{if config.base, do: "|> assign(:#{config.base.plural}, [])", else: ""}
      end
      
      #{if config.middle, do: generate_middle_functions(config), else: ""}
      
      #{if config.include_stats, do: generate_stats_function(config), else: ""}
    """
  end

  defp generate_middle_functions(config) do
    """
    defp list_#{config.middle.plural}(#{config.apex.singular}_id) do
        #{config.middle.module}
        |> where([t], t.#{config.relationships.apex_to_middle.foreign_key || "#{config.apex.singular}_id"} == ^#{config.apex.singular}_id)
        |> order_by([t], desc: t.#{get_primary_key(config.middle)})
        |> SelectoCone.Repo.all()
      end
      
      defp load_#{config.middle.singular}(socket, nil), do: socket
      defp load_#{config.middle.singular}(socket, #{config.middle.singular}_id) do
        #{config.middle.singular} = SelectoCone.Repo.get!(#{config.middle.module}, #{config.middle.singular}_id)
        #{if config.base, do: "#{config.base.plural} = list_#{config.base.plural}(#{config.middle.singular}.#{get_primary_key(config.middle)})", else: ""}
        
        socket
        |> assign(:selected_#{config.middle.singular}, #{config.middle.singular})
        #{if config.base, do: "|> assign(:#{config.base.plural}, #{config.base.plural})", else: ""}
      end
      
      #{if config.base, do: generate_base_functions(config), else: ""}
    """
  end

  defp generate_base_functions(config) do
    """
    defp list_#{config.base.plural}(#{config.middle.singular}_id) do
        #{config.base.module}
        |> where([t], t.#{config.relationships.middle_to_base.foreign_key || "#{config.middle.singular}_id"} == ^#{config.middle.singular}_id)
        |> order_by([t], desc: t.#{get_primary_key(config.base)})
        |> SelectoCone.Repo.all()
      end
    """
  end

  defp generate_stats_function(config) do
    """
    defp calculate_stats(#{config.apex.plural}) do
        %{
          total_#{config.apex.plural}: length(#{config.apex.plural})#{if config.middle, do: ",\n          active_#{config.middle.plural}: 0", else: ""}
        }
      end
    """
  end

  defp get_primary_key(schema_config) do
    # Try to get the actual primary key from the schema module
    try do
      schema_module = Module.safe_concat([schema_config.module])
      case schema_module.__schema__(:primary_key) do
        [key] -> to_string(key)
        _ -> "id"
      end
    rescue
      _ -> 
        # If we can't introspect, use a reasonable default based on naming convention
        # Many schemas use table_name_id pattern (e.g., customer_id for customer table)
        "#{schema_config.singular}_id"
    end
  end

  defp pluralize(word) do
    cond do
      String.ends_with?(word, "y") -> String.replace_suffix(word, "y", "ies")
      String.ends_with?(word, "s") -> word <> "es"
      true -> word <> "s"
    end
  end

  defp humanize(word) do
    word
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end