defmodule SelectoMix.TemplateEngine do
  @moduledoc """
  Template engine for generating Selecto domains with adapter-specific variations.
  
  Supports dynamic template selection based on database adapter, feature availability,
  and user preferences.
  """
  
  alias SelectoMix.AdapterDetector
  
    
  @type template_context :: %{
    module: module(),
    schema_info: map(),
    adapter: atom(),
    features: map(),
    joins: map(),
    type_mappings: map(),
    version: String.t() | nil,
    format: atom(),
    style: atom(),
    namespace: String.t() | nil,
    warnings: list(String.t()),
    suggestions: list(String.t())
  }
  
  @doc """
  Renders a domain module from templates.
  """
  @spec render_domain(module(), map(), atom(), keyword()) :: String.t()
  def render_domain(schema_module, analysis, adapter, opts \\ []) do
    context = build_template_context(schema_module, analysis, adapter, opts)
    
    # Select appropriate template
    template = select_template(:domain, adapter, context.features)
    
    # Render with EEx or use our internal renderer
    render_template(template, context)
  end
  
  @doc """
  Renders LiveView module from templates.
  """
  @spec render_live_view(module(), map(), atom(), keyword()) :: String.t()
  def render_live_view(schema_module, analysis, adapter, opts \\ []) do
    context = build_template_context(schema_module, analysis, adapter, opts)
    
    template = select_template(:live_view, adapter, context.features)
    render_template(template, context)
  end
  
  @doc """
  Renders migration file from templates.
  """
  @spec render_migration(module(), map(), atom(), keyword()) :: String.t()
  def render_migration(schema_module, analysis, adapter, opts \\ []) do
    context = build_template_context(schema_module, analysis, adapter, opts)
    
    template = select_template(:migration, adapter, context.features)
    render_template(template, context)
  end
  
  @doc """
  Gets the base domain template (adapter-agnostic).
  """
  @spec get_base_domain_template() :: String.t()
  def get_base_domain_template do
    """
    defmodule <%= @namespace %>.<%= @module_name %>Domain do
      @moduledoc \"\"\"
      Selecto domain configuration for <%= @module_name %>.
      
      Generated for <%= @adapter %> adapter.
      <%= if @warnings != [], do: format_warnings(@warnings) %>
      \"\"\"
      
      use Selecto.Domain
      
      @doc \"\"\"
      Returns the domain configuration.
      \"\"\"
      @spec domain() :: Selecto.Domain.t()
      def domain do
        %{
          source: "<%= @table_name %>",
          schemas: %{
            <%= @schema_name %> => %{
              module: <%= @schema_module %>,
              columns: <%= format_columns(@columns, @adapter) %>,
              <%= if @custom_columns != %{}, do: "custom_columns: " <> format_custom_columns(@custom_columns, @adapter) <> "," %>
              <%= if @filters != [], do: "filters: " <> format_filters(@filters, @adapter) <> "," %>
              <%= if @aggregates != [], do: "aggregates: " <> format_aggregates(@aggregates, @adapter) <> "," %>
              <%= if @select_options != %{}, do: "select_options: " <> format_select_options(@select_options) <> "," %>
            }
          },
          <%= if @joins != %{}, do: "joins: " <> format_joins(@joins, @adapter) <> "," %>
          <%= if @metadata != %{}, do: "metadata: " <> format_metadata(@metadata) <> "," %>
        }
      end
      
      <%= render_helper_functions(@context) %>
    end
    """
  end
  
  @doc """
  Gets adapter-specific domain template overrides.
  """
  @spec get_adapter_template(:domain | :migration | :live_view, atom()) :: String.t() | nil
  def get_adapter_template(:domain, :mysql) do
    """
    # MySQL-specific additions to domain template
    <%= if has_arrays?(@columns) do %>
      # Note: Arrays are stored as JSON in MySQL
      @doc \"\"\"
      Converts JSON arrays to Elixir lists for MySQL compatibility.
      \"\"\"
      def decode_array(nil), do: []
      def decode_array(json) when is_binary(json) do
        case Jason.decode(json) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end
      end
      def decode_array(list) when is_list(list), do: list
    <% end %>
    
    <%= if @features[:ctes] == false do %>
      # Note: CTEs are not available in MySQL < 8.0
      # Hierarchical queries will use alternative methods
    <% end %>
    
    <%= if has_full_text_search?(@columns) do %>
      @doc \"\"\"
      Builds MySQL FULLTEXT search conditions.
      \"\"\"
      def fulltext_search(field, query) do
        "MATCH(\#{field}) AGAINST('\#{query}' IN NATURAL LANGUAGE MODE)"
      end
    <% end %>
    """
  end
  
  def get_adapter_template(:domain, :sqlite) do
    """
    # SQLite-specific additions to domain template
    <%= if has_arrays?(@columns) do %>
      # Note: Arrays are stored as JSON in SQLite
      @doc \"\"\"
      Converts JSON arrays to Elixir lists for SQLite compatibility.
      \"\"\"
      def decode_array(nil), do: []
      def decode_array(json) when is_binary(json) do
        case Jason.decode(json) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end
      end
      def decode_array(list) when is_list(list), do: list
    <% end %>
    
    <%= if has_uuid_fields?(@columns) do %>
      # Note: UUIDs are stored as TEXT in SQLite
      # No conversion needed, but be aware of string comparison
    <% end %>
    
    <%= if @features[:window_functions] == false do %>
      # Note: Window functions require SQLite 3.25+
      # Using alternative aggregation methods
    <% end %>
    """
  end
  
  def get_adapter_template(:domain, :postgres), do: nil  # Use base template
  
  def get_adapter_template(:migration, :mysql) do
    """
    defmodule <%= @repo %>.Migrations.Create<%= @table_name_camelized %> do
      use Ecto.Migration
      
      def change do
        create table(:<%= @table_name %><%= if @uuid_primary_key do %>, primary_key: false<% end %>) do
          <%= if @uuid_primary_key do %>
          add :id, :binary_id, primary_key: true
          <% end %>
          <%= for {name, type} <- @fields do %>
          add :<%= name %>, <%= mysql_type(type) %><%= mysql_field_opts(name, type) %>
          <% end %>
          
          timestamps()
        end
        
        <%= for index <- @indexes do %>
        <%= mysql_index(index) %>
        <% end %>
      end
      
      defp mysql_type(:uuid), do: :string
      defp mysql_type({:array, _}), do: :json
      defp mysql_type(:text), do: :text
      defp mysql_type(type), do: type
    end
    """
  end
  
  def get_adapter_template(:migration, :sqlite) do
    """
    defmodule <%= @repo %>.Migrations.Create<%= @table_name_camelized %> do
      use Ecto.Migration
      
      def change do
        create table(:<%= @table_name %><%= if @uuid_primary_key do %>, primary_key: false<% end %>) do
          <%= if @uuid_primary_key do %>
          add :id, :string, primary_key: true, default: fragment("lower(hex(randomblob(16)))")
          <% end %>
          <%= for {name, type} <- @fields do %>
          add :<%= name %>, <%= sqlite_type(type) %><%= sqlite_field_opts(name, type) %>
          <% end %>
          
          timestamps()
        end
        
        <%= for index <- @indexes do %>
        <%= sqlite_index(index) %>
        <% end %>
        
        <%= if has_full_text_search?(@fields) do %>
        # Create FTS5 virtual table for full-text search
        execute "CREATE VIRTUAL TABLE <%= @table_name %>_fts USING fts5(<%= fts_fields(@fields) %>)"
        <% end %>
      end
      
      defp sqlite_type(:uuid), do: :string
      defp sqlite_type(:binary_id), do: :string
      defp sqlite_type({:array, _}), do: :string  # JSON as TEXT
      defp sqlite_type(:json), do: :string
      defp sqlite_type(:jsonb), do: :string
      defp sqlite_type(:boolean), do: :integer
      defp sqlite_type(:bigint), do: :integer
      defp sqlite_type(type), do: type
    end
    """
  end
  
  def get_adapter_template(:migration, :postgres) do
    """
    defmodule <%= @repo %>.Migrations.Create<%= @table_name_camelized %> do
      use Ecto.Migration
      
      def change do
        <%= if needs_extensions?(@fields) do %>
        # Enable required PostgreSQL extensions
        <%= for ext <- required_extensions(@fields) do %>
        execute "CREATE EXTENSION IF NOT EXISTS <%= ext %>"
        <% end %>
        <% end %>
        
        create table(:<%= @table_name %><%= if @uuid_primary_key do %>, primary_key: false<% end %>) do
          <%= if @uuid_primary_key do %>
          add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
          <% end %>
          <%= for {name, type} <- @fields do %>
          add :<%= name %>, <%= postgres_type(type) %><%= postgres_field_opts(name, type) %>
          <% end %>
          
          timestamps()
        end
        
        <%= for index <- @indexes do %>
        <%= postgres_index(index) %>
        <% end %>
      end
    end
    """
  end
  
  # Private functions
  
  defp build_template_context(schema_module, analysis, adapter, opts) do
    features = AdapterDetector.get_features(adapter, opts[:adapter_version])
    type_mappings = AdapterDetector.get_type_mappings(adapter)
    
    schema_info = analysis[:schema_info] || %{}
    
    %{
      module: schema_module,
      module_name: module_name(schema_module),
      schema_name: schema_name(schema_module),
      schema_module: inspect(schema_module),
      table_name: table_name(schema_info),
      columns: extract_columns(schema_info, type_mappings),
      custom_columns: analysis[:custom_columns] || %{},
      filters: analysis[:filters] || [],
      aggregates: analysis[:aggregates] || [],
      select_options: analysis[:select_options] || %{},
      joins: analysis[:joins] || %{},
      metadata: build_metadata(analysis),
      adapter: adapter,
      features: features,
      type_mappings: type_mappings,
      version: opts[:adapter_version],
      format: opts[:format] || :expanded,
      style: opts[:style] || :phoenix,
      namespace: opts[:namespace] || default_namespace(),
      warnings: analysis[:warnings] || [],
      suggestions: analysis[:suggestions] || [],
      repo: repo_module()
    }
  end
  
  defp select_template(type, adapter, _features) do
    # Try adapter-specific template first
    adapter_template = get_adapter_template(type, adapter)
    
    if adapter_template do
      # Combine base + adapter-specific
      base = get_base_template(type)
      combine_templates(base, adapter_template)
    else
      # Use base template only
      get_base_template(type)
    end
  end
  
  defp get_base_template(:domain), do: get_base_domain_template()
  defp get_base_template(:migration), do: get_base_migration_template()
  defp get_base_template(:live_view), do: get_base_live_view_template()
  
  defp get_base_migration_template do
    # Simplified base migration template
    """
    defmodule <%= @repo %>.Migrations.Create<%= @table_name_camelized %> do
      use Ecto.Migration
      
      def change do
        create table(:<%= @table_name %>) do
          <%= for {name, type} <- @fields do %>
          add :<%= name %>, :<%= type %>
          <% end %>
          
          timestamps()
        end
      end
    end
    """
  end
  
  defp get_base_live_view_template do
    # Simplified LiveView template
    """
    defmodule <%= @namespace %>Web.<%= @module_name %>Live do
      use <%= @namespace %>Web, :live_view
      use SelectoComponents.Form
      
      alias <%= @namespace %>.<%= @module_name %>Domain
      
      @impl true
      def mount(_params, _session, socket) do
        domain = <%= @module_name %>Domain.domain()
        selecto = Selecto.configure(domain, <%= @repo %>)
        
        views = [
          {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate View", %{drill_down: :detail}},
          {:detail, SelectoComponents.Views.Detail, "Detail View", %{}},
          {:graph, SelectoComponents.Views.Graph, "Graph View", %{}}
        ]
        
        state = get_initial_state(views, selecto)
        {:ok, assign(socket, state)}
      end
    end
    """
  end
  
  defp render_template(template, context) do
    # Use EEx to render the template with context
    # For now, simple string interpolation
    template
    |> String.replace("<%= @module_name %>", context.module_name)
    |> String.replace("<%= @namespace %>", context.namespace || "MyApp")
    |> String.replace("<%= @table_name %>", context.table_name)
    |> String.replace("<%= @adapter %>", to_string(context.adapter))
    |> String.replace("<%= @repo %>", context.repo || "Repo")
    # Add more replacements as needed
  end
  
  defp combine_templates(base, additions) do
    # Combine base template with adapter-specific additions
    base <> "\n" <> additions
  end
  
  defp module_name(module) do
    module
    |> Module.split()
    |> List.last()
  end
  
  defp schema_name(module) do
    module
    |> module_name()
    |> Macro.underscore()
    |> String.to_atom()
  end
  
  defp table_name(schema_info) do
    schema_info[:source] || schema_info[:table] || "unknown"
  end
  
  defp extract_columns(schema_info, type_mappings) do
    fields = schema_info[:fields] || []
    
    Enum.map(fields, fn field ->
      original_type = field[:type]
      mapped_type = Map.get(type_mappings, original_type, original_type)
      
      %{
        name: field[:name],
        type: mapped_type,
        original_type: original_type
      }
    end)
  end
  
  defp build_metadata(analysis) do
    %{
      generated_at: DateTime.utc_now(),
      generator_version: "1.0.0",
      warnings_count: length(analysis[:warnings] || []),
      suggestions_count: length(analysis[:suggestions] || [])
    }
  end
  
  defp default_namespace do
    Mix.Project.config()[:app]
    |> to_string()
    |> Macro.camelize()
  end
  
  defp repo_module do
    app = Mix.Project.config()[:app]
    "#{Macro.camelize(to_string(app))}.Repo"
  end
  
end