# Postgrex Support Implementation Plan

## Executive Summary

Enable SelectoMix to generate Selecto domains directly from PostgreSQL databases without requiring Ecto schemas. The Selecto runtime already supports Postgrex connections - this plan focuses on adding database introspection capabilities to the code generation tools.

## Current State Analysis

### ✅ Working: Selecto Runtime (No Changes Needed)

**Files**: `vendor/selecto/lib/selecto/`
- `configuration.ex` - Accepts `Postgrex.conn()` connections
- `executor.ex` - Executes queries via Postgrex.query/3
- `connection_pool.ex` - Manages Postgrex connection pools
- `option_provider.ex` - Loads options via raw SQL

**Verdict**: Runtime is fully functional with Postgrex connections.

### ❌ Missing: SelectoMix Code Generation

**Problem Files**:

1. **`lib/selecto_mix/schema_introspector.ex`** (353 lines)
   - 100% Ecto-dependent via `__schema__/1` callbacks
   - No PostgreSQL system catalog queries
   - Cannot introspect databases without Ecto schemas

2. **`lib/selecto_mix/domain_generator.ex`** (849 lines)
   - Lines 337-375: Uses `__schema__/1` for related schemas
   - No fallback for non-Ecto introspection

3. **`lib/mix/selecto/schema_analyzer.ex`** (200 lines)
   - All functions use `__schema__/1` callbacks
   - Cannot analyze non-Ecto schemas

4. **`lib/mix/tasks/selecto.gen.domain.ex`**
   - Only accepts Ecto schema module names
   - No connection options

5. **`lib/mix/tasks/selecto.gen.cone.ex`** (795 lines)
   - Uses Ecto repos exclusively
   - No Postgrex mode

## Implementation Plan

### Phase 1: PostgreSQL Introspection Foundation

#### Task 1.1: Create Postgres Introspector Module

**File**: `lib/selecto_mix/introspector/postgres.ex` (NEW)

```elixir
defmodule SelectoMix.Introspector.Postgres do
  @moduledoc """
  Introspects PostgreSQL databases directly using system catalogs.
  Works with Postgrex connections without requiring Ecto schemas.
  """

  @doc "Get list of tables in schema"
  def list_tables(conn, schema \\ "public")

  @doc "Get full table metadata including columns, keys, constraints"
  def introspect_table(conn, table_name, opts \\ [])

  @doc "Get column definitions for a table"
  def get_columns(conn, table_name, schema \\ "public")

  @doc "Get primary key column(s) for a table"
  def get_primary_key(conn, table_name, schema \\ "public")

  @doc "Get foreign key relationships"
  def get_foreign_keys(conn, table_name, schema \\ "public")

  @doc "Get indexes for a table"
  def get_indexes(conn, table_name, schema \\ "public")

  @doc "Map PostgreSQL type to Elixir/Ecto type"
  def map_pg_type(pg_type_name)

  @doc "Detect if column is an enum type"
  def get_enum_values(conn, enum_type_name)
end
```

**Required SQL Queries**:

```sql
-- List tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = $1
  AND table_type = 'BASE TABLE'

-- Get columns
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default,
  character_maximum_length,
  numeric_precision,
  numeric_scale
FROM information_schema.columns
WHERE table_schema = $1 AND table_name = $2
ORDER BY ordinal_position

-- Get primary key
SELECT a.attname
FROM pg_index i
JOIN pg_attribute a ON a.attrelid = i.indrelid
  AND a.attnum = ANY(i.indkey)
WHERE i.indrelid = $1::regclass
  AND i.indisprimary

-- Get foreign keys
SELECT
  kcu.column_name,
  ccu.table_schema AS foreign_table_schema,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  rc.constraint_name
FROM information_schema.key_column_usage AS kcu
JOIN information_schema.referential_constraints AS rc
  ON kcu.constraint_name = rc.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON rc.unique_constraint_name = ccu.constraint_name
WHERE kcu.table_schema = $1
  AND kcu.table_name = $2

-- Get enum values
SELECT e.enumlabel
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = $1
ORDER BY e.enumsortorder
```

**Type Mapping**:
- `integer`, `int4`, `int8` → `:integer`
- `varchar`, `text`, `char` → `:string`
- `boolean`, `bool` → `:boolean`
- `timestamp`, `timestamptz` → `:utc_datetime`
- `date` → `:date`
- `numeric`, `decimal` → `:decimal`
- `jsonb`, `json` → `:map`
- `uuid` → `:binary_id`
- Custom types → Check for enums, default to `:string`

#### Task 1.2: Create Introspector Protocol

**File**: `lib/selecto_mix/introspector.ex` (NEW)

```elixir
defprotocol SelectoMix.Introspector do
  @moduledoc """
  Protocol for introspecting different schema sources.
  """

  @doc "Introspect a schema source and return standardized metadata"
  def introspect(source, opts)
end

defimpl SelectoMix.Introspector, for: Atom do
  # Ecto schema module
  def introspect(schema_module, opts) do
    SelectoMix.Introspector.Ecto.introspect(schema_module, opts)
  end
end

defimpl SelectoMix.Introspector, for: Tuple do
  # {:postgrex, conn, table_name} or {:postgrex, conn, table_name, schema}
  def introspect({:postgrex, conn, table_name}, opts) do
    SelectoMix.Introspector.Postgres.introspect_table(conn, table_name, opts)
  end

  def introspect({:postgrex, conn, table_name, schema}, opts) do
    opts = Keyword.put(opts, :schema, schema)
    SelectoMix.Introspector.Postgres.introspect_table(conn, table_name, opts)
  end
end
```

#### Task 1.3: Extract Ecto Introspection

**File**: `lib/selecto_mix/introspector/ecto.ex` (NEW)

Extract existing Ecto introspection logic from `SchemaIntrospector.ex` into dedicated module:

```elixir
defmodule SelectoMix.Introspector.Ecto do
  @moduledoc """
  Introspects Ecto schemas using __schema__/1 callbacks.
  """

  def introspect(schema_module, opts \\ [])
  def get_table_name(schema_module)
  def get_fields(schema_module)
  def get_associations(schema_module)
  def get_primary_key(schema_module)
end
```

Move existing code from `SchemaIntrospector.ex` to this new module.

### Phase 2: Update Existing Modules

#### Task 2.1: Refactor SchemaIntrospector

**File**: `lib/selecto_mix/schema_introspector.ex` (MODIFY)

Replace Ecto-specific logic with protocol-based introspection:

```elixir
defmodule SelectoMix.SchemaIntrospector do
  @moduledoc """
  Unified interface for introspecting schemas from any source.
  Supports both Ecto schemas and direct database connections.
  """

  @doc """
  Introspect a schema source.

  ## Examples

      # Ecto schema
      introspect_schema(MyApp.User)

      # Postgrex connection
      {:ok, conn} = Postgrex.start_link(...)
      introspect_schema({:postgrex, conn, "users"})

      # With schema name
      introspect_schema({:postgrex, conn, "users", "public"})
  """
  def introspect_schema(source, opts \\ []) do
    SelectoMix.Introspector.introspect(source, opts)
  end
end
```

#### Task 2.2: Update DomainGenerator

**File**: `lib/selecto_mix/domain_generator.ex` (MODIFY)

Lines 337-375: Replace `introspect_related_schema/1` with protocol-based approach:

```elixir
defp introspect_related_schema(source) do
  try do
    case SelectoMix.Introspector.introspect(source, []) do
      {:ok, schema_config} -> {:ok, schema_config}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :introspection_failed}
  end
end
```

#### Task 2.3: Update SchemaAnalyzer

**File**: `lib/mix/selecto/schema_analyzer.ex` (MODIFY)

Make source-agnostic by using `SchemaIntrospector`:

```elixir
def analyze_schema(source, opts \\ []) do
  case SelectoMix.SchemaIntrospector.introspect_schema(source, opts) do
    {:ok, metadata} ->
      %{
        module: metadata.source,
        fields: metadata.fields,
        associations: metadata.associations,
        # ... rest of analysis
      }
    {:error, reason} ->
      {:error, reason}
  end
end
```

### Phase 3: Mix Task Updates

#### Task 3.1: Update mix selecto.gen.domain

**File**: `lib/mix/tasks/selecto.gen.domain.ex` (MODIFY)

Add connection options:

```elixir
@switches [
  # Existing switches...
  connection: :string,    # DATABASE_URL or connection string
  host: :string,
  port: :integer,
  database: :string,
  username: :string,
  password: :string,
  table: :string,         # Required when using connection
  schema: :string         # Default: "public"
]

def run(args) do
  {opts, argv} = OptionParser.parse!(args, switches: @switches)

  source = case {argv, opts[:connection], opts[:table]} do
    # Ecto schema module (existing behavior)
    {[module_name], nil, nil} ->
      Module.concat([module_name])

    # Postgrex connection via DATABASE_URL
    {[], conn_url, table} when not is_nil(conn_url) ->
      conn = start_postgrex_from_url(conn_url)
      {:postgrex, conn, table, opts[:schema] || "public"}

    # Postgrex connection via explicit options
    {[], nil, table} when not is_nil(table) ->
      conn = start_postgrex_from_opts(opts)
      {:postgrex, conn, table, opts[:schema] || "public"}

    _ ->
      Mix.raise """
      Usage:
        mix selecto.gen.domain MyApp.User
        mix selecto.gen.domain --table users --connection $DATABASE_URL
        mix selecto.gen.domain --table users --host localhost --database mydb
      """
  end

  # Rest of existing logic works with source
  generate_domain(source, opts)
end
```

#### Task 3.2: Add Connection Helper Module

**File**: `lib/selecto_mix/connection.ex` (NEW)

```elixir
defmodule SelectoMix.Connection do
  @moduledoc """
  Helper utilities for managing database connections in Mix tasks.
  """

  @doc "Parse DATABASE_URL and start Postgrex connection"
  def start_from_url(database_url)

  @doc "Start Postgrex connection from keyword options"
  def start_from_opts(opts)

  @doc "Get connection from app configuration"
  def get_configured_connection(repo_module)

  @doc "Close connection when done"
  def close(conn)
end
```

#### Task 3.3: Update Cone Generators

**Files**:
- `lib/mix/tasks/selecto.gen.cone.ex` (MODIFY)
- `lib/mix/tasks/selecto.gen.cone.pg.ex` (MODIFY)

Add `--postgrex` mode to both generators:

```elixir
# Add to switches
@switches [
  # Existing...
  postgrex: :boolean,
  connection: :string,
  table: :string
]

# Update run/1 to support Postgrex sources
def run(args) do
  source = case {opts[:postgrex], opts[:table]} do
    {true, table} when not is_nil(table) ->
      conn = SelectoMix.Connection.start_from_opts(opts)
      {:postgrex, conn, table}
    _ ->
      # Existing Ecto behavior
      Module.concat([schema_name])
  end

  generate_cone(source, opts)
end
```

### Phase 4: Testing & Documentation

#### Task 4.1: Add Test Suite

**File**: `test/selecto_mix/introspector/postgres_test.exs` (NEW)

```elixir
defmodule SelectoMix.Introspector.PostgresTest do
  use ExUnit.Case

  setup do
    # Start test Postgrex connection
    {:ok, conn} = Postgrex.start_link([
      hostname: "localhost",
      database: "selecto_test",
      username: "postgres"
    ])

    # Create test tables
    setup_test_schema(conn)

    {:ok, conn: conn}
  end

  test "list_tables/2 returns all tables", %{conn: conn}
  test "introspect_table/3 returns full metadata", %{conn: conn}
  test "get_columns/3 returns column definitions", %{conn: conn}
  test "get_primary_key/3 detects primary key", %{conn: conn}
  test "get_foreign_keys/3 detects relationships", %{conn: conn}
  test "map_pg_type/1 maps all common types"
  test "get_enum_values/2 returns enum options", %{conn: conn}
end
```

**File**: `test/selecto_mix/introspector_test.exs` (NEW)

Test protocol implementation for both Ecto and Postgrex.

**File**: `test/mix/tasks/selecto.gen.domain_test.exs` (MODIFY)

Add tests for Postgrex connection mode.

#### Task 4.2: Create Example Project

**Directory**: `examples/postgrex_only/` (NEW)

Create minimal Phoenix app that uses Selecto + Postgrex without Ecto:

```elixir
# config/config.exs
config :my_app, :database,
  hostname: "localhost",
  database: "myapp_dev",
  username: "postgres",
  pool_size: 10

# lib/my_app/application.ex
def start(_type, _args) do
  db_config = Application.get_env(:my_app, :database)

  children = [
    {Postgrex, db_config ++ [name: MyApp.DB]},
    MyAppWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# lib/my_app/domains/users_domain.ex
# Generated via: mix selecto.gen.domain --table users --connection $DATABASE_URL
defmodule MyApp.Domains.UsersDomain do
  def domain, do: %{...}
end

# lib/my_app_web/live/users_live.ex
defmodule MyAppWeb.UsersLive do
  use MyAppWeb, :live_view
  use SelectoComponents.Form, domain: MyApp.Domains.UsersDomain.domain()

  def get_connection, do: MyApp.DB
end
```

#### Task 4.3: Update Documentation

**File**: `README.md` (MODIFY)

Add "Using Selecto without Ecto" section:

```markdown
## Using Selecto without Ecto

Selecto supports direct PostgreSQL connections via Postgrex, allowing you to
use Selecto in projects that don't use Ecto.

### Generating Domains from Database

```bash
# Using DATABASE_URL
DATABASE_URL=postgres://user:pass@localhost/mydb \
  mix selecto.gen.domain --table users

# Using explicit connection parameters
mix selecto.gen.domain \
  --table users \
  --host localhost \
  --database mydb \
  --username postgres \
  --password secret
```

### Runtime Usage

```elixir
# Start Postgrex connection
{:ok, conn} = Postgrex.start_link(
  hostname: "localhost",
  database: "mydb"
)

# Configure Selecto with Postgrex connection
selecto = Selecto.configure(MyDomain.domain(), conn)

# Execute queries
{:ok, {rows, columns, aliases}} = Selecto.execute(selecto)
```

### Connection Pooling

For production use, configure a supervised Postgrex connection:

```elixir
children = [
  {Postgrex, [name: MyApp.DB] ++ db_config}
]

# Use named connection
selecto = Selecto.configure(domain, MyApp.DB)
```
```

**File**: `docs/postgrex_migration.md` (NEW)

Guide for migrating Ecto projects to pure Postgrex.

**File**: `docs/architecture.md` (MODIFY)

Document introspector protocol architecture.

## File Structure

```
vendor/selecto_mix/
├── lib/
│   ├── selecto_mix/
│   │   ├── introspector.ex          # NEW - Protocol definition
│   │   ├── introspector/
│   │   │   ├── postgres.ex          # NEW - PostgreSQL introspection
│   │   │   └── ecto.ex              # NEW - Extracted Ecto introspection
│   │   ├── connection.ex            # NEW - Connection helpers
│   │   ├── schema_introspector.ex   # MODIFY - Use protocol
│   │   ├── domain_generator.ex      # MODIFY - Use protocol
│   │   └── join_analyzer.ex         # No changes needed
│   ├── mix/
│   │   ├── tasks/
│   │   │   ├── selecto.gen.domain.ex   # MODIFY - Add --connection
│   │   │   ├── selecto.gen.cone.ex     # MODIFY - Add --postgrex
│   │   │   └── selecto.gen.cone.pg.ex  # MODIFY - Add --postgrex
│   │   └── selecto/
│   │       └── schema_analyzer.ex      # MODIFY - Use protocol
├── test/
│   ├── selecto_mix/
│   │   ├── introspector_test.exs             # NEW
│   │   └── introspector/
│   │       ├── postgres_test.exs             # NEW
│   │       └── ecto_test.exs                 # NEW
│   └── mix/tasks/
│       └── selecto.gen.domain_test.exs       # MODIFY - Add Postgrex tests
├── examples/
│   └── postgrex_only/                        # NEW - Example project
├── docs/
│   ├── postgrex_support_plan.md              # THIS FILE
│   ├── postgrex_migration.md                 # NEW
│   └── architecture.md                       # MODIFY
└── README.md                                  # MODIFY - Add Postgrex docs
```

## Implementation Timeline

### Week 1: Foundation
- Day 1-2: Task 1.1 - Create `Introspector.Postgres` module
- Day 3: Task 1.2 - Create `Introspector` protocol
- Day 4: Task 1.3 - Extract `Introspector.Ecto` module
- Day 5: Testing and bug fixes

### Week 2: Integration
- Day 1: Task 2.1 - Refactor `SchemaIntrospector`
- Day 2: Task 2.2 - Update `DomainGenerator`
- Day 3: Task 2.3 - Update `SchemaAnalyzer`
- Day 4-5: Testing and bug fixes

### Week 3: Mix Tasks & Polish
- Day 1: Task 3.1 - Update `selecto.gen.domain`
- Day 2: Task 3.2 - Create `Connection` helper
- Day 3: Task 3.3 - Update cone generators
- Day 4: Task 4.1 - Add test suite
- Day 5: Task 4.2 - Create example project

### Week 4: Documentation
- Day 1-2: Task 4.3 - Update all documentation
- Day 3-4: Code review and polish
- Day 5: Final testing and release

## Success Criteria

1. ✅ Can generate domain file using: `mix selecto.gen.domain --table users --connection $DATABASE_URL`
2. ✅ Generated domain matches Ecto-generated domain (same fields, types, associations)
3. ✅ Can detect and map all common PostgreSQL types
4. ✅ Can detect primary keys and foreign key relationships
5. ✅ Can detect enum types and generate appropriate option providers
6. ✅ Can generate cone files using `--postgrex` flag
7. ✅ Example project runs without Ecto dependency
8. ✅ All tests pass for both Ecto and Postgrex modes
9. ✅ Documentation covers Postgrex workflow end-to-end

## Breaking Changes

None. This is purely additive functionality. Existing Ecto-based workflows continue to work exactly as before.

## Dependencies

- `postgrex` ~> 0.17 (already a dependency of Selecto)
- No new dependencies required

## Migration Path

Existing projects can gradually migrate:

1. **Phase 1**: Keep Ecto schemas, use Postgrex connections at runtime
2. **Phase 2**: Stop creating new Ecto schemas, generate domains from DB
3. **Phase 3**: Remove Ecto dependency entirely

No forced migration - both approaches can coexist indefinitely.

## Open Questions

1. **Schema naming**: How to handle domains when table name != module name?
   - **Decision**: Use `--module-name` flag to override generated module name

2. **Multi-database support**: Should we support MySQL/SQLite introspection?
   - **Decision**: Start with PostgreSQL only, add adapter pattern later

3. **Association detection**: How to handle polymorphic associations?
   - **Decision**: V1 only supports simple FK relationships, polymorphic in V2

4. **Enum handling**: Should we generate Ecto.Enum-compatible modules?
   - **Decision**: No, just document enum values in domain comments

5. **Default values**: Should we include column defaults in domain?
   - **Decision**: Yes, add `:default` key to column metadata

## Notes

- Selecto runtime already fully supports Postgrex (no changes needed there)
- This plan focuses exclusively on code generation (SelectoMix)
- Estimated total effort: 3-4 weeks for complete implementation
- Core functionality (introspection + domain generation): ~1 week
- Polish, testing, docs: ~2-3 weeks
