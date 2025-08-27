defmodule SelectoMix.ApiDocsGenerator do
  @moduledoc """
  Generates comprehensive API reference documentation for Selecto modules.
  """

  @doc """
  Generate API index page.
  """
  def generate_api_index(modules, format \\ :markdown) do
    case format do
      :markdown -> generate_markdown_api_index(modules)
      :html -> generate_html_api_index(modules)
    end
  end

  @doc """
  Generate comprehensive module documentation.
  """
  def generate_module_docs(module, format \\ :markdown, opts \\ []) do
    module_info = analyze_module(module, opts)
    
    case format do
      :markdown -> generate_markdown_module_docs(module, module_info, opts)
      :html -> generate_html_module_docs(module, module_info, opts)
    end
  end

  # Private functions

  defp analyze_module(module, opts) do
    %{
      name: module,
      moduledoc: get_module_doc(module),
      functions: get_module_functions(module, opts),
      types: get_module_types(module, opts),
      callbacks: get_module_callbacks(module, opts),
      examples: get_module_examples(module, opts)
    }
  end

  defp get_module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} -> moduledoc
      {:docs_v1, _, _, _, :none, _, _} -> "No module documentation available."
      _ -> "Documentation could not be loaded."
    end
  end

  defp get_module_functions(module, opts) do
    include_private = opts[:include_private] || false
    
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, function_docs} ->
        function_docs
        |> Enum.filter(fn {kind, _, _, _, _, _} -> kind == :function end)
        |> Enum.filter(fn {_, name_arity, _, _, _, _} -> 
          {name, _arity} = name_arity
          include_private or not String.starts_with?(to_string(name), "_")
        end)
        |> Enum.map(&extract_function_info/1)
      _ -> []
    end
  end

  defp get_module_types(module, _opts) do
    # Extract type specifications
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        docs
        |> Enum.filter(fn {kind, _, _, _, _, _} -> kind == :type end)
        |> Enum.map(&extract_type_info/1)
      _ -> []
    end
  end

  defp get_module_callbacks(module, _opts) do
    # Extract callback specifications
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        docs
        |> Enum.filter(fn {kind, _, _, _, _, _} -> kind == :callback end)
        |> Enum.map(&extract_callback_info/1)
      _ -> []
    end
  end

  defp get_module_examples(module, opts) do
    if opts[:with_examples] do
      generate_function_examples(module)
    else
      []
    end
  end

  defp extract_function_info({_kind, {name, arity}, signatures, doc, metadata, _anno}) do
    %{
      name: name,
      arity: arity,
      signatures: signatures || [],
      doc: extract_doc_content(doc),
      metadata: metadata || %{},
      examples: generate_function_example(name, arity)
    }
  end

  defp extract_type_info({_kind, {name, arity}, signatures, doc, metadata, _anno}) do
    %{
      name: name,
      arity: arity,
      signatures: signatures || [],
      doc: extract_doc_content(doc),
      metadata: metadata || %{}
    }
  end

  defp extract_callback_info({_kind, {name, arity}, signatures, doc, metadata, _anno}) do
    %{
      name: name,
      arity: arity,
      signatures: signatures || [],
      doc: extract_doc_content(doc),
      metadata: metadata || %{}
    }
  end

  defp extract_doc_content(%{"en" => doc}), do: doc
  defp extract_doc_content(:none), do: "No documentation available."
  defp extract_doc_content(_), do: "Documentation format not supported."

  defp generate_function_example(name, arity) do
    # Generate basic usage examples for common functions
    case {name, arity} do
      {:select, 2} -> 
        """
        # Basic field selection
        Selecto.select(domain, [:id, :name])

        # Select all fields
        Selecto.select(domain, :all)
        """
      {:filter, 4} ->
        """
        # Basic filtering
        Selecto.filter(query, :name, :eq, "example")

        # Multiple filters
        query
        |> Selecto.filter(:status, :eq, "active")
        |> Selecto.filter(:priority, :gt, 5)
        """
      {:join, 5} ->
        """
        # Inner join
        Selecto.join(query, :inner, :categories, :category_id, :id)

        # Left join with alias
        Selecto.join(query, :left, :users, :user_id, :id, alias: "u")
        """
      {:aggregate, 3} ->
        """
        # Count aggregation
        Selecto.aggregate(query, :count, :id)

        # Multiple aggregations
        query
        |> Selecto.aggregate(:count, :id, alias: :total_count)
        |> Selecto.aggregate(:avg, :score, alias: :avg_score)
        """
      {:group_by, 2} ->
        """
        # Group by single field
        Selecto.group_by(query, [:category])

        # Group by multiple fields
        Selecto.group_by(query, [:category, :status])
        """
      {:order_by, 2} ->
        """
        # Ascending order
        Selecto.order_by(query, [{:name, :asc}])

        # Descending order with multiple fields
        Selecto.order_by(query, [{:created_at, :desc}, {:name, :asc}])
        """
      {:limit, 2} ->
        """
        # Limit results
        Selecto.limit(query, 25)

        # Pagination with offset
        query
        |> Selecto.limit(25)
        |> Selecto.offset(50)
        """
      _ -> nil
    end
  end

  defp generate_function_examples(_module) do
    # This could be expanded to generate comprehensive examples for each module
    []
  end

  # Markdown generation functions

  defp generate_markdown_api_index(modules) do
    """
    # Selecto API Reference

    This is the comprehensive API reference for the Selecto ecosystem.

    ## Core Modules

    #{generate_module_list(modules, :core)}

    ## Components

    #{generate_module_list(modules, :components)}

    ## Mix Tasks

    #{generate_module_list(modules, :mix_tasks)}

    ## Utilities

    #{generate_module_list(modules, :utilities)}

    ## Getting Started

    To get started with the Selecto API:

    1. **Choose your integration point**: Start with `Selecto` for basic queries or `SelectoComponents` for LiveView integration
    2. **Review domain configuration**: Understand how to configure domains for your data
    3. **Explore query building**: Learn the query building patterns and filtering options
    4. **Check performance guidance**: Review optimization recommendations for your use case

    ## Common Patterns

    ### Basic Query Building
    ```elixir
    # Simple selection and filtering
    Selecto.select(my_domain(), [:id, :name])
    |> Selecto.filter(:status, :eq, "active")
    |> Selecto.limit(50)
    |> Selecto.execute(MyApp.Repo)
    ```

    ### Advanced Aggregations
    ```elixir
    # Grouped aggregations
    Selecto.select(my_domain(), [:category, :count, :avg_score])
    |> Selecto.group_by([:category])
    |> Selecto.aggregate(:count, :id, alias: :count)
    |> Selecto.aggregate(:avg, :score, alias: :avg_score)
    |> Selecto.execute(MyApp.Repo)
    ```

    ### LiveView Integration
    ```elixir
    # Using SelectoComponents in LiveView
    <.live_component 
      module={SelectoComponents.Form} 
      id="my-data-view"
      domain={my_domain()}
      connection={@db_connection}
    />
    ```

    ## Support and Resources

    - [Domain Documentation](../selecto/) - Generated domain-specific guides
    - [Examples Repository](https://github.com/your-org/selecto-examples) - Real-world usage examples
    - [Performance Guide](performance.md) - Optimization recommendations
    - [Migration Guide](migration.md) - Upgrading between versions

    ---

    *Generated by `mix selecto.docs.api`*
    """
  end

  defp generate_module_list(modules, category) do
    filtered_modules = filter_modules_by_category(modules, category)
    
    if Enum.empty?(filtered_modules) do
      "*No modules in this category*"
    else
      Enum.map(filtered_modules, fn module ->
        module_name = to_string(module) |> String.replace("Elixir.", "")
        file_name = Macro.underscore(module_name)
        description = get_module_short_description(module)
        
        "- [#{module_name}](#{file_name}.md) - #{description}"
      end)
      |> Enum.join("\n")
    end
  end

  defp filter_modules_by_category(modules, category) do
    Enum.filter(modules, fn module ->
      module_str = to_string(module)
      case category do
        :core -> String.starts_with?(module_str, "Elixir.Selecto") and 
                 not String.contains?(module_str, "Components") and
                 not String.contains?(module_str, "Mix.Tasks")
        :components -> String.contains?(module_str, "Components")
        :mix_tasks -> String.contains?(module_str, "Mix.Tasks")
        :utilities -> String.contains?(module_str, ["Util", "Helper", "Support"])
      end
    end)
  end

  defp get_module_short_description(module) do
    case get_module_doc(module) do
      doc when is_binary(doc) ->
        doc
        |> String.split("\n")
        |> Enum.find(&(String.trim(&1) != ""), fn -> "" end)
        |> String.trim()
        |> String.slice(0, 100)
        |> case do
          long when byte_size(long) > 97 -> long <> "..."
          short -> short
        end
      _ -> "No description available"
    end
  end

  defp generate_markdown_module_docs(module, module_info, opts) do
    module_name = to_string(module) |> String.replace("Elixir.", "")
    
    """
    # #{module_name}

    #{module_info.moduledoc}

    ## Functions

    #{generate_functions_documentation(module_info.functions, opts)}

    #{if not Enum.empty?(module_info.types), do: "## Types\n\n#{generate_types_documentation(module_info.types)}", else: ""}

    #{if not Enum.empty?(module_info.callbacks), do: "## Callbacks\n\n#{generate_callbacks_documentation(module_info.callbacks)}", else: ""}

    ## Related Modules

    #{generate_related_modules_section(module)}

    ---

    *Generated by `mix selecto.docs.api`*
    """
  end

  defp generate_functions_documentation(functions, opts) do
    if Enum.empty?(functions) do
      "*No public functions documented.*"
    else
      functions
      |> Enum.sort_by(&{&1.name, &1.arity})
      |> Enum.map(&generate_function_doc(&1, opts))
      |> Enum.join("\n\n")
    end
  end

  defp generate_function_doc(func_info, _opts) do
    signatures = format_function_signatures(func_info.signatures)
    
    example_section = if func_info.examples do
      """
      
      ### Example
      
      ```elixir
      #{String.trim(func_info.examples)}
      ```
      """
    else
      ""
    end

    """
    ### #{func_info.name}/#{func_info.arity}

    ```elixir
    #{signatures}
    ```

    #{func_info.doc}#{example_section}
    """
  end

  defp format_function_signatures(signatures) when is_list(signatures) do
    signatures
    |> Enum.map(&to_string/1)
    |> Enum.join("\n")
  end
  defp format_function_signatures(_), do: "Signature information not available"

  defp generate_types_documentation(types) do
    types
    |> Enum.map(fn type ->
      signatures = format_function_signatures(type.signatures)
      
      """
      ### #{type.name}/#{type.arity}

      ```elixir
      #{signatures}
      ```

      #{type.doc}
      """
    end)
    |> Enum.join("\n\n")
  end

  defp generate_callbacks_documentation(callbacks) do
    callbacks
    |> Enum.map(fn callback ->
      signatures = format_function_signatures(callback.signatures)
      
      """
      ### #{callback.name}/#{callback.arity}

      ```elixir
      #{signatures}
      ```

      #{callback.doc}
      """
    end)
    |> Enum.join("\n\n")
  end

  defp generate_related_modules_section(module) do
    # This could be expanded to show actual related modules
    module_str = to_string(module)
    
    suggestions = cond do
      String.contains?(module_str, "Selecto.") and not String.contains?(module_str, "Components") ->
        "- [SelectoComponents](selecto_components.md) - LiveView integration\n- [SelectoKino](selecto_kino.md) - Livebook integration"
      String.contains?(module_str, "SelectoComponents") ->
        "- [Selecto](selecto.md) - Core query building\n- [SelectoComponents.UI](selecto_components_ui.md) - UI utilities"
      true ->
        "- [Selecto](selecto.md) - Core query building\n- [SelectoComponents](selecto_components.md) - LiveView components"
    end

    """
    See also:

    #{suggestions}
    """
  end

  # HTML generation functions (placeholder - would generate full HTML)

  defp generate_html_api_index(_modules) do
    "<!-- HTML API index would be generated here -->"
  end

  defp generate_html_module_docs(_module, _module_info, _opts) do
    "<!-- HTML module documentation would be generated here -->"
  end
end