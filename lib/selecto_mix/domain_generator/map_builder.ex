defmodule SelectoMix.DomainGenerator.MapBuilder do
  @moduledoc false

  alias SelectoMix.DomainGenerator.{FileTemplate, SchemaExpansion}

  @doc """
  Generate the core domain configuration map.
  """
  def generate_domain_map(config) do
    generated_from = FileTemplate.generated_from_label(config)

    "%{\n      # Generated from: #{generated_from}\n" <>
      "      # Canonical Selecto domain schema version\n" <>
      "      schema_version: 1,\n      \n" <>
      "      # Authored domain version; update when this domain contract changes meaning\n" <>
      "      domain_version: \"0.1.0\",\n      \n" <>
      "      # Optional content fingerprint; populate from a stable artifact hash when available\n" <>
      "      # domain_fingerprint: \"sha256:...\",\n      \n" <>
      "      source: #{generate_source_config(config)},\n" <>
      "      schemas: #{generate_schemas_config(config)},\n" <>
      "      name: #{generate_domain_name(config)},\n      \n" <>
      "      # Default selections (customize as needed)\n" <>
      "      default_selected: #{generate_default_selected(config)},\n      \n" <>
      "      # Suggested filters (add/remove as needed)\n" <>
      "      filters: #{generate_filters_config(config)},\n      \n" <>
      "      # Named UDF registry (prefer overlay deffunction for custom additions)\n" <>
      "      functions: #{generate_functions_config(config)},\n      \n" <>
      "      # Subfilters for relationship-based filtering (Selecto 0.3.0+)\n" <>
      "      subfilters: #{generate_subfilters_config(config)},\n" <>
      "      \n" <>
      "      # Window functions configuration (Selecto 0.3.0+)\n" <>
      "      window_functions: #{generate_window_functions_config(config)},\n" <>
      "      \n" <>
      "      # Query pagination settings\n" <>
      "      pagination: #{generate_pagination_config(config)},\n" <>
      "      \n" <>
      "      # Retarget table configuration (Selecto 0.3.0+)\n" <>
      "      retarget: #{generate_retarget_config(config)},\n      \n" <>
      "      # Join configurations\n" <>
      "      joins: #{generate_joins_config(config)}\n    }"
  end

  # Private generation functions

  defp generate_source_config(config) do
    primary_key = config[:primary_key] || :id

    table_name =
      config[:table_name] ||
        raise(ArgumentError, "domain config is missing :table_name")

    fields = config[:fields] || []
    redacted_fields = config[:redacted_fields] || []
    field_types = config[:field_types] || %{}
    polymorphic_config = config[:polymorphic_config]
    source_kind = config[:source_kind]
    readonly = config[:readonly]

    # Only include redact_fields if there are redacted fields, otherwise use empty list
    redacted_config =
      if redacted_fields != [] do
        "        # Fields to exclude from queries\n" <>
          "        redact_fields: #{inspect(redacted_fields)},\n        \n"
      else
        "        # Fields to exclude from queries\n" <>
          "        redact_fields: [],\n        \n"
      end

    "%{\n        source_table: \"#{table_name}\",\n" <>
      "        primary_key: #{inspect(primary_key)},\n" <>
      generate_relation_metadata(source_kind, readonly) <>
      "        \n" <>
      "        # Available fields from schema\n" <>
      "        # NOTE: This is redundant with columns - consider using Map.keys(columns) instead\n" <>
      "        fields: #{inspect(fields)},\n        \n" <>
      redacted_config <>
      "        # Field type definitions (contains the same info as fields above)\n" <>
      "        columns: #{generate_columns_config(fields, field_types, polymorphic_config)},\n        \n" <>
      "        # Schema associations\n" <>
      "        associations: #{generate_source_associations(config)}\n      }"
  end

  defp generate_relation_metadata(nil, nil), do: ""

  defp generate_relation_metadata(source_kind, readonly) do
    []
    |> maybe_relation_metadata_line(:source_kind, source_kind)
    |> maybe_relation_metadata_line(:readonly, readonly)
    |> Enum.join("")
  end

  defp maybe_relation_metadata_line(lines, _key, nil), do: lines

  defp maybe_relation_metadata_line(lines, key, value) do
    lines ++ ["        #{key}: #{inspect(value)},\n"]
  end

  defp generate_columns_config(fields, field_types, polymorphic_config \\ nil) do
    # Detect polymorphic associations (auto-detect OR use provided config)
    polymorphic_assocs =
      if polymorphic_config do
        # Use provided config from --expand-polymorphic
        [polymorphic_config]
      else
        # Auto-detect from field patterns
        SchemaExpansion.detect_polymorphic_associations(fields, field_types)
      end

    columns_map =
      Enum.into(fields, %{}, fn field ->
        type = Map.get(field_types, field, :string)
        base_config = %{type: type}

        # For JSONB columns, add a placeholder schema that can be customized in the overlay
        config =
          if type == :jsonb do
            Map.put(base_config, :schema, :stub)
          else
            base_config
          end

        {field, config}
      end)

    # Add polymorphic virtual column for each detected polymorphic association
    polymorphic_columns =
      Enum.into(polymorphic_assocs, %{}, fn assoc ->
        # Handle both auto-detected format and CLI-provided format
        {virtual_field, type_field, id_field, entity_types, display_name} =
          case assoc do
            # CLI-provided format from --expand-polymorphic
            %{field_name: field_name, type_field: tf, id_field: idf, entity_types: types} ->
              {SelectoMix.Identifier.to_atom!(field_name), tf, idf, types,
               String.capitalize(field_name)}

            # Auto-detected format
            %{base_name: base, type_field: tf, id_field: idf, suggested_types: types} ->
              {SelectoMix.Identifier.to_atom!(base), to_string(tf), to_string(idf), types,
               String.capitalize(base)}
          end

        {virtual_field,
         %{
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
      |> sorted_pairs()
      |> Enum.map(fn {field, type_map} ->
        "          #{inspect(field)} => #{inspect(type_map)}"
      end)
      |> Enum.join(",\n")

    "%{\n#{formatted_columns}\n        }"
  end

  # Generate columns config with special join mode handling
  defp generate_columns_config_with_mode(
         fields,
         field_types,
         join_mode,
         primary_key,
         assoc_config
       ) do
    case join_mode do
      {mode_type, display_field} when mode_type in [:tag, :star, :lookup] ->
        display_field_atom = SelectoMix.Identifier.to_atom!(display_field)

        # Start with ALL fields to satisfy validator
        columns_map =
          Enum.into(fields, %{}, fn field ->
            type = Map.get(field_types, field, :string)
            {field, %{type: type}}
          end)

        # Extract the foreign key field from association config
        # This allows filtering on the local foreign key instead of joining
        foreign_key_field =
          case assoc_config do
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

        # Add group_by_filter when the association has a local foreign key.
        # Many-to-many tag associations use owner_key for the source row id,
        # so tag display fields should fall back to their qualified tag id.
        metadata =
          if foreign_key_field && mode_type != :tag do
            Map.put(metadata, :group_by_filter, foreign_key_field)
          else
            metadata
          end

        # Enhance the display field with special metadata
        columns_map =
          Map.update!(columns_map, display_field_atom, fn col ->
            Map.merge(col, metadata)
          end)

        # Mark ID field as hidden if it's not the display field
        columns_map =
          if display_field_atom != primary_key && Map.has_key?(columns_map, primary_key) do
            Map.update!(columns_map, primary_key, fn col ->
              Map.put(col, :hidden, true)
            end)
          else
            columns_map
          end

        # Format with nice indentation and helpful comments
        formatted_columns =
          columns_map
          |> sorted_pairs()
          |> Enum.map(fn {field, config_map} ->
            comment =
              case {field == display_field_atom, mode_type} do
                {true, :tag} -> "# tag mode: displays #{display_field}, filters by tag ID"
                {true, mode} -> "# #{mode} mode: displays #{display_field}, filters by ID"
                _ -> ""
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
        |> sorted_pairs()
        |> Enum.map(fn {assoc_name, assoc_config} ->
          format_association_config(assoc_name, assoc_config)
        end)
        |> Enum.join(",\n        ")

      "%{\n        #{formatted_assocs}\n        }"
    end
  end

  # Format a single association configuration for source.associations
  defp format_association_config(assoc_name, assoc_config) do
    assoc_name_key = assoc_name |> inspect()

    # Check if this is a through association
    if assoc_config[:is_through] do
      format_through_association(assoc_name_key, assoc_name, assoc_config)
    else
      format_standard_association(assoc_name_key, assoc_name, assoc_config)
    end
  end

  # Format a standard (non-through) association
  defp format_standard_association(assoc_name_key, assoc_name, assoc_config) do
    queryable_name = get_queryable_name(assoc_config) |> inspect()
    owner_key = assoc_config[:owner_key] |> inspect()
    related_key = assoc_config[:related_key] |> inspect()

    # Check for many-to-many with join_through
    if assoc_config[:join_through] do
      join_through = assoc_config[:join_through] |> inspect()

      join_keys_line =
        case assoc_config[:join_keys] do
          join_keys when is_list(join_keys) and join_keys != [] ->
            "              join_keys: #{inspect(join_keys)}\n"

          _ ->
            ""
        end

      "#{assoc_name_key} => %{\n" <>
        "              queryable: #{queryable_name},\n" <>
        "              field: #{inspect(assoc_name)},\n" <>
        "              owner_key: #{owner_key},\n" <>
        "              related_key: #{related_key},\n" <>
        "              join_through: #{join_through},\n" <>
        join_keys_line <>
        "            }"
    else
      "#{assoc_name_key} => %{\n" <>
        "              queryable: #{queryable_name},\n" <>
        "              field: #{inspect(assoc_name)},\n" <>
        "              owner_key: #{owner_key},\n" <>
        "              related_key: #{related_key}\n" <>
        "            }"
    end
  end

  # Format a through association - includes the through path for selecto to expand
  defp format_through_association(assoc_name_key, assoc_name, assoc_config) do
    queryable_name = get_queryable_name(assoc_config) |> inspect()

    # Get the through path - this tells selecto how to traverse the associations
    through_path =
      case assoc_config[:through_path] do
        path when is_list(path) -> inspect(path)
        _ -> "[]"
      end

    "#{assoc_name_key} => %{\n" <>
      "              queryable: #{queryable_name},\n" <>
      "              field: #{inspect(assoc_name)},\n" <>
      "              through: #{through_path}\n" <>
      "            }"
  end

  defp get_queryable_name(assoc_config) do
    case assoc_config[:related_schema] do
      nil ->
        :unknown

      schema when is_atom(schema) ->
        schema
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> SelectoMix.Identifier.to_atom!()

      other ->
        other
    end
  end

  defp generate_schemas_config(config) do
    associations = config[:associations] || %{}
    expand_schemas_list = config[:expand_schemas_list] || []
    expand_modes = config[:expand_modes] || %{}
    expanded_schemas = config[:expanded_schemas] || %{}

    {schema_order, schema_candidates} =
      associations
      |> sorted_pairs()
      |> Enum.reduce({[], %{}}, fn {assoc_name, assoc_config}, {order, candidates} ->
        candidate =
          build_schema_config_candidate(
            assoc_name,
            assoc_config,
            expanded_schemas,
            expand_schemas_list,
            expand_modes
          )

        schema_name = candidate.schema_name

        case Map.get(candidates, schema_name) do
          nil ->
            {[schema_name | order], Map.put(candidates, schema_name, candidate)}

          existing_candidate ->
            {order,
             Map.put(
               candidates,
               schema_name,
               preferred_schema_candidate(existing_candidate, candidate)
             )}
        end
      end)

    schema_configs =
      schema_order
      |> Enum.reverse()
      |> Enum.map(&Map.fetch!(schema_candidates, &1).content)
      |> Enum.join(",\n      ")

    if schema_configs == "" do
      "%{}"
    else
      "%{\n      #{schema_configs}\n    }"
    end
  end

  defp build_schema_config_candidate(
         assoc_name,
         assoc_config,
         expanded_schemas,
         expand_schemas_list,
         expand_modes
       ) do
    related_schema = association_related_schema(assoc_config)
    schema_name = association_schema_key(assoc_name, assoc_config)
    table_name = association_related_table(assoc_config, schema_name)
    related_schema_string = inspect(related_schema)

    expanded_schema =
      Map.get(expanded_schemas, schema_name) || Map.get(expanded_schemas, assoc_name)

    should_expand = should_expand_schema?(schema_name, related_schema, expand_schemas_list)
    join_mode = get_join_mode_for_schema(schema_name, expand_modes)

    {priority, content} =
      cond do
        is_map(expanded_schema) ->
          {2,
           generate_preexpanded_schema_config(
             schema_name,
             expanded_schema,
             join_mode,
             assoc_config
           )}

        should_expand ->
          {1,
           generate_expanded_schema_config(
             schema_name,
             related_schema,
             table_name,
             join_mode,
             assoc_config
           )}

        true ->
          {0, generate_placeholder_schema_config(schema_name, related_schema_string, table_name)}
      end

    %{schema_name: schema_name, priority: priority, content: content}
  end

  defp preferred_schema_candidate(existing_candidate, candidate) do
    if candidate.priority > existing_candidate.priority, do: candidate, else: existing_candidate
  end

  defp should_expand_schema?(schema_name, related_schema, expand_schemas_list) do
    schema_name_str = to_string(schema_name)
    related_schema_str = to_string(related_schema)

    result =
      Enum.any?(expand_schemas_list || [], fn expand_name ->
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

  defp generate_preexpanded_schema_config(schema_name, expanded_schema, join_mode, assoc_config) do
    fields = expanded_schema[:fields] || []
    field_types = expanded_schema[:field_types] || expanded_schema[:columns] || %{}
    primary_key = expanded_schema[:primary_key] || :id
    associations = expanded_schema[:associations] || %{}

    table_name =
      expanded_schema[:source_table] || expanded_schema[:table_name] || to_string(schema_name)

    columns_config =
      generate_columns_config_with_mode(fields, field_types, join_mode, primary_key, assoc_config)

    associations_config = generate_nested_associations_config(associations)

    mode_comment =
      case join_mode do
        {:tag, _} -> "            # Join mode: tag (many-to-many with ID-based filtering)\n"
        {:star, _} -> "            # Join mode: star (lookup table with ID-based filtering)\n"
        {:lookup, _} -> "            # Join mode: lookup (small reference table)\n"
        _ -> ""
      end

    schema_name_key = inspect(schema_name)

    "#{schema_name_key} => %{\n" <>
      "            # Expanded schema configuration for #{table_name}\n" <>
      mode_comment <>
      "            source_table: \"#{table_name}\",\n" <>
      "            primary_key: #{inspect(primary_key)},\n" <>
      "            fields: #{inspect(fields)},\n" <>
      "            redact_fields: [],\n" <>
      "            columns: #{columns_config},\n" <>
      "            associations: #{associations_config}\n" <>
      "          }"
  end

  # Get join mode configuration for a schema if specified
  # Returns {mode, display_field} tuple or nil
  defp get_join_mode_for_schema(schema_name, expand_modes) do
    schema_name_str = to_string(schema_name)
    schema_name_lower = String.downcase(schema_name_str)

    # Try multiple matching strategies
    expand_modes
    |> sorted_pairs()
    |> Enum.find_value(fn {key, value} ->
      key_lower = String.downcase(key)

      cond do
        # Exact match (case-insensitive)
        key_lower == schema_name_lower ->
          value

        # Plural form match (Tags matches Tag, Categories matches Category)
        key_lower == schema_name_lower <> "s" ->
          value

        key_lower <> "s" == schema_name_lower ->
          value

        # Remove common plural suffixes for matching
        String.ends_with?(key_lower, "ies") &&
            String.replace_suffix(key_lower, "ies", "y") == schema_name_lower ->
          value

        String.ends_with?(schema_name_lower, "ies") &&
            String.replace_suffix(schema_name_lower, "ies", "y") == key_lower ->
          value

        # Partial match (if key contains schema name or vice versa)
        String.contains?(key_lower, schema_name_lower) &&
            String.length(key_lower) < String.length(schema_name_lower) + 3 ->
          value

        String.contains?(schema_name_lower, key_lower) &&
            String.length(schema_name_lower) < String.length(key_lower) + 3 ->
          value

        true ->
          nil
      end
    end)
  end

  defp generate_placeholder_schema_config(schema_name, related_schema_string, table_name) do
    schema_name_key = schema_name |> inspect()

    "#{schema_name_key} => %{\n" <>
      "            # Placeholder for #{related_schema_string}; run\n" <>
      "            # mix selecto.gen.domain #{related_schema_string}\n" <>
      "            # or add --expand-schemas #{schema_name} to expand this schema automatically\n" <>
      "            source_table: \"#{table_name}\",\n" <>
      "            primary_key: :id,\n" <>
      "            fields: [],\n" <>
      "            redact_fields: [],\n" <>
      "            columns: %{},\n" <>
      "            associations: %{}\n" <>
      "          }"
  end

  defp generate_expanded_schema_config(
         schema_name,
         related_schema,
         table_name,
         join_mode,
         assoc_config
       ) do
    # Attempt to introspect the related schema
    case SchemaExpansion.introspect_related_schema(related_schema) do
      {:ok, schema_config} ->
        fields = schema_config[:fields] || []
        field_types = schema_config[:field_types] || %{}
        primary_key = schema_config[:primary_key] || :id
        associations = schema_config[:associations] || %{}

        # Generate columns config with join mode awareness
        columns_config =
          generate_columns_config_with_mode(
            fields,
            field_types,
            join_mode,
            primary_key,
            assoc_config
          )

        associations_config = generate_nested_associations_config(associations)

        # Add join mode metadata if present
        mode_comment =
          case join_mode do
            {:tag, _} -> "            # Join mode: tag (many-to-many with ID-based filtering)\n"
            {:star, _} -> "            # Join mode: star (lookup table with ID-based filtering)\n"
            {:lookup, _} -> "            # Join mode: lookup (small reference table)\n"
            _ -> ""
          end

        # Use proper atom syntax for map key
        # KEY FIX
        schema_name_key = schema_name |> inspect()

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

  defp generate_nested_associations_config(associations) do
    if Enum.empty?(associations) do
      "%{}"
    else
      formatted_assocs =
        associations
        |> sorted_pairs()
        |> Enum.map(fn {assoc_name, assoc_config} ->
          # Ensure all values are properly inspected for valid Elixir syntax
          queryable_name = assoc_config[:queryable] |> inspect()
          owner_key = assoc_config[:owner_key] |> inspect()
          related_key = assoc_config[:related_key] |> inspect()
          # Use proper atom syntax for map key
          assoc_name_key = assoc_name |> inspect()

          "#{assoc_name_key} => %{\n" <>
            "                queryable: #{queryable_name},\n" <>
            "                field: #{inspect(assoc_name)},\n" <>
            "                owner_key: #{owner_key},\n" <>
            "                related_key: #{related_key}\n" <>
            "              }"
        end)
        |> Enum.join(",\n          ")

      "%{\n          #{formatted_assocs}\n        }"
    end
  end

  defp generate_domain_name(config) do
    base_name = config[:metadata][:module_name] || "Unknown"
    inspect("#{base_name} Domain")
  end

  defp generate_default_selected(config) do
    defaults = config[:suggested_defaults][:default_selected] || []

    formatted_defaults = defaults |> Enum.map(&inspect(to_string(&1))) |> Enum.join(", ")

    case defaults do
      [] -> "[]"
      _ -> "[#{formatted_defaults}]"
    end
  end

  defp generate_filters_config(config) do
    filters = config[:suggested_defaults][:default_filters] || %{}

    if Enum.empty?(filters) do
      "%{}"
    else
      formatted_filters =
        filters
        |> sorted_pairs()
        |> Enum.map(fn {filter_name, filter_config} ->
          formatted_config = format_filter_config(filter_config)

          "\"#{filter_name}\" => #{formatted_config}"
        end)
        |> Enum.join(",\n      ")

      "%{\n      #{formatted_filters}\n    }"
    end
  end

  defp generate_functions_config(config) do
    functions = config[:functions] || %{}

    if is_map(functions) and map_size(functions) > 0 do
      inspect(functions, pretty: true, width: 60)
    else
      "%{}"
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
    all_joins =
      Map.merge(
        generate_association_joins(associations, config[:table_name] || "main"),
        parameterized_joins
      )

    if Enum.empty?(all_joins) do
      "%{}"
    else
      formatted_joins =
        all_joins
        |> sorted_pairs()
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

  defp generate_retarget_config(_config) do
    "%{}"
  end

  # Helper functions for join generation

  defp generate_association_joins(associations, main_table) do
    # Include through associations - selecto now handles them properly
    associations
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

      # Add through association configuration
      join_config =
        if assoc_config[:is_through] do
          Map.merge(join_config, %{
            is_through: true,
            through_path: assoc_config[:through_path] || []
          })
        else
          join_config
        end

      # Add many-to-many specific configuration
      join_config =
        if assoc_config[:association_type] == :many_to_many do
          {main_foreign_key, tag_foreign_key} =
            infer_many_to_many_foreign_keys(assoc_config, main_table)

          Map.merge(join_config, %{
            join_table: assoc_config[:join_through],
            join_through: assoc_config[:join_through],
            join_keys: assoc_config[:join_keys] || [],
            main_foreign_key: main_foreign_key,
            tag_foreign_key: tag_foreign_key,
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
    [
      %{
        left: to_string(owner_key),
        right: to_string(related_key)
      }
    ]
  end

  defp format_single_join(join_name, join_config) do
    is_non_assoc = Map.get(join_config, :non_assoc, false)
    is_parameterized = Map.has_key?(join_config, :parameters)
    is_many_to_many = Map.has_key?(join_config, :join_through)
    is_through = Map.get(join_config, :is_through, false)

    join_type = inspect(Map.get(join_config, :type, :left))
    join_name_str = Map.get(join_config, :name, humanize_name(join_name))

    base_config =
      "#{inspect(join_name)} => %{\n" <>
        "              name: \"#{join_name_str}\",\n" <>
        "              type: #{join_type}"

    # Add non_assoc flag for custom joins without Ecto associations
    non_assoc_config =
      if is_non_assoc do
        owner_key = Map.get(join_config, :owner_key, :id)
        related_key = Map.get(join_config, :related_key, :id)
        source_table = Map.get(join_config, :source, to_string(join_name))

        config =
          ",\n              non_assoc: true,\n" <>
            "              source: #{inspect(source_table)},\n" <>
            "              owner_key: #{inspect(owner_key)},\n" <>
            "              related_key: #{inspect(related_key)}"

        # Add optional fields configuration for non-assoc joins
        config =
          if fields = Map.get(join_config, :fields) do
            fields_config = format_join_fields_config(fields)
            config <> ",\n              fields: #{fields_config}"
          else
            config
          end

        # Add optional filters configuration for non-assoc joins
        if filters = Map.get(join_config, :filters) do
          config <> ",\n              filters: #{inspect(filters)}"
        else
          config
        end
      else
        ""
      end

    # Add source and on clause (required for association-based joins, skip for non_assoc)
    source_config =
      if !is_non_assoc do
        case Map.get(join_config, :source) do
          nil ->
            ""

          source_val ->
            on_clause = Map.get(join_config, :on, [])

            ",\n              source: #{inspect(source_val)},\n" <>
              "              on: #{inspect(on_clause)}"
        end
      else
        ""
      end

    # Add many-to-many specific configuration
    many_to_many_config =
      if is_many_to_many do
        join_table = Map.get(join_config, :join_table)
        join_through = Map.get(join_config, :join_through)
        join_keys = Map.get(join_config, :join_keys, [])
        main_foreign_key = Map.get(join_config, :main_foreign_key)
        tag_foreign_key = Map.get(join_config, :tag_foreign_key)
        owner_key = Map.get(join_config, :owner_key, :id)
        assoc_key = Map.get(join_config, :assoc_key, :id)

        ",\n              join_table: #{inspect(join_table)},\n" <>
          "              join_through: #{inspect(join_through)},\n" <>
          "              join_keys: #{inspect(join_keys)},\n" <>
          "              main_foreign_key: #{inspect(main_foreign_key)},\n" <>
          "              tag_foreign_key: #{inspect(tag_foreign_key)},\n" <>
          "              owner_key: #{inspect(owner_key)},\n" <>
          "              assoc_key: #{inspect(assoc_key)}"
      else
        ""
      end

    # Add through association specific configuration
    through_config =
      if is_through do
        through_path = Map.get(join_config, :through_path, [])
        ",\n              through: #{inspect(through_path)}"
      else
        ""
      end

    # Add parameterized join specific configurations
    parameterized_config =
      if is_parameterized do
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

    join_condition_config =
      case Map.get(join_config, :join_condition) do
        nil -> ""
        condition -> ",\n              join_condition: #{inspect(condition)}"
      end

    base_config <>
      non_assoc_config <>
      source_config <>
      many_to_many_config <>
      through_config <> parameterized_config <> join_condition_config <> "\n            }"
  end

  defp format_parameters_config(parameters) when is_list(parameters) do
    if Enum.empty?(parameters) do
      "[]"
    else
      formatted_params =
        parameters
        |> Enum.map(fn param ->
          param_config =
            param
            |> ordered_take([:name, :type, :required, :default, :description])
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
        |> sorted_pairs()
        |> Enum.map(fn {field_name, field_config} ->
          config_str =
            case field_config do
              %{} ->
                config_pairs =
                  field_config
                  |> sorted_pairs()
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

  def sorted_pairs(map_or_keyword) do
    map_or_keyword
    |> Enum.sort_by(fn {key, _value} -> {to_string(key), inspect(key)} end)
  end

  defp ordered_take(map, keys) when is_map(map) do
    keys
    |> Enum.filter(&Map.has_key?(map, &1))
    |> Enum.map(&{&1, Map.fetch!(map, &1)})
  end

  defp humanize_name(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp infer_many_to_many_foreign_keys(assoc_config, main_table) do
    case assoc_config[:join_keys] do
      [{main_key, _}, {tag_key, _} | _rest] ->
        {to_string(main_key), to_string(tag_key)}

      [main_key, tag_key | _rest] when is_atom(main_key) and is_atom(tag_key) ->
        {to_string(main_key), to_string(tag_key)}

      [main_key, tag_key | _rest] when is_binary(main_key) and is_binary(tag_key) ->
        {main_key, tag_key}

      _ ->
        {
          infer_main_foreign_key_from_main_table(main_table),
          infer_tag_foreign_key_from_assoc(assoc_config)
        }
    end
  end

  defp infer_main_foreign_key_from_main_table(main_table) do
    main_table
    |> to_string()
    |> String.trim_trailing("s")
    |> Kernel.<>("_id")
  end

  defp infer_tag_foreign_key_from_assoc(assoc_config) do
    assoc_config
    |> Map.get(:related_schema, :tag)
    |> SchemaExpansion.get_schema_name_from_module()
    |> to_string()
    |> String.trim_trailing("s")
    |> Kernel.<>("_id")
  end

  defp association_related_schema(assoc_config) do
    assoc_config[:related_schema] || assoc_config[:related_module_name] ||
      assoc_config[:related_table]
  end

  defp association_schema_key(assoc_name, assoc_config) do
    cond do
      module_name = assoc_config[:related_module_name] ->
        module_name
        |> to_string()
        |> Macro.underscore()
        |> SelectoMix.Identifier.to_atom!()

      related_schema = assoc_config[:related_schema] ->
        SchemaExpansion.get_schema_name_from_module(related_schema)

      related_table = assoc_config[:related_table] ->
        related_table
        |> SelectoMix.Inflect.singularize()
        |> SelectoMix.Identifier.to_atom!()

      true ->
        assoc_name
    end
  end

  defp association_related_table(assoc_config, schema_name) do
    assoc_config[:related_table] || assoc_config[:queryable] ||
      SchemaExpansion.guess_table_name(schema_name)
  end
end
