defmodule SelectoMix.DomainGenerator do
  @moduledoc """
  Generates Selecto domain configuration files from schema introspection data.
  
  This module creates complete, functional Selecto domain files that users
  can immediately use in their applications. The generated files include
  helpful comments, customization markers, and suggested configurations.
  """

  @doc """
  Generate a complete Selecto domain file.
  
  Creates a comprehensive domain configuration file with:
  - Schema-based field and type definitions
  - Association configurations for joins
  - Suggested default selections and filters
  - Customization markers for user modifications
  - Documentation and usage examples
  """
  def generate_domain_file(schema_module, config) do
    module_name = get_domain_module_name(schema_module, config)
    
    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      Selecto domain configuration for #{inspect(schema_module)}.
      
      This file was automatically generated from the Ecto schema.
      You can customize this configuration by modifying the domain map below.
      
      ## Usage
      
          # Basic usage
          selecto = Selecto.configure(#{module_name}.domain(), MyApp.Repo)
          
          # With Ecto integration
          selecto = Selecto.from_ecto(MyApp.Repo, #{inspect(schema_module)})
          
          # Execute queries
          {:ok, {rows, columns, aliases}} = Selecto.execute(selecto)
      
      ## Customization
      
      You can customize this domain by:
      - Adding custom fields to the fields list
      - Modifying default selections and filters
      - Adjusting join configurations
      - Adding custom domain metadata
      
      Fields, filters, and joins marked with "# CUSTOM" comments will be
      preserved when this file is regenerated.
      
      ## Regeneration
      
      To regenerate this file after schema changes:
      
          mix selecto.gen.domain #{inspect(schema_module)}
          
      Your customizations will be preserved during regeneration.
      \"\"\"

      @doc \"\"\"
      Returns the Selecto domain configuration for #{inspect(schema_module)}.
      \"\"\"
      def domain do
        #{generate_domain_map(config)}
      end

      #{generate_helper_functions(schema_module, config)}
    end
    """
  end

  @doc """
  Generate the core domain configuration map.
  """
  def generate_domain_map(config) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    custom_metadata = generate_custom_metadata(config)
    
    "%{\n      # Generated from schema: #{config[:schema_module]}\n" <>
    "      # Last updated: #{timestamp}\n      \n" <>
    "      source: #{generate_source_config(config)},\n" <>
    "      schemas: #{generate_schemas_config(config)},\n" <>
    "      name: #{generate_domain_name(config)},\n      \n" <>
    "      # Default selections (customize as needed)\n" <>
    "      default_selected: #{generate_default_selected(config)},\n      \n" <>
    "      # Suggested filters (add/remove as needed)\n" <>
    "      filters: #{generate_filters_config(config)},\n      \n" <>
    "      # Join configurations\n" <>
    "      joins: #{generate_joins_config(config)}#{custom_metadata}\n    }"
  end

  # Private generation functions

  defp get_domain_module_name(schema_module, config) do
    base_name = config[:metadata][:module_name] || 
                Module.split(schema_module) |> List.last()
    
    _context_name = config[:metadata][:context_name] || "Domains"
    
    # Generate appropriate module name
    app_name = Application.get_env(:selecto_mix, :app_name) || 
               detect_app_name() || 
               "MyApp"
    "#{app_name}.SelectoDomains.#{base_name}Domain"
  end

  defp generate_source_config(config) do
    primary_key = config[:primary_key] || :id
    table_name = config[:table_name] || "unknown_table"
    fields = config[:fields] || []
    redacted_fields = config[:redacted_fields] || []
    field_types = config[:field_types] || %{}
    
    redacted_line = if redacted_fields != [], do: "\n        redact_fields: #{inspect(redacted_fields)},", else: ""
    
    "%{\n        source_table: \"#{table_name}\",\n" <>
    "        primary_key: #{inspect(primary_key)},\n        \n" <>
    "        # Available fields from schema\n" <>
    "        # NOTE: This is redundant with columns - consider using Map.keys(columns) instead\n" <>
    "        fields: #{inspect(fields)},\n        \n" <>
    "        # Fields to exclude from queries#{redacted_line}\n" <>
    "        redact_fields: [],\n        \n" <>
    "        # Field type definitions (contains the same info as fields above)\n" <>
    "        columns: #{generate_columns_config(fields, field_types)},\n        \n" <>
    "        # Schema associations\n" <>
    "        associations: #{generate_source_associations(config)}\n      }"
  end

  defp generate_columns_config(fields, field_types) do
    columns_map = Enum.into(fields, %{}, fn field ->
      type = Map.get(field_types, field, :string)
      {field, %{type: type}}
    end)
    
    # Format the map with nice indentation
    formatted_columns = 
      columns_map
      |> Enum.map(fn {field, type_map} ->
        "          #{inspect(field)} => #{inspect(type_map)}"
      end)
      |> Enum.join(",\n")
    
    "%{\n#{formatted_columns}\n        }"
  end

  defp generate_source_associations(config) do
    associations = config[:associations] || %{}
    
    if Enum.empty?(associations) do
      "%{}"
    else
      formatted_assocs = 
        associations
        |> Enum.reject(fn {_name, assoc} -> assoc[:is_through] end)  # Skip through associations for now
        |> Enum.map(fn {assoc_name, assoc_config} ->
          custom_marker = if assoc_config[:is_custom], do: " # CUSTOM", else: ""
          queryable_name = inspect(get_queryable_name(assoc_config))
          owner_key = inspect(assoc_config[:owner_key])
          related_key = inspect(assoc_config[:related_key])
          
          "#{inspect(assoc_name)} => %{\n" <>
          "              queryable: #{queryable_name},\n" <>
          "              field: #{inspect(assoc_name)},\n" <>
          "              owner_key: #{owner_key},\n" <>
          "              related_key: #{related_key}#{custom_marker}\n" <>
          "            }"
        end)
        |> Enum.join(",\n        ")
      
      "%{\n        #{formatted_assocs}\n        }"
    end
  end

  defp get_queryable_name(assoc_config) do
    case assoc_config[:related_schema] do
      nil -> :unknown
      schema when is_atom(schema) ->
        schema
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()
      other -> other
    end
  end

  defp generate_schemas_config(config) do
    associations = config[:associations] || %{}
    
    # Generate schema configurations for associations
    schema_configs = 
      associations
      |> Enum.reject(fn {_name, assoc} -> assoc[:is_through] end)
      |> Enum.map(fn {_assoc_name, assoc_config} ->
        schema_name = get_queryable_name(assoc_config)
        table_name = guess_table_name(assoc_config[:related_schema])
        related_schema = inspect(assoc_config[:related_schema])
        
        "#{inspect(schema_name)} => %{\n" <>
        "            # TODO: Add proper schema configuration for #{related_schema}\n" <>
        "            # This will be auto-generated when you run:\n" <>
        "            # mix selecto.gen.domain #{related_schema}\n" <>
        "            source_table: \"#{table_name}\",\n" <>
        "            primary_key: :id,\n" <>
        "            fields: [], # Add fields for #{related_schema}\n" <>
        "            redact_fields: [],\n" <>
        "            columns: %{},\n" <>
        "            associations: %{}\n" <>
        "          }"
      end)
      |> Enum.join(",\n      ")
    
    if schema_configs == "" do
      "%{}"
    else
      "%{\n      #{schema_configs}\n    }"
    end
  end

  defp guess_table_name(schema_module) when is_atom(schema_module) do
    schema_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> Igniter.Inflex.pluralize()
  rescue
    _ -> "unknown_table"
  end
  
  defp guess_table_name(_), do: "unknown_table"

  defp generate_domain_name(config) do
    custom_name = get_in(config, [:preserved_customizations, :custom_metadata, :custom_name])
    
    case custom_name do
      nil -> 
        base_name = config[:metadata][:module_name] || "Unknown"
        inspect("#{base_name} Domain")
      name -> 
        inspect(name) <> " # CUSTOM"
    end
  end

  defp generate_default_selected(config) do
    suggested_defaults = config[:suggested_defaults][:default_selected] || []
    custom_defaults = get_in(config, [:preserved_customizations, :custom_metadata, :custom_defaults])
    
    defaults = case custom_defaults do
      nil -> suggested_defaults
      custom -> custom ++ suggested_defaults
    end
    
    formatted_defaults = defaults |> Enum.map(&inspect(to_string(&1))) |> Enum.join(", ")
    
    case defaults do
      [] -> "[]"
      _ -> "[#{formatted_defaults}]"
    end <> (if custom_defaults, do: " # CUSTOM", else: "")
  end

  defp generate_filters_config(config) do
    suggested_filters = config[:suggested_defaults][:default_filters] || %{}
    custom_filters = get_in(config, [:preserved_customizations, :custom_filters]) || %{}
    
    all_filters = Map.merge(suggested_filters, custom_filters)
    
    if Enum.empty?(all_filters) do
      "%{}"
    else
      formatted_filters = 
        all_filters
        |> Enum.map(fn {filter_name, filter_config} ->
          is_custom = Map.has_key?(custom_filters, filter_name)
          custom_marker = if is_custom, do: " # CUSTOM", else: ""
          formatted_config = format_filter_config(filter_config)
          
          "\"#{filter_name}\" => #{formatted_config}#{custom_marker}"
        end)
        |> Enum.join(",\n      ")
      
      "%{\n      #{formatted_filters}\n    }"
    end
  end

  defp format_filter_config(filter_config) when is_map(filter_config) do
    inspect(filter_config, pretty: true, width: 60)
  end
  
  defp format_filter_config(:custom) do
    "%{\n" <>
    "        # Custom filter configuration\n" <>
    "        # Add your filter definition here\n" <>
    "      }"
  end

  defp generate_joins_config(config) do
    associations = config[:associations] || %{}
    
    if Enum.empty?(associations) do
      "%{}"
    else
      formatted_joins = 
        associations
        |> Enum.reject(fn {_name, assoc} -> assoc[:is_through] end)
        |> Enum.map(fn {assoc_name, assoc_config} ->
          is_custom = assoc_config[:is_custom] == true
          custom_marker = if is_custom, do: " # CUSTOM JOIN", else: ""
          join_type = inspect(assoc_config[:join_type] || :left)
          
          "#{inspect(assoc_name)} => %{\n" <>
          "              name: \"#{humanize_name(assoc_name)}\",\n" <>
          "              type: #{join_type}\n" <>
          "            }#{custom_marker}"
        end)
        |> Enum.join(",\n      ")
      
      "%{\n      #{formatted_joins}\n    }"
    end
  end

  defp generate_custom_metadata(config) do
    custom_metadata = get_in(config, [:preserved_customizations, :custom_metadata]) || %{}
    
    if Enum.empty?(custom_metadata) do
      ""
    else
      "\n      \n      # Custom domain metadata\n      # Add any additional domain configuration here"
    end
  end

  defp generate_helper_functions(schema_module, config) do
    suggested_queries = generate_suggested_queries(config)
    
    [
      "@doc \"Create a new Selecto instance configured with this domain.\"",
      "def new(repo, opts \\\\ []) do",
      "  Selecto.configure(domain(), repo, opts)",
      "end",
      "",
      "@doc \"Create a Selecto instance using Ecto integration.\"",
      "def from_ecto(repo, opts \\\\ []) do",
      "  Selecto.from_ecto(repo, #{inspect(schema_module)}, opts)",
      "end",
      "",
      "@doc \"Get the schema module this domain represents.\"",
      "def schema_module, do: #{inspect(schema_module)}",
      "",
      "@doc \"Get available fields (derived from columns to avoid duplication).\"",
      "def available_fields do",
      "  domain().source.columns |> Map.keys()",
      "end",
      "",
      "@doc \"Common query: get all records with default selection.\"",
      "def all(repo, opts \\\\ []) do",
      "  new(repo, opts)",
      "  |> Selecto.select(domain().default_selected)",
      "  |> Selecto.execute()",
      "end",
      "",
      "@doc \"Common query: find by primary key.\"",
      "def find(repo, id, opts \\\\ []) do",
      "  primary_key = domain().source.primary_key",
      "  ",
      "  new(repo, opts)",
      "  |> Selecto.select(domain().default_selected)",
      "  |> Selecto.filter({to_string(primary_key), id})",
      "  |> Selecto.execute_one()",
      "end"
    ]
    |> Enum.join("\n    ")
    |> Kernel.<>("#{suggested_queries}")
  end

  defp generate_suggested_queries(config) do
    # Generate some suggested query functions based on the schema
    filters = config[:suggested_defaults][:default_filters] || %{}
    
    filter_queries = 
      filters
      |> Enum.take(2)  # Limit to avoid too many generated functions
      |> Enum.map(fn {filter_name, _filter_config} ->
        function_name = filter_name |> String.replace(" ", "_") |> String.downcase()
        
        [
          "",
          "@doc \"Common query: filter by #{filter_name}.\"",
          "def by_#{function_name}(repo, value, opts \\\\ []) do",
          "  new(repo, opts)",
          "  |> Selecto.select(domain().default_selected)",
          "  |> Selecto.filter({\"#{filter_name}\", value})",
          "  |> Selecto.execute()",
          "end"
        ]
        |> Enum.join("\n    ")
      end)
      |> Enum.join("")
    
    filter_queries
  end

  defp humanize_name(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp detect_app_name do
    # Try to detect the app name from the current Mix project
    case Mix.Project.get() do
      nil -> nil
      project -> 
        app_name = project.project()[:app]
        if app_name do
          app_name
          |> to_string()
          |> Macro.camelize()
        else
          nil
        end
    end
  end
end