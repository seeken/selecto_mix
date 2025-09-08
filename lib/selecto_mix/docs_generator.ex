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
      :exs -> generate_executable_examples(domain, domain_info, opts)
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
    # Try to get actual domain configuration
    domain_module = try_get_domain_module(domain)
    
    if domain_module && function_exported?(domain_module, :domain, 0) do
      # Get actual configuration from the domain module
      config = domain_module.domain()
      source = config[:source] || %{}
      
      %{
        table: source[:source_table] || "#{domain}",
        primary_key: source[:primary_key] || :id,
        fields: source[:fields] || get_default_fields(source[:fields]),
        types: source[:columns] || get_default_types(source[:columns]),
        associations: source[:associations] || %{}
      }
    else
      # Fall back to minimal defaults if domain module doesn't exist
      %{
        table: "#{domain}",
        primary_key: :id,
        fields: [:id],
        types: %{id: :integer},
        associations: %{}
      }
    end
  end
  
  defp try_get_domain_module(domain) do
    # Try to find the domain module
    # First try SelectoNorthwind.SelectoDomains.{Domain}Domain
    # Convert atom to string if needed
    domain_string = to_string(domain)
    module_name = "Elixir.SelectoNorthwind.SelectoDomains.#{String.capitalize(domain_string)}Domain"
    
    case Code.ensure_compiled(String.to_atom(module_name)) do
      {:module, module} -> module
      _ -> nil
    end
  end
  
  defp get_default_fields(fields) when is_list(fields) do
    # Just take the first few fields from what's actually available
    # Always include :id if present, then take up to 3-4 more fields
    id_field = if :id in fields, do: [:id], else: []
    other_fields = fields
                   |> Enum.reject(&(&1 == :id))
                   |> Enum.take(3)
    
    id_field ++ other_fields
  end
  defp get_default_fields(_) do
    # Fallback if fields aren't a list
    [:id]
  end
  
  defp get_default_types(types) when is_map(types) do
    # Just return the actual types map from the domain
    types
  end
  defp get_default_types(_) do
    # Minimal fallback
    %{id: :integer}
  end

  defp analyze_related_schemas(domain) do
    # Try to get actual domain configuration
    domain_module = try_get_domain_module(domain)
    
    if domain_module && function_exported?(domain_module, :domain, 0) do
      # Get actual configuration from the domain module
      config = domain_module.domain()
      config[:schemas] || %{}
    else
      %{}
    end
  end

  defp analyze_join_relationships(domain) do
    # Try to get actual domain configuration
    domain_module = try_get_domain_module(domain)
    
    if domain_module && function_exported?(domain_module, :domain, 0) do
      # Get actual configuration from the domain module
      config = domain_module.domain()
      config[:joins] || %{}
    else
      %{}
    end
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

    ## Configuration

    ```elixir
    # Get the domain configuration from your generated domain module
    domain = SelectoNorthwind.SelectoDomains.#{String.capitalize(domain)}Domain.domain()
    
    # Configure Selecto to use your Repo
    selecto = Selecto.configure(domain, SelectoNorthwind.Repo)
    ```

    ## Usage Patterns

    The #{domain} domain supports the following common usage patterns:

    ### Basic Queries
    ```elixir
    # Select all records
    selecto
    |> Selecto.select([:id, :name])

    # Filter by specific criteria
    selecto
    |> Selecto.select([:id, :name])
    |> Selecto.filter([{:name, {:eq, "example"}}])
    ```

    ### Aggregations
    ```elixir
    # Count records using proper Selecto syntax
    selecto
    |> Selecto.select([{:field, {:count, "id"}, "total_count"}])
    |> Selecto.execute()

    # Group by fields with aggregation
    selecto
    |> Selecto.select([:name, {:field, {:count, "id"}, "count"}])
    |> Selecto.group_by([:name])
    |> Selecto.execute()
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
        selecto
    |> Selecto.select( [:id, :name])
        |> Selecto.limit(10)
        |> Selecto.execute(SelectoNorthwind.Repo)

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
    selecto
    |> Selecto.select( [:id, :name])

    # Select all fields
    selecto
    |> Selecto.select( :all)
    ```

    ### Field Filtering
    ```elixir
    # String field filtering
    selecto
    |> Selecto.select([:id, :name])
    |> Selecto.filter([{:name, {:like, "%example%"}}])

    # Numeric field filtering
    selecto
    |> Selecto.select([:id, :name])
    |> Selecto.filter([{:id, {:gt, 100}}])

    # Date field filtering
    selecto
    |> Selecto.select([:id, :created_at])
    |> Selecto.filter([{:created_at, {:gt, ~D[2024-01-01]}}])
    ```

    ### Field Aggregations
    ```elixir
    # Count distinct values using proper Selecto syntax
    selecto
    |> Selecto.select([:name, {:field, {:count, "id"}, "count"}])
    |> Selecto.group_by([:name])
    |> Selecto.execute()

    # Calculate averages (numeric fields only)
    selecto
    |> Selecto.select([{:field, {:avg, "numeric_field"}, "avg_value"}])
    |> Selecto.execute()
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
    # #{String.capitalize(domain)} Domain Relationships Guide

    This document explains how Selecto automatically handles relationships and joins
    in the #{domain} domain through intelligent field selection.

    ## How Joins Work in Selecto

    **Selecto automatically infers joins based on the fields you select.** There are no explicit
    join functions - instead, when you reference fields from related tables using dot notation,
    Selecto automatically creates the necessary joins.

    ## Available Relationships

    #{generate_joins_documentation(domain_info.joins)}

    ## Accessing Related Data

    ### Basic Relationship Access
    ```elixir
    # Selecto automatically joins when you reference related fields
    selecto
    |> Selecto.select([:id, :product_name, "category.category_name", "supplier.company_name"])
    |> Selecto.execute()
    # Selecto automatically creates the necessary joins to categories and suppliers tables
    ```

    ### Filtering on Related Fields
    ```elixir
    # Filter by related table fields - joins are automatic
    selecto
    |> Selecto.select([:id, :product_name])
    |> Selecto.filter([{"category.category_name", {:eq, "Beverages"}}])
    |> Selecto.execute()
    # Selecto automatically joins to categories table when filtering
    ```

    ### Multiple Relationship Access
    ```elixir
    # Access multiple relationships - all joins handled automatically
    selecto
    |> Selecto.select([
      :id, 
      :product_name,
      "category.category_name",
      "supplier.company_name",
      "supplier.country"
    ])
    |> Selecto.filter([
      {"category.category_name", {:like, "%Food%"}},
      {"supplier.country", {:eq, "USA"}}
    ])
    |> Selecto.execute()
    ```

    ## Relationship Types Handled

    ### One-to-Many Relationships
    When the domain has a foreign key to another table:
    
    ```elixir
    # Product belongs to Category (via category_id)
    selecto
    |> Selecto.select([:product_name, "category.category_name"])
    |> Selecto.execute()
    ```

    ### Many-to-One Relationships  
    When other tables reference this domain:
    
    ```elixir
    # Access order details that reference this product
    selecto
    |> Selecto.select([:product_name, "order_details.quantity", "order_details.unit_price"])
    |> Selecto.execute()
    ```

    ### Many-to-Many Relationships
    Through junction tables (when configured in the domain):

    ```elixir
    # Access data through a junction table
    selecto
    |> Selecto.select([:product_name, "product_tags.tag_name"])
    |> Selecto.execute()
    ```

    ## Performance Optimization

    ### Index Usage
    Ensure proper indexes exist on foreign key columns that Selecto will use for joins:
    
    ```sql
    -- Example indexes for relationship columns
    CREATE INDEX idx_#{domain}_category_id ON #{domain} (category_id);
    CREATE INDEX idx_#{domain}_supplier_id ON #{domain} (supplier_id);
    ```

    ### Query Optimization Tips
    - **Filter early**: Apply filters to reduce the dataset before accessing related fields
    - **Select only needed fields**: Don't select all columns if you only need a few
    - **Use aggregations wisely**: When accessing one-to-many relationships, consider using aggregations

    ```elixir
    # Efficient: Filter before accessing related data
    selecto
    |> Selecto.filter([{:discontinued, {:eq, false}}])
    |> Selecto.select([:product_name, "category.category_name"])
    |> Selecto.limit(100)
    |> Selecto.execute()
    ```

    ## Common Patterns

    ### Aggregating Related Data
    ```elixir
    # Count related records using proper Selecto syntax
    selecto
    |> Selecto.select([
      :product_name,
      {:field, {:count, "order_details.id"}, "total_orders"}
    ])
    |> Selecto.group_by([:id, :product_name])
    |> Selecto.execute()
    ```

    ### Filtering by Relationship Existence
    ```elixir
    # Products that have been ordered (using EXISTS semantics)
    selecto
    |> Selecto.select([:product_name])
    |> Selecto.filter([{"order_details.id", {:is_not_null, nil}}])
    |> Selecto.distinct()
    |> Selecto.execute()
    ```

    ### Complex Relationship Queries
    ```elixir
    # Products with their category and supplier, filtered by both
    selecto
    |> Selecto.select([
      :product_name,
      :unit_price,
      "category.category_name",
      "supplier.company_name",
      "supplier.country"
    ])
    |> Selecto.filter([
      {"category.category_name", {:in, ["Beverages", "Dairy Products"]}},
      {"supplier.country", {:in, ["USA", "UK", "France"]}}
    ])
    |> Selecto.order_by([{"category.category_name", :asc}, {:product_name, :asc}])
    |> Selecto.execute()
    ```

    ## Troubleshooting

    ### Common Issues

    **Ambiguous column names**: When multiple tables have the same column name:
    ```elixir
    # Be specific with table prefixes when needed
    selecto
    |> Selecto.select(["products.id", "categories.id as category_id"])
    |> Selecto.execute()
    ```

    **Performance with multiple relationships**: 
    - Consider breaking complex queries into multiple simpler ones
    - Use database query analysis tools to understand the generated SQL
    - Monitor query execution time in production

    ### Performance Issues

    **Slow queries with relationships**: 
    
    1. Check for appropriate indexes on foreign key columns
    2. Use database EXPLAIN to understand the query plan
    3. Consider limiting the number of relationships accessed in a single query
    4. Use field selection to avoid fetching unnecessary columns

    **Memory Issues**: Large result sets from relationship queries can cause memory problems.
    
    1. Use pagination with `limit` and `offset`
    2. Apply filters to reduce the dataset size
    3. Consider streaming results for large datasets

    ## Best Practices

    1. **Index foreign key columns** - Critical for relationship performance  
    2. **Select only needed fields** - Reduces data transfer and memory usage
    3. **Filter early** - Apply filters before accessing related data
    4. **Test with realistic data volumes** - Performance characteristics change with scale
    5. **Monitor query performance** - Use database profiling tools regularly
    6. **Understand your data** - Know which relationships will multiply rows

    ## Understanding the Generated SQL

    Selecto generates efficient SQL with appropriate JOIN clauses based on your field selections.
    Use logging or debugging to see the actual SQL being generated:

    ```elixir
    # Enable query logging to see the generated SQL
    selecto
    |> Selecto.select([:product_name, "category.category_name"])
    |> Selecto.to_sql()  # Returns the SQL string for inspection
    ```

    ## Related Documentation

    - [Performance Guide](#{domain}_performance.md) - Detailed performance optimization
    - [Examples](#{domain}_examples.md) - Real-world relationship examples
    - [Field Reference](#{domain}_fields.md) - Available fields and relationships
    """
  end

  defp generate_markdown_examples(domain, domain_info, _opts) do
    # Get actual fields from domain_info
    fields = domain_info.source.fields
    
    # Pick appropriate fields for examples based on type
    string_field = find_field_by_type(fields, domain_info.source.types, :string) || :name
    _numeric_field = find_field_by_type(fields, domain_info.source.types, [:integer, :decimal]) || :id
    date_field = find_field_by_type(fields, domain_info.source.types, [:date, :datetime, :naive_datetime]) || :inserted_at
    boolean_field = find_field_by_type(fields, domain_info.source.types, :boolean)
    
    # Pick 2-3 main fields for basic examples (prefer name fields)
    main_fields = pick_main_fields(fields, domain_info.source.types)
    """
    # #{String.capitalize(domain)} Domain Examples

    This document provides practical examples of using the #{domain} domain for
    common data querying and visualization scenarios.

    ## Configuration

    First, get the domain configuration and configure Selecto:

    ```elixir
    # Get the domain configuration from your generated domain module
    domain = SelectoNorthwind.SelectoDomains.#{String.capitalize(domain)}Domain.domain()
    
    # Configure Selecto to use your Repo
    selecto = Selecto.configure(domain, SelectoNorthwind.Repo)
    ```

    ## Basic Operations

    ### Simple Data Retrieval
    ```elixir
    # Get all records with basic fields
    selecto
    |> Selecto.select(#{inspect(main_fields)})
    |> Selecto.limit(50)
    |> Selecto.execute()

    # Get single record by ID
    selecto
    |> Selecto.select(#{inspect(main_fields ++ [date_field])})
    |> Selecto.filter([{:id, {:eq, 123}}])
    |> Selecto.execute()
    |> List.first()
    ```

    ### Filtering Examples
    ```elixir
    # String filtering
    selecto
    |> Selecto.select(#{inspect(main_fields)})
    |> Selecto.filter([{#{inspect(string_field)}, {:like, "%search%"}}])
    |> Selecto.execute()

    # Multiple filters with AND logic
    selecto
    |> Selecto.select(#{inspect(main_fields ++ [date_field])})
    |> Selecto.filter([
      {#{inspect(string_field)}, {:like, "%active%"}},
      {#{inspect(date_field)}, {:gte, #{get_date_literal_for_field(date_field, domain_info.source.types)}}}
    ])
    |> Selecto.execute()
    #{if boolean_field do """

      # Boolean field filtering
      selecto
      |> Selecto.select(#{inspect(main_fields)})
      |> Selecto.filter([{#{inspect(boolean_field)}, {:eq, true}}])
      |> Selecto.execute()
      """ else "" end}
    ```

    ## Aggregation Examples

    ### Basic Aggregations
    ```elixir
    # Count total records using proper Selecto syntax
    selecto
    |> Selecto.select([{:field, {:count, "id"}, "total"}])
    |> Selecto.execute()
    
    # Group by with count
    selecto
    |> Selecto.select([#{inspect(string_field)}, {:field, {:count, "id"}, "product_count"}])
    |> Selecto.group_by([#{inspect(string_field)}])
    |> Selecto.execute()
    ```

    ### Complex Aggregations  
    ```elixir
    # Multiple aggregation functions with proper Selecto syntax
    selecto
    |> Selecto.select([
      "category_id",
      {:field, {:count, "id"}, "total_count"},
      {:field, {:avg, "unit_price"}, "avg_price"},
      {:field, {:max, "units_in_stock"}, "max_stock"}
    ])
    |> Selecto.group_by(["category_id"])
    |> Selecto.execute()
    ```

    ## Automatic Join Inference

    Selecto automatically infers joins based on your field selections. When you reference
    fields from related tables using dot notation, the necessary joins are created automatically.

    ### Accessing Related Data
    ```elixir
    # Selecto automatically joins when you reference related fields
    selecto
    |> Selecto.select(#{inspect(main_fields)} ++ ["category.name", "supplier.company_name"])
    |> Selecto.execute()
    # The joins to category and supplier tables are automatic

    # Filter by related fields - joins are automatic
    selecto
    |> Selecto.select(#{inspect(main_fields)})
    |> Selecto.filter([{"category.name", {:like, "%Electronics%"}}])
    |> Selecto.execute()
    
    # Complex filtering across multiple joined tables
    selecto
    |> Selecto.select([#{inspect(string_field)}, :unit_price, "category.name", "supplier.country"])
    |> Selecto.filter([
      {"category.name", {:in, ["Beverages", "Dairy Products"]}},
      {"supplier.country", {:eq, "USA"}},
      {:unit_price, {:between, {10, 50}}}
    ])
    |> Selecto.order_by([{"category.name", :asc}, {#{inspect(string_field)}, :asc}])
    |> Selecto.execute()
    ```

    ### Aggregating Related Data
    ```elixir
    # Count related records with automatic joins
    selecto
    |> Selecto.select([
      #{inspect(List.first(main_fields))},
      {:field, {:count, "order_details.id"}, "order_count"},
      "category.name"
    ])
    |> Selecto.group_by([#{inspect(List.first(main_fields))}, "category.name"])
    |> Selecto.execute()
    ```

    ## Pivot Operations

    Pivot allows you to change the primary focus of your query, essentially "rotating" the data
    to view it from a different perspective.

    ### Basic Pivot
    ```elixir
    # Pivot from products to categories
    selecto
    |> Selecto.pivot("categories")
    |> Selecto.select(["categories.category_name", {:field, {:count, "products.id"}, "product_count"}])
    |> Selecto.group_by(["categories.category_name"])
    |> Selecto.execute()
    
    # Pivot to suppliers with aggregation
    selecto
    |> Selecto.pivot("suppliers")
    |> Selecto.select([
      "suppliers.company_name",
      "suppliers.country",
      {:field, {:count, "products.id"}, "product_count"},
      {:field, {:avg, "products.unit_price"}, "avg_price"}
    ])
    |> Selecto.group_by(["suppliers.company_name", "suppliers.country"])
    |> Selecto.filter([{"suppliers.country", {:in, ["USA", "UK", "Germany"]}}])
    |> Selecto.order_by([{:desc, "product_count"}])
    |> Selecto.limit(10)
    |> Selecto.execute()
    ```

    ### Complex Pivot with Multiple Joins
    ```elixir
    # Pivot to analyze data from category perspective
    selecto
    |> Selecto.pivot("categories")
    |> Selecto.select([
      "categories.category_name",
      {:field, {:count, "products.id"}, "total_products"},
      {:field, {:count_distinct, "products.supplier_id"}, "unique_suppliers"},
      {:field, {:avg, "products.unit_price"}, "avg_price"},
      {:field, {:sum, "order_details.quantity"}, "total_quantity_sold"}
    ])
    |> Selecto.group_by(["categories.category_name"])
    |> Selecto.having([{{:field, {:count, "products.id"}, "total_products"}, {:gt, 5}}])
    |> Selecto.execute()
    ```

    ## LiveView Integration Examples

    ### Basic LiveView Setup
    ```elixir
    defmodule SelectoNorthwindWeb.#{String.capitalize(domain)}Live do
      use SelectoNorthwindWeb, :live_view
      
      def mount(_params, _session, socket) do
        {:ok, load_#{domain}_data(socket)}
      end
      
      defp load_#{domain}_data(socket) do
        domain = SelectoNorthwind.SelectoDomains.#{String.capitalize(domain)}Domain.domain()
        selecto = Selecto.configure(domain, SelectoNorthwind.Repo)
        
        #{domain}_data = 
          selecto
          |> Selecto.select([:id, :name, :created_at])
          |> Selecto.order_by([{:created_at, :desc}])
          |> Selecto.limit(25)
          |> Selecto.execute()
        
        assign(socket, #{domain}_data: #{domain}_data)
      end
    end
    ```

    ### Interactive Filtering
    ```elixir
    def handle_event("filter", %{"search" => search_term}, socket) do
      domain = SelectoNorthwind.SelectoDomains.#{String.capitalize(domain)}Domain.domain()
      selecto = Selecto.configure(domain, SelectoNorthwind.Repo)
      
      filtered_data = 
        selecto
        |> Selecto.select([:id, :name, :created_at])
        |> maybe_filter_by_search(search_term)
        |> Selecto.order_by([{:created_at, :desc}])
        |> Selecto.limit(25)
        |> Selecto.execute()
      
      {:noreply, assign(socket, #{domain}_data: filtered_data)}
    end
    
    defp maybe_filter_by_search(query, ""), do: query
    defp maybe_filter_by_search(query, search_term) do
      Selecto.filter(query, [{:name, {:ilike, "%\#{search_term}%"}}])
    end
    ```

    ### Pagination Example
    ```elixir
    def handle_event("load_more", _params, socket) do
      current_data = socket.assigns.#{domain}_data
      offset = length(current_data)
      
      domain = SelectoNorthwind.SelectoDomains.#{String.capitalize(domain)}Domain.domain()
      selecto = Selecto.configure(domain, SelectoNorthwind.Repo)
      
      new_data = 
        selecto
        |> Selecto.select([:id, :name, :created_at])
        |> Selecto.order_by([{:created_at, :desc}])
        |> Selecto.limit(25)
        |> Selecto.offset(offset)
        |> Selecto.execute()
      
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
      domain={@#{domain}_domain}
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
      domain={@#{domain}_domain}
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
      base_query = selecto
    |> Selecto.select( [:id, :name, :created_at])
      
      query = case cursor_id do
        nil -> base_query
        id -> Selecto.filter(base_query, [{:id, {:gt, id}}])
      end
      
      query
      |> Selecto.order_by([{:id, :asc}])
      |> Selecto.limit(limit)
      |> Selecto.execute(SelectoNorthwind.Repo)
    end
    ```

    ### Batch Operations
    ```elixir
    # Batch loading related data
    def load_#{domain}_with_related(#{domain}_ids) do
      # Load main records
      #{domain}s = 
        selecto
    |> Selecto.select( [:id, :name])
        |> Selecto.filter([{:id, {:in, #{domain}_ids}}])
        |> Selecto.execute(SelectoNorthwind.Repo)
      
      # Load related data in batch
      # Configure related domain similarly
      related_data = 
        related_selecto
        |> Selecto.filter([{:#{domain}_id, {:in, #{domain}_ids}}])
        |> Selecto.execute(SelectoNorthwind.Repo)
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
          selecto
    |> Selecto.select( [:id, :name])
          |> Selecto.filter([{:id, {:eq, id}}])
          |> Selecto.execute(SelectoNorthwind.Repo)
        
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
    defmodule SelectoNorthwind.#{String.capitalize(domain)}QueriesTest do
      use SelectoNorthwind.DataCase
      
      describe "#{domain} domain queries" do
        test "basic selection works" do
          #{domain} = insert(:#{domain})
          
          result = 
            selecto
    |> Selecto.select( [:id, :name])
            |> Selecto.filter([{:id, {:eq, #{domain}.id}}])
            |> Selecto.execute(SelectoNorthwind.Repo)
          
          assert [found_#{domain}] = result
          assert found_#{domain}.id == #{domain}.id
          assert found_#{domain}.name == #{domain}.name
        end
        
        test "filtering by multiple criteria" do
          matching_#{domain} = insert(:#{domain}, status: "active", priority: "high")
          _non_matching = insert(:#{domain}, status: "inactive", priority: "high")
          
          result = 
            selecto
    |> Selecto.select( [:id])
            |> Selecto.filter([{:status, {:eq, "active"}}])
            |> Selecto.filter([{:priority, {:eq, "high"}}])
            |> Selecto.execute(SelectoNorthwind.Repo)
          
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
      
      selecto
    |> Selecto.select( fields)
      |> add_search_filters(search_term)
      |> Selecto.order_by([{:name, :asc}])
      |> Selecto.limit(limit)
      |> Selecto.execute(SelectoNorthwind.Repo)
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
      selecto
      |> Selecto.select([{:field, {:count, "id"}, "count"}])
      |> Selecto.execute(SelectoNorthwind.Repo)
      |> case do
        {:ok, {[[count]], _, _}} -> count
        _ -> 0
      end
    end
    
    defp get_recent_#{domain}s(limit) do
      selecto
    |> Selecto.select( [:id, :name, :created_at])
      |> Selecto.order_by([{:created_at, :desc}])
      |> Selecto.limit(limit)
      |> Selecto.execute(SelectoNorthwind.Repo)
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
    selecto
    |> Selecto.select( [:id, :name, :status])
    
    # Avoid - selecting all fields
    selecto
    |> Selecto.select( :all)  # Can be slow with many columns
    ```

    ### Filter Optimization
    ```elixir
    # Good - use indexed fields for filtering
    selecto
    |> Selecto.select( [:id, :name])
    |> Selecto.filter([{:status, {:eq, "active"}}])  # Uses index
    
    # Less efficient - function calls in filters
    selecto
    |> Selecto.select( [:id, :name])
    |> Selecto.filter([{"UPPER(name)", {:like, "PATTERN%"}}])  # No index usage
    ```

    ### Join Optimization
    ```elixir
    # Efficient join order - most selective first
    selecto
    |> Selecto.select( [:id, :name])
    |> Selecto.filter([{:status, {:eq, "active"}}])          # Reduces result set first
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
      
      selecto
    |> Selecto.select( [:id, :name])
      |> Selecto.order_by([{:created_at, :desc}])
      |> Selecto.limit(per_page)
      |> Selecto.offset(offset)
      |> Selecto.execute(SelectoNorthwind.Repo)
    end
    ```

    ### Cursor-Based Pagination (Recommended)
    ```elixir
    # Better for large datasets
    def get_#{domain}_page_cursor(cursor_id \\\\ nil, limit \\\\ 25) do
      base_query = 
        selecto
    |> Selecto.select( [:id, :name, :created_at])
        |> Selecto.order_by([{:created_at, :desc}, {:id, :desc}])
      
      query = case cursor_id do
        nil -> base_query
        id -> 
          # Get the timestamp of the cursor record for proper ordering
          cursor_time = get_#{domain}_timestamp(id)
          Selecto.filter(base_query, [{:created_at, {:lte, cursor_time}}])
          |> Selecto.filter([{:id, {:lt, id}}])
      end
      
      query |> Selecto.limit(limit) |> Selecto.execute(SelectoNorthwind.Repo)
    end
    ```

    ## Aggregation Performance

    ### Efficient Grouping
    ```elixir
    # Good - group by indexed fields
    selecto
    |> Selecto.select([:status, {:field, {:count, "id"}, "count"}])
    |> Selecto.group_by([:status])
    |> Selecto.execute()
    
    # Consider materialized views for complex aggregations
    Selecto.select("#{domain}_daily_stats", [:date, :total_count, :avg_score])
    |> Selecto.filter([{:date, {:gte, Date.add(Date.utc_today(), -30)}}])
    ```

    ### Memory-Efficient Aggregations
    ```elixir
    # Stream large aggregations to avoid memory issues
    def calculate_#{domain}_stats do
      SelectoNorthwind.Repo.transaction(fn ->
        selecto
    |> Selecto.select( [:category, :score])
        |> Selecto.stream(SelectoNorthwind.Repo)
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
      selecto
    |> Selecto.select( [:id, :name])
      |> Selecto.filter([{:status, {:eq, status}}])
      |> Selecto.execute(SelectoNorthwind.Repo)
    end
    ```

    ## Memory Management

    ### Streaming Large Results
    ```elixir
    def process_all_#{domain}s do
      selecto
    |> Selecto.select( [:id, :name, :data])
      |> Selecto.stream(SelectoNorthwind.Repo, max_rows: 500)
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
        selecto
    |> Selecto.select( [:id])
        |> Selecto.filter([{:id, {:in, batch}}])
        |> Selecto.update(updates)
        |> Selecto.execute(SelectoNorthwind.Repo)
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
      SelectoNorthwind.Telemetry.execute([:#{domain}, :query], %{
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
    config :my_app, SelectoNorthwind.Repo,
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
            selecto
    |> Selecto.select( [:id, :name])
            |> Selecto.filter([{:status, {:eq, "active"}}])
            |> Selecto.limit(50)
            |> Selecto.execute(SelectoNorthwind.Repo)
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
          selecto
    |> Selecto.select( [:id, :name])
          |> Selecto.limit(100)
          |> Selecto.execute(SelectoNorthwind.Repo)
        end,
        
        "filtered_select" => fn ->
          selecto
    |> Selecto.select( [:id, :name])
          |> Selecto.filter([{:status, {:eq, "active"}}])
          |> Selecto.limit(100)
          |> Selecto.execute(SelectoNorthwind.Repo)
        end,
        
        "join_query" => fn ->
          selecto
    |> Selecto.select( [:id, :name, "categories.name"])
          |> Selecto.join(:inner, :categories, :category_id, :id)
          |> Selecto.limit(100)
          |> Selecto.execute(SelectoNorthwind.Repo)
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
      |> Selecto.filter([{:name, {:like, "%example%"}}])
      |> Selecto.limit(25)

    filtered_results = Selecto.execute(filtered_query, conn)
    Kino.DataTable.new(filtered_results)
    ```

    ## Aggregation Examples

    ### Basic Aggregations
    ```elixir
    # Count total records using proper Selecto syntax
    count_query = 
      Selecto.select(#{domain}_domain, [{:field, {:count, "id"}, "count"}])

    count_result = Selecto.execute(count_query, conn)
    IO.inspect(count_result, label: "Total #{domain} count")
    ```

    ### Grouped Aggregations
    ```elixir
    # Group by a field and count
    grouped_query = 
      Selecto.select(#{domain}_domain, [:category, {:field, {:count, "id"}, "count"}])
      |> Selecto.group_by([:category])
      |> Selecto.order_by([{:desc, "count"}])

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
        Selecto.select(#{domain}_domain, [:category, {:field, {:count, "id"}, "count"}])
        |> Selecto.group_by([:category])
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
      |> Selecto.filter([{:created_at, {:gte, Date.add(Date.utc_today(), -30)}}])
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
      
      query = if search != "", do: Selecto.filter(query, [{:name, {:ilike, "%\#{search}%"}}]), else: query
      query = if status, do: Selecto.filter(query, [{:status, {:eq, status}}]), else: query
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
    # Multiple aggregation functions using proper Selecto syntax
    advanced_stats = 
      Selecto.select(#{domain}_domain, [
        {:field, {:count, "id"}, "total_count"},
        {:field, {:count_distinct, "status"}, "status_variety"}, 
        {:field, {:min, "created_at"}, "oldest_record"},
        {:field, {:max, "created_at"}, "newest_record"}
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
                        let query = `selecto
    |> Selecto.select( [\${this.selectedFields.map(f => ':' + f).join(', ')}])`;
                        
                        this.filters.forEach(filter => {
                            if (filter.field && filter.operator && filter.value) {
                                query += `\\n|> Selecto.filter([{:\${filter.field}, {:\${filter.operator}, "\${filter.value}"}}])`;
                            }
                        });
                        
                        query += `\\n|> Selecto.limit(\${this.limit})`;
                        query += `\\n|> Selecto.execute(SelectoNorthwind.Repo)`;
                        
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

  defp get_field_type(types, field) do
    case Map.get(types, field) do
      %{type: type} -> type
      type when is_atom(type) -> type
      _ -> :unknown
    end
  end
  
  defp get_date_literal_for_field(field, types) do
    case get_field_type(types, field) do
      :date -> "~D[2024-01-01]"
      :datetime -> "~U[2024-01-01 00:00:00Z]"
      :utc_datetime -> "~U[2024-01-01 00:00:00Z]"
      :naive_datetime -> "~N[2024-01-01 00:00:00]"
      _ -> "~N[2024-01-01 00:00:00]"  # Default to naive datetime
    end
  end
  
  defp find_field_by_type(fields, types, target_type) when is_atom(target_type) do
    Enum.find(fields, fn field ->
      get_field_type(types, field) == target_type
    end)
  end
  defp find_field_by_type(fields, types, target_types) when is_list(target_types) do
    Enum.find(fields, fn field ->
      field_type = get_field_type(types, field)
      field_type in target_types
    end)
  end
  
  defp pick_main_fields(fields, types) do
    # Try to pick 2-3 meaningful fields for examples
    # Prioritize: id, name fields, then other string fields
    main = if :id in fields, do: [:id], else: []
    
    # Look for name-like fields
    name_field = Enum.find(fields, fn f -> 
      String.contains?(to_string(f), "name") && get_field_type(types, f) == :string
    end)
    
    if name_field do
      main ++ [name_field]
    else
      # Fall back to any string field
      string_field = find_field_by_type(fields, types, :string)
      if string_field, do: main ++ [string_field], else: main
    end
  end
  
  defp get_first_string_field_for_assoc(assoc_table) do
    # Try to guess a reasonable field name for the associated table
    # This is a simple heuristic - in real usage, we'd inspect the actual schema
    case assoc_table do
      table when table in ["category", "categories"] -> "category_name"
      table when table in ["supplier", "suppliers"] -> "company_name"
      table when table in ["customer", "customers"] -> "company_name"
      table when table in ["order", "orders"] -> "order_date"
      table when table in ["employee", "employees"] -> "first_name"
      _ -> "name"  # Default fallback
    end
  end

  defp generate_field_list(fields, types) do
    Enum.map(fields, fn field ->
      type_info = Map.get(types, field, %{})
      type = if is_map(type_info), do: type_info[:type] || :unknown, else: type_info
      "- **#{field}** (`#{type}`)"
    end)
    |> Enum.join("\n")
  end

  defp generate_detailed_field_reference(fields, types) do
    Enum.map(fields, fn field ->
      type = get_field_type(types, field)
      
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
    Selecto automatically infers joins based on the fields you select. Simply reference
    fields from related tables using dot notation, and the necessary joins will be
    created automatically.
    
    ```elixir
    # Example: Automatic join by field reference
    selecto
    |> Selecto.select(["product.name", "category.name"])
    # Selecto automatically determines and creates the necessary join
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
      selecto
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

  # Executable .exs file generation
  
  defp generate_executable_examples(domain, domain_info, _opts) do
    # Convert domain atom to string for String operations
    domain_string = to_string(domain)
    domain_capitalized = String.capitalize(domain_string)
    
    # Get actual fields from domain_info
    fields = domain_info.source.fields
    
    # Pick appropriate fields for examples based on type
    string_field = find_field_by_type(fields, domain_info.source.types, :string) || :name
    date_field = find_field_by_type(fields, domain_info.source.types, [:date, :datetime, :naive_datetime]) || :inserted_at
    boolean_field = find_field_by_type(fields, domain_info.source.types, :boolean)
    numeric_field = find_field_by_type(fields, domain_info.source.types, [:integer, :float, :decimal])
    
    # Pick 2-3 main fields for basic examples (prefer name fields)
    main_fields = pick_main_fields(fields, domain_info.source.types)
    
    """
# #{domain_capitalized} Domain Examples
# 
# This is an executable script demonstrating Selecto usage with the #{domain} domain.
# Run with: mix run docs/selecto/#{domain}_examples.exs
# Or in IEx: c "docs/selecto/#{domain}_examples.exs"

# Setup and configuration
IO.puts("\\n==== #{domain_capitalized} Domain Examples ====\\n")
IO.puts("Setting up domain configuration...")

domain = SelectoNorthwind.SelectoDomains.#{domain_capitalized}Domain.domain()
selecto = Selecto.configure(domain, SelectoNorthwind.Repo)

IO.puts("✓ Configuration complete\\n")

# ============================================================================
# Basic Operations
# ============================================================================

IO.puts("\\n--- Basic Data Retrieval ---\\n")

# Get all records with basic fields
IO.puts("Fetching records with basic fields (limit 5):")
selecto
|> Selecto.select(#{inspect(main_fields)})
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# Get single record by ID
IO.puts("Fetching single record by ID:")
selecto
|> Selecto.select(#{inspect(main_fields ++ [date_field])})
|> Selecto.filter([{:id, {:eq, 1}}])
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    case rows do
      [row | _] -> IO.inspect(row, label: "  → Record ID=1")
      [] -> IO.puts("  → No record found with ID=1")
    end
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

# ============================================================================
# Filtering Examples
# ============================================================================

IO.puts("\\n--- Filtering Examples ---\\n")

# String filtering
IO.puts("Filtering by string field (#{inspect(string_field)}):")
selecto
|> Selecto.select(#{inspect(main_fields)})
|> Selecto.filter([{#{inspect(string_field)}, {:like, "%a%"}}])
|> Selecto.limit(3)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found \#{length(rows)} matching records")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# Multiple filters with AND logic
IO.puts("Multiple filters (AND logic):")
selecto
|> Selecto.select(#{inspect(main_fields ++ [date_field])})
|> Selecto.filter([
  {#{inspect(string_field)}, {:like, "%a%"}},
  {#{inspect(date_field)}, {:gte, #{get_date_literal_for_field(date_field, domain_info.source.types)}}}
])
|> Selecto.limit(3)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found \#{length(rows)} matching records")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end
#{if boolean_field do """

  IO.puts("")

  # Boolean field filtering
  IO.puts("Filtering by boolean field (#{inspect(boolean_field)}):")
  selecto
  |> Selecto.select(#{inspect(main_fields)})
  |> Selecto.filter([{#{inspect(boolean_field)}, {:eq, true}}])
  |> Selecto.limit(3)
  |> Selecto.execute()
  |> case do
    {:ok, {rows, _columns, _aliases}} ->
      IO.puts("  Found \#{length(rows)} records where #{boolean_field} = true")
      Enum.each(rows, fn row ->
        IO.inspect(row, label: "  →")
      end)
    {:error, error} ->
      IO.puts("Error: \#{inspect(error)}")
  end
  """ else "" end}

# ============================================================================
# Aggregation Examples
# ============================================================================

IO.puts("\\n--- Aggregation Examples ---\\n")

# Group by with count using proper Selecto aggregation syntax
IO.puts("Group by with count:")
selecto
|> Selecto.select([#{inspect(string_field)}, {:field, {:count, "id"}, "count"}])
|> Selecto.group_by([#{inspect(string_field)}])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Top 5 groups:")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# Multiple aggregations with proper syntax
IO.puts("Multiple aggregation functions:")
selecto
|> Selecto.select([
  #{inspect(string_field)},
  {:field, {:count, "id"}, "total_count"},
  {:field, {:min, #{inspect(date_field)}}, "oldest"},
  {:field, {:max, #{inspect(date_field)}}, "newest"}
])
|> Selecto.group_by([#{inspect(string_field)}])
|> Selecto.limit(3)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found \#{length(rows)} groups")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

# ============================================================================
# Automatic Join Inference
# ============================================================================
#{if not Enum.empty?(domain_info.source.associations) do
  # Get first association for examples
  {assoc_name, assoc_info} = domain_info.source.associations |> Map.to_list() |> List.first()
  assoc_table = to_string(assoc_info[:queryable] || assoc_name)
"""

IO.puts("\\n--- Automatic Join Inference ---\\n")

IO.puts("Accessing related data through automatic joins:")

# Select fields from joined table
IO.puts("\\nSelecting fields from related #{assoc_table} table:")
selecto
|> Selecto.select([
  #{inspect(List.first(main_fields))},
  #{inspect(string_field)},
  "#{assoc_table}.id",
  "#{assoc_table}.#{get_first_string_field_for_assoc(assoc_table)}"
])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, columns, _aliases}} ->
    IO.puts("  Columns: \#{inspect(columns)}")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# Filter by joined table fields
IO.puts("Filtering by related #{assoc_table} fields:")
selecto
|> Selecto.select([#{inspect(List.first(main_fields))}, #{inspect(string_field)}])
|> Selecto.filter([{"#{assoc_table}.id", {:gt, 0}}])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found \#{length(rows)} records with associated #{assoc_table}")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# Aggregate with joins
IO.puts("Aggregating with joined data:")
selecto
|> Selecto.select([
  "#{assoc_table}.id",
  {:field, {:count, "id"}, "count"},
  {:field, {:avg, #{inspect(numeric_field || "id")}}, "average"}
])
|> Selecto.group_by(["#{assoc_table}.id"])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Top 5 #{assoc_table} by count:")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end
"""
else
"""

IO.puts("\\n--- Automatic Join Inference ---\\n")

IO.puts("No associations found in this domain.")
IO.puts("Joins are automatically inferred when you reference fields with dot notation.")
IO.puts("Example: selecting 'category.name' automatically joins to category table")
"""
end}

# ============================================================================  
# Pivot Examples
# ============================================================================
#{if map_size(domain_info.joins) > 0 do
"""

IO.puts("\\n--- Pivot Operations ---\\n")

IO.puts("Pivoting to a related domain:")
IO.puts("  Note: Pivot allows you to change the primary focus of your query")

# Example pivot operation
#{if map_size(domain_info.source.associations) > 0 do
  {assoc_name, assoc_info} = domain_info.source.associations |> Map.to_list() |> List.first()
  target_table = to_string(assoc_info[:queryable] || assoc_name)
"""
# Pivot from #{domain} to #{target_table}
# This changes the primary table from #{domain} to #{target_table}
selecto
|> Selecto.pivot(#{inspect(assoc_name)})
|> Selecto.select(["#{target_table}.id", "#{target_table}.#{get_first_string_field_for_assoc(target_table)}"])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Showing #{target_table} records after pivot:")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# Pivot preserves the context of your original filters
IO.puts("Note: Pivot maintains the relationship context from the original table.")
IO.puts("The query above shows all #{target_table} records that have associated #{domain} records.")
"""
else
  "# No associations available for pivot example"
end}
"""
else
  ""
end}

# ============================================================================
# Subselect Examples (Aggregating Related Data)
# ============================================================================
#{if map_size(domain_info.source.associations) > 0 do
  {assoc_name, assoc_info} = domain_info.source.associations |> Map.to_list() |> List.first()
  target_table = to_string(assoc_info[:queryable] || assoc_name)
  target_field = get_first_string_field_for_assoc(target_table)
  
  ~s"""
  
  IO.puts("\\n--- Subselect Operations ---\\n")
  
  IO.puts("Subselect - Getting related data as JSON array:")
  IO.puts("  Note: Subselect returns related records as aggregated data within each row")

  # Get #{domain} records with related #{target_table} as JSON array
  selecto
  |> Selecto.select([#{inspect(List.first(main_fields))}, #{inspect(string_field)}])
|> Selecto.subselect(["#{target_table}.#{target_field}"], format: :json_agg)
|> Selecto.limit(3)
|> Selecto.execute()
|> case do
  {:ok, {rows, columns, _aliases}} ->
    IO.puts("  Columns: \#{inspect(columns)}")
    
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
    
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# Count of related records
IO.puts("Subselect - Count of related records:")

selecto
|> Selecto.select([#{inspect(List.first(main_fields))}, #{inspect(string_field)}])
|> Selecto.subselect(["#{target_table}.id"], format: :count)
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found \#{length(rows)} records with counts")
    
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
    
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end
  """
else
  ""
end}

# ============================================================================
# Advanced Filtering Examples
# ============================================================================

IO.puts("\\n--- Advanced Filtering ---\\n")

# OR conditions
IO.puts("Using OR conditions in filters:")

selecto
|> Selecto.select([#{inspect(List.first(main_fields))}, #{inspect(string_field)}])
|> Selecto.filter([
  {:or, [
    {#{inspect(string_field)}, {:like, "%a%"}},
    {#{inspect(string_field)}, {:like, "%e%"}}
  ]}
])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found \#{length(rows)} records matching 'a' OR 'e'")
    
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
    
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# IN clause
IO.puts("Using IN clause for multiple values:")

selecto
|> Selecto.select([#{inspect(List.first(main_fields))}, #{inspect(string_field)}])
|> Selecto.filter([
  {#{inspect(List.first(main_fields))}, {:in, [1, 2, 3, 5, 8]}}
])
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found \#{length(rows)} records with ID in [1, 2, 3, 5, 8]")
    
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
    
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

# Boolean field filtering
IO.puts("Filtering by boolean field:")

selecto
|> Selecto.select([#{inspect(List.first(main_fields))}, #{inspect(string_field)}])
|> Selecto.filter([
  {:discontinued, {:eq, false}}
])
|> Selecto.limit(3)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found \#{length(rows)} records where discontinued = false")
    
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
    
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

#{if map_size(domain_info.source.associations) > 0 do
  {assoc_name, assoc_info} = domain_info.source.associations |> Map.to_list() |> List.first()
  target_table = to_string(assoc_info[:queryable] || assoc_name)
  
  ~s"""
    # ============================================================================
    # Related Data Filtering Examples
    # ============================================================================
    
    IO.puts("\\n--- Filtering by Related Data ---\\n")

    IO.puts("Filter where related #{target_table} exists:")
    IO.puts("  Note: You can filter by related data using join syntax")

  # Find #{domain} records that have a specific related #{target_table}
  selecto
  |> Selecto.select([#{inspect(List.first(main_fields))}, #{inspect(string_field)}])
  |> Selecto.filter([
    {"#{target_table}.id", {:gt, 0}}
  ])
  |> Selecto.limit(5)
  |> Selecto.execute()
  |> case do
    {:ok, {rows, _columns, _aliases}} ->
      IO.puts("  Found \#{length(rows)} records with related #{target_table}")
      
      Enum.each(rows, fn row ->
        IO.inspect(row, label: "  →")
      end)
      
    {:error, error} ->
      IO.puts("Error: \#{inspect(error)}")
  end
    """
else
  ""
end}

# ============================================================================
# Pagination Examples
# ============================================================================

IO.puts("\\n--- Pagination ---\\n")

IO.puts("Page 1 (first 5 records):")
selecto
|> Selecto.select(#{inspect(main_fields)})
|> Selecto.order_by([{#{inspect(List.first(main_fields))}, :asc}])
|> Selecto.limit(5)
|> Selecto.offset(0)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    Enum.each(rows, fn row ->
      IO.inspect(Enum.at(row, 0), label: "  → ID")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("")

IO.puts("Page 2 (next 5 records):")
selecto
|> Selecto.select(#{inspect(main_fields)})
|> Selecto.order_by([{#{inspect(List.first(main_fields))}, :asc}])
|> Selecto.limit(5)
|> Selecto.offset(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    Enum.each(rows, fn row ->
      IO.inspect(Enum.at(row, 0), label: "  → ID")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

# ============================================================================
# Advanced Patterns
# ============================================================================

IO.puts("\\n--- Advanced Patterns ---\\n")

# Combining multiple operations
IO.puts("Complex query with multiple operations:")
selecto
|> Selecto.select(#{inspect(main_fields)})
|> Selecto.filter([{#{inspect(string_field)}, {:like, "%a%"}}])
|> Selecto.order_by([{#{inspect(date_field)}, :desc}])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, columns, _aliases}} ->
    IO.puts("  Columns: \#{inspect(columns)}")
    IO.puts("  Found \#{length(rows)} records (newest first)")
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)
  {:error, error} ->
    IO.puts("Error: \#{inspect(error)}")
end

IO.puts("\\n==== Examples Complete ====\\n")
"""
  end
end