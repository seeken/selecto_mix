defmodule SelectoMix.OverlayGenerator do
  @moduledoc """
  Generates overlay configuration files for domain customization.

  Overlay files allow users to customize domain configurations without
  modifying the generated domain files, enabling safe regeneration.
  """

  @doc """
  Generates an overlay file template for a domain.

  ## Parameters

    - `module_name` - The full module name (e.g., "MyApp.SelectoDomains.ProductDomain")
    - `config` - The domain configuration map (used to extract column names, etc.)
    - `opts` - Options (currently unused, for future extensibility)

  ## Returns

  A string containing the overlay module code.
  """
  def generate_overlay_file(module_name, config, _opts \\ []) do
    overlay_module_name = overlay_module_name(module_name)
    column_examples = generate_column_examples_dsl(config)
    filter_examples = generate_filter_examples_dsl(config)
    function_examples = generate_function_examples_dsl()
    redaction_example = generate_redaction_example(config)
    jsonb_examples = generate_jsonb_schema_examples(config)
    query_member_examples = generate_query_member_examples_dsl()

    """
    defmodule #{overlay_module_name} do
      @moduledoc \"\"\"
      Overlay configuration for #{module_name}.

      This file contains user-defined customizations for the domain configuration.
      It will NOT be overwritten when you regenerate the domain file.

      ## Purpose

       Use this overlay file to:
       - Customize column display properties (labels, formats, aggregations)
       - Add redaction to sensitive fields
       - Define custom filters
       - Register named UDFs with `deffunction`
       - Define JSONB schemas for structured data columns
       - Define named query members (CTE/VALUES/subquery/LATERAL/UNNEST presets)
       - Add domain-specific validations (future)
      - Configure custom transformations (future)

      ## DSL Usage

      This overlay uses a clean DSL (Domain-Specific Language) syntax:

          # Module attributes for redactions
          @redactions [:field1, :field2]

          # Column customizations with defcolumn
          defcolumn :price do
            label "Product Price"
            format :currency
            aggregate_functions [:sum, :avg]
          end

           # Custom filters with deffilter
           deffilter "price_range" do
             name "Price Range"
             type :string
             description "Filter by price range"
           end

           # UDF registrations with deffunction
           deffunction "similarity" do
             kind :scalar
             sql_name "public.similarity"
             args [
               %{name: :left, type: :string, source: :selector},
               %{name: :right, type: :string, source: :value}
             ]
             returns :float
             allowed_in [:select, :order_by]
           end

          # JSONB schema definitions with defjsonb_schema
          defjsonb_schema :attributes do
            %{
              "color" => %{type: :string, required: true},
              "size" => %{type: :string, enum: ["small", "medium", "large"]}
            }
          end

          # Named CTE/VALUES/subquery/LATERAL/UNNEST presets
          defcte :active_rows do
            query &__MODULE__.active_rows_cte/1
            columns ["id"]
            join [owner_key: :id, related_key: :id]
          end

          defvalues :status_lookup do
            rows [["active", "Active"], ["inactive", "Inactive"]]
            columns ["status", "label"]
            as "status_lookup"
            join [owner_key: :status, related_key: :status]
          end

          defsubquery :high_value_rows do
            query &__MODULE__.high_value_rows_subquery/1
            on [%{left: "id", right: "entity_id"}]
          end

          deflateral :recent_series do
            source {:function, :generate_series, [1, 3]}
            as "recent_series"
            join_type :inner
          end

          defunnest :tag_values do
            array_field "tags"
            as "tag_value"
            ordinality "tag_position"
          end

      ## How It Works

      The DSL compiles into an overlay configuration map that is merged with the
      base domain configuration at runtime. Column configurations are deep-merged,
      allowing you to override or extend specific properties without replacing
      the entire column configuration.

      ## Examples

      See the commented examples below for common customization patterns based on
      your schema.
      \"\"\"

      use Selecto.Config.OverlayDSL

      # Uncomment to redact sensitive fields from query results
      #{redaction_example}

      # Uncomment and customize column configurations as needed
    #{column_examples}

      # Uncomment and add custom filters
    #{filter_examples}

      # Uncomment and register domain UDFs
    #{function_examples}
    #{query_member_examples}
    #{jsonb_examples}
    end
    """
  end

  @doc """
  Generates the overlay module name from the domain module name.

  ## Examples

      iex> overlay_module_name("MyApp.SelectoDomains.ProductDomain")
      "MyApp.SelectoDomains.Overlays.ProductDomainOverlay"
  """
  def overlay_module_name(domain_module_name) do
    parts = String.split(domain_module_name, ".")
    {last, prefix} = List.pop_at(parts, -1)

    overlay_name = last <> "Overlay"
    (prefix ++ ["Overlays", overlay_name]) |> Enum.join(".")
  end

  @doc """
  Generates the overlay file path from the domain file path.

  ## Examples

      iex> overlay_file_path("lib/my_app/selecto_domains/product_domain.ex")
      "lib/my_app/selecto_domains/overlays/product_domain_overlay.ex"
  """
  def overlay_file_path(domain_file_path) do
    dir = Path.dirname(domain_file_path)
    basename = Path.basename(domain_file_path, ".ex")
    overlay_basename = basename <> "_overlay.ex"

    Path.join([dir, "overlays", overlay_basename])
  end

  # Private helper functions

  defp generate_redaction_example(config) do
    columns = extract_columns(config)

    # Find fields that might be sensitive
    sensitive_fields =
      columns
      |> Enum.filter(fn {field_name, _} ->
        field_str = to_string(field_name)

        String.contains?(field_str, "password") ||
          String.contains?(field_str, "secret") ||
          String.contains?(field_str, "token") ||
          String.contains?(field_str, "key") ||
          String.contains?(field_str, "internal")
      end)
      |> Enum.map(fn {field_name, _} -> field_name end)
      |> Enum.take(3)

    if length(sensitive_fields) > 0 do
      fields_list = Enum.map_join(sensitive_fields, ", ", &inspect/1)
      "# @redactions [#{fields_list}]"
    else
      "# @redactions [:sensitive_field1, :sensitive_field2]"
    end
  end

  defp generate_column_examples_dsl(config) do
    columns = extract_columns(config)

    # Pick a few example columns to show patterns
    examples =
      columns
      |> Enum.take(3)
      |> Enum.map(fn {field_name, column_config} ->
        generate_column_example_dsl(field_name, column_config)
      end)
      |> Enum.join("\n\n")

    if examples == "" do
      """
        # defcolumn :field_name do
        #   label "Custom Label"
        #   format :currency  # or :percentage, :number, :date, etc.
        #   aggregate_functions [:sum, :avg, :min, :max]
        # end
      """
    else
      examples
    end
  end

  defp generate_column_example_dsl(field_name, column_config) do
    type = Map.get(column_config, :type, :string)

    case type do
      :decimal ->
        """
          # defcolumn :#{field_name} do
          #   label "#{humanize(field_name)}"
          #   format :currency
          #   precision 2
          #   aggregate_functions [:sum, :avg, :min, :max]
          # end
        """

      :integer ->
        """
          # defcolumn :#{field_name} do
          #   label "#{humanize(field_name)}"
          #   aggregate_functions [:sum, :avg, :count, :min, :max]
          # end
        """

      :boolean ->
        """
          # defcolumn :#{field_name} do
          #   label "#{humanize(field_name)}"
          #   format :yes_no
          # end
        """

      :date ->
        """
          # defcolumn :#{field_name} do
          #   label "#{humanize(field_name)}"
          #   format :date
          # end
        """

      :utc_datetime ->
        """
          # defcolumn :#{field_name} do
          #   label "#{humanize(field_name)}"
          #   format :datetime
          # end
        """

      _ ->
        """
          # defcolumn :#{field_name} do
          #   label "#{humanize(field_name)}"
          #   max_length 100
          # end
        """
    end
    |> String.trim_trailing()
  end

  defp generate_filter_examples_dsl(config) do
    columns = extract_columns(config)

    # Find a good example column for filtering
    example_field =
      columns
      |> Enum.find(fn {_field, col_config} ->
        Map.get(col_config, :type) in [:string, :integer, :decimal, :boolean]
      end)

    case example_field do
      {field_name, %{type: :string}} ->
        """
          # deffilter "#{field_name}_search" do
          #   name "Search #{humanize(field_name)}"
          #   type :string
          #   description "Filter by #{field_name} containing text"
          # end
        """

      {field_name, %{type: type}} when type in [:integer, :decimal] ->
        """
          # deffilter "#{field_name}_range" do
          #   name "#{humanize(field_name)} Range"
          #   type :string
          #   description "Filter by #{field_name} range (e.g., '100-500')"
          # end
        """

      {field_name, %{type: :boolean}} ->
        """
          # deffilter "#{field_name}" do
          #   name "#{humanize(field_name)}"
          #   type :boolean
          #   description "Filter by #{field_name}"
          #   default false
          # end
        """

      _ ->
        """
          # deffilter "custom_filter" do
          #   name "Custom Filter"
          #   type :string
          #   description "Your custom filter description"
          # end
        """
    end
    |> String.trim_trailing()
  end

  defp generate_function_examples_dsl do
    """
      # deffunction "similarity" do
      #   kind :scalar
      #   sql_name "public.similarity"
      #   args [
      #     %{name: :left, type: :string, source: :selector},
      #     %{name: :right, type: :string, source: :value}
      #   ]
      #   returns :float
      #   allowed_in [:select, :order_by]
      # end

      # deffunction "nearby_points" do
      #   kind :table
      #   sql_name "gis.nearby_points"
      #   args [
      #     %{name: :origin, type: :geometry, source: :selector},
      #     %{name: :radius_m, type: :integer, source: :value}
      #   ]
      #   returns %{columns: %{id: %{type: :integer}, distance_m: %{type: :float}}}
      #   allowed_in [:lateral, :query_member]
      # end
    """
    |> String.trim_trailing()
  end

  defp generate_query_member_examples_dsl do
    """

      # Optional named query members (used by Selecto.with_cte/2, with_values/2,
      # with_subquery/2, with_lateral/2, and with_unnest/2)
      # defcte :active_rows do
      #   query &__MODULE__.active_rows_cte/1
      #   columns ["id"]
      #   join [owner_key: :id, related_key: :id, fields: :infer]
      # end

      # defvalues :status_lookup do
      #   rows [["active", "Active"], ["inactive", "Inactive"]]
      #   columns ["status", "label"]
      #   as "status_lookup"
      #   join [owner_key: :status, related_key: :status]
      # end

      # defsubquery :high_value_rows do
      #   query &__MODULE__.high_value_rows_subquery/1
      #   type :inner
      #   on [%{left: "id", right: "entity_id"}]
      # end

      # deflateral :recent_series do
      #   source {:function, :generate_series, [1, 3]}
      #   as "recent_series"
      #   join_type :inner
      # end

      # defunnest :tag_values do
      #   array_field "tags"
      #   as "tag_value"
      #   ordinality "tag_position"
      # end
    """
    |> String.trim_trailing()
  end

  defp humanize(atom_or_string) do
    atom_or_string
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp generate_jsonb_schema_examples(config) do
    columns = extract_columns(config, config[:field_types] || %{})

    # Find JSONB columns
    jsonb_columns =
      columns
      |> Enum.filter(fn {_field, col_config} ->
        type = if is_map(col_config), do: Map.get(col_config, :type), else: col_config
        type == :jsonb
      end)
      |> Enum.map(fn {field_name, _} -> field_name end)

    if Enum.empty?(jsonb_columns) do
      ""
    else
      examples =
        jsonb_columns
        |> Enum.map(&generate_jsonb_schema_example/1)
        |> Enum.join("\n\n")

      """

        # ============================================================================
        # JSONB Schema Definitions
        # ============================================================================
        #
        # Define the structure of your JSONB columns to enable:
        # - Type-safe filtering with dot notation (e.g., attributes.color = "red")
        # - Validation on inserts/updates
        # - GraphQL type generation
        #
        # Uncomment and customize the schema definitions below:

      #{examples}
      """
    end
  end

  defp generate_jsonb_schema_example(field_name) do
    field_str = to_string(field_name)

    """
      # defjsonb_schema :#{field_str} do
      #   %{
      #     # String field with validation
      #     "color" => %{type: :string, required: true},
      #
      #     # Enum field with allowed values
      #     "size" => %{type: :string, enum: ["small", "medium", "large", "xl"]},
      #
      #     # Numeric field with bounds
      #     "weight" => %{type: :decimal, min: 0},
      #
      #     # Boolean field with default
      #     "in_stock" => %{type: :boolean, default: true},
      #
      #     # Nested object
      #     "dimensions" => %{
      #       type: :object,
      #       schema: %{
      #         "length" => %{type: :decimal, required: true},
      #         "width" => %{type: :decimal},
      #         "height" => %{type: :decimal}
      #       }
      #     },
      #
      #     # Array of strings
      #     "tags" => %{
      #       type: :array,
      #       items: %{type: :string}
      #     }
      #   }
      # end
    """
    |> String.trim_trailing()
  end

  defp extract_columns(config, default \\ %{}) do
    cond do
      is_map(config[:columns]) ->
        config[:columns]

      is_map(config[:source]) and is_map(config[:source][:columns]) ->
        config[:source][:columns]

      true ->
        default
    end
  end
end
