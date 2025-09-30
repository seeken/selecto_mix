defmodule SelectoMix.Introspector.Postgres do
  @moduledoc """
  Introspects PostgreSQL databases directly using system catalogs.

  Works with Postgrex connections without requiring Ecto schemas. Uses
  information_schema and pg_catalog to discover table structure, relationships,
  and constraints.

  ## Usage

      {:ok, conn} = Postgrex.start_link(hostname: "localhost", database: "mydb")

      # List all tables
      {:ok, tables} = SelectoMix.Introspector.Postgres.list_tables(conn)

      # Introspect specific table
      {:ok, metadata} = SelectoMix.Introspector.Postgres.introspect_table(conn, "users")
  """

  require Logger

  @doc """
  List all tables in a schema.

  ## Parameters

  - `conn` - Postgrex connection (PID or named process)
  - `schema` - Schema name (default: "public")

  ## Returns

  - `{:ok, [table_name, ...]}` - List of table names
  - `{:error, reason}` - Error details

  ## Examples

      {:ok, tables} = list_tables(conn)
      {:ok, tables} = list_tables(conn, "inventory")
  """
  def list_tables(conn, schema \\ "public") do
    query = """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = $1
      AND table_type = 'BASE TABLE'
    ORDER BY table_name
    """

    case Postgrex.query(conn, query, [schema]) do
      {:ok, %{rows: rows}} ->
        tables = Enum.map(rows, fn [table_name] -> table_name end)
        {:ok, tables}

      {:error, error} ->
        {:error, {:query_failed, error}}
    end
  end

  @doc """
  Introspect a table and return complete metadata.

  Returns standardized metadata structure compatible with Ecto introspection
  format used by SelectoMix.

  ## Parameters

  - `conn` - Postgrex connection
  - `table_name` - Table name
  - `opts` - Options
    - `:schema` - Schema name (default: "public")
    - `:include_indexes` - Include index information (default: false)

  ## Returns

  - `{:ok, metadata}` - Table metadata map
  - `{:error, reason}` - Error details

  The metadata map includes:
  - `:table_name` - Table name
  - `:schema` - Schema name
  - `:fields` - List of field names
  - `:field_types` - Map of field name to Elixir type
  - `:primary_key` - Primary key field name (or list for composite keys)
  - `:associations` - Map of detected foreign key relationships
  - `:columns` - Detailed column metadata
  """
  def introspect_table(conn, table_name, opts \\ []) do
    schema = Keyword.get(opts, :schema, "public")

    with {:ok, columns} <- get_columns(conn, table_name, schema),
         {:ok, primary_key} <- get_primary_key(conn, table_name, schema),
         {:ok, foreign_keys} <- get_foreign_keys(conn, table_name, schema) do

      # Extract field names and types
      fields = Enum.map(columns, & &1.column_name)

      field_types =
        columns
        |> Enum.into(%{}, fn col ->
          elixir_type = map_pg_type(col.data_type, col.udt_name, conn)
          {col.column_name, elixir_type}
        end)

      # Build associations from foreign keys
      associations = build_associations(foreign_keys)

      # Build detailed column metadata
      column_metadata =
        columns
        |> Enum.into(%{}, fn col ->
          {col.column_name, %{
            type: Map.get(field_types, col.column_name),
            nullable: col.is_nullable == "YES",
            default: col.column_default,
            max_length: col.character_maximum_length,
            precision: col.numeric_precision,
            scale: col.numeric_scale
          }}
        end)

      metadata = %{
        table_name: table_name,
        schema: schema,
        fields: fields,
        field_types: field_types,
        primary_key: primary_key,
        associations: associations,
        columns: column_metadata,
        source: :postgres
      }

      {:ok, metadata}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get column definitions for a table.

  Returns detailed column information from information_schema.columns.

  ## Returns

  List of column maps with keys:
  - `:column_name` - Column name (atom)
  - `:data_type` - PostgreSQL type name
  - `:udt_name` - User-defined type name (for enums, etc)
  - `:is_nullable` - "YES" or "NO"
  - `:column_default` - Default value expression
  - `:character_maximum_length` - For string types
  - `:numeric_precision` - For numeric types
  - `:numeric_scale` - For numeric types
  """
  def get_columns(conn, table_name, schema \\ "public") do
    query = """
    SELECT
      column_name,
      data_type,
      udt_name,
      is_nullable,
      column_default,
      character_maximum_length,
      numeric_precision,
      numeric_scale,
      ordinal_position
    FROM information_schema.columns
    WHERE table_schema = $1 AND table_name = $2
    ORDER BY ordinal_position
    """

    case Postgrex.query(conn, query, [schema, table_name]) do
      {:ok, %{rows: rows, columns: _cols}} ->
        columns =
          rows
          |> Enum.map(fn [col_name, data_type, udt_name, is_nullable, col_default,
                          max_length, precision, scale, _position] ->
            %{
              column_name: String.to_atom(col_name),
              data_type: data_type,
              udt_name: udt_name,
              is_nullable: is_nullable,
              column_default: col_default,
              character_maximum_length: max_length,
              numeric_precision: precision,
              numeric_scale: scale
            }
          end)

        {:ok, columns}

      {:error, error} ->
        {:error, {:columns_query_failed, error}}
    end
  end

  @doc """
  Get primary key column(s) for a table.

  Returns the primary key field name, or a list of field names for composite keys.

  ## Returns

  - `{:ok, :id}` - Single primary key field
  - `{:ok, [:field1, :field2]}` - Composite primary key
  - `{:ok, nil}` - No primary key defined
  - `{:error, reason}` - Query error
  """
  def get_primary_key(conn, table_name, schema \\ "public") do
    query = """
    SELECT a.attname
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid
      AND a.attnum = ANY(i.indkey)
    WHERE i.indrelid = ($1 || '.' || $2)::regclass
      AND i.indisprimary
    ORDER BY a.attnum
    """

    case Postgrex.query(conn, query, [schema, table_name]) do
      {:ok, %{rows: []}} ->
        {:ok, nil}

      {:ok, %{rows: [[single_key]]}} ->
        {:ok, String.to_atom(single_key)}

      {:ok, %{rows: multiple_keys}} ->
        keys = Enum.map(multiple_keys, fn [key] -> String.to_atom(key) end)
        {:ok, keys}

      {:error, error} ->
        {:error, {:primary_key_query_failed, error}}
    end
  end

  @doc """
  Get foreign key relationships for a table.

  Returns information about foreign key constraints, which can be used to
  infer associations (belongs_to relationships).

  ## Returns

  - `{:ok, [foreign_key_info, ...]}` - List of foreign key maps
  - `{:error, reason}` - Query error

  Each foreign key map contains:
  - `:constraint_name` - Name of the constraint
  - `:column_name` - Column in this table (atom)
  - `:foreign_table_schema` - Referenced table schema
  - `:foreign_table_name` - Referenced table name
  - `:foreign_column_name` - Referenced column name (atom)
  """
  def get_foreign_keys(conn, table_name, schema \\ "public") do
    query = """
    SELECT
      tc.constraint_name,
      kcu.column_name,
      ccu.table_schema AS foreign_table_schema,
      ccu.table_name AS foreign_table_name,
      ccu.column_name AS foreign_column_name
    FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = $1
      AND tc.table_name = $2
    """

    case Postgrex.query(conn, query, [schema, table_name]) do
      {:ok, %{rows: rows}} ->
        foreign_keys =
          rows
          |> Enum.map(fn [constraint_name, col_name, foreign_schema,
                          foreign_table, foreign_col] ->
            %{
              constraint_name: constraint_name,
              column_name: String.to_atom(col_name),
              foreign_table_schema: foreign_schema,
              foreign_table_name: foreign_table,
              foreign_column_name: String.to_atom(foreign_col)
            }
          end)

        {:ok, foreign_keys}

      {:error, error} ->
        {:error, {:foreign_keys_query_failed, error}}
    end
  end

  @doc """
  Get index definitions for a table.

  ## Returns

  - `{:ok, [index_info, ...]}` - List of index maps
  - `{:error, reason}` - Query error
  """
  def get_indexes(conn, table_name, schema \\ "public") do
    query = """
    SELECT
      i.relname AS index_name,
      a.attname AS column_name,
      ix.indisunique AS is_unique,
      ix.indisprimary AS is_primary
    FROM pg_class t
    JOIN pg_index ix ON t.oid = ix.indrelid
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = $1
      AND t.relname = $2
    ORDER BY i.relname, a.attnum
    """

    case Postgrex.query(conn, query, [schema, table_name]) do
      {:ok, %{rows: rows}} ->
        indexes =
          rows
          |> Enum.map(fn [index_name, col_name, is_unique, is_primary] ->
            %{
              index_name: index_name,
              column_name: String.to_atom(col_name),
              is_unique: is_unique,
              is_primary: is_primary
            }
          end)

        {:ok, indexes}

      {:error, error} ->
        {:error, {:indexes_query_failed, error}}
    end
  end

  @doc """
  Get enum values for a PostgreSQL enum type.

  ## Parameters

  - `conn` - Postgrex connection
  - `enum_type_name` - Name of the enum type (string)

  ## Returns

  - `{:ok, [value1, value2, ...]}` - List of enum values as strings
  - `{:error, reason}` - Query error or type not found
  """
  def get_enum_values(conn, enum_type_name) do
    query = """
    SELECT e.enumlabel
    FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typname = $1
    ORDER BY e.enumsortorder
    """

    case Postgrex.query(conn, query, [enum_type_name]) do
      {:ok, %{rows: []}} ->
        {:error, :enum_not_found}

      {:ok, %{rows: rows}} ->
        values = Enum.map(rows, fn [value] -> value end)
        {:ok, values}

      {:error, error} ->
        {:error, {:enum_query_failed, error}}
    end
  end

  @doc """
  Map PostgreSQL type to Elixir/Ecto type.

  Converts PostgreSQL type names to the corresponding Elixir type atoms
  used by Ecto and Selecto.

  ## Parameters

  - `data_type` - PostgreSQL data type name from information_schema
  - `udt_name` - User-defined type name (for enums and custom types)
  - `conn` - Optional Postgrex connection for enum detection

  ## Returns

  Elixir type atom (`:integer`, `:string`, `:boolean`, etc)
  """
  def map_pg_type(data_type, udt_name \\ nil, conn \\ nil)

  # Integer types
  def map_pg_type("integer", _, _), do: :integer
  def map_pg_type("bigint", _, _), do: :integer
  def map_pg_type("smallint", _, _), do: :integer
  def map_pg_type("int2", _, _), do: :integer
  def map_pg_type("int4", _, _), do: :integer
  def map_pg_type("int8", _, _), do: :integer

  # String types
  def map_pg_type("character varying", _, _), do: :string
  def map_pg_type("varchar", _, _), do: :string
  def map_pg_type("character", _, _), do: :string
  def map_pg_type("char", _, _), do: :string
  def map_pg_type("text", _, _), do: :string

  # Boolean
  def map_pg_type("boolean", _, _), do: :boolean
  def map_pg_type("bool", _, _), do: :boolean

  # Numeric/Decimal
  def map_pg_type("numeric", _, _), do: :decimal
  def map_pg_type("decimal", _, _), do: :decimal
  def map_pg_type("money", _, _), do: :decimal

  # Float/Double
  def map_pg_type("real", _, _), do: :float
  def map_pg_type("double precision", _, _), do: :float
  def map_pg_type("float4", _, _), do: :float
  def map_pg_type("float8", _, _), do: :float

  # Date/Time types
  def map_pg_type("timestamp without time zone", _, _), do: :naive_datetime
  def map_pg_type("timestamp with time zone", _, _), do: :utc_datetime
  def map_pg_type("timestamp", _, _), do: :naive_datetime
  def map_pg_type("timestamptz", _, _), do: :utc_datetime
  def map_pg_type("date", _, _), do: :date
  def map_pg_type("time", _, _), do: :time
  def map_pg_type("time without time zone", _, _), do: :time
  def map_pg_type("time with time zone", _, _), do: :time

  # UUID
  def map_pg_type("uuid", _, _), do: :binary_id

  # JSON
  def map_pg_type("json", _, _), do: :map
  def map_pg_type("jsonb", _, _), do: :map

  # Binary
  def map_pg_type("bytea", _, _), do: :binary

  # Array types
  def map_pg_type("ARRAY", udt_name, conn) do
    # udt_name will be like "_int4" or "_text"
    inner_type =
      udt_name
      |> String.trim_leading("_")
      |> then(&map_pg_type(&1, nil, conn))

    {:array, inner_type}
  end

  # User-defined types (likely enums)
  def map_pg_type("USER-DEFINED", udt_name, conn) when not is_nil(udt_name) do
    # Check if it's an enum type
    if conn do
      case get_enum_values(conn, udt_name) do
        {:ok, _values} ->
          # Return string type for now - could enhance to include enum values
          :string
        {:error, _} ->
          :string
      end
    else
      :string
    end
  end

  # Default fallback
  def map_pg_type(_data_type, _udt_name, _conn), do: :string

  # Private helper functions

  defp build_associations(foreign_keys) do
    foreign_keys
    |> Enum.into(%{}, fn fk ->
      # Create association name from foreign key column
      # e.g., :category_id -> :category
      assoc_name =
        fk.column_name
        |> Atom.to_string()
        |> String.replace_suffix("_id", "")
        |> String.to_atom()

      # Guess the related schema module name
      related_schema = guess_schema_module(fk.foreign_table_name)

      association = %{
        type: :belongs_to,
        queryable: String.to_atom(fk.foreign_table_name),
        field: assoc_name,
        owner_key: fk.column_name,
        related_key: fk.foreign_column_name,
        related_schema: related_schema,
        foreign_table: fk.foreign_table_name,
        constraint_name: fk.constraint_name
      }

      {assoc_name, association}
    end)
  end

  defp guess_schema_module(table_name) do
    # Convert table_name to likely module name
    # e.g., "categories" -> Categories, "order_items" -> OrderItems
    table_name
    |> Macro.camelize()
    |> String.replace_suffix("s", "")  # Simple pluralization handling
    |> String.to_atom()
  end
end
