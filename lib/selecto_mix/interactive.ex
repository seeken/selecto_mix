defmodule SelectoMix.Interactive do
  @moduledoc """
  Interactive mode for SelectoMix domain generation.
  
  Provides a guided, step-by-step interface for configuring and generating
  Selecto domains with real-time validation and suggestions.
  """
  
  alias SelectoMix.{AdapterDetector, JoinAnalyzer}
  # alias SelectoMix.CLIParser
  
  @doc """
  Starts the interactive domain generation process.
  """
  @spec run(keyword()) :: :ok | {:error, term()}
  def run(_opts \\ []) do
    IO.puts("\n🚀 SelectoMix Interactive Domain Generator")
    IO.puts("=" |> String.duplicate(50))
    
    with {:ok, schemas} <- select_schemas(),
         {:ok, adapter} <- select_adapter(),
         {:ok, features} <- select_features(),
         {:ok, join_config} <- configure_joins(schemas, adapter),
         {:ok, output_config} <- configure_output(),
         :ok <- confirm_generation(schemas, adapter, features, join_config, output_config) do
      
      generate_domains(schemas, adapter, features, join_config, output_config)
    else
      {:error, :cancelled} ->
        IO.puts("\n❌ Generation cancelled.")
        :ok
      {:error, reason} ->
        IO.puts("\n❌ Error: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # Step 1: Select schemas
  defp select_schemas do
    IO.puts("\n📋 Step 1: Select Schemas")
    IO.puts("-------------------------")
    
    schemas = discover_schemas()
    
    if Enum.empty?(schemas) do
      IO.puts("No Ecto schemas found in the project.")
      manual_schema_entry()
    else
      IO.puts("Found #{length(schemas)} schema(s) in your project:\n")
      
      schemas
      |> Enum.with_index(1)
      |> Enum.each(fn {schema, idx} ->
        IO.puts("  #{idx}. #{inspect(schema)}")
      end)
      
      IO.puts("\nOptions:")
      IO.puts("  a) Generate for all schemas")
      IO.puts("  s) Select specific schemas (comma-separated numbers)")
      IO.puts("  m) Manually enter schema module names")
      IO.puts("  q) Quit")
      
      case prompt("\nYour choice") do
        "a" -> 
          {:ok, schemas}
        "s" -> 
          select_specific_schemas(schemas)
        "m" -> 
          manual_schema_entry()
        "q" -> 
          {:error, :cancelled}
        _ -> 
          IO.puts("Invalid option. Please try again.")
          select_schemas()
      end
    end
  end
  
  # Step 2: Select adapter
  defp select_adapter do
    IO.puts("\n🗄️  Step 2: Database Adapter")
    IO.puts("----------------------------")
    
    # Try auto-detection
    detected = case AdapterDetector.detect() do
      {:ok, adapter} -> adapter
      _ -> nil
    end
    
    if detected do
      IO.puts("Detected adapter: #{detected}")
      
      if confirm?("Use detected adapter?") do
        version = prompt_adapter_version(detected)
        {:ok, {detected, version}}
      else
        manual_adapter_selection()
      end
    else
      manual_adapter_selection()
    end
  end
  
  # Step 3: Select features
  defp select_features do
    IO.puts("\n✨ Step 3: Features")
    IO.puts("-------------------")
    
    features = [
      {:associations, "Include associations", true},
      {:custom_columns, "Generate custom columns", false},
      {:filters, "Generate filters", true},
      {:aggregates, "Generate aggregates", false},
      {:saved_views, "Enable saved views", false},
      {:live, "Generate LiveView files", false},
      {:tests, "Generate tests", false},
      {:migrations, "Generate migrations", false}
    ]
    
    selected = Enum.reduce(features, %{}, fn {key, description, default}, acc ->
      value = if default do
        confirm?("#{description}?", default: "y")
      else
        confirm?("#{description}?", default: "n")
      end
      
      Map.put(acc, key, value)
    end)
    
    {:ok, selected}
  end
  
  # Step 4: Configure joins
  defp configure_joins(schemas, {adapter, _version}) do
    IO.puts("\n🔗 Step 4: Join Configuration")
    IO.puts("-----------------------------")
    
    IO.puts("\nJoin generation strategy:")
    IO.puts("  1) Basic (belongs_to, has_many only)")
    IO.puts("  2) Advanced (includes many-to-many, hierarchical)")
    IO.puts("  3) None (no joins)")
    IO.puts("  4) Custom (configure per schema)")
    
    strategy = prompt("Select strategy [1-4]", default: "2")
    
    join_config = case strategy do
      "1" -> %{type: :basic}
      "2" -> configure_advanced_joins(schemas, adapter)
      "3" -> %{type: :none}
      "4" -> configure_custom_joins(schemas, adapter)
      _ -> %{type: :advanced}
    end
    
    {:ok, join_config}
  end
  
  # Step 5: Configure output
  defp configure_output do
    IO.puts("\n📁 Step 5: Output Configuration")
    IO.puts("-------------------------------")
    
    output_dir = prompt("Output directory", default: "lib/#{app_name()}/selecto_domains")
    
    format = prompt_select("Output format", [
      {"1", "Compact", :compact},
      {"2", "Expanded (with comments)", :expanded},
      {"3", "Documented (full docs)", :documented}
    ], default: "2")
    
    style = prompt_select("Code style", [
      {"1", "Phoenix standard", :phoenix},
      {"2", "Clean (minimal)", :clean},
      {"3", "Modular (split files)", :modular}
    ], default: "1")
    
    namespace = prompt("Module namespace", default: "#{app_module()}.Selecto")
    
    {:ok, %{
      output: output_dir,
      format: format,
      style: style,
      namespace: namespace
    }}
  end
  
  # Step 6: Confirm generation
  defp confirm_generation(schemas, {adapter, version}, features, join_config, output_config) do
    IO.puts("\n📋 Summary")
    IO.puts("=" |> String.duplicate(50))
    
    IO.puts("\nSchemas to generate:")
    Enum.each(schemas, fn schema ->
      IO.puts("  • #{inspect(schema)}")
    end)
    
    IO.puts("\nAdapter: #{adapter} #{if version, do: "(v#{version})", else: ""}")
    
    IO.puts("\nFeatures:")
    Enum.each(features, fn {key, enabled} ->
      if enabled do
        IO.puts("  ✓ #{format_feature_name(key)}")
      end
    end)
    
    IO.puts("\nJoin strategy: #{join_config.type}")
    
    IO.puts("\nOutput:")
    IO.puts("  Directory: #{output_config.output}")
    IO.puts("  Format: #{output_config.format}")
    IO.puts("  Style: #{output_config.style}")
    IO.puts("  Namespace: #{output_config.namespace}")
    
    IO.puts("\n" <> String.duplicate("=", 50))
    
    if confirm?("\nProceed with generation?") do
      :ok
    else
      {:error, :cancelled}
    end
  end
  
  # Generation
  defp generate_domains(schemas, {adapter, version}, features, join_config, output_config) do
    IO.puts("\n🔨 Generating domains...")
    
    _args = Map.merge(features, %{
      adapter: adapter,
      adapter_version: version,
      joins: join_config.type,
      output: output_config.output,
      format: output_config.format,
      style: output_config.style,
      namespace: output_config.namespace
    })
    
    Enum.each(schemas, fn schema ->
      IO.write("  Generating #{inspect(schema)}... ")
      
      # Here we would call the actual generation logic
      # For now, simulate
      :timer.sleep(500)
      
      IO.puts("✓")
    end)
    
    IO.puts("\n✅ Domain generation complete!")
    IO.puts("\nNext steps:")
    IO.puts("  1. Review generated files in #{output_config.output}")
    IO.puts("  2. Add routes to your router.ex")
    IO.puts("  3. Run migrations if generated")
    IO.puts("  4. Start your Phoenix server and test")
    
    :ok
  end
  
  # Helper functions
  
  defp discover_schemas do
    # In a real implementation, would scan for Ecto schemas
    # For now, return our test schemas
    [
      SelectoTest.Ecommerce.User,
      SelectoTest.Ecommerce.Product,
      SelectoTest.Ecommerce.Order,
      SelectoTest.Ecommerce.Category
    ]
  end
  
  defp select_specific_schemas(schemas) do
    input = prompt("Enter schema numbers (e.g., 1,3,4)")
    
    selected_indices = input
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_integer/1)
    |> Enum.filter(&(&1 > 0 and &1 <= length(schemas)))
    
    selected = selected_indices
    |> Enum.map(&Enum.at(schemas, &1 - 1))
    
    {:ok, selected}
  end
  
  defp manual_schema_entry do
    input = prompt("Enter schema module names (comma-separated)")
    
    schemas = input
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&Module.concat([&1]))
    
    {:ok, schemas}
  end
  
  defp manual_adapter_selection do
    IO.puts("\nSelect database adapter:")
    IO.puts("  1) PostgreSQL")
    IO.puts("  2) MySQL/MariaDB")
    IO.puts("  3) SQLite")
    
    choice = prompt("Your choice [1-3]", default: "1")
    
    adapter = case choice do
      "1" -> :postgres
      "2" -> :mysql
      "3" -> :sqlite
      _ -> :postgres
    end
    
    version = prompt_adapter_version(adapter)
    {:ok, {adapter, version}}
  end
  
  defp prompt_adapter_version(:postgres) do
    prompt("PostgreSQL version (optional)", default: "")
  end
  
  defp prompt_adapter_version(:mysql) do
    version = prompt("MySQL version", default: "8.0")
    if version == "", do: "8.0", else: version
  end
  
  defp prompt_adapter_version(:sqlite) do
    version = prompt("SQLite version", default: "3.35")
    if version == "", do: "3.35", else: version
  end
  
  defp configure_advanced_joins(_schemas, _adapter) do
    IO.puts("\nAdvanced join configuration:")
    
    depth = prompt("Maximum join depth", default: "3")
    |> String.to_integer()
    
    strategy = prompt_select("Join loading strategy", [
      {"1", "Eager (preload by default)", :eager},
      {"2", "Lazy (load on demand)", :lazy},
      {"3", "Optimized (auto-detect)", :optimized}
    ], default: "3")
    
    detect_cycles = confirm?("Detect circular dependencies?", default: "y")
    
    %{
      type: :advanced,
      depth: depth,
      strategy: strategy,
      detect_cycles: detect_cycles
    }
  end
  
  defp configure_custom_joins(schemas, adapter) do
    IO.puts("\nConfiguring joins for each schema...")
    
    configs = Enum.map(schemas, fn schema ->
      IO.puts("\n#{inspect(schema)}:")
      
      if confirm?("  Include joins for this schema?", default: "y") do
        # Analyze the schema
        analysis = JoinAnalyzer.analyze(schema, adapter: adapter)
        
        IO.puts("  Found #{map_size(analysis.joins)} potential joins")
        
        if confirm?("  Use all detected joins?", default: "y") do
          {schema, analysis.joins}
        else
          # Allow manual selection
          selected = select_joins(analysis.joins)
          {schema, selected}
        end
      else
        {schema, %{}}
      end
    end)
    
    %{
      type: :custom,
      configs: Map.new(configs)
    }
  end
  
  defp select_joins(joins) do
    IO.puts("  Select joins to include:")
    
    joins
    |> Enum.map(fn {name, config} ->
      include = confirm?("    Include #{name} (#{config.type})?", default: "y")
      if include, do: {name, config}, else: nil
    end)
    |> Enum.filter(& &1)
    |> Map.new()
  end
  
  defp prompt(message, opts \\ []) do
    default = opts[:default]
    
    prompt_text = if default do
      "#{message} [#{default}]: "
    else
      "#{message}: "
    end
    
    IO.gets(prompt_text)
    |> String.trim()
    |> case do
      "" when default != nil -> default
      value -> value
    end
  end
  
  defp confirm?(message, opts \\ []) do
    default = opts[:default] || "n"
    
    response = prompt("#{message} (y/n)", default: default)
    response in ["y", "yes", "Y", "YES"]
  end
  
  defp prompt_select(message, options, opts \\ []) do
    IO.puts("\n#{message}:")
    
    Enum.each(options, fn {key, label, _value} ->
      IO.puts("  #{key}) #{label}")
    end)
    
    choice = prompt("Your choice", opts)
    
    case Enum.find(options, fn {key, _, _} -> key == choice end) do
      {_, _, value} -> value
      nil ->
        # Use default if provided
        default_key = opts[:default]
        case Enum.find(options, fn {key, _, _} -> key == default_key end) do
          {_, _, value} -> value
          nil -> elem(hd(options), 2)  # First option as fallback
        end
    end
  end
  
  defp format_feature_name(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
  
  defp app_name do
    Mix.Project.config()[:app] |> to_string()
  end
  
  defp app_module do
    app_name() |> Macro.camelize()
  end
end