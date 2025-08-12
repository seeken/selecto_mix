defmodule SelectoMix.QueriesGenerator do
  @moduledoc """
  Generates common query helper modules for Selecto domains.
  
  This module creates query helper files that provide convenient
  functions for common query patterns, making it easier for developers
  to work with Selecto domains in their applications.
  """

  @doc """
  Generate a queries helper file for a schema.
  
  Creates a module with common query patterns and helpers
  that developers can use as a starting point.
  """
  def generate_queries_file(schema_module, opts) do
    module_name = get_queries_module_name(schema_module)
    domain_module = get_domain_module_name(schema_module)
    
    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      Common query helpers for #{inspect(schema_module)}.
      
      This module provides convenient functions for common query patterns
      using the Selecto domain configuration. You can customize and extend
      these queries as needed for your application.
      
      ## Usage
      
          # Get all records
          {:ok, {users, columns, aliases}} = #{module_name}.all(MyApp.Repo)
          
          # Find by ID
          {:ok, {user, aliases}} = #{module_name}.find(MyApp.Repo, 123)
          
          # Search with filters
          {:ok, {users, columns, aliases}} = #{module_name}.search(MyApp.Repo, %{
            "status" => "active",
            "name" => "John"
          })
      
      ## Customization
      
      Feel free to add your own query functions to this module. Common patterns:
      
      - Scope functions (active, inactive, recent, etc.)
      - Search and filter combinations
      - Reporting and analytics queries
      - Pagination helpers
      
      This file will not be overwritten when running `mix selecto.gen.domain`
      unless you use the `--force` flag.
      \"\"\"

      alias #{domain_module}

      @doc \"\"\"
      Get all records with default selection and optional filters.
      
      ## Examples
      
          # Get all records
          #{module_name}.all(repo)
          
          # Get with limit
          #{module_name}.all(repo, limit: 10)
          
          # Get with custom selection
          #{module_name}.all(repo, select: ["id", "name"])
      \"\"\"
      def all(repo, opts \\\\ []) do
        #{domain_module}.new(repo)
        |> apply_select_option(opts)
        |> apply_limit_option(opts)
        |> apply_order_option(opts)
        |> Selecto.execute()
      end

      @doc \"\"\"
      Find a single record by primary key.
      
      ## Examples
      
          case #{module_name}.find(repo, 123) do
            {:ok, {record, aliases}} -> 
              # Found the record
            {:error, :no_results} -> 
              # Record not found
          end
      \"\"\"
      def find(repo, id, opts \\\\ []) do
        primary_key = #{domain_module}.domain().source.primary_key
        
        #{domain_module}.new(repo)
        |> apply_select_option(opts)
        |> Selecto.filter({to_string(primary_key), id})
        |> Selecto.execute_one()
      end

      @doc \"\"\"
      Search records with multiple filters.
      
      ## Examples
      
          filters = %{
            "status" => "active",
            "name" => "John"
          }
          
          #{module_name}.search(repo, filters)
          
          # With additional options
          #{module_name}.search(repo, filters, limit: 20, order: {"name", :asc})
      \"\"\"
      def search(repo, filters, opts \\\\ []) when is_map(filters) do
        selecto = #{domain_module}.new(repo)
        |> apply_select_option(opts)
        
        # Apply all filters
        selecto = Enum.reduce(filters, selecto, fn {field, value}, acc ->
          if value not in [nil, ""] do
            Selecto.filter(acc, {field, value})
          else
            acc
          end
        end)
        
        selecto
        |> apply_limit_option(opts)
        |> apply_order_option(opts)
        |> Selecto.execute()
      end

      @doc \"\"\"
      Count records with optional filters.
      
      ## Examples
      
          # Count all records
          {:ok, {[count], aliases}} = #{module_name}.count(repo)
          
          # Count with filters
          {:ok, {[count], aliases}} = #{module_name}.count(repo, %{"status" => "active"})
      \"\"\"
      def count(repo, filters \\\\ %{}) do
        primary_key = #{domain_module}.domain().source.primary_key
        
        selecto = #{domain_module}.new(repo)
        |> Selecto.select([{to_string(primary_key), %{"format" => "count"}}])
        
        # Apply filters if provided
        selecto = if Enum.empty?(filters) do
          selecto
        else
          Enum.reduce(filters, selecto, fn {field, value}, acc ->
            if value not in [nil, ""] do
              Selecto.filter(acc, {field, value})
            else
              acc
            end
          end)
        end
        
        Selecto.execute_one(selecto)
      end

      @doc \"\"\"
      Get paginated results.
      
      ## Examples
      
          # First page
          #{module_name}.paginate(repo, page: 1, per_page: 20)
          
          # With filters
          #{module_name}.paginate(repo, %{"status" => "active"}, page: 2, per_page: 10)
      \"\"\"
      def paginate(repo, filters \\\\ %{}, opts \\\\ []) do
        page = Keyword.get(opts, :page, 1)
        per_page = Keyword.get(opts, :per_page, 20)
        
        # Calculate offset
        offset = (page - 1) * per_page
        
        # Get records
        records_result = search(repo, filters, Keyword.merge(opts, [limit: per_page, offset: offset]))
        
        # Get total count
        count_result = count(repo, filters)
        
        case {records_result, count_result} do
          {{:ok, {records, columns, aliases}}, {:ok, {[total_count], _}}} ->
            pagination_info = %{
              page: page,
              per_page: per_page,
              total_count: total_count,
              total_pages: ceil(total_count / per_page),
              has_prev: page > 1,
              has_next: page * per_page < total_count
            }
            
            {:ok, {records, columns, aliases, pagination_info}}
            
          {records_error, _} -> records_error
          {_, count_error} -> count_error
        end
      end

      #{generate_scope_functions(schema_module, opts)}

      #{generate_aggregation_functions(schema_module, opts)}

      ## Helper functions for query building

      defp apply_select_option(selecto, opts) do
        case Keyword.get(opts, :select) do
          nil -> 
            # Use domain defaults
            Selecto.select(selecto, #{domain_module}.domain().default_selected)
          fields when is_list(fields) -> 
            Selecto.select(selecto, fields)
          field when is_binary(field) -> 
            Selecto.select(selecto, [field])
        end
      end

      defp apply_limit_option(selecto, opts) do
        case Keyword.get(opts, :limit) do
          nil -> selecto
          limit -> 
            # Note: Selecto doesn't have built-in limit, this would need to be added to SQL generation
            selecto
        end
      end

      defp apply_order_option(selecto, opts) do
        case Keyword.get(opts, :order) do
          nil -> 
            # Use domain default ordering if available
            case #{domain_module}.domain() do
              %{default_order: [order | _]} -> Selecto.order_by(selecto, [order])
              _ -> selecto
            end
          {field, direction} -> 
            Selecto.order_by(selecto, [{field, direction}])
          orders when is_list(orders) -> 
            Selecto.order_by(selecto, orders)
        end
      end
    end
    """
  end

  # Private helper functions

  defp get_queries_module_name(schema_module) do
    base_name = Module.split(schema_module) |> List.last()
    context_name = get_context_name(schema_module)
    
    "#{context_name}.#{base_name}Queries"
  end

  defp get_domain_module_name(schema_module) do
    base_name = Module.split(schema_module) |> List.last()
    app_name = Application.get_env(:selecto_mix, :app_name) || 
               detect_app_name() || 
               "MyApp"
    
    "#{app_name}.SelectoDomains.#{base_name}Domain"
  end

  defp get_context_name(schema_module) do
    parts = Module.split(schema_module)
    case parts do
      [app, context | _] when length(parts) >= 3 -> "#{app}.#{context}"
      [app] -> app
      _ -> "MyApp"
    end
  end

  defp generate_scope_functions(schema_module, _opts) do
    # Generate some common scope functions based on typical patterns
    _schema_name = Module.split(schema_module) |> List.last() |> String.downcase()
    
    "\n\n      ## Common scope functions\n" <>
    "      ## Add your own scope functions here based on your domain needs\n\n" <>
    "      @doc \"\"\"\n      Example scope function for active records.\n" <>
    "      Customize this based on your schema's fields.\n      \"\"\"\n" <>
    "      def active(repo, opts \\\\\\\\ []) do\n" <>
    "        # This assumes an 'active' or 'status' field exists\n" <>
    "        # Modify according to your schema\n" <>
    "        search(repo, %{\"active\" => true}, opts)\n      end\n\n" <>
    "      @doc \"\"\"\n      Example scope function for recent records.\n" <>
    "      Customize this based on your schema's timestamp fields.\n      \"\"\"\n" <>
    "      def recent(repo, opts \\\\\\\\ []) do\n" <>
    "        # This assumes a timestamp field exists\n" <>
    "        # Modify according to your schema\n" <>
    "        days_ago = Keyword.get(opts, :days, 7)\n" <>
    "        cutoff_date = Date.utc_today() |> Date.add(-days_ago)\n        \n" <>
    "        search(repo, %{\"inserted_at\" => {:gte, cutoff_date}}, opts)\n      end\n\n" <>
    "      @doc \"\"\"\n      Search by text fields.\n" <>
    "      Customize this based on your schema's searchable text fields.\n      \"\"\"\n" <>
    "      def search_text(repo, query, opts \\\\\\\\ []) do\n" <>
    "        # This is a simple example - customize based on your schema\n" <>
    "        # You might want to search across multiple text fields\n" <>
    "        filters = case String.trim(query || \"\") do\n          \"\" -> %{}\n" <>
    "          text -> %{\"name\" => {:ilike, \"%\#{text}%\"}}  # Adjust field name as needed\n" <>
    "        end\n        \n        search(repo, filters, opts)\n      end"
  end

  defp generate_aggregation_functions(schema_module, _opts) do
    domain_module = get_domain_module_name(schema_module)
    queries_module = get_queries_module_name(schema_module)
    
    "\n\n      ## Aggregation and reporting functions\n\n      @doc \"\"\"\n" <>
    "      Group records by a field and count them.\n      \n" <>
    "      ## Examples\n      \n          # Group by status\n" <>
    "          {:ok, {groups, columns, aliases}} = #{queries_module}.group_count(repo, \"status\")\n" <>
    "      \"\"\"\n      def group_count(repo, group_field, filters \\\\\\\\ %{}) do\n" <>
    "        selecto = #{domain_module}.new(repo)\n" <>
    "        |> Selecto.select([group_field, {\"id\", %{\"format\" => \"count\"}}])\n" <>
    "        |> Selecto.group_by([group_field])\n        \n" <>
    "        # Apply filters if provided\n" <>
    "        selecto = Enum.reduce(filters, selecto, fn {field, value}, acc ->\n" <>
    "          if value not in [nil, \"\"] do\n" <>
    "            Selecto.filter(acc, {field, value})\n          else\n            acc\n" <>
    "          end\n        end)\n        \n        Selecto.execute(selecto)\n      end\n\n" <>
    "      @doc \"\"\"\n      Get summary statistics for numeric fields.\n" <>
    "      Customize this based on your schema's numeric fields.\n      \"\"\"\n" <>
    "      def summary_stats(repo, field, filters \\\\\\\\ %{}) when is_binary(field) do\n" <>
    "        # This would require aggregation functions in Selecto\n" <>
    "        # For now, this is a placeholder showing the intended API\n" <>
    "        selecto = #{domain_module}.new(repo)\n        |> Selecto.select([\n" <>
    "          {field, %{\"format\" => \"count\"}},\n" <>
    "          {field, %{\"format\" => \"avg\"}},\n" <>
    "          {field, %{\"format\" => \"min\"}},\n" <>
    "          {field, %{\"format\" => \"max\"}}\n        ])\n        \n" <>
    "        # Apply filters\n" <>
    "        selecto = Enum.reduce(filters, selecto, fn {filter_field, value}, acc ->\n" <>
    "          if value not in [nil, \"\"] do\n" <>
    "            Selecto.filter(acc, {filter_field, value})\n" <>
    "          else\n            acc\n          end\n        end)\n        \n" <>
    "        case Selecto.execute_one(selecto) do\n" <>
    "          {:ok, {[count, avg, min, max], aliases}} ->\n            {:ok, %{\n" <>
    "              count: count,\n              average: avg,\n" <>
    "              minimum: min,\n              maximum: max,\n" <>
    "              field: field\n            }}\n          error -> error\n        end\n      end"
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