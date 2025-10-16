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
  def generate_domain_file(schema_module, config, opts \\ []) do
    module_name = get_domain_module_name(schema_module, config)
    saved_views_use = generate_saved_views_use(opts)

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
      - Adding parameterized joins with dynamic parameters
      - Configuring subfilters for relationship-based filtering (Selecto 0.3.0+)
      - Setting up window functions for advanced analytics (Selecto 0.3.0+)
      - Defining pivot table configurations (Selecto 0.3.0+)
      - Customizing pagination settings with LIMIT/OFFSET support
      - Adding custom domain metadata
      
      Fields, filters, and joins marked with "# CUSTOM" comments will be
      preserved when this file is regenerated.
      
      ## Parameterized Joins
      
      This domain supports parameterized joins that accept runtime parameters:
      
      ```elixir
      joins: %{
        products: %{
          type: :left,
          name: "Products",
          parameters: [
            %{name: :category, type: :string, required: true},
            %{name: :active, type: :boolean, required: false, default: true}
          ],
          fields: %{
            name: %{type: :string},
            price: %{type: :decimal}
          }
        }
      }
      ```
      
      Use dot notation to reference parameterized fields:
      - `products:electronics.name` - Products in electronics category
      - `products:electronics:true.price` - Active products in electronics
      
      ## Regeneration
      
      To regenerate this file after schema changes:
      
          mix selecto.gen.domain #{inspect(schema_module)}
          
      Additional options:
      
          # Force regenerate (overwrites customizations)
          mix selecto.gen.domain #{inspect(schema_module)} --force
          
          # Preview changes without writing files
          mix selecto.gen.domain #{inspect(schema_module)} --dry-run
          
          # Include associations as joins
          mix selecto.gen.domain #{inspect(schema_module)} --include-associations
          
          # Generate with LiveView files
          mix selecto.gen.domain #{inspect(schema_module)} --live
          
          # Generate with saved views support
          mix selecto.gen.domain #{inspect(schema_module)} --live --saved-views
          
          # Expand specific associated schemas with full columns/associations
          mix selecto.gen.domain #{inspect(schema_module)} --expand-schemas categories,tags
          
      Your customizations will be preserved during regeneration (unless --force is used).
      \"\"\"
#{saved_views_use}
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
    "      # Subfilters for relationship-based filtering (Selecto 0.3.0+)\n" <>
    "      subfilters: #{generate_subfilters_config(config)},\n" <>
    "      \n" <>
    "      # Window functions configuration (Selecto 0.3.0+)\n" <>
    "      window_functions: #{generate_window_functions_config(config)},\n" <>
    "      \n" <>
    "      # Query pagination settings\n" <>
    "      pagination: #{generate_pagination_config(config)},\n" <>
    "      \n" <>
    "      # Pivot table configuration (Selecto 0.3.0+)\n" <>
    "      pivot: #{generate_pivot_config(config)},\n      \n" <>
    "      # Join configurations\n" <>
    "      joins: #{generate_joins_config(config)}#{custom_metadata}\n    }"
  end

  # Private generation functions

  defp get_domain_module_name(schema_module, config) do
    base_name = config[:metadata][:module_name] ||
                Module.split(schema_module) |> List.last()

    _context_name = config[:metadata][:context_name] || "Domains"

    # Generate appropriate module name - use schema module as source of truth
    app_name = Application.get_env(:selecto_mix, :app_name) ||
               infer_app_name_from_schema(schema_module) ||  # KEY FIX: Use schema module
               "MyApp"
    "#{app_name}.SelectoDomains.#{base_name}Domain"
  end

  defp generate_source_config(config) do
    primary_key = config[:primary_key] || :id
    table_name = config[:table_name] || "unknown_table"
    fields = config[:fields] || []
    redacted_fields = config[:redacted_fields] || []
    field_types = config[:field_types] || %{}
    polymorphic_config = config[:polymorphic_config]
    
    redacted_line = if redacted_fields != [], do: "\n        redact_fields: #{inspect(redacted_fields)},", else: ""
    
    "%{\n        source_table: \"#{table_name}\",\n" <>
    "        primary_key: #{inspect(primary_key)},\n        \n" <>
    "        # Available fields from schema\n" <>
    "        # NOTE: This is redundant with columns - consider using Map.keys(columns) instead\n" <>
    "        fields: #{inspect(fields)},\n        \n" <>
    "        # Fields to exclude from queries#{redacted_line}\n" <>
    "        redact_fields: [],\n        \n" <>
    "        # Field type definitions (contains the same info as fields above)\n" <>
    "        columns: #{generate_columns_config(fields, field_types, polymorphic_config)},\n        \n" <>
    "        # Schema associations\n" <>
    "        associations: #{generate_source_associations(config)}\n      }"
  end

  defp generate_columns_config(fields, field_types, polymorphic_config \\ nil) do
    # Detect polymorphic associations (auto-detect OR use provided config)
    polymorphic_assocs = if polymorphic_config do
      # Use provided config from --expand-polymorphic
      [polymorphic_config]
    else
      # Auto-detect from field patterns
      detect_polymorphic_associations(fields, field_types)
    end

    columns_map = Enum.into(fields, %{}, fn field ->
      type = Map.get(field_types, field, :string)
      {field, %{type: type}}
    end)

    # Add polymorphic virtual column for each detected polymorphic association
    polymorphic_columns = Enum.into(polymorphic_assocs, %{}, fn assoc ->
      # Handle both auto-detected format and CLI-provided format
      {virtual_field, type_field, id_field, entity_types, display_name} = case assoc do
        # CLI-provided format from --expand-polymorphic
        %{field_name: field_name, type_field: tf, id_field: idf, entity_types: types} ->
          {String.to_atom(field_name), tf, idf, types, String.capitalize(field_name)}

        # Auto-detected format
        %{base_name: base, type_field: tf, id_field: idf, suggested_types: types} ->
          {String.to_atom(base), to_string(tf), to_string(idf), types, String.capitalize(base)}
      end

      {virtual_field, %{
        type: :string,
        join_mode: :polymorphic,
        filter_type: :polymorphic,
        type_field: type_field,
        id_field: id_field,
        entity_types: entity_types,
        display_name: display_name
      }}
    end)

    # Merge regular columns with polymorphic virtual columns
    all_columns = Map.merge(columns_map, polymorphic_columns)

    # Format the map with nice indentation
    formatted_columns =
      all_columns
      |> Enum.map(fn {field, type_map} ->
        "          #{inspect(field)} => #{inspect(type_map)}"
      end)
      |> Enum.join(",\n")

    "%{\n#{formatted_columns}\n        }"
  end

  # Generate columns config with special join mode handling
  defp generate_columns_config_with_mode(fields, field_types, join_mode, primary_key, assoc_config) do
    case join_mode do
      {mode_type, display_field} when mode_type in [:tag, :star, :lookup] ->
        display_field_atom = String.to_atom(display_field)

        # Start with ALL fields to satisfy validator
        columns_map = Enum.into(fields, %{}, fn field ->
          type = Map.get(field_types, field, :string)
          {field, %{type: type}}
        end)

        # Extract the foreign key field from association config
        # This allows filtering on the local foreign key instead of joining
        foreign_key_field = case assoc_config do
          %{owner_key: owner_key} -> Atom.to_string(owner_key)
          _ -> nil
        end

        # Build metadata map for the display field
        metadata = %{
          join_mode: mode_type,
          id_field: primary_key,
          display_field: display_field_atom,
          prevent_denormalization: true,
          filter_type: :multi_select_id
        }

        # Add group_by_filter if we have a foreign key to filter on
        metadata = if foreign_key_field do
          Map.put(metadata, :group_by_filter, foreign_key_field)
        else
          metadata
        end

        # Enhance the display field with special metadata
        columns_map = Map.update!(columns_map, display_field_atom, fn col ->
          Map.merge(col, metadata)
        end)

        # Mark ID field as hidden if it's not the display field
        columns_map = if display_field_atom != primary_key && Map.has_key?(columns_map, primary_key) do
          Map.update!(columns_map, primary_key, fn col ->
            Map.put(col, :hidden, true)
          end)
        else
          columns_map
        end

        # Format with nice indentation and helpful comments
        formatted_columns =
          columns_map
          |> Enum.map(fn {field, config_map} ->
            comment = if field == display_field_atom do
              "# #{mode_type} mode: displays name, filters by ID"
            else
              ""
            end
            comment_line = if comment != "", do: "          #{comment}\n", else: ""
            "#{comment_line}          #{inspect(field)} => #{inspect(config_map)}"
          end)
          |> Enum.join(",\n")

        "%{\n#{formatted_columns}\n        }"

      _ ->
        # No special mode, use standard column generation
        generate_columns_config(fields, field_types)
    end
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
          # Ensure all values are properly inspected for valid Elixir syntax
          queryable_name = get_queryable_name(assoc_config) |> inspect()
          owner_key = assoc_config[:owner_key] |> inspect()
          related_key = assoc_config[:related_key] |> inspect()
          assoc_name_key = assoc_name |> inspect()  # KEY FIX: Store inspected value

          "#{assoc_name_key} => %{\n" <>  # Use stored variable instead of inline inspect
          "              queryable: #{queryable_name},\n" <>
          "              field: #{assoc_name_key},\n" <>
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
    expand_schemas_list = config[:expand_schemas_list] || []
    expand_modes = config[:expand_modes] || %{}

    # Generate schema configurations for associations
    schema_configs =
      associations
      |> Enum.reject(fn {_name, assoc} -> assoc[:is_through] end)
      |> Enum.map(fn {_assoc_name, assoc_config} ->
        # Use the singular schema name, not the queryable/association name
        related_schema = assoc_config[:related_schema]
        schema_name = get_schema_name_from_module(related_schema)
        table_name = guess_table_name(related_schema)
        related_schema_string = inspect(related_schema)

        # Check if this schema should be expanded
        should_expand = should_expand_schema?(schema_name, related_schema, expand_schemas_list)

        # Check if there's a special join mode for this schema
        join_mode = get_join_mode_for_schema(schema_name, expand_modes)

        if should_expand do
          generate_expanded_schema_config(schema_name, related_schema, table_name, join_mode, assoc_config)
        else
          generate_placeholder_schema_config(schema_name, related_schema_string, table_name)
        end
      end)
      |> Enum.join(",\n      ")
    
    if schema_configs == "" do
      "%{}"
    else
      "%{\n      #{schema_configs}\n    }"
    end
  end

  defp should_expand_schema?(schema_name, related_schema, expand_schemas_list) do
    schema_name_str = to_string(schema_name)
    related_schema_str = to_string(related_schema)

    result = Enum.any?(expand_schemas_list || [], fn expand_name ->
      expand_name_lower = String.downcase(expand_name)
      schema_name_lower = String.downcase(schema_name_str)
      related_schema_lower = String.downcase(related_schema_str)

      # Match by exact schema name, or if expand_name contains schema_name, or vice versa
      expand_name_lower == schema_name_lower ||
      expand_name_lower == related_schema_lower ||
      String.contains?(expand_name_lower, schema_name_lower) ||
      String.contains?(related_schema_lower, expand_name_lower)
    end)

    result
  end

  # Get join mode configuration for a schema if specified
  # Returns {mode, display_field} tuple or nil
  defp get_join_mode_for_schema(schema_name, expand_modes) do
    schema_name_str = to_string(schema_name)
    schema_name_lower = String.downcase(schema_name_str)

    # Try multiple matching strategies
    Enum.find_value(expand_modes, fn {key, value} ->
      key_lower = String.downcase(key)

      cond do
        # Exact match (case-insensitive)
        key_lower == schema_name_lower -> value

        # Plural form match (Tags matches Tag, Categories matches Category)
        key_lower == schema_name_lower <> "s" -> value
        key_lower <> "s" == schema_name_lower -> value

        # Remove common plural suffixes for matching
        String.ends_with?(key_lower, "ies") && String.replace_suffix(key_lower, "ies", "y") == schema_name_lower -> value
        String.ends_with?(schema_name_lower, "ies") && String.replace_suffix(schema_name_lower, "ies", "y") == key_lower -> value

        # Partial match (if key contains schema name or vice versa)
        String.contains?(key_lower, schema_name_lower) && String.length(key_lower) < String.length(schema_name_lower) + 3 -> value
        String.contains?(schema_name_lower, key_lower) && String.length(schema_name_lower) < String.length(key_lower) + 3 -> value

        true -> nil
      end
    end)
  end
  
  defp generate_placeholder_schema_config(schema_name, related_schema_string, table_name) do
    # Use proper atom syntax for map key
    schema_name_key = schema_name |> inspect()  # KEY FIX

    "#{schema_name_key} => %{\n" <>
    "            # TODO: Add proper schema configuration for #{related_schema_string}\n" <>
    "            # This will be auto-generated when you run:\n" <>
    "            # mix selecto.gen.domain #{related_schema_string}\n" <>
    "            # Or use --expand-schemas #{schema_name} to expand automatically\n" <>
    "            source_table: \"#{table_name}\",\n" <>
    "            primary_key: :id,\n" <>
    "            fields: [], # Add fields for #{related_schema_string}\n" <>
    "            redact_fields: [],\n" <>
    "            columns: %{},\n" <>
    "            associations: %{}\n" <>
    "          }"
  end
  
  defp generate_expanded_schema_config(schema_name, related_schema, table_name, join_mode, assoc_config) do
    # Attempt to introspect the related schema
    case introspect_related_schema(related_schema) do
      {:ok, schema_config} ->
        fields = schema_config[:fields] || []
        field_types = schema_config[:field_types] || %{}
        primary_key = schema_config[:primary_key] || :id
        associations = schema_config[:associations] || %{}

        # Generate columns config with join mode awareness
        columns_config = generate_columns_config_with_mode(fields, field_types, join_mode, primary_key, assoc_config)
        associations_config = generate_nested_associations_config(associations)

        # Add join mode metadata if present
        mode_comment = case join_mode do
          {:tag, _} -> "            # Join mode: tag (many-to-many with ID-based filtering)\n"
          {:star, _} -> "            # Join mode: star (lookup table with ID-based filtering)\n"
          {:lookup, _} -> "            # Join mode: lookup (small reference table)\n"
          _ -> ""
        end

        # Use proper atom syntax for map key
        schema_name_key = schema_name |> inspect()  # KEY FIX

        "#{schema_name_key} => %{\n" <>
        "            # Expanded schema configuration for #{inspect(related_schema)}\n" <>
        mode_comment <>
        "            source_table: \"#{table_name}\",\n" <>
        "            primary_key: #{inspect(primary_key)},\n" <>
        "            fields: #{inspect(fields)},\n" <>
        "            redact_fields: [],\n" <>
        "            columns: #{columns_config},\n" <>
        "            associations: #{associations_config}\n" <>
        "          }"
      {:error, _reason} ->
        # Fallback to placeholder if introspection fails
        generate_placeholder_schema_config(schema_name, inspect(related_schema), table_name)
    end
  end
  
  defp introspect_related_schema(schema_module) do
    try do
      # Try to load the module and introspect it
      # Ensure the module is loaded
      case Code.ensure_loaded(schema_module) do
        {:module, _} ->
          if function_exported?(schema_module, :__schema__, 1) do
            fields = schema_module.__schema__(:fields)
            primary_key = schema_module.__schema__(:primary_key) |> List.first() || :id
            
            # Convert types to simplified format
            field_types = 
              fields
              |> Enum.into(%{}, fn field ->
                type = schema_module.__schema__(:type, field)
                simplified_type = simplify_ecto_type(type)
                {field, simplified_type}
              end)
            
            # No associations in expanded schemas to avoid circular references
            associations = %{}
            
            {:ok, %{
              fields: fields,
              field_types: field_types,
              primary_key: primary_key,
              associations: associations
            }}
          else
            {:error, :not_ecto_schema}
          end
        {:error, _reason} ->
          {:error, :module_not_loaded}
      end
    rescue
      _ -> 
        {:error, :introspection_failed}
    end
  end
  
  defp simplify_ecto_type({:parameterized, Ecto.Enum, _}), do: :string
  defp simplify_ecto_type({:array, inner_type}), do: {:array, simplify_ecto_type(inner_type)}
  defp simplify_ecto_type(:id), do: :integer
  defp simplify_ecto_type(:binary_id), do: :string
  defp simplify_ecto_type(:naive_datetime), do: :naive_datetime
  defp simplify_ecto_type(:utc_datetime), do: :utc_datetime
  defp simplify_ecto_type(type) when is_atom(type), do: type
  defp simplify_ecto_type(_), do: :string

  # Detect polymorphic associations in a schema.
  #
  # Looks for patterns like:
  # - commentable_type + commentable_id
  # - taggable_type + taggable_id
  # - attachable_type + attachable_id
  #
  # Returns a list of polymorphic associations:
  # [
  #   %{
  #     base_name: "commentable",
  #     type_field: :commentable_type,
  #     id_field: :commentable_id,
  #     suggested_types: ["Product", "Order", "Customer"]  # From seed data or manual
  #   }
  # ]
  defp detect_polymorphic_associations(fields, _field_types) do
    # Find all fields ending in _type
    type_fields = Enum.filter(fields, fn field ->
      field_str = to_string(field)
      String.ends_with?(field_str, "_type")
    end)

    # For each type field, check if corresponding _id field exists
    Enum.flat_map(type_fields, fn type_field ->
      type_field_str = to_string(type_field)
      base_name = String.replace_suffix(type_field_str, "_type", "")
      id_field = String.to_atom(base_name <> "_id")

      if id_field in fields do
        # Found a polymorphic pair!
        [%{
          base_name: base_name,
          type_field: type_field,
          id_field: id_field,
          # Default suggested types - can be overridden by --expand-polymorphic option
          suggested_types: ["Product", "Order", "Customer"]
        }]
      else
        []
      end
    end)
  end
  
  # defp discover_basic_associations(schema_module) do
  #   try do
  #     # This is a simplified version - in a full implementation, 
  #     # we would introspect associations from the schema
  #     associations = schema_module.__schema__(:associations)
  #     
  #     Enum.into(associations, %{}, fn assoc_name ->
  #       assoc = schema_module.__schema__(:association, assoc_name)
  #       
  #       {assoc_name, %{
  #         queryable: get_association_queryable(assoc),
  #         field: assoc_name,
  #         owner_key: assoc.owner_key,
  #         related_key: assoc.related_key
  #       }}
  #     end)
  #   rescue
  #     _ -> %{}
  #   end
  # end
  
  # defp get_association_queryable(assoc) do
  #   case assoc.queryable do
  #     module when is_atom(module) ->
  #       # For now, we'll just exclude associations that point back to the main schema
  #       # This is a temporary fix - a proper solution would handle self-referential associations
  #       module_name = module
  #       |> Module.split()
  #       |> List.last()
  #       |> Macro.underscore()
  #       
  #       # Return nil for associations we want to skip
  #       # The calling code should filter these out
  #       String.to_atom(module_name)
  #     other -> other
  #   end
  # end
  
  defp generate_nested_associations_config(associations) do
    if Enum.empty?(associations) do
      "%{}"
    else
      formatted_assocs =
        associations
        |> Enum.map(fn {assoc_name, assoc_config} ->
          # Ensure all values are properly inspected for valid Elixir syntax
          queryable_name = assoc_config[:queryable] |> inspect()
          owner_key = assoc_config[:owner_key] |> inspect()
          related_key = assoc_config[:related_key] |> inspect()
          assoc_name_key = assoc_name |> inspect()  # KEY FIX

          "#{assoc_name_key} => %{\n" <>
          "                queryable: #{queryable_name},\n" <>
          "                field: #{assoc_name_key},\n" <>
          "                owner_key: #{owner_key},\n" <>
          "                related_key: #{related_key}\n" <>
          "              }"
        end)
        |> Enum.join(",\n          ")

      "%{\n          #{formatted_assocs}\n        }"
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
    parameterized_joins = config[:parameterized_joins] || %{}
    
    # Combine regular associations and parameterized joins
    all_joins = Map.merge(
      generate_association_joins(associations),
      parameterized_joins
    )
    
    if Enum.empty?(all_joins) do
      "%{}"
    else
      formatted_joins = 
        all_joins
        |> Enum.map(fn {join_name, join_config} ->
          format_single_join(join_name, join_config)
        end)
        |> Enum.join(",\n      ")
      
      "%{\n      #{formatted_joins}\n    }"
    end
  end

  defp generate_subfilters_config(config) do
    # Generate subfilter examples based on associations
    associations = config[:associations] || %{}
    
    if Enum.empty?(associations) do
      "%{}"
    else
      # Generate example subfilters based on actual associations as comments
      # We'll just return an empty map for now
      "%{}"
    end
  end

  defp generate_window_functions_config(_config) do
    "%{}"
  end

  defp generate_pagination_config(_config) do
    "%{\n" <>
    "        # Default pagination settings\n" <>
    "        default_limit: 50,\n" <>
    "        max_limit: 1000,\n" <>
    "        \n" <>
    "        # Cursor-based pagination support\n" <>
    "        cursor_fields: [:id],\n" <>
    "        \n" <>
    "        # Enable/disable pagination features\n" <>
    "        allow_offset: true,\n" <>
    "        require_limit: false\n" <>
    "      }"
  end

  defp generate_pivot_config(_config) do
    "%{}"
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
      "  # Enable validation by default in development and test environments",
      "  validate = Keyword.get(opts, :validate, Mix.env() in [:dev, :test])",
      "  opts = Keyword.put(opts, :validate, validate)",
      "  ",
      "  Selecto.configure(domain(), repo, opts)",
      "end",
      "",
      "@doc \"Create a Selecto instance using Ecto integration.\"",
      "def from_ecto(repo, opts \\\\ []) do",
      "  Selecto.from_ecto(repo, #{inspect(schema_module)}, opts)",
      "end",
      "",
      "@doc \"Validate the domain configuration (Selecto 0.3.0+).\"",
      "def validate_domain! do",
      "  case Selecto.DomainValidator.validate_domain(domain()) do",
      "    :ok -> ",
      "      :ok",
      "    {:error, errors} ->",
      "      raise Selecto.DomainValidator.ValidationError, errors: errors",
      "  end",
      "end",
      "",
      "@doc \"Check if the domain configuration is valid.\"",
      "def valid_domain? do",
      "  case Selecto.DomainValidator.validate_domain(domain()) do",
      "    :ok -> true",
      "    {:error, _} -> false",
      "  end",
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

  # Helper functions for join generation
  
  defp generate_association_joins(associations) do
    associations
    |> Enum.reject(fn {_name, assoc} -> assoc[:is_through] end)
    |> Enum.into(%{}, fn {assoc_name, assoc_config} ->
      # Determine the source table/schema name
      queryable = assoc_config[:queryable] || assoc_name

      # Build complete join configuration
      join_config = %{
        name: humanize_name(assoc_name),
        type: assoc_config[:join_type] || :left,
        source: queryable,
        on: build_join_on_clause(assoc_config),
        is_custom: assoc_config[:is_custom] == true
      }

      # Add many-to-many specific configuration
      join_config = if assoc_config[:association_type] == :many_to_many do
        Map.merge(join_config, %{
          join_through: assoc_config[:join_through],
          owner_key: assoc_config[:owner_key] || :id,
          assoc_key: assoc_config[:related_key] || :id
        })
      else
        join_config
      end

      {assoc_name, join_config}
    end)
  end

  # Build the ON clause for a join based on association configuration
  defp build_join_on_clause(assoc_config) do
    owner_key = assoc_config[:owner_key] || :id
    related_key = assoc_config[:related_key] || :id

    # Convert to strings for Selecto
    [%{
      left: to_string(owner_key),
      right: to_string(related_key)
    }]
  end
  
  defp format_single_join(join_name, join_config) do
    is_custom = Map.get(join_config, :is_custom, false)
    is_parameterized = Map.has_key?(join_config, :parameters)
    is_many_to_many = Map.has_key?(join_config, :join_through)

    custom_marker = cond do
      is_custom and is_parameterized -> " # CUSTOM PARAMETERIZED JOIN"
      is_custom -> " # CUSTOM JOIN"
      is_parameterized -> " # PARAMETERIZED JOIN"
      is_many_to_many -> " # MANY-TO-MANY"
      true -> ""
    end

    join_type = inspect(Map.get(join_config, :type, :left))
    join_name_str = Map.get(join_config, :name, humanize_name(join_name))

    base_config = "#{inspect(join_name)} => %{\n" <>
                  "              name: \"#{join_name_str}\",\n" <>
                  "              type: #{join_type}"

    # Add source and on clause (required for all joins)
    source_config = if source = Map.get(join_config, :source) do
      on_clause = Map.get(join_config, :on, [])
      ",\n              source: #{inspect(source)},\n" <>
      "              on: #{inspect(on_clause)}"
    else
      ""
    end

    # Add many-to-many specific configuration
    many_to_many_config = if is_many_to_many do
      join_through = Map.get(join_config, :join_through)
      owner_key = Map.get(join_config, :owner_key, :id)
      assoc_key = Map.get(join_config, :assoc_key, :id)

      ",\n              join_through: #{inspect(join_through)},\n" <>
      "              owner_key: #{inspect(owner_key)},\n" <>
      "              assoc_key: #{inspect(assoc_key)}"
    else
      ""
    end

    # Add parameterized join specific configurations
    parameterized_config = if is_parameterized do
      parameters_config = format_parameters_config(join_config[:parameters])
      source_table = inspect(Map.get(join_config, :source_table, to_string(join_name)))
      fields_config = format_join_fields_config(Map.get(join_config, :fields, %{}))

      ",\n              \n              # Parameterized join configuration\n" <>
      "              source_table: #{source_table},\n" <>
      "              parameters: #{parameters_config},\n" <>
      "              fields: #{fields_config}"
    else
      ""
    end

    join_condition_config = case Map.get(join_config, :join_condition) do
      nil -> ""
      condition -> ",\n              join_condition: #{inspect(condition)}"
    end

    base_config <> source_config <> many_to_many_config <> parameterized_config <> join_condition_config <> "\n            }#{custom_marker}"
  end
  
  defp format_parameters_config(parameters) when is_list(parameters) do
    if Enum.empty?(parameters) do
      "[]"
    else
      formatted_params = 
        parameters
        |> Enum.map(fn param ->
          param_config = param
          |> Map.take([:name, :type, :required, :default, :description])
          |> Map.to_list()
          |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
          |> Enum.join(", ")
          
          "              %{#{param_config}}"
        end)
        |> Enum.join(",\n")
      
      "[\n#{formatted_params}\n            ]"
    end
  end
  
  defp format_parameters_config(_), do: "[]"
  
  defp format_join_fields_config(fields) when is_map(fields) do
    if Enum.empty?(fields) do
      "%{}"
    else
      formatted_fields = 
        fields
        |> Enum.map(fn {field_name, field_config} ->
          config_str = case field_config do
            %{} -> 
              config_pairs = 
                field_config
                |> Map.to_list()
                |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
                |> Enum.join(", ")
              "%{#{config_pairs}}"
            _ -> 
              inspect(field_config)
          end
          
          "              #{inspect(field_name)} => #{config_str}"
        end)
        |> Enum.join(",\n")
      
      "%{\n#{formatted_fields}\n            }"
    end
  end
  
  defp format_join_fields_config(_), do: "%{}"

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

  # New helper functions for advanced Selecto features


  # Unused - kept for future CTE support
  # defp generate_ctes_config(config) do
  #   # Generate CTE configurations
  #   if config[:generate_ctes] do
  #     "%{
  #       # Example CTEs - define reusable query expressions
  #       # recent_records: %{
  #       #   query: fn selecto ->
  #       #     selecto
  #       #     |> Selecto.filter({{\"created_at\", \">=\"}, Date.add(Date.utc_today(), -30)})
  #       #   end
  #       # }
  #     }"
  #   else
  #     ""
  #   end
  # end


  # Unused - kept for future VALUES clause support
  # defp generate_values_clauses_config(_config) do
  #   ""
  # end

  # Unused helper - kept for future use
  # defp generate_window_function_helpers(_config) do
  #   ""
  # end

  defp generate_saved_views_use(opts) do
    if opts[:saved_views] do
      app_name = opts[:app_name] || infer_app_name_from_schema(opts[:schema_module])
      saved_view_context = "#{app_name}.SavedViewContext"
      "\n      use #{saved_view_context}\n"
    else
      ""
    end
  end

  defp infer_app_name_from_schema(schema_module) when is_atom(schema_module) do
    schema_module
    |> Module.split()
    |> List.first()
  end

  defp infer_app_name_from_schema(_), do: "MyApp"

  defp get_schema_name_from_module(schema_module) when is_atom(schema_module) do
    schema_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp get_schema_name_from_module(_), do: :unknown
end