defmodule SelectoMix.ConfigLoader do
  @moduledoc """
  Loads and processes SelectoMix configuration from YAML files.
  
  Supports hierarchical configuration with environment-specific overrides
  and profile-based settings.
  """
  
  @default_config_paths [
    ".selecto.yml",
    ".selecto.yaml",
    "config/selecto.yml",
    "config/selecto.yaml",
    ".selecto/config.yml"
  ]
  
  @type config :: %{
    version: String.t(),
    defaults: map(),
    adapters: map(),
    generation: map(),
    templates: map(),
    environments: map(),
    profiles: map()
  }
  
  @doc """
  Loads configuration from file or auto-detects config file.
  
  ## Options
    * `:path` - Explicit path to config file
    * `:env` - Environment to use (default: Mix.env())
    * `:profile` - Profile to apply
  """
  @spec load(keyword()) :: {:ok, config()} | {:error, String.t()}
  def load(opts \\ []) do
    case find_config_file(opts[:path]) do
      {:ok, path} ->
        load_from_file(path, opts)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Loads configuration from a specific file path.
  """
  @spec load_from_file(String.t(), keyword()) :: {:ok, config()} | {:error, String.t()}
  def load_from_file(path, opts \\ []) do
    with {:ok, content} <- File.read(path),
         {:ok, yaml} <- parse_yaml(content),
         {:ok, config} <- validate_config(yaml) do
      
      final_config = config
      |> apply_environment(opts[:env] || Mix.env())
      |> apply_profile(opts[:profile])
      |> resolve_variables()
      
      {:ok, final_config}
    end
  end
  
  @doc """
  Merges configuration with CLI arguments.
  CLI arguments take precedence over file configuration.
  """
  @spec merge_with_cli(config(), map()) :: map()
  def merge_with_cli(config, cli_args) do
    base = extract_base_config(config)
    
    # CLI args override config file settings
    Map.merge(base, cli_args, fn _key, config_val, cli_val ->
      cli_val || config_val
    end)
  end
  
  @doc """
  Creates a default configuration template.
  """
  @spec generate_template(String.t()) :: :ok | {:error, term()}
  def generate_template(path \\ ".selecto.yml") do
    template = """
    # SelectoMix Configuration
    version: "1.0"
    
    # Default settings for all environments
    defaults:
      adapter: postgres
      validate: true
      associations: true
      joins: advanced
      join_depth: 3
      join_strategy: optimized
      detect_cycles: true
    
    # Database adapter configurations
    adapters:
      postgres:
        extensions: [uuid-ossp, ltree]
        version: "14.0"
      mysql:
        version: "8.0"
        charset: utf8mb4
        collation: utf8mb4_unicode_ci
      sqlite:
        extensions: [json1, fts5]
        journal_mode: wal
        foreign_keys: on
    
    # Code generation settings
    generation:
      output: lib/${app_name}/selecto_domains
      style: modular
      format: documented
      namespace: ${app_module}.Selecto
      
      features:
        custom_columns: true
        filters: true
        aggregates: true
        saved_views: false
        tests: false
        migrations: false
        live: false
    
    # Template customization
    templates:
      override_path: null
      use_custom: false
      
    # Environment-specific overrides
    environments:
      development:
        adapter: postgres
        validate: false
        generation:
          format: expanded
          
      test:
        adapter: sqlite
        validate: false
        generation:
          output: lib/${app_name}/selecto_test
          tests: true
          
      production:
        adapter: ${DATABASE_ADAPTER}
        validate: true
        generation:
          format: compact
          optimize: true
    
    # Named profiles for common scenarios
    profiles:
      minimal:
        associations: false
        joins: none
        features:
          custom_columns: false
          filters: false
          aggregates: false
          
      full:
        associations: true
        joins: advanced
        features:
          custom_columns: true
          filters: true
          aggregates: true
          saved_views: true
          tests: true
          migrations: true
          live: true
          
      performance:
        join_strategy: lazy
        join_depth: 2
        detect_cycles: false
        generation:
          format: compact
          optimize: true
    """
    
    File.write(path, template)
  end
  
  # Private functions
  
  defp find_config_file(nil) do
    # Auto-detect config file
    case Enum.find(@default_config_paths, &File.exists?/1) do
      nil -> {:error, "No configuration file found. Create .selecto.yml or use --config"}
      path -> {:ok, path}
    end
  end
  
  defp find_config_file(path) do
    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "Configuration file not found: #{path}"}
    end
  end
  
  defp parse_yaml(content) do
    # Use YamlElixir or similar library
    # For now, we'll use a simple implementation
    try do
      # This would use a YAML parser library in production
      parsed = parse_simple_yaml(content)
      {:ok, parsed}
    rescue
      e -> {:error, "Failed to parse YAML: #{inspect(e)}"}
    end
  end
  
  defp parse_simple_yaml(content) do
    # Simplified YAML parser for demonstration
    # In production, use :yaml_elixir or :yamerl
    
    content
    |> String.split("\n")
    |> Enum.reduce(%{current_section: nil, result: %{}}, fn line, acc ->
      cond do
        # Skip comments and empty lines
        String.starts_with?(String.trim(line), "#") or String.trim(line) == "" ->
          acc
          
        # Section header
        String.match?(line, ~r/^[a-z_]+:$/) ->
          section = line |> String.trim() |> String.trim_trailing(":")
          %{acc | current_section: String.to_atom(section)}
          
        # Key-value pair
        String.contains?(line, ":") ->
          [key, value] = String.split(line, ":", parts: 2)
          key = key |> String.trim() |> String.to_atom()
          value = parse_yaml_value(String.trim(value))
          
          if acc.current_section do
            result = Map.update(acc.result, acc.current_section, %{key => value}, 
              &Map.put(&1, key, value))
            %{acc | result: result}
          else
            %{acc | result: Map.put(acc.result, key, value)}
          end
          
        true ->
          acc
      end
    end)
    |> Map.get(:result)
  end
  
  defp parse_yaml_value("true"), do: true
  defp parse_yaml_value("false"), do: false
  defp parse_yaml_value("null"), do: nil
  defp parse_yaml_value("nil"), do: nil
  defp parse_yaml_value("\"" <> _ = str), do: String.trim(str, "\"")
  defp parse_yaml_value("'" <> _ = str), do: String.trim(str, "'")
  defp parse_yaml_value("[" <> _ = str), do: parse_yaml_array(str)
  
  defp parse_yaml_value(str) do
    cond do
      String.match?(str, ~r/^\d+$/) -> String.to_integer(str)
      String.match?(str, ~r/^\d+\.\d+$/) -> String.to_float(str)
      true -> str
    end
  end
  
  defp parse_yaml_array(str) do
    str
    |> String.trim("[")
    |> String.trim("]")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_yaml_value/1)
  end
  
  defp validate_config(yaml) do
    # Basic validation
    cond do
      not is_map(yaml) ->
        {:error, "Invalid configuration format"}
        
      Map.get(yaml, :version) not in ["1.0", nil] ->
        {:error, "Unsupported configuration version"}
        
      true ->
        {:ok, yaml}
    end
  end
  
  defp apply_environment(config, env) do
    env_config = get_in(config, [:environments, env]) || %{}
    deep_merge(config, env_config)
  end
  
  defp apply_profile(config, nil), do: config
  
  defp apply_profile(config, profile) when is_binary(profile) do
    apply_profile(config, String.to_atom(profile))
  end
  
  defp apply_profile(config, profile) when is_atom(profile) do
    profile_config = get_in(config, [:profiles, profile]) || %{}
    deep_merge(config, profile_config)
  end
  
  defp resolve_variables(config) do
    # Replace ${var} with actual values
    config_str = inspect(config)
    
    resolved_str = config_str
    |> String.replace("${app_name}", to_string(Mix.Project.config()[:app]))
    |> String.replace("${app_module}", Mix.Project.config()[:app] |> to_string() |> Macro.camelize())
    |> String.replace("${DATABASE_ADAPTER}", System.get_env("DATABASE_ADAPTER", "postgres"))
    
    # Convert back to map (simplified)
    {resolved, _} = Code.eval_string(resolved_str)
    resolved
  end
  
  defp extract_base_config(config) do
    defaults = Map.get(config, :defaults, %{})
    generation = Map.get(config, :generation, %{})
    
    # Flatten the configuration into CLI-compatible format
    Map.merge(defaults, %{
      output: generation[:output],
      format: String.to_atom(to_string(generation[:format] || :expanded)),
      style: String.to_atom(to_string(generation[:style] || :phoenix)),
      namespace: generation[:namespace]
    })
    |> Map.merge(generation[:features] || %{})
  end
  
  defp deep_merge(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn
      _key, val1, val2 when is_map(val1) and is_map(val2) ->
        deep_merge(val1, val2)
      _key, _val1, val2 ->
        val2
    end)
  end
  
  defp deep_merge(map1, _map2), do: map1
end