defmodule SelectoMix.CLIParser do
  @moduledoc """
  Comprehensive command-line argument parser for SelectoMix tasks.
  
  Provides a rich set of options for controlling domain generation,
  database adapter configuration, and output customization.
  """
  
  @type parsed_args :: %{
    # Core options
    adapter: atom() | nil,
    output: String.t() | nil,
    force: boolean(),
    dry_run: boolean(),
    validate: boolean(),
    verbose: boolean(),
    quiet: boolean(),
    
    # Feature flags
    associations: boolean(),
    joins: atom(),  # :all | :basic | :advanced | :none
    custom_columns: boolean(),
    filters: boolean(),
    aggregates: boolean(),
    saved_views: boolean(),
    live: boolean(),
    tests: boolean(),
    migrations: boolean(),
    
    # Join configuration
    join_depth: integer(),
    join_strategy: atom(),  # :eager | :lazy | :optimized
    parameterized_joins: boolean(),
    hierarchical: boolean(),
    detect_cycles: boolean(),
    
    # Database-specific
    adapter_version: String.t() | nil,
    extensions: [String.t()],
    
    # Schema selection
    schemas: [String.t()],
    exclude: [String.t()],
    expand_schemas: [String.t()],
    context: String.t() | nil,
    
    # Output control
    format: atom(),  # :compact | :expanded | :documented
    style: atom(),   # :phoenix | :clean | :modular
    namespace: String.t() | nil,
    
    # Configuration
    config_file: String.t() | nil,
    environment: atom(),
    profile: String.t() | nil,
    
    # Interactive mode
    interactive: boolean(),
    
    # Raw args for passthrough
    raw_args: [String.t()]
  }
  
  @doc """
  Defines the schema for all available CLI options.
  """
  @spec option_schema() :: keyword()
  def option_schema do
    [
      # Core options
      adapter: :string,
      output: :string,
      force: :boolean,
      dry_run: :boolean,
      validate: :boolean,
      verbose: :boolean,
      quiet: :boolean,
      
      # Feature flags
      associations: :boolean,
      joins: :string,
      custom_columns: :boolean,
      filters: :boolean,
      aggregates: :boolean,
      saved_views: :boolean,
      live: :boolean,
      tests: :boolean,
      migrations: :boolean,
      
      # Join configuration
      join_depth: :integer,
      join_strategy: :string,
      parameterized_joins: :boolean,
      hierarchical: :boolean,
      detect_cycles: :boolean,
      
      # Database-specific
      mysql_version: :string,
      postgres_version: :string,
      sqlite_version: :string,
      mysql_extensions: :string,
      postgres_extensions: :string,
      sqlite_extensions: :string,
      
      # Schema selection
      all: :boolean,
      exclude: :string,
      expand_schemas: :string,
      context: :string,
      
      # Output control
      format: :string,
      style: :string,
      namespace: :string,
      
      # Configuration
      config: :string,
      env: :string,
      profile: :string,
      
      # Interactive mode
      interactive: :boolean,
      
      # Help
      help: :boolean
    ]
  end
  
  @doc """
  Defines aliases for common options.
  """
  @spec option_aliases() :: keyword()
  def option_aliases do
    [
      a: :adapter,
      o: :output,
      f: :force,
      d: :dry_run,
      v: :verbose,
      q: :quiet,
      l: :live,
      s: :saved_views,
      t: :tests,
      e: :expand_schemas,
      p: :parameterized_joins,
      c: :config,
      i: :interactive,
      h: :help,
      n: :namespace,
      j: :joins
    ]
  end
  
  @doc """
  Parses command-line arguments into a structured map.
  """
  @spec parse(list(String.t())) :: {:ok, parsed_args()} | {:error, String.t()}
  def parse(argv) do
    case OptionParser.parse(argv, 
           strict: option_schema(), 
           aliases: option_aliases()) do
      {opts, args, []} ->
        {:ok, build_parsed_args(opts, args)}
      
      {_opts, _args, [{key, value}]} ->
        {:error, format_parse_error(key, value)}
      
      {_opts, _args, errors} ->
        {:error, format_multiple_errors(errors)}
    end
  end
  
  @doc """
  Parses arguments with enhanced validation and defaults.
  """
  @spec parse!(list(String.t())) :: parsed_args()
  def parse!(argv) do
    case parse(argv) do
      {:ok, args} -> args
      {:error, message} -> Mix.raise(message)
    end
  end
  
  @doc """
  Merges CLI arguments with configuration file settings.
  """
  @spec merge_with_config(parsed_args(), map()) :: parsed_args()
  def merge_with_config(cli_args, config) do
    # CLI args take precedence over config file
    Map.merge(config, cli_args, fn _key, config_val, cli_val -> 
      cli_val || config_val
    end)
  end
  
  @doc """
  Validates parsed arguments for consistency and correctness.
  """
  @spec validate_args(parsed_args()) :: :ok | {:error, [String.t()]}
  def validate_args(args) do
    errors = []
    
    # Validate adapter
    errors = case args[:adapter] do
      nil -> errors
      adapter when adapter in [:postgres, :mysql, :sqlite] -> errors
      adapter -> ["Invalid adapter: #{adapter}" | errors]
    end
    
    # Validate joins option
    errors = case args[:joins] do
      nil -> errors
      joins when joins in [:all, :basic, :advanced, :none] -> errors
      joins -> ["Invalid joins option: #{joins}" | errors]
    end
    
    # Validate join strategy
    errors = case args[:join_strategy] do
      nil -> errors
      strategy when strategy in [:eager, :lazy, :optimized] -> errors
      strategy -> ["Invalid join strategy: #{strategy}" | errors]
    end
    
    # Validate format
    errors = case args[:format] do
      nil -> errors
      format when format in [:compact, :expanded, :documented] -> errors
      format -> ["Invalid format: #{format}" | errors]
    end
    
    # Validate style
    errors = case args[:style] do
      nil -> errors
      style when style in [:phoenix, :clean, :modular] -> errors
      style -> ["Invalid style: #{style}" | errors]
    end
    
    # Check for conflicting options
    errors = if args[:quiet] && args[:verbose] do
      ["Cannot use --quiet and --verbose together" | errors]
    else
      errors
    end
    
    errors = if args[:saved_views] && !args[:live] do
      ["--saved-views requires --live to be set" | errors]
    else
      errors
    end
    
    errors = if args[:interactive] && args[:dry_run] do
      ["Cannot use --interactive with --dry-run" | errors]
    else
      errors
    end
    
    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end
  
  @doc """
  Provides help text for all available options.
  """
  @spec help_text() :: String.t()
  def help_text do
    """
    SelectoMix Domain Generator
    
    Usage:
      mix selecto.gen.domain [SCHEMAS] [OPTIONS]
    
    Core Options:
      --adapter ADAPTER        Database adapter (postgres|mysql|sqlite|auto)
      -o, --output PATH       Output directory for generated files
      -f, --force            Overwrite existing files without confirmation
      -d, --dry-run          Preview changes without creating files
      --validate             Validate generated domains
      -v, --verbose          Show detailed output
      -q, --quiet            Suppress non-essential output
    
    Feature Flags:
      --associations         Include association configurations (default: true)
      -j, --joins TYPE       Join generation (all|basic|advanced|none)
      --custom-columns       Generate custom column configurations
      --filters              Generate filter configurations
      --aggregates           Generate aggregate configurations
      -s, --saved-views      Generate saved views support (requires --live)
      -l, --live             Generate LiveView files
      -t, --tests            Generate test files
      --migrations           Generate migration files
    
    Join Configuration:
      --join-depth DEPTH          Maximum join traversal depth (default: 3)
      --join-strategy STRATEGY    Join strategy (eager|lazy|optimized)
      -p, --parameterized-joins   Include parameterized join examples
      --hierarchical              Detect hierarchical relationships
      --detect-cycles             Detect and prevent circular dependencies
    
    Database-Specific:
      --mysql-version VERSION      MySQL version for feature detection
      --postgres-version VERSION   PostgreSQL version
      --sqlite-version VERSION     SQLite version
      --mysql-extensions EXTS      MySQL extensions (comma-separated)
      --postgres-extensions EXTS   PostgreSQL extensions
      --sqlite-extensions EXTS     SQLite extensions (e.g., json1,fts5)
    
    Schema Selection:
      --all                    Generate domains for all schemas
      --exclude PATTERN        Exclude schemas matching pattern
      -e, --expand-schemas     Fully expand specified schemas
      --context MODULE         Context module for organization
    
    Output Control:
      --format FORMAT          Output format (compact|expanded|documented)
      --style STYLE           Code style (phoenix|clean|modular)
      -n, --namespace NS       Custom namespace for modules
    
    Configuration:
      -c, --config FILE        Configuration file path
      --env ENVIRONMENT        Environment to use from config
      --profile PROFILE        Profile to use from config
    
    Interactive:
      -i, --interactive        Interactive mode with prompts
    
    Examples:
      # Generate domain for a single schema
      mix selecto.gen.domain Blog.Post
      
      # Generate with MySQL adapter
      mix selecto.gen.domain Blog.Post --adapter mysql --mysql-version 8.0
      
      # Generate all domains with tests
      mix selecto.gen.domain --all --tests --validate
      
      # Interactive mode
      mix selecto.gen.domain --interactive
      
      # Use configuration file
      mix selecto.gen.domain Blog.* --config .selecto.yml --env production
    """
  end
  
  # Private functions
  
  defp build_parsed_args(opts, positional_args) do
    %{
      # Core options
      adapter: parse_atom(opts[:adapter]),
      output: opts[:output],
      force: opts[:force] || false,
      dry_run: opts[:dry_run] || false,
      validate: opts[:validate] || false,
      verbose: opts[:verbose] || false,
      quiet: opts[:quiet] || false,
      
      # Feature flags with defaults
      associations: Keyword.get(opts, :associations, true),
      joins: parse_atom(opts[:joins]) || :basic,
      custom_columns: opts[:custom_columns] || false,
      filters: opts[:filters] || false,
      aggregates: opts[:aggregates] || false,
      saved_views: opts[:saved_views] || false,
      live: opts[:live] || false,
      tests: opts[:tests] || false,
      migrations: opts[:migrations] || false,
      
      # Join configuration
      join_depth: opts[:join_depth] || 3,
      join_strategy: parse_atom(opts[:join_strategy]) || :optimized,
      parameterized_joins: opts[:parameterized_joins] || false,
      hierarchical: opts[:hierarchical] || false,
      detect_cycles: Keyword.get(opts, :detect_cycles, true),
      
      # Database-specific
      adapter_version: get_adapter_version(opts),
      extensions: get_extensions(opts),
      
      # Schema selection
      schemas: parse_schemas(positional_args, opts),
      exclude: parse_list(opts[:exclude]),
      expand_schemas: parse_list(opts[:expand_schemas]),
      context: opts[:context],
      
      # Output control
      format: parse_atom(opts[:format]) || :expanded,
      style: parse_atom(opts[:style]) || :phoenix,
      namespace: opts[:namespace],
      
      # Configuration
      config_file: opts[:config],
      environment: parse_atom(opts[:env]) || Mix.env(),
      profile: opts[:profile],
      
      # Interactive mode
      interactive: opts[:interactive] || false,
      
      # Help flag
      help: opts[:help] || false,
      
      # Raw args for passthrough
      raw_args: positional_args
    }
  end
  
  defp parse_atom(nil), do: nil
  defp parse_atom(value) when is_atom(value), do: value
  defp parse_atom(value) when is_binary(value), do: String.to_atom(value)
  
  defp parse_list(nil), do: []
  defp parse_list(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
  
  defp parse_schemas(positional_args, opts) do
    cond do
      opts[:all] -> [:all]
      positional_args != [] -> positional_args
      true -> []
    end
  end
  
  defp get_adapter_version(opts) do
    opts[:mysql_version] || opts[:postgres_version] || opts[:sqlite_version]
  end
  
  defp get_extensions(opts) do
    extensions = []
    
    extensions = if opts[:mysql_extensions] do
      extensions ++ parse_list(opts[:mysql_extensions])
    else
      extensions
    end
    
    extensions = if opts[:postgres_extensions] do
      extensions ++ parse_list(opts[:postgres_extensions])
    else
      extensions
    end
    
    extensions = if opts[:sqlite_extensions] do
      extensions ++ parse_list(opts[:sqlite_extensions])
    else
      extensions
    end
    
    extensions
  end
  
  defp format_parse_error(key, nil) do
    "Invalid option: --#{key}"
  end
  
  defp format_parse_error(key, value) do
    "Invalid value for --#{key}: #{value}"
  end
  
  defp format_multiple_errors(errors) do
    error_messages = Enum.map(errors, fn {key, value} ->
      format_parse_error(key, value)
    end)
    
    Enum.join(["Multiple errors:" | error_messages], "\n  ")
  end
end