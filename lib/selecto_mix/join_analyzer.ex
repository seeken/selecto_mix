defmodule SelectoMix.JoinAnalyzer do
  @moduledoc """
  Analyzes Ecto schemas to detect and configure optimal join relationships.
  
  Features:
  - Foreign key relationship detection
  - Many-to-many junction table recognition
  - Hierarchical relationship identification
  - Dimension table pattern detection
  - Slowly changing dimension support
  - Circular dependency detection
  - Join optimization strategies
  """
  
  alias Mix.Selecto.SchemaAnalyzer
  
  @type join_type :: :inner | :left | :right | :full | :cross | 
                     :hierarchical | :dimension | :snowflake_dimension
  
  @type join_config :: %{
    type: join_type(),
    schema: module(),
    on: tuple() | list(tuple()),
    through: atom() | nil,
    strategy: atom() | nil,
    required_fields: list(atom()),
    optional_fields: list(atom()),
    metadata: map()
  }
  
  @type analysis_result :: %{
    joins: %{atom() => join_config()},
    relationships: map(),
    hierarchies: list(map()),
    dimensions: list(map()),
    junction_tables: list(map()),
    warnings: list(String.t()),
    suggestions: list(String.t())
  }
  
  @doc """
  Analyzes a schema module to detect all join relationships.
  """
  @spec analyze(module(), keyword()) :: analysis_result()
  def analyze(schema_module, opts \\ []) do
    adapter = opts[:adapter] || :postgres
    depth = opts[:join_depth] || 3
    
    # Get basic schema info
    schema_info = SchemaAnalyzer.analyze_schema(schema_module, 
      include_associations: true)
    
    # Analyze different relationship types
    basic_joins = analyze_basic_joins(schema_info, adapter)
    many_to_many = analyze_many_to_many(schema_module)
    hierarchical = analyze_hierarchical(schema_info)
    dimensions = analyze_dimensions(schema_info, opts)
    
    # Detect issues
    cycles = detect_circular_dependencies(basic_joins, depth)
    
    # Generate optimal join configuration
    optimized_joins = optimize_joins(basic_joins ++ many_to_many, opts)
    
    %{
      joins: Map.merge(basic_joins, optimized_joins),
      relationships: categorize_relationships(schema_info.associations),
      hierarchies: hierarchical,
      dimensions: dimensions,
      junction_tables: detect_junction_tables(many_to_many),
      warnings: generate_warnings(cycles, hierarchical),
      suggestions: generate_suggestions(schema_info, optimized_joins)
    }
  end
  
  @doc """
  Analyzes basic foreign key relationships (belongs_to, has_many, has_one).
  """
  @spec analyze_basic_joins(map(), atom()) :: map()
  def analyze_basic_joins(schema_info, adapter) do
    schema_info.associations
    |> Enum.filter(&(&1.type in [:belongs_to, :has_many, :has_one]))
    |> Enum.map(fn assoc ->
      {assoc.name, build_basic_join_config(assoc, adapter)}
    end)
    |> Map.new()
  end
  
  @doc """
  Detects many-to-many relationships through junction tables.
  """
  @spec analyze_many_to_many(module()) :: map()
  def analyze_many_to_many(schema_module) do
    try do
      schema_module.__schema__(:associations)
      |> Enum.filter(&is_many_to_many?/1)
      |> Enum.map(fn assoc_name ->
        assoc = schema_module.__schema__(:association, assoc_name)
        {assoc_name, build_many_to_many_config(assoc, schema_module)}
      end)
      |> Map.new()
    rescue
      _ -> %{}
    end
  end
  
  @doc """
  Detects hierarchical relationships (self-referential).
  """
  @spec analyze_hierarchical(map()) :: list(map())
  def analyze_hierarchical(schema_info) do
    module = schema_info.module
    
    schema_info.associations
    |> Enum.filter(fn assoc ->
      # Check if association points to same module (self-referential)
      assoc[:related] == module
    end)
    |> Enum.map(fn assoc ->
      analyze_hierarchy_type(assoc, schema_info)
    end)
  end
  
  @doc """
  Detects dimension table patterns (star/snowflake schema).
  """
  @spec analyze_dimensions(map(), keyword()) :: list(map())
  def analyze_dimensions(schema_info, _opts) do
    # Look for typical dimension patterns
    dimensions = []
    
    # Check for SCD Type 2 pattern (history tables)
    dimensions = if has_history_table?(schema_info) do
      [build_scd_dimension(schema_info) | dimensions]
    else
      dimensions
    end
    
    # Check for star schema pattern
    dimensions = if looks_like_dimension?(schema_info) do
      [build_star_dimension(schema_info) | dimensions]
    else
      dimensions
    end
    
    dimensions
  end
  
  @doc """
  Detects circular dependencies in join relationships.
  """
  @spec detect_circular_dependencies(map(), integer()) :: list(list(atom()))
  def detect_circular_dependencies(joins, max_depth) do
    # Build adjacency list
    graph = Enum.reduce(joins, %{}, fn {from, config}, acc ->
      to = config.schema
      Map.update(acc, from, [to], &[to | &1])
    end)
    
    # Find cycles using DFS
    find_cycles(graph, max_depth)
  end
  
  @doc """
  Optimizes join configurations based on usage patterns and adapter.
  """
  @spec optimize_joins(map(), keyword()) :: map()
  def optimize_joins(joins, opts) do
    strategy = opts[:join_strategy] || :optimized
    adapter = opts[:adapter] || :postgres
    
    joins
    |> Enum.map(fn {name, config} ->
      {name, optimize_join_config(config, strategy, adapter)}
    end)
    |> Map.new()
  end
  
  @doc """
  Generates join configuration for use in Selecto domains.
  """
  @spec generate_join_config(analysis_result(), atom()) :: map()
  def generate_join_config(analysis, adapter) do
    analysis.joins
    |> Enum.map(fn {name, config} ->
      {name, format_for_selecto(config, adapter)}
    end)
    |> Map.new()
  end
  
  # Private helper functions
  
  defp build_basic_join_config(assoc, adapter) do
    base_config = %{
      type: determine_join_type(assoc),
      schema: assoc.related,
      on: build_join_condition(assoc),
      through: nil,
      strategy: :lazy,
      required_fields: [],
      optional_fields: [],
      metadata: %{
        cardinality: assoc.type,
        foreign_key: assoc[:foreign_key],
        owner_key: assoc[:owner_key] || :id
      }
    }
    
    # Adapter-specific adjustments
    adjust_for_adapter(base_config, adapter)
  end
  
  defp build_many_to_many_config(assoc, _schema_module) do
    %{
      type: :inner,
      schema: assoc.related,
      through: assoc.join_through,
      on: build_many_to_many_condition(assoc),
      strategy: :optimized,
      required_fields: get_junction_fields(assoc.join_through),
      optional_fields: [],
      metadata: %{
        cardinality: :many_to_many,
        junction_table: assoc.join_through,
        join_keys: assoc.join_keys
      }
    }
  end
  
  defp analyze_hierarchy_type(assoc, schema_info) do
    cond do
      # Adjacency list pattern (parent_id)
      assoc[:foreign_key] in [:parent_id, :parent] ->
        %{
          type: :adjacency_list,
          field: assoc.name,
          parent_field: assoc[:foreign_key],
          strategy: :recursive_cte
        }
      
      # Nested set pattern (lft, rgt fields)
      has_nested_set_fields?(schema_info) ->
        %{
          type: :nested_set,
          field: assoc.name,
          left_field: :lft,
          right_field: :rgt,
          strategy: :range_query
        }
      
      # Materialized path pattern
      has_path_field?(schema_info) ->
        %{
          type: :materialized_path,
          field: assoc.name,
          path_field: :path,
          strategy: :like_query
        }
      
      # Generic self-reference
      true ->
        %{
          type: :self_reference,
          field: assoc.name,
          foreign_key: assoc[:foreign_key],
          strategy: :standard_join
        }
    end
  end
  
  defp has_history_table?(schema_info) do
    # Check for common SCD patterns
    module_name = schema_info.module |> to_string()
    
    # Look for corresponding history table
    history_module = Module.concat([schema_info.module, "History"])
    dimension_module = Module.concat([schema_info.module, "Dim"])
    
    Code.ensure_loaded?(history_module) or 
    Code.ensure_loaded?(dimension_module) or
    String.ends_with?(module_name, "History") or
    String.ends_with?(module_name, "Dimension")
  end
  
  defp looks_like_dimension?(schema_info) do
    fields = schema_info.fields |> Enum.map(& &1.name)
    
    # Common dimension table indicators
    dimension_indicators = [
      # Has dimension key fields
      Enum.any?(fields, &(&1 in [:dimension_key, :surrogate_key, :business_key])),
      # Has SCD tracking fields
      Enum.any?(fields, &(&1 in [:valid_from, :valid_to, :effective_date, :expiry_date])),
      # Has version/current flags
      Enum.any?(fields, &(&1 in [:is_current, :version, :row_version])),
      # Name pattern
      schema_info.module |> to_string() |> String.ends_with?("Dim")
    ]
    
    Enum.count(dimension_indicators, & &1) >= 2
  end
  
  defp build_scd_dimension(schema_info) do
    %{
      type: :scd_type2,
      table: schema_info[:table] || schema_info[:source],
      natural_key: find_natural_key(schema_info),
      surrogate_key: :id,
      valid_from: find_field(schema_info, [:valid_from, :effective_date, :created_at]),
      valid_to: find_field(schema_info, [:valid_to, :expiry_date, :end_date]),
      is_current: find_field(schema_info, [:is_current, :current_flag, :active]),
      change_tracking: detect_change_tracking_fields(schema_info)
    }
  end
  
  defp build_star_dimension(schema_info) do
    %{
      type: :star_dimension,
      table: schema_info[:table] || schema_info[:source],
      hierarchy_levels: detect_hierarchy_levels(schema_info),
      attributes: detect_dimension_attributes(schema_info),
      measures: []  # Dimensions typically don't have measures
    }
  end
  
  defp determine_join_type(assoc) do
    case assoc.type do
      :belongs_to -> :inner  # Usually required relationship
      :has_many -> :left     # Optional, may have zero
      :has_one -> :left      # Optional, may not exist
      _ -> :left
    end
  end
  
  defp build_join_condition(assoc) do
    case assoc.type do
      :belongs_to ->
        {assoc[:foreign_key] || :"#{assoc.name}_id", :id}
      :has_many ->
        {:id, assoc[:foreign_key] || :"#{assoc.name}_id"}
      :has_one ->
        {:id, assoc[:foreign_key] || :"#{assoc.name}_id"}
      _ ->
        {:id, :id}
    end
  end
  
  defp build_many_to_many_condition(assoc) do
    [{:id, elem(assoc.join_keys, 0)}, 
     {elem(assoc.join_keys, 1), :id}]
  end
  
  defp adjust_for_adapter(config, :mysql) do
    # MySQL doesn't support FULL OUTER JOIN
    config = if config.type == :full do
      %{config | type: :left, 
        metadata: Map.put(config.metadata, :original_type, :full)}
    else
      config
    end
    
    config
  end
  
  defp adjust_for_adapter(config, :sqlite) do
    # SQLite doesn't support RIGHT or FULL joins
    config = case config.type do
      :right -> 
        %{config | type: :left,
          metadata: Map.put(config.metadata, :original_type, :right)}
      :full ->
        %{config | type: :left,
          metadata: Map.put(config.metadata, :original_type, :full)}
      _ -> config
    end
    
    config
  end
  
  defp adjust_for_adapter(config, _adapter), do: config
  
  defp is_many_to_many?(_assoc_name) do
    # This is a simplified check - in reality would need schema inspection
    false  # Placeholder
  end
  
  defp get_junction_fields(junction_module) do
    try do
      junction_module.__schema__(:fields)
    rescue
      _ -> []
    end
  end
  
  defp has_nested_set_fields?(schema_info) do
    fields = schema_info.fields |> Enum.map(& &1.name)
    :lft in fields and :rgt in fields
  end
  
  defp has_path_field?(schema_info) do
    fields = schema_info.fields |> Enum.map(& &1.name)
    :path in fields or :materialized_path in fields
  end
  
  defp find_natural_key(schema_info) do
    fields = schema_info.fields |> Enum.map(& &1.name)
    
    Enum.find(fields, :id, fn field ->
      field in [:business_key, :natural_key, :code, :sku, :email, :username]
    end)
  end
  
  defp find_field(schema_info, candidates) do
    fields = schema_info.fields |> Enum.map(& &1.name)
    Enum.find(candidates, fn candidate -> candidate in fields end)
  end
  
  defp detect_change_tracking_fields(schema_info) do
    fields = schema_info.fields |> Enum.map(& &1.name)
    
    Enum.filter(fields, fn field ->
      field in [:change_reason, :change_type, :modified_by, :audit_action]
    end)
  end
  
  defp detect_hierarchy_levels(schema_info) do
    # Look for level indicators in field names
    fields = schema_info.fields |> Enum.map(& &1.name)
    
    Enum.filter(fields, fn field ->
      String.contains?(to_string(field), ["level", "tier", "category", "group"])
    end)
  end
  
  defp detect_dimension_attributes(schema_info) do
    # Separate descriptive attributes from keys and dates
    fields = schema_info.fields |> Enum.map(& &1.name)
    
    Enum.reject(fields, fn field ->
      field in [:id, :inserted_at, :updated_at] or
      String.ends_with?(to_string(field), "_id") or
      String.ends_with?(to_string(field), "_key")
    end)
  end
  
  defp find_cycles(graph, max_depth) do
    nodes = Map.keys(graph)
    
    Enum.reduce(nodes, [], fn node, cycles ->
      case dfs_find_cycle(graph, node, [node], MapSet.new([node]), max_depth) do
        nil -> cycles
        cycle -> [cycle | cycles]
      end
    end)
  end
  
  defp dfs_find_cycle(_graph, _current, _path, _visited, 0), do: nil
  
  defp dfs_find_cycle(graph, current, path, visited, depth) do
    neighbors = Map.get(graph, current, [])
    
    Enum.find_value(neighbors, fn neighbor ->
      cond do
        neighbor in visited ->
          # Found a cycle
          Enum.reverse([neighbor | path])
        
        true ->
          # Continue DFS
          new_visited = MapSet.put(visited, neighbor)
          dfs_find_cycle(graph, neighbor, [neighbor | path], new_visited, depth - 1)
      end
    end)
  end
  
  defp optimize_join_config(config, :eager, _adapter) do
    %{config | strategy: :eager}
  end
  
  defp optimize_join_config(config, :lazy, _adapter) do
    %{config | strategy: :lazy}
  end
  
  defp optimize_join_config(config, :optimized, _adapter) do
    # Apply intelligent optimization based on relationship type
    strategy = case config.metadata[:cardinality] do
      :belongs_to -> :eager  # Usually want parent data
      :has_one -> :lazy      # May not always need
      :has_many -> :lazy     # Often large datasets
      :many_to_many -> :lazy # Complex, load on demand
      _ -> :lazy
    end
    
    %{config | strategy: strategy}
  end
  
  defp categorize_relationships(associations) do
    associations
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, assocs} ->
      {type, Enum.map(assocs, & &1.name)}
    end)
    |> Map.new()
  end
  
  defp detect_junction_tables(many_to_many_joins) do
    many_to_many_joins
    |> Map.values()
    |> Enum.map(& &1.metadata[:junction_table])
    |> Enum.uniq()
    |> Enum.filter(& &1)
  end
  
  defp generate_warnings(cycles, hierarchies) do
    warnings = []
    
    warnings = if cycles != [] do
      cycle_warnings = Enum.map(cycles, fn cycle ->
        "Circular dependency detected: #{inspect(cycle)}"
      end)
      warnings ++ cycle_warnings
    else
      warnings
    end
    
    warnings = if length(hierarchies) > 1 do
      ["Multiple hierarchical relationships detected. Consider using only one hierarchy pattern." | warnings]
    else
      warnings
    end
    
    warnings
  end
  
  defp generate_suggestions(_schema_info, optimized_joins) do
    suggestions = []
    
    # Suggest indexes for foreign keys
    fk_suggestions = optimized_joins
    |> Enum.filter(fn {_name, config} ->
      config.metadata[:cardinality] == :belongs_to
    end)
    |> Enum.map(fn {_name, config} ->
      "Consider adding index on #{config.metadata[:foreign_key]}"
    end)
    
    suggestions ++ fk_suggestions
  end
  
  defp format_for_selecto(config, adapter) do
    base = %{
      type: config.type,
      schema: config.schema,
      on: config.on
    }
    
    base = if config.through do
      Map.put(base, :through, config.through)
    else
      base
    end
    
    # Add adapter-specific metadata
    if adapter != :postgres and config.metadata[:original_type] do
      Map.put(base, :adapter_note, 
        "Originally #{config.metadata[:original_type]}, adapted for #{adapter}")
    else
      base
    end
  end
end