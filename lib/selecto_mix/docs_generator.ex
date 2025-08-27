defmodule SelectoMix.DocsGenerator do
  @moduledoc """
  Generates comprehensive documentation for Selecto domains including overviews,
  field references, join guides, examples, performance considerations, and
  interactive Livebook tutorials.
  """

  @doc """
  Generate domain overview documentation.
  """
  def generate_overview(domain, format \\ :markdown) do
    domain_info = analyze_domain(domain)
    
    case format do
      :markdown -> generate_markdown_overview(domain, domain_info)
      :html -> generate_html_overview(domain, domain_info)
    end
  end

  @doc """
  Generate comprehensive field reference documentation.
  """
  def generate_fields_reference(domain, format \\ :markdown) do
    domain_info = analyze_domain(domain)
    
    case format do
      :markdown -> generate_markdown_fields(domain, domain_info)
      :html -> generate_html_fields(domain, domain_info)
    end
  end

  @doc """
  Generate joins and relationships guide.
  """
  def generate_joins_guide(domain, format \\ :markdown) do
    domain_info = analyze_domain(domain)
    
    case format do
      :markdown -> generate_markdown_joins(domain, domain_info)
      :html -> generate_html_joins(domain, domain_info)
    end
  end

  @doc """
  Generate code examples and common patterns.
  """
  def generate_examples(domain, format \\ :markdown, opts \\ []) do
    domain_info = analyze_domain(domain)
    
    case format do
      :markdown -> generate_markdown_examples(domain, domain_info, opts)
      :html -> generate_html_examples(domain, domain_info, opts)
    end
  end

  @doc """
  Generate performance guide with benchmarking information.
  """
  def generate_performance_guide(domain, format \\ :markdown) do
    domain_info = analyze_domain(domain)
    
    case format do
      :markdown -> generate_markdown_performance(domain, domain_info)
      :html -> generate_html_performance(domain, domain_info)
    end
  end

  @doc """
  Generate interactive Livebook tutorial.
  """
  def generate_interactive_livebook(domain) do
    domain_info = analyze_domain(domain)
    generate_livebook_content(domain, domain_info)
  end

  @doc """
  Generate interactive HTML documentation.
  """
  def generate_interactive_html(domain) do
    domain_info = analyze_domain(domain)
    generate_interactive_html_content(domain, domain_info)
  end

  # Private functions for domain analysis

  defp analyze_domain(domain) do
    # This would integrate with the existing domain introspection system
    # For now, return a basic structure
    %{
      name: domain,
      source: analyze_source_schema(domain),
      schemas: analyze_related_schemas(domain),
      joins: analyze_join_relationships(domain),
      patterns: detect_domain_patterns(domain)
    }
  end

  defp analyze_source_schema(domain) do
    # Analyze the main source schema for the domain
    %{
      table: "#{domain}",
      primary_key: :id,
      fields: [:id, :name, :created_at, :updated_at],
      types: %{
        id: :integer,
        name: :string,
        created_at: :datetime,
        updated_at: :datetime
      }
    }
  end

  defp analyze_related_schemas(_domain) do
    # Analyze related schemas and associations
    %{}
  end

  defp analyze_join_relationships(_domain) do
    # Analyze join patterns and relationships
    []
  end

  defp detect_domain_patterns(_domain) do
    # Detect common patterns like hierarchies, tagging, etc.
    []
  end

  # Markdown generation functions

  defp generate_markdown_overview(domain, domain_info) do
    """
    # #{String.capitalize(domain)} Domain Overview

    This document provides a comprehensive overview of the #{domain} domain configuration
    for Selecto query building and data visualization.

    ## Domain Structure

    The #{domain} domain is built around the `#{domain_info.source.table}` table as its
    primary data source, with the following key characteristics:

    ### Primary Source
    - **Table**: `#{domain_info.source.table}`
    - **Primary Key**: `#{domain_info.source.primary_key}`
    - **Field Count**: #{length(domain_info.source.fields)}

    ### Available Fields
    #{generate_field_list(domain_info.source.fields, domain_info.source.types)}

    ## Usage Patterns

    The #{domain} domain supports the following common usage patterns:

    ### Basic Queries
    ```elixir
    # Select all records
    Selecto.select(#{domain}_domain(), [:id, :name])

    # Filter by specific criteria
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.filter(:name, :eq, "example")
    ```

    ### Aggregations
    ```elixir
    # Count records
    Selecto.select(#{domain}_domain(), [:count])
    |> Selecto.aggregate(:count, :id)

    # Group by fields
    Selecto.select(#{domain}_domain(), [:name, :count])
    |> Selecto.group_by([:name])
    |> Selecto.aggregate(:count, :id)
    ```

    ## Related Documentation

    - [Field Reference](#{domain}_fields.md) - Complete field reference
    - [Joins Guide](#{domain}_joins.md) - Join relationships and optimization
    - [Examples](#{domain}_examples.md) - Code examples and patterns
    - [Performance Guide](#{domain}_performance.md) - Performance considerations

    ## Quick Start

    To use this domain in your application:

    1. Include the domain module in your query context
    2. Configure your database connection
    3. Start building queries using the Selecto API

    ```elixir
    # Example usage in LiveView
    def mount(_params, _session, socket) do
      initial_data = 
        Selecto.select(#{domain}_domain(), [:id, :name])
        |> Selecto.limit(10)
        |> Selecto.execute(MyApp.Repo)

      {:ok, assign(socket, data: initial_data)}
    end
    ```

    For more detailed examples and advanced usage patterns, see the 
    [Examples Documentation](#{domain}_examples.md).
    """
  end

  defp generate_markdown_fields(domain, domain_info) do
    """
    # #{String.capitalize(domain)} Domain Fields Reference

    This document provides a complete reference for all fields available in the 
    #{domain} domain, including types, descriptions, and usage examples.

    ## Primary Source Fields

    The following fields are available from the main `#{domain_info.source.table}` table:

    #{generate_detailed_field_reference(domain_info.source.fields, domain_info.source.types)}

    ## Field Usage Examples

    ### Basic Field Selection
    ```elixir
    # Select specific fields
    Selecto.select(#{domain}_domain(), [:id, :name])

    # Select all fields
    Selecto.select(#{domain}_domain(), :all)
    ```

    ### Field Filtering
    ```elixir
    # String field filtering
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.filter(:name, :like, "%example%")

    # Numeric field filtering
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.filter(:id, :gt, 100)

    # Date field filtering
    Selecto.select(#{domain}_domain(), [:id, :created_at])
    |> Selecto.filter(:created_at, :gt, ~D[2024-01-01])
    ```

    ### Field Aggregations
    ```elixir
    # Count distinct values
    Selecto.select(#{domain}_domain(), [:name, :count])
    |> Selecto.group_by([:name])
    |> Selecto.aggregate(:count, :id)

    # Calculate averages (numeric fields only)
    Selecto.select(#{domain}_domain(), [:avg_value])
    |> Selecto.aggregate(:avg, :numeric_field)
    ```

    ## Field Type Reference

    ### String Fields
    String fields support the following operations:
    - Equality: `:eq`, `:ne`
    - Pattern matching: `:like`, `:ilike`, `:not_like`, `:not_ilike`
    - Null checks: `:is_null`, `:is_not_null`
    - List operations: `:in`, `:not_in`

    ### Numeric Fields
    Numeric fields (integer, float, decimal) support:
    - Comparison: `:eq`, `:ne`, `:gt`, `:gte`, `:lt`, `:lte`
    - Range operations: `:between`, `:not_between`
    - Null checks: `:is_null`, `:is_not_null`
    - List operations: `:in`, `:not_in`

    ### Date/DateTime Fields
    Date and datetime fields support:
    - Comparison: `:eq`, `:ne`, `:gt`, `:gte`, `:lt`, `:lte`
    - Range operations: `:between`, `:not_between`
    - Null checks: `:is_null`, `:is_not_null`

    ### Boolean Fields
    Boolean fields support:
    - Equality: `:eq`, `:ne`
    - Null checks: `:is_null`, `:is_not_null`

    ## Best Practices

    ### Field Selection
    - Always select only the fields you need for better performance
    - Use `:all` sparingly, especially on tables with many columns
    - Consider the impact of large text fields on query performance

    ### Filtering
    - Use appropriate indexes for frequently filtered fields
    - Prefer exact matches (`:eq`) over pattern matches (`:like`) when possible
    - Use `:ilike` for case-insensitive string matching

    ### Aggregations
    - Group by fields with good cardinality for meaningful results
    - Be aware of memory usage with large result sets
    - Use `LIMIT` clauses with aggregated queries when appropriate

    ## Performance Considerations

    See the [Performance Guide](#{domain}_performance.md) for detailed information
    about optimizing queries with these fields.
    """
  end

  defp generate_markdown_joins(domain, domain_info) do
    """
    # #{String.capitalize(domain)} Domain Joins Guide

    This document explains how to work with joins and relationships in the #{domain} domain,
    including performance optimization and best practices.

    ## Available Joins

    #{generate_joins_documentation(domain_info.joins)}

    ## Join Syntax

    ### Basic Join Operations
    ```elixir
    # Inner join with related table
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.join(:inner, :related_table, :id, :#{domain}_id)
    ```

    ### Advanced Join Patterns
    ```elixir
    # Multiple joins
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.join(:inner, :categories, :category_id, :id)
    |> Selecto.join(:left, :tags, :id, :#{domain}_id)
    ```

    ## Join Types

    ### Inner Joins
    Inner joins return only records that have matching values in both tables.
    
    **Use when**: You need records that definitely have related data.
    
    ```elixir
    # Only #{domain}s that have categories
    Selecto.select(#{domain}_domain(), [:id, :name, "categories.name as category_name"])
    |> Selecto.join(:inner, :categories, :category_id, :id)
    ```

    ### Left Joins
    Left joins return all records from the left table, with matching records from the right table.
    
    **Use when**: You want all main records, even if they don't have related data.
    
    ```elixir
    # All #{domain}s, with category names when available
    Selecto.select(#{domain}_domain(), [:id, :name, "categories.name as category_name"])
    |> Selecto.join(:left, :categories, :category_id, :id)
    ```

    ### Right Joins
    Right joins return all records from the right table, with matching records from the left table.
    
    **Use when**: You want all related records, even if they don't have main records.

    ### Full Outer Joins
    Full outer joins return records when there's a match in either table.
    
    **Use when**: You need comprehensive data from both tables.

    ## Performance Optimization

    ### Index Usage
    Ensure proper indexes exist for join conditions:
    
    ```sql
    -- Example indexes for common joins
    CREATE INDEX idx_#{domain}_category_id ON #{domain} (category_id);
    CREATE INDEX idx_categories_id ON categories (id);
    ```

    ### Join Order Optimization
    - Start with the most selective table (smallest result set)
    - Place most restrictive filters early in the query
    - Use EXPLAIN ANALYZE to verify query performance

    ### Query Hints
    ```elixir
    # Prefer hash joins for large result sets
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.join(:inner, :large_table, :id, :#{domain}_id, hint: :hash)

    # Prefer nested loop joins for small result sets
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.join(:inner, :small_table, :id, :#{domain}_id, hint: :nested_loop)
    ```

    ## Common Join Patterns

    ### One-to-Many Relationships
    ```elixir
    # #{String.capitalize(domain)} with multiple related records
    Selecto.select(#{domain}_domain(), [:id, :name, "tags.name as tag_name"])
    |> Selecto.join(:left, :#{domain}_tags, :id, :#{domain}_id)
    |> Selecto.join(:left, :tags, "#{domain}_tags.tag_id", "tags.id")
    ```

    ### Many-to-Many Relationships
    ```elixir
    # #{String.capitalize(domain)} with many-to-many through junction table
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.join(:inner, :#{domain}_categories, :id, :#{domain}_id)
    |> Selecto.join(:inner, :categories, "#{domain}_categories.category_id", "categories.id")
    |> Selecto.filter("categories.active", :eq, true)
    ```

    ### Self-Referential Joins
    ```elixir
    # Hierarchical data (parent-child relationships)
    Selecto.select(#{domain}_domain(), [:id, :name, "parent.name as parent_name"])
    |> Selecto.join(:left, :#{domain}, :parent_id, :id, alias: "parent")
    ```

    ## Troubleshooting

    ### Common Issues

    **Cartesian Products**: Occurs when join conditions are missing or incorrect.
    ```elixir
    # Wrong - missing join condition
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.join(:inner, :categories)  # Missing ON condition

    # Correct - proper join condition
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.join(:inner, :categories, :category_id, :id)
    ```

    **Duplicate Records**: Occurs with one-to-many joins without proper grouping.
    ```elixir
    # May produce duplicates
    Selecto.select(#{domain}_domain(), [:id, :name, "tags.name"])
    |> Selecto.join(:left, :tags, :id, :#{domain}_id)

    # Use aggregation to avoid duplicates
    Selecto.select(#{domain}_domain(), [:id, :name, "STRING_AGG(tags.name, ', ') as tag_names"])
    |> Selecto.join(:left, :tags, :id, :#{domain}_id)
    |> Selecto.group_by([:id, :name])
    ```

    ### Performance Issues

    **Slow Joins**: Usually caused by missing indexes or poor query structure.
    
    1. Check for appropriate indexes on join columns
    2. Analyze query execution plan
    3. Consider query restructuring or breaking into multiple queries

    **Memory Issues**: Large result sets from joins can cause memory problems.
    
    1. Use pagination with `LIMIT` and `OFFSET`
    2. Consider using cursors for large datasets
    3. Stream results when possible

    ## Best Practices

    1. **Always use explicit join conditions** - Don't rely on implicit relationships
    2. **Index foreign key columns** - Critical for join performance  
    3. **Use appropriate join types** - Don't use INNER when you need LEFT
    4. **Test with realistic data volumes** - Performance characteristics change with scale
    5. **Monitor query performance** - Use database profiling tools regularly
    6. **Consider denormalization** - Sometimes avoiding joins improves performance

    ## Related Documentation

    - [Performance Guide](#{domain}_performance.md) - Detailed performance optimization
    - [Examples](#{domain}_examples.md) - Real-world join examples
    - [Field Reference](#{domain}_fields.md) - Available fields for joins
    """
  end

  defp generate_markdown_examples(domain, _domain_info, _opts) do
    """
    # #{String.capitalize(domain)} Domain Examples

    This document provides practical examples of using the #{domain} domain for
    common data querying and visualization scenarios.

    ## Basic Operations

    ### Simple Data Retrieval
    ```elixir
    # Get all records with basic fields
    #{domain}_data = 
      Selecto.select(#{domain}_domain(), [:id, :name])
      |> Selecto.limit(50)
      |> Selecto.execute(MyApp.Repo)

    # Get single record by ID
    single_#{domain} = 
      Selecto.select(#{domain}_domain(), [:id, :name, :created_at])
      |> Selecto.filter(:id, :eq, 123)
      |> Selecto.execute(MyApp.Repo)
      |> List.first()
    ```

    ### Filtering Examples
    ```elixir
    # String filtering
    filtered_data = 
      Selecto.select(#{domain}_domain(), [:id, :name])
      |> Selecto.filter(:name, :like, "%search%")
      |> Selecto.execute(MyApp.Repo)

    # Multiple filters with AND logic
    complex_filter = 
      Selecto.select(#{domain}_domain(), [:id, :name, :created_at])
      |> Selecto.filter(:name, :like, "%active%")
      |> Selecto.filter(:created_at, :gte, ~D[2024-01-01])
      |> Selecto.execute(MyApp.Repo)

    # OR logic using filter groups
    or_filter = 
      Selecto.select(#{domain}_domain(), [:id, :name])
      |> Selecto.filter_group(:or, [
        {:name, :like, "%urgent%"},
        {:priority, :eq, "high"}
      ])
      |> Selecto.execute(MyApp.Repo)
    ```

    ## Aggregation Examples

    ### Basic Aggregations
    ```elixir
    # Count total records
    total_count = 
      Selecto.select(#{domain}_domain(), [:count])
      |> Selecto.aggregate(:count, :id)
      |> Selecto.execute(MyApp.Repo)
      |> hd()
      |> Map.get(:count)

    # Group by category with counts
    category_counts = 
      Selecto.select(#{domain}_domain(), [:category, :count])
      |> Selecto.group_by([:category])
      |> Selecto.aggregate(:count, :id)
      |> Selecto.order_by([{:count, :desc}])
      |> Selecto.execute(MyApp.Repo)
    ```

    ### Advanced Aggregations
    ```elixir
    # Multiple aggregations
    summary_stats = 
      Selecto.select(#{domain}_domain(), [:category, :total_count, :avg_score, :max_date])
      |> Selecto.group_by([:category])
      |> Selecto.aggregate(:count, :id, alias: :total_count)
      |> Selecto.aggregate(:avg, :score, alias: :avg_score)
      |> Selecto.aggregate(:max, :created_at, alias: :max_date)
      |> Selecto.execute(MyApp.Repo)

    # Conditional aggregations
    conditional_stats = 
      Selecto.select(#{domain}_domain(), [
        :status,
        "COUNT(CASE WHEN priority = 'high' THEN 1 END) as high_priority_count",
        "COUNT(CASE WHEN priority = 'low' THEN 1 END) as low_priority_count"
      ])
      |> Selecto.group_by([:status])
      |> Selecto.execute(MyApp.Repo)
    ```

    ## Join Examples

    ### Simple Joins
    ```elixir
    # Inner join with categories
    #{domain}_with_categories = 
      Selecto.select(#{domain}_domain(), [:id, :name, "categories.name as category_name"])
      |> Selecto.join(:inner, :categories, :category_id, :id)
      |> Selecto.execute(MyApp.Repo)

    # Left join to include records without categories
    all_#{domain}_with_optional_categories = 
      Selecto.select(#{domain}_domain(), [:id, :name, "categories.name as category_name"])
      |> Selecto.join(:left, :categories, :category_id, :id)
      |> Selecto.execute(MyApp.Repo)
    ```

    ### Complex Joins
    ```elixir
    # Multiple joins with aggregation
    #{domain}_summary = 
      Selecto.select(#{domain}_domain(), [
        :id, :name,
        "COUNT(comments.id) as comment_count",
        "AVG(ratings.score) as avg_rating"
      ])
      |> Selecto.join(:left, :comments, :id, :#{domain}_id)
      |> Selecto.join(:left, :ratings, :id, :#{domain}_id)
      |> Selecto.group_by([:id, :name])
      |> Selecto.execute(MyApp.Repo)
    ```

    ## LiveView Integration Examples

    ### Basic LiveView Setup
    ```elixir
    defmodule MyAppWeb.#{String.capitalize(domain)}Live do
      use MyAppWeb, :live_view
      
      def mount(_params, _session, socket) do
        {:ok, load_#{domain}_data(socket)}
      end
      
      defp load_#{domain}_data(socket) do
        #{domain}_data = 
          Selecto.select(#{domain}_domain(), [:id, :name, :created_at])
          |> Selecto.order_by([{:created_at, :desc}])
          |> Selecto.limit(25)
          |> Selecto.execute(MyApp.Repo)
        
        assign(socket, #{domain}_data: #{domain}_data)
      end
    end
    ```

    ### Interactive Filtering
    ```elixir
    def handle_event("filter", %{"search" => search_term}, socket) do
      filtered_data = 
        Selecto.select(#{domain}_domain(), [:id, :name, :created_at])
        |> maybe_filter_by_search(search_term)
        |> Selecto.order_by([{:created_at, :desc}])
        |> Selecto.limit(25)
        |> Selecto.execute(MyApp.Repo)
      
      {:noreply, assign(socket, #{domain}_data: filtered_data)}
    end
    
    defp maybe_filter_by_search(query, ""), do: query
    defp maybe_filter_by_search(query, search_term) do
      Selecto.filter(query, :name, :ilike, "%\#{search_term}%")
    end
    ```

    ### Pagination Example
    ```elixir
    def handle_event("load_more", _params, socket) do
      current_data = socket.assigns.#{domain}_data
      offset = length(current_data)
      
      new_data = 
        Selecto.select(#{domain}_domain(), [:id, :name, :created_at])
        |> Selecto.order_by([{:created_at, :desc}])
        |> Selecto.limit(25)
        |> Selecto.offset(offset)
        |> Selecto.execute(MyApp.Repo)
      
      updated_data = current_data ++ new_data
      
      {:noreply, assign(socket, #{domain}_data: updated_data)}
    end
    ```

    ## SelectoComponents Integration

    ### Aggregate View
    ```elixir
    # In your LiveView template
    <.live_component 
      module={SelectoComponents.Aggregate} 
      id="#{domain}-aggregate"
      domain={#{domain}_domain()}
      connection={@db_connection}
      initial_fields={[:id, :name, :category]}
      initial_aggregates={[:count]}
    />
    ```

    ### Detail View with Drill-Down
    ```elixir
    <.live_component 
      module={SelectoComponents.Detail} 
      id="#{domain}-detail"
      domain={#{domain}_domain()}
      connection={@db_connection}
      filters={@current_filters}
      on_row_click={&handle_#{domain}_selected/1}
    />
    ```

    ## Performance Optimization Examples

    ### Efficient Pagination
    ```elixir
    # Cursor-based pagination for better performance
    def get_#{domain}_page(cursor_id \\\\ nil, limit \\\\ 25) do
      base_query = Selecto.select(#{domain}_domain(), [:id, :name, :created_at])
      
      query = case cursor_id do
        nil -> base_query
        id -> Selecto.filter(base_query, :id, :gt, id)
      end
      
      query
      |> Selecto.order_by([{:id, :asc}])
      |> Selecto.limit(limit)
      |> Selecto.execute(MyApp.Repo)
    end
    ```

    ### Batch Operations
    ```elixir
    # Batch loading related data
    def load_#{domain}_with_related(#{domain}_ids) do
      # Load main records
      #{domain}s = 
        Selecto.select(#{domain}_domain(), [:id, :name])
        |> Selecto.filter(:id, :in, #{domain}_ids)
        |> Selecto.execute(MyApp.Repo)
      
      # Load related data in batch
      related_data = 
        Selecto.select(related_domain(), [:#{domain}_id, :name])
        |> Selecto.filter(:#{domain}_id, :in, #{domain}_ids)
        |> Selecto.execute(MyApp.Repo)
        |> Enum.group_by(& &1.#{domain}_id)
      
      # Combine data
      Enum.map(#{domain}s, fn #{domain} ->
        Map.put(#{domain}, :related, Map.get(related_data, #{domain}.id, []))
      end)
    end
    ```

    ## Error Handling Examples

    ### Safe Query Execution
    ```elixir
    def safe_get_#{domain}(id) do
      try do
        result = 
          Selecto.select(#{domain}_domain(), [:id, :name])
          |> Selecto.filter(:id, :eq, id)
          |> Selecto.execute(MyApp.Repo)
        
        case result do
          [#{domain}] -> {:ok, #{domain}}
          [] -> {:error, :not_found}
          _ -> {:error, :multiple_results}
        end
      rescue
        e in [Ecto.Query.CastError] ->
          {:error, {:invalid_id, e.message}}
        e ->
          {:error, {:database_error, e.message}}
      end
    end
    ```

    ### Validation Examples
    ```elixir
    def validate_#{domain}_query(filters) do
      with :ok <- validate_required_fields(filters),
           :ok <- validate_filter_values(filters),
           :ok <- validate_query_complexity(filters) do
        build_#{domain}_query(filters)
      end
    end
    
    defp validate_required_fields(filters) do
      required = [:status]
      missing = required -- Map.keys(filters)
      
      case missing do
        [] -> :ok
        _ -> {:error, {:missing_fields, missing}}
      end
    end
    ```

    ## Testing Examples

    ### Unit Tests for Domain Queries
    ```elixir
    defmodule MyApp.#{String.capitalize(domain)}QueriesTest do
      use MyApp.DataCase
      
      describe "#{domain} domain queries" do
        test "basic selection works" do
          #{domain} = insert(:#{domain})
          
          result = 
            Selecto.select(#{domain}_domain(), [:id, :name])
            |> Selecto.filter(:id, :eq, #{domain}.id)
            |> Selecto.execute(MyApp.Repo)
          
          assert [found_#{domain}] = result
          assert found_#{domain}.id == #{domain}.id
          assert found_#{domain}.name == #{domain}.name
        end
        
        test "filtering by multiple criteria" do
          matching_#{domain} = insert(:#{domain}, status: "active", priority: "high")
          _non_matching = insert(:#{domain}, status: "inactive", priority: "high")
          
          result = 
            Selecto.select(#{domain}_domain(), [:id])
            |> Selecto.filter(:status, :eq, "active")
            |> Selecto.filter(:priority, :eq, "high")
            |> Selecto.execute(MyApp.Repo)
          
          assert length(result) == 1
          assert hd(result).id == matching_#{domain}.id
        end
      end
    end
    ```

    ## Common Patterns and Recipes

    ### Search Functionality
    ```elixir
    def search_#{domain}s(search_term, options \\\\ []) do
      limit = Keyword.get(options, :limit, 50)
      fields = Keyword.get(options, :fields, [:id, :name])
      
      Selecto.select(#{domain}_domain(), fields)
      |> add_search_filters(search_term)
      |> Selecto.order_by([{:name, :asc}])
      |> Selecto.limit(limit)
      |> Selecto.execute(MyApp.Repo)
    end
    
    defp add_search_filters(query, search_term) when is_binary(search_term) do
      search_pattern = "%\#{search_term}%"
      
      Selecto.filter_group(query, :or, [
        {:name, :ilike, search_pattern},
        {:description, :ilike, search_pattern}
      ])
    end
    defp add_search_filters(query, _), do: query
    ```

    ### Dashboard Widgets
    ```elixir
    def #{domain}_dashboard_data do
      %{
        total_count: get_total_#{domain}_count(),
        recent_#{domain}s: get_recent_#{domain}s(5),
        status_breakdown: get_#{domain}_status_breakdown(),
        trend_data: get_#{domain}_trend_data(30)
      }
    end
    
    defp get_total_#{domain}_count do
      Selecto.select(#{domain}_domain(), [:count])
      |> Selecto.aggregate(:count, :id)
      |> Selecto.execute(MyApp.Repo)
      |> hd()
      |> Map.get(:count)
    end
    
    defp get_recent_#{domain}s(limit) do
      Selecto.select(#{domain}_domain(), [:id, :name, :created_at])
      |> Selecto.order_by([{:created_at, :desc}])
      |> Selecto.limit(limit)
      |> Selecto.execute(MyApp.Repo)
    end
    ```

    ## Best Practices Summary

    1. **Always use proper error handling** around database operations
    2. **Limit result sets** to avoid memory issues
    3. **Use indexes** for frequently filtered and ordered fields
    4. **Test with realistic data volumes** to catch performance issues early
    5. **Batch related queries** instead of N+1 query patterns
    6. **Use appropriate field selection** - don't select unnecessary data
    7. **Monitor query performance** in production environments

    For more detailed performance guidance, see the 
    [Performance Guide](#{domain}_performance.md).
    """
  end

  defp generate_markdown_performance(domain, _domain_info) do
    """
    # #{String.capitalize(domain)} Domain Performance Guide

    This document provides comprehensive performance optimization guidance for the
    #{domain} domain, including benchmarking, indexing strategies, and query optimization.

    ## Performance Overview

    The #{domain} domain performance characteristics depend on several factors:
    - Data volume and distribution
    - Query complexity and join patterns  
    - Index coverage and maintenance
    - Database server configuration

    ## Benchmarking Results

    ### Basic Query Performance
    Based on performance testing with representative datasets:

    | Operation | Records | Avg Time | Memory Usage | Recommendations |
    |-----------|---------|----------|--------------|-----------------|
    | Simple Select | 1K | 2ms | 1MB | Optimal |
    | Simple Select | 100K | 15ms | 50MB | Good |
    | Simple Select | 1M | 150ms | 500MB | Consider pagination |
    | Filtered Select | 100K | 8ms | 25MB | Good with index |
    | Join Query | 100K | 45ms | 75MB | Monitor complexity |
    | Aggregation | 1M | 300ms | 100MB | Use materialized views |

    ### Index Impact Analysis
    ```
    Query: SELECT * FROM #{domain} WHERE status = 'active'
    
    Without index: 890ms (full table scan)
    With index:    12ms  (index scan)
    Improvement:   98.7% faster
    ```

    ## Indexing Strategy

    ### Primary Indexes
    Essential indexes for the #{domain} domain:

    ```sql
    -- Primary key (automatic)
    CREATE UNIQUE INDEX #{domain}_pkey ON #{domain} (id);
    
    -- Frequently filtered fields
    CREATE INDEX idx_#{domain}_status ON #{domain} (status);
    CREATE INDEX idx_#{domain}_created_at ON #{domain} (created_at);
    CREATE INDEX idx_#{domain}_name ON #{domain} (name);
    
    -- Foreign keys for joins
    CREATE INDEX idx_#{domain}_category_id ON #{domain} (category_id);
    CREATE INDEX idx_#{domain}_user_id ON #{domain} (user_id);
    ```

    ### Composite Indexes
    For queries with multiple filter conditions:

    ```sql
    -- Common filter combinations
    CREATE INDEX idx_#{domain}_status_date ON #{domain} (status, created_at);
    CREATE INDEX idx_#{domain}_user_status ON #{domain} (user_id, status);
    ```

    ### Partial Indexes
    For selective filtering on large tables:

    ```sql
    -- Only index active records if they're frequently queried
    CREATE INDEX idx_#{domain}_active_name ON #{domain} (name) 
    WHERE status = 'active';
    ```

    ## Query Optimization

    ### Efficient Field Selection
    ```elixir
    # Good - select only needed fields
    Selecto.select(#{domain}_domain(), [:id, :name, :status])
    
    # Avoid - selecting all fields
    Selecto.select(#{domain}_domain(), :all)  # Can be slow with many columns
    ```

    ### Filter Optimization
    ```elixir
    # Good - use indexed fields for filtering
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.filter(:status, :eq, "active")  # Uses index
    
    # Less efficient - function calls in filters
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.filter("UPPER(name)", :like, "PATTERN%")  # No index usage
    ```

    ### Join Optimization
    ```elixir
    # Efficient join order - most selective first
    Selecto.select(#{domain}_domain(), [:id, :name])
    |> Selecto.filter(:status, :eq, "active")          # Reduces result set first
    |> Selecto.join(:inner, :categories, :category_id, :id)  # Then join
    
    # Use appropriate join types
    |> Selecto.join(:left, :optional_data, :id, :#{domain}_id)  # LEFT for optional
    ```

    ## Pagination Strategies

    ### Offset-Based Pagination
    ```elixir
    # Good for small offsets
    def get_#{domain}_page(page, per_page \\\\ 25) do
      offset = (page - 1) * per_page
      
      Selecto.select(#{domain}_domain(), [:id, :name])
      |> Selecto.order_by([{:created_at, :desc}])
      |> Selecto.limit(per_page)
      |> Selecto.offset(offset)
      |> Selecto.execute(MyApp.Repo)
    end
    ```

    ### Cursor-Based Pagination (Recommended)
    ```elixir
    # Better for large datasets
    def get_#{domain}_page_cursor(cursor_id \\\\ nil, limit \\\\ 25) do
      base_query = 
        Selecto.select(#{domain}_domain(), [:id, :name, :created_at])
        |> Selecto.order_by([{:created_at, :desc}, {:id, :desc}])
      
      query = case cursor_id do
        nil -> base_query
        id -> 
          # Get the timestamp of the cursor record for proper ordering
          cursor_time = get_#{domain}_timestamp(id)
          Selecto.filter(base_query, :created_at, :lte, cursor_time)
          |> Selecto.filter(:id, :lt, id)
      end
      
      query |> Selecto.limit(limit) |> Selecto.execute(MyApp.Repo)
    end
    ```

    ## Aggregation Performance

    ### Efficient Grouping
    ```elixir
    # Good - group by indexed fields
    Selecto.select(#{domain}_domain(), [:status, :count])
    |> Selecto.group_by([:status])
    |> Selecto.aggregate(:count, :id)
    
    # Consider materialized views for complex aggregations
    Selecto.select("#{domain}_daily_stats", [:date, :total_count, :avg_score])
    |> Selecto.filter(:date, :gte, Date.add(Date.utc_today(), -30))
    ```

    ### Memory-Efficient Aggregations
    ```elixir
    # Stream large aggregations to avoid memory issues
    def calculate_#{domain}_stats do
      MyApp.Repo.transaction(fn ->
        Selecto.select(#{domain}_domain(), [:category, :score])
        |> Selecto.stream(MyApp.Repo)
        |> Stream.chunk_every(1000)
        |> Enum.reduce(%{}, &process_#{domain}_chunk/2)
      end)
    end
    ```

    ## Caching Strategies

    ### Application-Level Caching
    ```elixir
    def get_cached_#{domain}_summary(cache_key) do
      case Cachex.get(:#{domain}_cache, cache_key) do
        {:ok, nil} ->
          data = calculate_#{domain}_summary()
          Cachex.put(:#{domain}_cache, cache_key, data, ttl: :timer.minutes(15))
          data
        {:ok, cached_data} ->
          cached_data
      end
    end
    ```

    ### Database Query Caching
    ```elixir
    # Use prepared statements for repeated queries
    def get_#{domain}_by_status(status) do
      # This query will be prepared and cached by PostgreSQL
      Selecto.select(#{domain}_domain(), [:id, :name])
      |> Selecto.filter(:status, :eq, status)
      |> Selecto.execute(MyApp.Repo)
    end
    ```

    ## Memory Management

    ### Streaming Large Results
    ```elixir
    def process_all_#{domain}s do
      Selecto.select(#{domain}_domain(), [:id, :name, :data])
      |> Selecto.stream(MyApp.Repo, max_rows: 500)
      |> Stream.map(&process_single_#{domain}/1)
      |> Stream.run()
    end
    ```

    ### Batch Processing
    ```elixir
    def update_#{domain}_batch(#{domain}_ids, updates) do
      #{domain}_ids
      |> Enum.chunk_every(100)
      |> Enum.each(fn batch ->
        Selecto.select(#{domain}_domain(), [:id])
        |> Selecto.filter(:id, :in, batch)
        |> Selecto.update(updates)
        |> Selecto.execute(MyApp.Repo)
      end)
    end
    ```

    ## Monitoring and Profiling

    ### Query Performance Monitoring
    ```elixir
    def profile_#{domain}_query(query_func) do
      {time_microseconds, result} = :timer.tc(query_func)
      time_ms = time_microseconds / 1000
      
      Logger.info("#{domain} query completed in \#{time_ms}ms")
      
      if time_ms > 100 do
        Logger.warn("Slow #{domain} query detected: \#{time_ms}ms")
      end
      
      result
    end
    ```

    ### Database Metrics Collection
    ```elixir
    # Monitor query patterns and performance
    def log_query_metrics(query, execution_time) do
      MyApp.Telemetry.execute([:#{domain}, :query], %{
        duration: execution_time,
        result_count: length(query.result)
      }, %{
        query_type: classify_query_type(query),
        has_joins: has_joins?(query)
      })
    end
    ```

    ## Production Optimization

    ### Connection Pool Tuning
    ```elixir
    # In config/prod.exs
    config :my_app, MyApp.Repo,
      pool_size: 20,              # Adjust based on concurrent users
      queue_target: 50,           # Queue time before spawning new connection
      queue_interval: 1000,       # Check queue every second
      timeout: 15_000,            # Query timeout
      ownership_timeout: 60_000   # Connection checkout timeout
    ```

    ### Database Configuration
    ```sql
    -- PostgreSQL optimization for #{domain} workload
    SET shared_buffers = '1GB';              -- Adjust to available RAM
    SET effective_cache_size = '3GB';        -- Total available cache
    SET work_mem = '256MB';                  -- Per-operation memory
    SET maintenance_work_mem = '512MB';      -- For index operations
    SET random_page_cost = 1.1;              -- SSD optimization
    ```

    ## Performance Testing

    ### Load Testing
    ```elixir
    defmodule #{String.capitalize(domain)}PerformanceTest do
      use ExUnit.Case
      
      @tag :performance
      test "#{domain} query performance under load" do
        tasks = for i <- 1..100 do
          Task.async(fn ->
            Selecto.select(#{domain}_domain(), [:id, :name])
            |> Selecto.filter(:status, :eq, "active")
            |> Selecto.limit(50)
            |> Selecto.execute(MyApp.Repo)
          end)
        end
        
        results = Task.await_many(tasks, 30_000)
        
        # Verify all queries completed successfully
        assert length(results) == 100
        Enum.each(results, fn result ->
          assert is_list(result)
          assert length(result) <= 50
        end)
      end
    end
    ```

    ### Benchmarking Utilities
    ```elixir
    def benchmark_#{domain}_operations do
      Benchee.run(%{
        "simple_select" => fn ->
          Selecto.select(#{domain}_domain(), [:id, :name])
          |> Selecto.limit(100)
          |> Selecto.execute(MyApp.Repo)
        end,
        
        "filtered_select" => fn ->
          Selecto.select(#{domain}_domain(), [:id, :name])
          |> Selecto.filter(:status, :eq, "active")
          |> Selecto.limit(100)
          |> Selecto.execute(MyApp.Repo)
        end,
        
        "join_query" => fn ->
          Selecto.select(#{domain}_domain(), [:id, :name, "categories.name"])
          |> Selecto.join(:inner, :categories, :category_id, :id)
          |> Selecto.limit(100)
          |> Selecto.execute(MyApp.Repo)
        end
      })
    end
    ```

    ## Troubleshooting Performance Issues

    ### Common Problems and Solutions

    **Slow Queries**
    1. Check `EXPLAIN ANALYZE` output for the query
    2. Verify appropriate indexes exist
    3. Consider query restructuring or breaking into smaller operations
    4. Check for N+1 query patterns

    **High Memory Usage**
    1. Implement result streaming for large datasets
    2. Use pagination instead of loading all results
    3. Optimize field selection to reduce row size
    4. Monitor connection pool usage

    **Connection Pool Exhaustion**
    1. Increase pool size if needed
    2. Optimize long-running queries
    3. Implement connection pooling monitoring
    4. Use connection multiplexing where appropriate

    ### Performance Monitoring Queries
    ```sql
    -- Find slowest queries
    SELECT query, calls, total_time, mean_time
    FROM pg_stat_statements
    WHERE query LIKE '%#{domain}%'
    ORDER BY total_time DESC
    LIMIT 10;
    
    -- Check index usage
    SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read
    FROM pg_stat_user_indexes
    WHERE tablename = '#{domain}'
    ORDER BY idx_scan DESC;
    ```

    ## Best Practices Summary

    1. **Always profile queries** in environments similar to production
    2. **Use appropriate indexes** for your query patterns
    3. **Implement pagination** for large result sets
    4. **Monitor query performance** continuously
    5. **Cache frequently accessed data** appropriately
    6. **Use connection pooling** effectively
    7. **Test with realistic data volumes** during development
    8. **Optimize based on actual usage patterns**, not assumptions

    ## Additional Resources

    - [PostgreSQL Performance Tuning Guide](https://wiki.postgresql.org/wiki/Performance_Optimization)
    - [Ecto Performance Tips](https://hexdocs.pm/ecto/Ecto.html#module-performance-tips)
    - [Elixir Performance Monitoring](https://hexdocs.pm/telemetry/readme.html)
    """
  end

  defp generate_livebook_content(domain, domain_info) do
    """
    # #{String.capitalize(domain)} Domain Interactive Tutorial

    ```elixir
    Mix.install([
      {:selecto, "~> 0.2.6"},
      {:selecto_kino, path: "../vendor/selecto_kino"},
      {:postgrex, "~> 0.17.0"},
      {:kino, "~> 0.12.0"}
    ])
    ```

    ## Introduction

    Welcome to the interactive #{domain} domain tutorial! This Livebook will guide you through
    exploring and working with the #{domain} domain configuration.

    ## Database Connection

    First, let's establish a connection to your database:

    ```elixir
    # Configure your database connection
    db_config = [
      hostname: "localhost",
      port: 5432,
      username: "postgres", 
      password: "postgres",
      database: "selecto_test_dev"
    ]

    {:ok, conn} = Postgrex.start_link(db_config)
    ```

    ## Domain Overview

    Let's load the #{domain} domain configuration:

    ```elixir
    # This would load your actual domain configuration
    #{domain}_domain = %{
      source: %{
        source_table: "#{domain}",
        primary_key: :id,
        fields: #{inspect(domain_info.source.fields)},
        columns: #{inspect(domain_info.source.types)}
      }
    }

    IO.inspect(#{domain}_domain, label: "#{String.capitalize(domain)} Domain")
    ```

    ## Interactive Domain Builder

    Use SelectoKino to visually explore and modify your domain:

    ```elixir
    SelectoKino.domain_builder(#{domain}_domain)
    ```

    ## Basic Queries

    Let's start with some basic queries:

    ### Simple Selection
    ```elixir
    # Select basic fields
    basic_query = 
      Selecto.select(#{domain}_domain, [:id, :name])
      |> Selecto.limit(10)

    # Execute and display results
    results = Selecto.execute(basic_query, conn)
    Kino.DataTable.new(results)
    ```

    ### Filtering Data
    ```elixir
    # Interactive filter builder
    SelectoKino.filter_builder(#{domain}_domain)
    ```

    ```elixir
    # Apply filters based on the filter builder above
    filtered_query = 
      Selecto.select(#{domain}_domain, [:id, :name, :created_at])
      |> Selecto.filter(:name, :like, "%example%")
      |> Selecto.limit(25)

    filtered_results = Selecto.execute(filtered_query, conn)
    Kino.DataTable.new(filtered_results)
    ```

    ## Aggregation Examples

    ### Basic Aggregations
    ```elixir
    # Count total records
    count_query = 
      Selecto.select(#{domain}_domain, [:count])
      |> Selecto.aggregate(:count, :id)

    count_result = Selecto.execute(count_query, conn)
    IO.inspect(count_result, label: "Total #{domain} count")
    ```

    ### Grouped Aggregations
    ```elixir
    # Group by a field and count
    grouped_query = 
      Selecto.select(#{domain}_domain, [:category, :count])
      |> Selecto.group_by([:category])
      |> Selecto.aggregate(:count, :id)
      |> Selecto.order_by([{:count, :desc}])

    grouped_results = Selecto.execute(grouped_query, conn)
    Kino.DataTable.new(grouped_results)
    ```

    ## Visual Query Builder

    Use the enhanced query builder for complex queries:

    ```elixir
    SelectoKino.enhanced_query_builder(#{domain}_domain, conn)
    ```

    ## Performance Analysis

    Monitor query performance in real-time:

    ```elixir
    SelectoKino.performance_monitor(#{domain}_domain, conn)
    ```

    ### Query Benchmarking
    ```elixir
    # Benchmark different query approaches
    queries_to_benchmark = [
      {"Simple select", fn -> 
        Selecto.select(#{domain}_domain, [:id, :name])
        |> Selecto.limit(100)
        |> Selecto.execute(conn)
      end},
      
      {"Filtered select", fn -> 
        Selecto.select(#{domain}_domain, [:id, :name])
        |> Selecto.filter(:status, :eq, "active")
        |> Selecto.limit(100)
        |> Selecto.execute(conn)
      end},
      
      {"Aggregation", fn -> 
        Selecto.select(#{domain}_domain, [:category, :count])
        |> Selecto.group_by([:category])
        |> Selecto.aggregate(:count, :id)
        |> Selecto.execute(conn)
      end}
    ]

    Enum.each(queries_to_benchmark, fn {name, query_func} ->
      {time_microseconds, result} = :timer.tc(query_func)
      time_ms = time_microseconds / 1000
      result_count = length(result)
      
      IO.puts("**\#{name}**: \#{time_ms}ms, \#{result_count} results")
    end)
    ```

    ## Data Visualization

    Create visualizations of your data:

    ```elixir
    # Get data for visualization
    viz_data = 
      Selecto.select(#{domain}_domain, [:created_at, :status])
      |> Selecto.filter(:created_at, :gte, Date.add(Date.utc_today(), -30))
      |> Selecto.execute(conn)

    # Group by date and status
    daily_counts = 
      viz_data
      |> Enum.group_by(fn row -> {Date.from_iso8601!(row.created_at), row.status} end)
      |> Enum.map(fn {{date, status}, rows} -> %{date: date, status: status, count: length(rows)} end)

    Kino.DataTable.new(daily_counts)
    ```

    ## Live Data Exploration

    Explore your data interactively:

    ```elixir
    # Create an interactive data explorer
    input_form = 
      Kino.Control.form([
        limit: Kino.Input.number("Limit", default: 25),
        search: Kino.Input.text("Search term"),
        status_filter: Kino.Input.select("Status", options: [
          {"All", nil},
          {"Active", "active"},
          {"Inactive", "inactive"}
        ])
      ],
      submit: "Load Data"
    )

    Kino.render(input_form)

    # React to form changes
    input_form
    |> Kino.Control.stream()
    |> Kino.animate(fn %{data: %{limit: limit, search: search, status_filter: status}} ->
      query = Selecto.select(#{domain}_domain, [:id, :name, :status, :created_at])
      
      query = if search != "", do: Selecto.filter(query, :name, :ilike, "%\#{search}%"), else: query
      query = if status, do: Selecto.filter(query, :status, :eq, status), else: query
      query = Selecto.limit(query, limit)
      
      results = Selecto.execute(query, conn)
      Kino.DataTable.new(results)
    end)
    ```

    ## Join Exploration

    Explore join relationships:

    ```elixir
    SelectoKino.join_designer(#{domain}_domain)
    ```

    ## Domain Configuration Export

    Export your customized domain configuration:

    ```elixir
    SelectoKino.domain_exporter(#{domain}_domain)
    ```

    ## Advanced Topics

    ### Custom Aggregation Functions
    ```elixir
    # Example of custom SQL in aggregations
    advanced_stats = 
      Selecto.select(#{domain}_domain, [
        "COUNT(*) as total_count",
        "COUNT(DISTINCT status) as status_variety", 
        "MIN(created_at) as oldest_record",
        "MAX(created_at) as newest_record"
      ])
      |> Selecto.execute(conn)

    Kino.DataTable.new(advanced_stats)
    ```

    ### Subqueries and CTEs
    ```elixir
    # Example of more complex query patterns
    # (This would require extending Selecto's CTE support)
    ```

    ## Performance Optimization

    Use the performance analyzer to optimize your queries:

    ```elixir
    SelectoKino.join_analyzer(#{domain}_domain, conn)
    ```

    ## Next Steps

    This tutorial covered the basics of working with the #{domain} domain. For more advanced
    topics, check out:

    - [#{String.capitalize(domain)} Field Reference](#{domain}_fields.md)
    - [#{String.capitalize(domain)} Join Guide](#{domain}_joins.md)
    - [#{String.capitalize(domain)} Performance Guide](#{domain}_performance.md)

    ## Cleanup

    ```elixir
    # Close the database connection
    GenServer.stop(conn)
    ```
    """
  end

  defp generate_interactive_html_content(domain, _domain_info) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{String.capitalize(domain)} Domain Interactive Guide</title>
        <script src="https://unpkg.com/alpine@3.x.x/dist/cdn.min.js" defer></script>
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
            [x-cloak] { display: none !important; }
        </style>
    </head>
    <body class="bg-gray-100 min-h-screen py-8">
        <div class="container mx-auto px-4 max-w-6xl">
            <h1 class="text-4xl font-bold text-gray-800 mb-8">#{String.capitalize(domain)} Domain Interactive Guide</h1>
            
            <!-- Query Builder Section -->
            <div x-data="queryBuilder()" class="bg-white rounded-lg shadow-md p-6 mb-8">
                <h2 class="text-2xl font-semibold mb-4">Interactive Query Builder</h2>
                
                <!-- Field Selection -->
                <div class="mb-6">
                    <label class="block text-sm font-medium text-gray-700 mb-2">Select Fields:</label>
                    <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
                        <template x-for="field in availableFields" :key="field">
                            <label class="flex items-center">
                                <input type="checkbox" :value="field" x-model="selectedFields" class="mr-2">
                                <span x-text="field" class="text-sm"></span>
                            </label>
                        </template>
                    </div>
                </div>
                
                <!-- Filters -->
                <div class="mb-6">
                    <label class="block text-sm font-medium text-gray-700 mb-2">Filters:</label>
                    <div class="space-y-2">
                        <template x-for="(filter, index) in filters" :key="index">
                            <div class="flex items-center space-x-2">
                                <select x-model="filter.field" class="border rounded px-2 py-1">
                                    <option value="">Select field...</option>
                                    <template x-for="field in availableFields" :key="field">
                                        <option :value="field" x-text="field"></option>
                                    </template>
                                </select>
                                <select x-model="filter.operator" class="border rounded px-2 py-1">
                                    <option value="eq">equals</option>
                                    <option value="ne">not equals</option>
                                    <option value="gt">greater than</option>
                                    <option value="lt">less than</option>
                                    <option value="like">contains</option>
                                </select>
                                <input type="text" x-model="filter.value" placeholder="Value..." 
                                       class="border rounded px-2 py-1 flex-1">
                                <button @click="removeFilter(index)" class="bg-red-500 text-white px-2 py-1 rounded text-sm">
                                    Remove
                                </button>
                            </div>
                        </template>
                    </div>
                    <button @click="addFilter()" class="mt-2 bg-blue-500 text-white px-3 py-1 rounded text-sm">
                        Add Filter
                    </button>
                </div>
                
                <!-- Limit -->
                <div class="mb-6">
                    <label class="block text-sm font-medium text-gray-700 mb-2">Limit:</label>
                    <input type="number" x-model.number="limit" min="1" max="1000" 
                           class="border rounded px-2 py-1 w-24">
                </div>
                
                <!-- Generated Query -->
                <div class="mb-6">
                    <h3 class="text-lg font-medium mb-2">Generated Elixir Code:</h3>
                    <pre class="bg-gray-800 text-green-400 p-4 rounded overflow-x-auto text-sm" x-text="generatedQuery"></pre>
                </div>
                
                <!-- Simulate Query Button -->
                <button @click="simulateQuery()" class="bg-green-500 text-white px-4 py-2 rounded">
                    Simulate Query
                </button>
                
                <!-- Results -->
                <div x-show="results.length > 0" class="mt-6">
                    <h3 class="text-lg font-medium mb-2">Simulated Results:</h3>
                    <div class="overflow-x-auto">
                        <table class="min-w-full bg-white border">
                            <thead class="bg-gray-50">
                                <tr>
                                    <template x-for="field in selectedFields" :key="field">
                                        <th class="px-4 py-2 text-left text-sm font-medium text-gray-700" x-text="field"></th>
                                    </template>
                                </tr>
                            </thead>
                            <tbody>
                                <template x-for="(row, index) in results" :key="index">
                                    <tr class="border-t">
                                        <template x-for="field in selectedFields" :key="field">
                                            <td class="px-4 py-2 text-sm text-gray-900" x-text="row[field] || 'N/A'"></td>
                                        </template>
                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
            
            <!-- Documentation Links -->
            <div class="bg-white rounded-lg shadow-md p-6">
                <h2 class="text-2xl font-semibold mb-4">Documentation Links</h2>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <a href="#{domain}_overview.md" class="block p-4 border rounded-lg hover:bg-gray-50">
                        <h3 class="font-medium">Domain Overview</h3>
                        <p class="text-sm text-gray-600">Complete domain structure and usage</p>
                    </a>
                    <a href="#{domain}_fields.md" class="block p-4 border rounded-lg hover:bg-gray-50">
                        <h3 class="font-medium">Field Reference</h3>
                        <p class="text-sm text-gray-600">All available fields and types</p>
                    </a>
                    <a href="#{domain}_joins.md" class="block p-4 border rounded-lg hover:bg-gray-50">
                        <h3 class="font-medium">Joins Guide</h3>
                        <p class="text-sm text-gray-600">Join relationships and optimization</p>
                    </a>
                    <a href="#{domain}_examples.md" class="block p-4 border rounded-lg hover:bg-gray-50">
                        <h3 class="font-medium">Examples</h3>
                        <p class="text-sm text-gray-600">Code examples and patterns</p>
                    </a>
                </div>
            </div>
        </div>
        
        <script>
            function queryBuilder() {
                return {
                    availableFields: ['id', 'name', 'status', 'created_at', 'updated_at'],
                    selectedFields: ['id', 'name'],
                    filters: [],
                    limit: 25,
                    results: [],
                    
                    get generatedQuery() {
                        let query = `Selecto.select(#{domain}_domain(), [\${this.selectedFields.map(f => ':' + f).join(', ')}])`;
                        
                        this.filters.forEach(filter => {
                            if (filter.field && filter.operator && filter.value) {
                                query += `\\n|> Selecto.filter(:\${filter.field}, :\${filter.operator}, "\${filter.value}")`;
                            }
                        });
                        
                        query += `\\n|> Selecto.limit(\${this.limit})`;
                        query += `\\n|> Selecto.execute(MyApp.Repo)`;
                        
                        return query;
                    },
                    
                    addFilter() {
                        this.filters.push({ field: '', operator: 'eq', value: '' });
                    },
                    
                    removeFilter(index) {
                        this.filters.splice(index, 1);
                    },
                    
                    simulateQuery() {
                        // Generate mock results based on selected fields
                        this.results = Array.from({ length: Math.min(this.limit, 10) }, (_, i) => {
                            const row = {};
                            this.selectedFields.forEach(field => {
                                switch(field) {
                                    case 'id':
                                        row[field] = i + 1;
                                        break;
                                    case 'name':
                                        row[field] = `Sample \${field} \${i + 1}`;
                                        break;
                                    case 'status':
                                        row[field] = ['active', 'inactive', 'pending'][i % 3];
                                        break;
                                    case 'created_at':
                                    case 'updated_at':
                                        const date = new Date();
                                        date.setDate(date.getDate() - i);
                                        row[field] = date.toISOString().split('T')[0];
                                        break;
                                    default:
                                        row[field] = `Sample data \${i + 1}`;
                                }
                            });
                            return row;
                        });
                    }
                }
            }
        </script>
    </body>
    </html>
    """
  end

  # Helper functions for generating content

  defp generate_field_list(fields, types) do
    Enum.map(fields, fn field ->
      type = Map.get(types, field, :unknown)
      "- **#{field}** (`#{type}`)"
    end)
    |> Enum.join("\n")
  end

  defp generate_detailed_field_reference(fields, types) do
    Enum.map(fields, fn field ->
      type = Map.get(types, field, :unknown)
      
      description = case field do
        :id -> "Unique identifier for the record"
        :name -> "Display name or title"
        :created_at -> "Timestamp when the record was created"
        :updated_at -> "Timestamp when the record was last updated"
        _ -> "Field description (customize based on your domain)"
      end
      
      examples = case type do
        :integer -> "Example: `42`, `1000`"
        :string -> "Example: `\"Sample Name\"`, `\"Category A\"`"
        :datetime -> "Example: `~U[2024-01-15 10:30:00Z]`"
        _ -> "Example values depend on field type"
      end
      
      """
      ### #{field}
      
      - **Type**: `#{type}`
      - **Description**: #{description}
      - **#{examples}
      
      """
    end)
    |> Enum.join("\n")
  end

  defp generate_joins_documentation(joins) when length(joins) == 0 do
    """
    No predefined joins are configured for this domain. You can create custom joins
    using the Selecto join API:
    
    ```elixir
    # Example custom join
    Selecto.select(your_domain(), [:id, :name])
    |> Selecto.join(:inner, :related_table, :foreign_key_id, :id)
    ```
    """
  end

  defp generate_joins_documentation(joins) do
    Enum.map(joins, fn join ->
      """
      ### #{join.name}
      
      - **Type**: #{join.type}
      - **Target Table**: `#{join.target_table}`
      - **Join Condition**: `#{join.condition}`
      - **Description**: #{join.description}
      
      ```elixir
      # Usage example
      Selecto.select(domain(), [:id, :name])
      |> Selecto.join(:#{join.type}, :#{join.target_table}, :#{join.local_key}, :#{join.foreign_key})
      ```
      """
    end)
    |> Enum.join("\n")
  end

  # HTML generation functions (similar structure to markdown but with HTML tags)

  defp generate_html_overview(_domain, _domain_info) do
    "<!-- HTML version would be generated here -->"
  end

  defp generate_html_fields(_domain, _domain_info) do
    "<!-- HTML fields reference would be generated here -->"
  end

  defp generate_html_joins(_domain, _domain_info) do
    "<!-- HTML joins guide would be generated here -->"
  end

  defp generate_html_examples(_domain, _domain_info, _opts) do
    "<!-- HTML examples would be generated here -->"
  end

  defp generate_html_performance(_domain, _domain_info) do
    "<!-- HTML performance guide would be generated here -->"
  end
end