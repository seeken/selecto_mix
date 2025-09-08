defmodule SelectoMix.AdapterDetector do
  @moduledoc """
  Detects and configures database adapters for Selecto domain generation.
  
  Supports automatic detection from project configuration and provides
  adapter-specific feature mapping and capabilities.
  """
  
  @known_adapters [:postgres, :mysql, :sqlite]
  
  # @adapter_modules %{
  #   postgres: {Ecto.Adapters.Postgres, Postgrex},
  #   mysql: {Ecto.Adapters.MyXQL, MyXQL},
  #   sqlite: {Ecto.Adapters.SQLite3, Exqlite}
  # }
  
  @adapter_features %{
    postgres: %{
      arrays: true,
      ctes: true,
      recursive_ctes: true,
      window_functions: true,
      lateral_joins: true,
      full_outer_join: true,
      json_operators: true,
      uuid_native: true,
      materialized_views: true,
      partial_indexes: true,
      check_constraints: true,
      exclusion_constraints: true,
      generated_columns: true,
      table_inheritance: true,
      listen_notify: true
    },
    mysql: %{
      arrays: false,  # Use JSON arrays instead
      ctes: {">= 8.0", true, false},  # Version dependent
      recursive_ctes: {">= 8.0", true, false},
      window_functions: {">= 8.0", true, false},
      lateral_joins: {">= 8.0.14", true, false},  # Limited support
      full_outer_join: false,
      json_operators: true,
      uuid_native: false,  # Store as string
      materialized_views: false,
      partial_indexes: {">= 8.0.13", true, false},
      check_constraints: {">= 8.0.16", true, false},
      exclusion_constraints: false,
      generated_columns: {">= 5.7", true, false},
      table_inheritance: false,
      listen_notify: false
    },
    sqlite: %{
      arrays: false,  # Use JSON arrays
      ctes: true,
      recursive_ctes: true,
      window_functions: {">= 3.25", true, false},
      lateral_joins: false,
      full_outer_join: false,
      json_operators: true,  # Requires JSON1 extension
      uuid_native: false,  # Store as text
      materialized_views: false,
      partial_indexes: true,
      check_constraints: true,
      exclusion_constraints: false,
      generated_columns: {">= 3.31", true, false},
      table_inheritance: false,
      listen_notify: false
    }
  }
  
  @type adapter :: :postgres | :mysql | :sqlite
  @type detection_result :: {:ok, adapter} | {:error, String.t()}
  @type feature_map :: %{atom() => boolean() | {String.t(), boolean(), boolean()}}
  
  @doc """
  Detects the database adapter from project configuration.
  
  ## Options
    * `:repo` - The repo module to check (default: auto-detect)
    * `:config_path` - Path to config file (default: config/config.exs)
    * `:env` - Environment to check (default: Mix.env())
  """
  @spec detect(keyword()) :: detection_result()
  def detect(opts \\ []) do
    cond do
      # Check if adapter was explicitly provided
      adapter = opts[:adapter] ->
        validate_adapter(adapter)
      
      # Check from repo configuration
      repo = opts[:repo] || auto_detect_repo() ->
        detect_from_repo(repo)
      
      # Check from dependencies
      true ->
        detect_from_deps()
    end
  end
  
  @doc """
  Auto-detects the primary repo module in the application.
  """
  @spec auto_detect_repo() :: module() | nil
  def auto_detect_repo do
    app = Mix.Project.config()[:app]
    
    # Try common repo naming patterns
    possible_repos = [
      Module.concat([Macro.camelize(to_string(app)), "Repo"]),
      Module.concat([Macro.camelize(to_string(app)), "Repo", "Local"]),
      Module.concat([Macro.camelize(to_string(app)), "Database", "Repo"])
    ]
    
    Enum.find(possible_repos, &Code.ensure_loaded?/1)
  end
  
  @doc """
  Detects adapter from a repo module configuration.
  """
  @spec detect_from_repo(module()) :: detection_result()
  def detect_from_repo(repo) when is_atom(repo) do
    if Code.ensure_loaded?(repo) do
      case repo.__adapter__() do
        Ecto.Adapters.Postgres -> {:ok, :postgres}
        Ecto.Adapters.MyXQL -> {:ok, :mysql}
        Ecto.Adapters.SQLite3 -> {:ok, :sqlite}
        adapter -> {:error, "Unknown adapter: #{inspect(adapter)}"}
      end
    else
      {:error, "Repo module #{inspect(repo)} not found"}
    end
  rescue
    _ -> {:error, "Could not detect adapter from repo #{inspect(repo)}"}
  end
  
  @doc """
  Detects adapter from project dependencies.
  """
  @spec detect_from_deps() :: detection_result()
  def detect_from_deps do
    deps = Mix.Project.config()[:deps] || []
    
    cond do
      has_dep?(deps, :postgrex) -> {:ok, :postgres}
      has_dep?(deps, :myxql) -> {:ok, :mysql}
      has_dep?(deps, :exqlite) -> {:ok, :sqlite}
      true -> {:error, "No database driver dependency found"}
    end
  end
  
  @doc """
  Gets the feature map for a given adapter and version.
  """
  @spec get_features(adapter(), String.t() | nil) :: feature_map()
  def get_features(adapter, version \\ nil) do
    base_features = @adapter_features[adapter] || %{}
    
    Enum.map(base_features, fn
      {feature, {min_version, supported, unsupported}} when is_binary(min_version) ->
        {feature, version_supported?(version, min_version, supported, unsupported)}
      
      {feature, value} ->
        {feature, value}
    end)
    |> Map.new()
  end
  
  @doc """
  Gets type mappings for converting between adapters.
  """
  @spec get_type_mappings(adapter()) :: map()
  def get_type_mappings(:postgres), do: %{}  # PostgreSQL is our baseline
  
  def get_type_mappings(:mysql) do
    %{
      uuid: :string,
      array: :json,
      jsonb: :json,
      text: :text,
      serial: :integer,
      bigserial: :bigint,
      boolean: :boolean,  # MySQL uses TINYINT(1)
      macaddr: :string,
      inet: :string,
      cidr: :string,
      ltree: :string
    }
  end
  
  def get_type_mappings(:sqlite) do
    %{
      uuid: :string,
      array: :json,
      jsonb: :json,
      json: :json,
      serial: :integer,
      bigserial: :integer,
      bigint: :integer,
      decimal: :real,
      boolean: :integer,  # SQLite uses 0/1
      timestamp: :text,
      timestamptz: :text,
      date: :text,
      time: :text,
      timetz: :text,
      macaddr: :text,
      inet: :text,
      cidr: :text,
      ltree: :text
    }
  end
  
  @doc """
  Generates adapter-specific SQL for common operations.
  """
  @spec sql_dialect(adapter(), atom(), keyword()) :: String.t()
  def sql_dialect(:postgres, :array_contains, field: field, value: value) do
    "#{field} @> ARRAY[#{value}]"
  end
  
  def sql_dialect(:mysql, :array_contains, field: field, value: value) do
    "JSON_CONTAINS(#{field}, '#{value}')"
  end
  
  def sql_dialect(:sqlite, :array_contains, field: field, value: value) do
    "json_array_contains(#{field}, '#{value}')"
  end
  
  def sql_dialect(:postgres, :json_extract, field: field, path: path) do
    "#{field}->>'#{path}'"
  end
  
  def sql_dialect(:mysql, :json_extract, field: field, path: path) do
    "JSON_UNQUOTE(JSON_EXTRACT(#{field}, '$.#{path}'))"
  end
  
  def sql_dialect(:sqlite, :json_extract, field: field, path: path) do
    "json_extract(#{field}, '$.#{path}')"
  end
  
  def sql_dialect(:postgres, :full_text_search, field: field, query: query) do
    "to_tsvector('english', #{field}) @@ plainto_tsquery('english', '#{query}')"
  end
  
  def sql_dialect(:mysql, :full_text_search, field: field, query: query) do
    "MATCH(#{field}) AGAINST('#{query}' IN NATURAL LANGUAGE MODE)"
  end
  
  def sql_dialect(:sqlite, :full_text_search, field: field, query: query) do
    "#{field} MATCH '#{query}'"  # Requires FTS5
  end
  
  @doc """
  Returns migration helpers for adapter-specific syntax.
  """
  @spec migration_helpers(adapter()) :: map()
  def migration_helpers(:postgres) do
    %{
      uuid_type: "uuid",
      uuid_default: "gen_random_uuid()",
      array_type: &"#{&1}[]",
      json_type: "jsonb",
      boolean_type: "boolean",
      text_search_index: fn idx, table, field -> "CREATE INDEX #{idx}_search_idx ON #{table} USING GIN(to_tsvector('english', #{field}))" end
    }
  end
  
  def migration_helpers(:mysql) do
    %{
      uuid_type: "VARCHAR(36)",
      uuid_default: "UUID()",
      array_type: fn _type -> "JSON" end,
      json_type: "JSON",
      boolean_type: "BOOLEAN",
      text_search_index: fn idx, table, field -> "CREATE FULLTEXT INDEX #{idx}_search_idx ON #{table}(#{field})" end
    }
  end
  
  def migration_helpers(:sqlite) do
    %{
      uuid_type: "TEXT",
      uuid_default: "lower(hex(randomblob(16)))",
      array_type: fn _type -> "TEXT" end,  # JSON stored as TEXT
      json_type: "TEXT",
      boolean_type: "INTEGER",
      text_search_index: fn _idx, table, field -> "CREATE VIRTUAL TABLE #{table}_fts USING fts5(#{field})" end
    }
  end
  
  # Private helpers
  
  defp validate_adapter(adapter) when adapter in @known_adapters do
    {:ok, adapter}
  end
  
  defp validate_adapter(adapter) do
    {:error, "Unknown adapter: #{inspect(adapter)}. Supported: #{inspect(@known_adapters)}"}
  end
  
  defp has_dep?(deps, package) do
    Enum.any?(deps, fn
      {^package, _} -> true
      {^package, _, _} -> true
      _ -> false
    end)
  end
  
  defp version_supported?(nil, _min_version, _supported, unsupported) do
    unsupported  # If no version specified, assume worst case
  end
  
  defp version_supported?(version, min_version, supported, unsupported) do
    if Version.match?(version, min_version) do
      supported
    else
      unsupported
    end
  end
end