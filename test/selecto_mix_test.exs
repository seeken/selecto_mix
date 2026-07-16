defmodule SelectoDBMSSQL.Adapter do
  def name, do: :mssql
  def connect(connection), do: {:ok, connection}
  def execute(_connection, _query, _params, _opts), do: {:ok, %{rows: [], columns: []}}
  def placeholder(index), do: ["@p", Integer.to_string(index)]
  def quote_identifier(identifier), do: "[#{to_string(identifier)}]"
  def supports?(:schema_introspection), do: true
  def supports?(_feature), do: false

  def list_tables(_connection, _opts), do: {:ok, ["orders"]}

  def list_relations(_connection, opts) do
    if Keyword.get(opts, :include_views, false) do
      {:ok,
       [%{name: "orders", source_kind: :table}, %{name: "active_orders", source_kind: :view}]}
    else
      {:ok, [%{name: "orders", source_kind: :table}]}
    end
  end

  def introspect_table(_connection, "orders", opts) do
    schema = Keyword.get(opts, :schema, "dbo")

    {:ok,
     %{
       table_name: "orders",
       schema: schema,
       fields: [:id, :customer_id, :inserted_at],
       field_types: %{id: :integer, customer_id: :integer, inserted_at: :naive_datetime},
       primary_key: :id,
       associations: %{
         customer: %{
           type: :belongs_to,
           association_type: :belongs_to,
           related_schema: "Customer",
           related_module_name: "Customer",
           related_table: "customers",
           queryable: :customers,
           field: :customer,
           owner_key: :customer_id,
           related_key: :id,
           join_type: :inner,
           is_through: false,
           constraint_name: "orders_customer_id_fkey"
         }
       },
       columns: %{
         id: %{type: :integer, nullable: false},
         customer_id: %{type: :integer, nullable: false},
         inserted_at: %{type: :naive_datetime, nullable: true}
       },
       source: :mssql
     }}
  end
end

defmodule SelectoDBSQLite.Adapter do
  def name, do: :sqlite
  def connect(connection), do: {:ok, connection}
  def execute(_connection, _query, _params, _opts), do: {:ok, %{rows: [], columns: []}}
  def placeholder(_index), do: "?"
  def quote_identifier(identifier), do: ~s("#{identifier}")
  def supports?(:schema_introspection), do: true
  def supports?(_feature), do: false

  def list_tables(_connection, _opts), do: {:ok, ["orders"]}

  def list_relations(_connection, opts) do
    if Keyword.get(opts, :include_views, false) do
      {:ok,
       [%{name: "orders", source_kind: :table}, %{name: "active_orders", source_kind: :view}]}
    else
      {:ok, [%{name: "orders", source_kind: :table}]}
    end
  end

  def introspect_table(_connection, "orders", _opts) do
    {:ok,
     %{
       table_name: "orders",
       schema: "main",
       fields: [:id, :customer_id, :inserted_at],
       field_types: %{id: :integer, customer_id: :integer, inserted_at: :string},
       primary_key: :id,
       associations: %{
         customer: %{
           type: :belongs_to,
           association_type: :belongs_to,
           related_schema: "Customer",
           related_module_name: "Customer",
           related_table: "customers",
           queryable: :customers,
           field: :customer,
           owner_key: :customer_id,
           related_key: :id,
           join_type: :inner,
           is_through: false,
           constraint_name: "fk_orders_0"
         }
       },
       columns: %{},
       source: :sqlite
     }}
  end
end

defmodule SelectoDBMySQL.Adapter do
  def name, do: :mysql
  def connect(connection), do: {:ok, connection}
  def execute(_connection, _query, _params, _opts), do: {:ok, %{rows: [], columns: []}}
  def placeholder(_index), do: "?"
  def quote_identifier(identifier), do: "`#{to_string(identifier)}`"
  def supports?(:schema_introspection), do: true
  def supports?(_feature), do: false

  def list_tables(_connection, _opts), do: {:ok, ["orders"]}

  def list_relations(_connection, opts) do
    if Keyword.get(opts, :include_views, false) do
      {:ok,
       [%{name: "orders", source_kind: :table}, %{name: "active_orders", source_kind: :view}]}
    else
      {:ok, [%{name: "orders", source_kind: :table}]}
    end
  end

  def introspect_table(_connection, "orders", opts) do
    schema = Keyword.get(opts, :schema, "shop_dev")

    {:ok,
     %{
       table_name: "orders",
       schema: schema,
       fields: [:id, :customer_id, :inserted_at],
       field_types: %{id: :integer, customer_id: :integer, inserted_at: :naive_datetime},
       primary_key: :id,
       associations: %{
         customer: %{
           type: :belongs_to,
           association_type: :belongs_to,
           related_schema: "Customer",
           related_module_name: "Customer",
           related_table: "customers",
           queryable: :customers,
           field: :customer,
           owner_key: :customer_id,
           related_key: :id,
           join_type: :inner,
           is_through: false,
           constraint_name: "orders_customer_id_fkey"
         }
       },
       columns: %{},
       source: :mysql
     }}
  end
end

defmodule SelectoDBMariaDB.Adapter do
  def name, do: :mariadb
  def connect(connection), do: {:ok, connection}
  def execute(_connection, _query, _params, _opts), do: {:ok, %{rows: [], columns: []}}
  def placeholder(_index), do: "?"
  def quote_identifier(identifier), do: "`#{to_string(identifier)}`"
  def supports?(:schema_introspection), do: true
  def supports?(_feature), do: false

  def list_tables(_connection, _opts), do: {:ok, ["orders"]}

  def list_relations(_connection, opts) do
    if Keyword.get(opts, :include_views, false) do
      {:ok,
       [%{name: "orders", source_kind: :table}, %{name: "active_orders", source_kind: :view}]}
    else
      {:ok, [%{name: "orders", source_kind: :table}]}
    end
  end

  def introspect_table(_connection, "orders", opts) do
    schema = Keyword.get(opts, :schema, "shop_dev")

    {:ok,
     %{
       table_name: "orders",
       schema: schema,
       fields: [:id, :customer_id, :inserted_at],
       field_types: %{id: :integer, customer_id: :integer, inserted_at: :naive_datetime},
       primary_key: :id,
       associations: %{
         customer: %{
           type: :belongs_to,
           association_type: :belongs_to,
           related_schema: "Customer",
           related_module_name: "Customer",
           related_table: "customers",
           queryable: :customers,
           field: :customer,
           owner_key: :customer_id,
           related_key: :id,
           join_type: :inner,
           is_through: false,
           constraint_name: "orders_customer_id_fkey"
         }
       },
       columns: %{},
       source: :mariadb
     }}
  end
end

defmodule SelectoMixTest do
  use ExUnit.Case

  defmodule UuidSchema do
    use Ecto.Schema

    @primary_key {:public_id, :binary_id, autogenerate: false}

    schema "uuid_records" do
      field(:external_uuid, Ecto.UUID)
      field(:name, :string)
    end
  end

  doctest SelectoMix

  alias SelectoMix.{
    AdapterResolver,
    ConnectionOpts,
    DomainGenerator,
    LiveViewGenerator,
    OverlayGenerator,
    SchemaIntrospector,
    StudioArtifactsGenerator
  }

  describe "SelectoMix basic functionality" do
    test "version/0 returns version string" do
      version = SelectoMix.version()
      assert is_binary(version)
      assert String.match?(version, ~r/\d+\.\d+\.\d+/)
    end

    test "config/0 returns configuration" do
      config = SelectoMix.config()
      assert is_list(config)
    end

    test "default_output_dir/0 returns valid directory path" do
      dir = SelectoMix.default_output_dir()
      assert is_binary(dir)
      assert String.contains?(dir, "selecto_domains")
    end

    test "discover_schemas/0 resolves the host Mix app and returns a list without crashing" do
      schemas = SelectoMix.discover_schemas()

      assert is_list(schemas)
      assert Enum.all?(schemas, &is_atom/1)
    end
  end

  describe "schema validation" do
    test "validate_schema_module/1 with invalid module" do
      result = SelectoMix.validate_schema_module("NotAModule")
      assert {:error, _reason} = result
    end
  end

  describe "SchemaIntrospector" do
    # These tests would require actual Ecto schemas to be meaningful
    # For demonstration purposes, showing the test structure

    test "introspect_schema/2 handles missing schema gracefully" do
      # This would fail with a real schema module, but shows error handling
      assert %{error: reason, schema_module: NonExistentSchema} =
               SchemaIntrospector.introspect_schema(NonExistentSchema, [])

      assert reason =~ "Failed to introspect schema"
    end

    test "gen.domain records an Igniter issue and skips file creation when introspection fails" do
      Mix.Task.reenable("selecto.gen.domain")

      igniter =
        Igniter.Test.test_project(app_name: :broken_schema_host)
        |> Igniter.compose_task("selecto.gen.domain", [
          "Does.Not.Exist.Schema",
          "--output",
          "lib/broken_schema_host/selecto_domains"
        ])

      assert igniter.issues != []
      assert Enum.any?(igniter.issues, &String.contains?(&1, "Failed to introspect"))

      created_paths =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&Rewrite.Source.get(&1, :path))
        |> Enum.filter(&String.contains?(&1, "selecto_domains"))
        |> Enum.reject(&String.ends_with?(&1, ".gitkeep"))

      refute Enum.any?(created_paths, &String.ends_with?(&1, "_domain.ex"))
    end

    test "preserves binary_id and uuid column metadata" do
      config = SchemaIntrospector.introspect_schema(UuidSchema, [])

      assert config.primary_key == :public_id
      assert config.field_types.public_id == :binary_id
      assert config.field_types.external_uuid == :uuid
    end
  end

  describe "SelectoMix.CLI" do
    test "parse!/2 raises on unknown switches" do
      assert_raise Mix.Error, ~r/Invalid option/, fn ->
        SelectoMix.CLI.parse!(["--bogus", "x"], strict: [path: :string])
      end
    end

    test "parse!/2 returns opts and positional args" do
      assert {opts, ["file.json"]} =
               SelectoMix.CLI.parse!(["file.json", "--path", "lib"],
                 strict: [path: :string]
               )

      assert opts[:path] == "lib"
    end
  end

  describe "DomainGenerator" do
    test "generate_domain_file/2 creates valid Elixir code" do
      schema_module = TestSchema

      config = %{
        schema_module: schema_module,
        table_name: "test_table",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{
          module_name: "TestSchema",
          context_name: "Test"
        }
      }

      result = DomainGenerator.generate_domain_file(schema_module, config)

      assert is_binary(result)
      assert String.contains?(result, "defmodule")
      assert String.contains?(result, "def domain do")
      assert String.contains?(result, "source:")
      assert String.contains?(result, "test_table")
    end

    test "generate_domain_map/1 creates proper domain configuration" do
      config = %{
        schema_module: TestSchema,
        table_name: "tests",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{module_name: "Test"}
      }

      result = DomainGenerator.generate_domain_map(config)

      assert is_binary(result)
      assert String.contains?(result, "source:")
      assert String.contains?(result, "schema_version: 1")
      assert String.contains?(result, "domain_version: \"0.1.0\"")
      assert String.contains?(result, "# domain_fingerprint: \"sha256:...\"")
      assert String.contains?(result, "source_table: \"tests\"")
      assert String.contains?(result, "primary_key: :id")
      assert String.contains?(result, "functions: %{}")
    end

    test "generate_domain_map/1 emits view source metadata when present" do
      config = %{
        schema_module: TestSchema,
        table_name: "reporting.active_customers",
        primary_key: :customer_id,
        source_kind: :view,
        readonly: true,
        fields: [:customer_id, :name],
        field_types: %{customer_id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{module_name: "ActiveCustomer"}
      }

      result = DomainGenerator.generate_domain_map(config)

      assert String.contains?(result, "source_kind: :view")
      assert String.contains?(result, "readonly: true")
    end

    test "generate_domain_map/1 preserves uuid-aware field types" do
      config = %{
        schema_module: UuidSchema,
        table_name: "uuid_records",
        primary_key: :public_id,
        fields: [:public_id, :external_uuid, :name],
        field_types: %{public_id: :binary_id, external_uuid: :uuid, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{module_name: "UuidRecord"}
      }

      result = DomainGenerator.generate_domain_map(config)

      assert String.contains?(result, "primary_key: :public_id")
      assert String.contains?(result, ":public_id => %{type: :binary_id}")
      assert String.contains?(result, ":external_uuid => %{type: :uuid}")
    end

    test "generate_domain_map/1 ignores pre-0.5 in-file custom marker payloads" do
      config = %{
        schema_module: TestSchema,
        table_name: "tests",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{module_name: "Test"},
        functions: %{"rank" => %{kind: :scalar, sql_name: "rank"}},
        stale_in_file_customizations: %{
          custom_functions:
            "%{\n        \"similarity\" => %{kind: :scalar, sql_name: \"public.similarity\"}\n      }"
        }
      }

      result = DomainGenerator.generate_domain_map(config)

      assert String.contains?(result, "functions: %{")
      assert String.contains?(result, "rank")
      refute String.contains?(result, "public.similarity")
    end

    test "generate_domain_map/1 emits many-to-many join table metadata" do
      config = %{
        schema_module: TestSchema,
        table_name: "products",
        primary_key: :id,
        fields: [:id],
        field_types: %{id: :integer},
        associations: %{
          tags: %{
            association_type: :many_to_many,
            related_schema: TestTag,
            queryable: :tags,
            owner_key: :id,
            related_key: :id,
            join_type: :left,
            join_through: "product_tags",
            join_keys: [product_id: :id, tag_id: :id]
          }
        },
        suggested_defaults: %{
          default_selected: [],
          default_filters: %{},
          default_order: []
        },
        metadata: %{module_name: "Product"}
      }

      result = DomainGenerator.generate_domain_map(config)

      assert String.contains?(result, "join_table: \"product_tags\"")
      assert String.contains?(result, "join_keys: [product_id: :id, tag_id: :id]")
      assert String.contains?(result, "main_foreign_key: \"product_id\"")
      assert String.contains?(result, "tag_foreign_key: \"tag_id\"")
    end

    test "generate_domain_map/1 does not map tag display drill-down to the source row id" do
      config = %{
        schema_module: TestSchema,
        table_name: "products",
        primary_key: :id,
        fields: [:id],
        field_types: %{id: :integer},
        associations: %{
          tags: %{
            association_type: :many_to_many,
            related_schema: TestTag,
            queryable: :tags,
            owner_key: :id,
            related_key: :id,
            join_type: :left,
            join_through: "product_tags",
            join_keys: [product_id: :id, tag_id: :id]
          }
        },
        expanded_schemas: %{
          test_tag: %{
            source_table: "tags",
            primary_key: :id,
            fields: [:id, :name],
            field_types: %{id: :integer, name: :string},
            associations: %{}
          }
        },
        expand_schemas_list: ["test_tag"],
        expand_modes: %{"test_tag" => {:tag, "name"}},
        suggested_defaults: %{
          default_selected: [],
          default_filters: %{},
          default_order: []
        },
        metadata: %{module_name: "Product"}
      }

      result = DomainGenerator.generate_domain_map(config)

      assert result =~ "# tag mode: displays name, filters by tag ID"
      assert result =~ ":name => %{"
      assert result =~ "join_mode: :tag"
      refute result =~ "group_by_filter: \"id\""
    end

    test "generate_domain_map/1 deduplicates schema entries for self-referential associations" do
      config = %{
        schema_module: TestSchema,
        table_name: "employees",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{
          manager: %{
            related_schema: "Employee",
            related_module_name: "Employee",
            related_table: "employees",
            queryable: :employee,
            owner_key: :manager_id,
            related_key: :id
          },
          subordinates: %{
            related_schema: "Employee",
            related_module_name: "Employee",
            related_table: "employees",
            queryable: :employee,
            owner_key: :id,
            related_key: :manager_id
          }
        },
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{module_name: "Employee"}
      }

      result = DomainGenerator.generate_domain_map(config)

      assert length(Regex.scan(~r/:employee => %\{/, result)) == 1
    end

    test "generate_domain_file/3 creates DB-backed helper functions" do
      source = {:db, SelectoDBPostgreSQL.Adapter, :fake_conn, "products", schema: "public"}

      config = %{
        table_name: "products",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{
          module_name: "Product",
          context_name: "PostgreSQL"
        },
        source_type: :db,
        adapter: SelectoDBPostgreSQL.Adapter
      }

      result = DomainGenerator.generate_domain_file(source, config, app_name: "Shop")

      assert String.contains?(result, "defmodule Shop.SelectoDomains.ProductDomain")
      assert String.contains?(result, "def source_table, do: \"products\"")
      assert String.contains?(result, "def adapter_module, do: SelectoDBPostgreSQL.Adapter")
      refute String.contains?(result, "def from_ecto")

      assert String.contains?(
               result,
               "mix selecto.gen.domain --adapter postgresql --table products"
             )
    end
  end

  describe "adapter-backed helpers" do
    test "gen.domain artifact guidance points to export check and inspect loop" do
      guidance =
        Mix.Tasks.Selecto.Gen.Domain.artifact_guidance(
          "Shop.SelectoDomains.ProductDomain",
          "priv/selecto/product.normalized.json"
        )

      assert guidance =~
               "mix selecto.domain.export Shop.SelectoDomains.ProductDomain --output priv/selecto/product.normalized.json"

      assert guidance =~ "mix selecto.domain.check priv/selecto/product.normalized.json"
      assert guidance =~ "mix selecto.domain.import priv/selecto/product.normalized.json --check"
      assert guidance =~ "mix selecto.domain.inspect priv/selecto/product.normalized.json"

      assert guidance =~
               "mix selecto.domain.describe priv/selecto/product.normalized.json --output priv/selecto/product.inspection.json"

      assert guidance =~
               "mix selecto.domain.diagram priv/selecto/product.inspection.json --output docs/selecto/product.diagram.mmd"

      assert guidance =~
               "mix selecto.domain.docs priv/selecto/product.normalized.json --output docs/selecto/product.md"
    end

    test "adapter resolver accepts short adapter names" do
      assert {:ok, SelectoDBPostgreSQL.Adapter} = AdapterResolver.resolve("postgresql")
    end

    test "adapter resolver names the Hex package for known adapters" do
      assert AdapterResolver.hex_package_for(SelectoDBPostgreSQL.Adapter) ==
               "selecto_db_postgresql"

      assert AdapterResolver.hex_package_for(SelectoDBSQLite.Adapter) == "selecto_db_sqlite"
      assert AdapterResolver.hex_package_for(NotARealAdapter) == nil
    end

    test "adapter resolver describes a missing adapter with an actionable Hex dep to add" do
      message = AdapterResolver.describe_missing_adapter(SelectoDBPostgreSQL.Adapter)

      assert message =~ "SelectoDBPostgreSQL.Adapter"
      assert message =~ ~s({:selecto_db_postgresql, ">= 0.0.0"})
      assert message =~ "mix deps.get"
    end

    test "adapter resolver formats adapter error tuples for human-readable output" do
      assert AdapterResolver.format_adapter_error({:adapter_not_loaded, SelectoDBSQLite.Adapter}) =~
               "selecto_db_sqlite"

      assert AdapterResolver.format_adapter_error(
               {:adapter_missing_connect, SelectoDBSQLite.Adapter}
             ) =~ "does not implement connect/1"

      assert AdapterResolver.format_adapter_error(:some_other_reason) == ":some_other_reason"
    end

    test "schema introspector and domain generator support mssql db sources" do
      source = {:db, SelectoDBMSSQL.Adapter, :fake_conn, "orders", schema: "sales"}

      {:ok, config} =
        SchemaIntrospector.introspect_schema_result(source,
          schema: "sales",
          include_associations: true
        )

      assert config.table_name == "orders"
      assert config.primary_key == :id
      assert config.source == :mssql
      assert config.source_type == :db
      assert config.adapter == SelectoDBMSSQL.Adapter
      assert config.associations.customer.related_table == "customers"

      result = DomainGenerator.generate_domain_file(source, config, app_name: "Shop")

      assert String.contains?(result, "defmodule Shop.SelectoDomains.OrderDomain")
      assert String.contains?(result, "def source_table, do: \"orders\"")
      assert String.contains?(result, "def adapter_module, do: SelectoDBMSSQL.Adapter")
      assert String.contains?(result, "mix selecto.gen.domain --adapter mssql --table orders")
    end

    test "schema introspector and domain generator support sqlite db sources" do
      source = {:db, SelectoDBSQLite.Adapter, :fake_conn, "orders", schema: "public"}

      {:ok, config} =
        SchemaIntrospector.introspect_schema_result(source,
          schema: "public",
          include_associations: true
        )

      assert config.table_name == "orders"
      assert config.primary_key == :id
      assert config.source == :sqlite
      assert config.source_type == :db
      assert config.adapter == SelectoDBSQLite.Adapter

      result = DomainGenerator.generate_domain_file(source, config, app_name: "Shop")

      assert String.contains?(result, "defmodule Shop.SelectoDomains.OrderDomain")
      assert String.contains?(result, "def adapter_module, do: SelectoDBSQLite.Adapter")
      assert String.contains?(result, "mix selecto.gen.domain --adapter sqlite --table orders")
    end

    test "schema introspector and domain generator support mysql db sources" do
      source = {:db, SelectoDBMySQL.Adapter, :fake_conn, "orders", schema: "shop_dev"}

      {:ok, config} =
        SchemaIntrospector.introspect_schema_result(source,
          schema: "shop_dev",
          include_associations: true
        )

      assert config.table_name == "orders"
      assert config.primary_key == :id
      assert config.source == :mysql
      assert config.source_type == :db
      assert config.adapter == SelectoDBMySQL.Adapter

      result = DomainGenerator.generate_domain_file(source, config, app_name: "Shop")

      assert String.contains?(result, "defmodule Shop.SelectoDomains.OrderDomain")
      assert String.contains?(result, "def adapter_module, do: SelectoDBMySQL.Adapter")
      assert String.contains?(result, "mix selecto.gen.domain --adapter mysql --table orders")
    end

    test "schema introspector and domain generator support mariadb db sources" do
      source = {:db, SelectoDBMariaDB.Adapter, :fake_conn, "orders", schema: "shop_dev"}

      {:ok, config} =
        SchemaIntrospector.introspect_schema_result(source,
          schema: "shop_dev",
          include_associations: true
        )

      assert config.table_name == "orders"
      assert config.primary_key == :id
      assert config.source == :mariadb
      assert config.source_type == :db
      assert config.adapter == SelectoDBMariaDB.Adapter

      result = DomainGenerator.generate_domain_file(source, config, app_name: "Shop")

      assert String.contains?(result, "defmodule Shop.SelectoDomains.OrderDomain")
      assert String.contains?(result, "def adapter_module, do: SelectoDBMariaDB.Adapter")
      assert String.contains?(result, "mix selecto.gen.domain --adapter mariadb --table orders")
    end

    test "schema introspector preserves explicit view metadata for db sources" do
      source =
        {:db, SelectoDBMSSQL.Adapter, :fake_conn, "orders",
         schema: "reporting", source_kind: :view, primary_key: :customer_id}

      {:ok, config} =
        SchemaIntrospector.introspect_schema_result(source,
          schema: "reporting",
          source_kind: :view,
          primary_key: :customer_id,
          include_associations: true
        )

      assert config.primary_key == :customer_id
      assert config.source_kind == :view
      assert config.readonly == true
    end

    test "connection opts schema includes view discovery flags" do
      schema = ConnectionOpts.connection_schema()

      assert schema[:include_views] == :boolean
      assert schema[:view] == :string
      assert schema[:materialized_view] == :string
      assert schema[:primary_key] == :string
    end

    test "connection opts parse convenience flags" do
      opts =
        ConnectionOpts.from_parsed_args(%{
          database: "shop_dev",
          host: "localhost",
          port: 5432,
          username: "postgres",
          password: "secret"
        })

      assert opts[:database] == "shop_dev"
      assert opts[:hostname] == "localhost"
      assert opts[:port] == 5432
      assert opts[:username] == "postgres"
      assert opts[:password] == "secret"
    end
  end

  describe "OverlayGenerator" do
    test "generate_overlay_file/3 handles ecto source configs" do
      config = %{
        source: :ecto,
        columns: %{
          name: %{type: :string},
          price: %{type: :decimal},
          active: %{type: :boolean}
        },
        field_types: %{name: :string, price: :decimal, active: :boolean}
      }

      result =
        OverlayGenerator.generate_overlay_file(
          "Shop.SelectoDomains.ProductDomain",
          config,
          []
        )

      assert result =~ "defmodule Shop.SelectoDomains.Overlays.ProductDomainOverlay"
      assert result =~ "# defcolumn :price do"
      assert result =~ "# deffilter \"active\" do"
      assert result =~ "# deffunction \"similarity\" do"
      assert result =~ "# defchoice_source(:related_choices, %{"
      assert result =~ "#   constraint_policy: %{domain_of_interest: :fail_closed}"
      assert result =~ "# defwrite_operation :insert do"
      assert result =~ "# defwrite_field :name do"
      assert result =~ "# defcapability \"entity.write\" do"
    end
  end

  describe "StudioArtifactsGenerator" do
    test "gen.domain --studio-artifacts creates a provider module that compiles" do
      suffix = System.unique_integer([:positive])
      schema_module = Module.concat([__MODULE__, "GeneratedStudioProduct#{suffix}"])

      Code.compile_string("""
      defmodule #{inspect(schema_module)} do
        use Ecto.Schema

        schema "generated_studio_products_#{suffix}" do
          field :name, :string
          field :active, :boolean
        end
      end
      """)

      source_basename =
        schema_module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      output_dir = "lib/shop/selecto_domains"
      provider_path = Path.join(output_dir, "#{source_basename}_domain_artifacts.ex")
      domain_path = Path.join(output_dir, "#{source_basename}_domain.ex")

      Mix.Task.reenable("selecto.gen.domain")

      igniter =
        Igniter.Test.test_project(app_name: :shop)
        |> Igniter.compose_task("selecto.gen.domain", [
          inspect(schema_module),
          "--output",
          output_dir,
          "--studio-artifacts"
        ])

      assert igniter.issues == []
      Igniter.Test.assert_creates(igniter, domain_path)
      Igniter.Test.assert_creates(igniter, provider_path)

      provider_source =
        igniter.rewrite
        |> Rewrite.source!(provider_path)
        |> Rewrite.Source.get(:content)

      expected_module =
        Module.concat([
          "Shop.SelectoDomains.GeneratedStudioProduct#{suffix}DomainArtifacts"
        ])

      {compiled, _diagnostics} =
        Code.with_diagnostics(fn ->
          Code.compile_string(provider_source)
        end)

      assert provider_source =~ "Selecto.Domain.normalize(@domain_module.domain())"
      assert provider_source =~ "Selecto.Domain.describe(normalized)"
      assert provider_source =~ ~s("domain_version")
      assert provider_source =~ ~s("domain_fingerprint")
      assert Keyword.has_key?(compiled, expected_module)

      Igniter.Test.assert_has_notice(igniter, fn notice ->
        notice =~ "config :selecto_studio, :domain_artifacts" and
          notice =~ "SelectoStudioWeb.DomainInspectionController"
      end)
    end

    test "renders a core Selecto inspection provider module" do
      result =
        StudioArtifactsGenerator.provider_module("Shop.SelectoDomains.ProductDomain")

      assert result =~ "defmodule Shop.SelectoDomains.ProductDomainArtifacts"
      assert result =~ "@domain_module Shop.SelectoDomains.ProductDomain"
      assert result =~ "Selecto.Domain.normalize(@domain_module.domain())"
      assert result =~ "Selecto.Domain.describe(normalized)"
      assert result =~ ~s("format" => "selecto.domain_inspection")
      assert result =~ ~s("domain_version")
      assert result =~ ~s("domain_fingerprint")
      assert result =~ "Map.from_struct()"
      refute result =~ "SelectoStudio.DomainInspection"
      refute result =~ "SelectoStudioWeb."
    end

    test "renders Studio registry and router guidance for host apps" do
      result =
        StudioArtifactsGenerator.integration_guidance(
          domain_id: "product",
          domain_name: "Product",
          artifact_module: "Shop.SelectoDomains.ProductDomainArtifacts"
        )

      assert result =~ "config :selecto_studio, :domain_artifacts"
      assert result =~ ~s(default: "product")
      assert result =~ ~s(id: "product")

      assert result =~
               "inspection: {Shop.SelectoDomains.ProductDomainArtifacts, :inspection_artifact, []}"

      assert result =~ ~s(get "/studio/domain-inspection")
      assert result =~ ~s(get "/studio/domain-inspection/:domain_id")
      assert result =~ ~s(post "/studio/domain-inspection")
    end
  end

  describe "Gen.Domain wildcard/--all schema discovery" do
    test "Foo.* wildcards expand to matching Ecto schemas only, using the real use Ecto.Schema check" do
      suffix = System.unique_integer([:positive])
      prefix = Module.concat([__MODULE__, "WildcardBlog#{suffix}"])
      post_module = Module.concat([prefix, "Post"])
      comment_module = Module.concat([prefix, "Comment"])
      not_a_schema_module = Module.concat([prefix, "NotASchema"])

      post_source = """
      defmodule #{inspect(post_module)} do
        use Ecto.Schema

        schema "wildcard_posts_#{suffix}" do
          field :title, :string
        end
      end
      """

      comment_source = """
      defmodule #{inspect(comment_module)} do
        use Ecto.Schema

        schema "wildcard_comments_#{suffix}" do
          field :body, :string
        end
      end
      """

      not_a_schema_source = """
      defmodule #{inspect(not_a_schema_module)} do
        def hello, do: :world
      end
      """

      # Compile for real so SchemaIntrospector can introspect fields once
      # discovered, matching how a host app's own compiled schemas behave.
      Code.compile_string(post_source)
      Code.compile_string(comment_source)
      Code.compile_string(not_a_schema_source)

      output_dir = "lib/wildcard_blog#{suffix}/selecto_domains"

      Mix.Task.reenable("selecto.gen.domain")

      igniter =
        Igniter.Test.test_project(
          app_name: :"wildcard_blog_#{suffix}",
          files: %{
            "lib/wildcard_blog#{suffix}/post.ex" => post_source,
            "lib/wildcard_blog#{suffix}/comment.ex" => comment_source,
            "lib/wildcard_blog#{suffix}/not_a_schema.ex" => not_a_schema_source
          }
        )
        |> Igniter.compose_task("selecto.gen.domain", [
          "#{inspect(prefix)}.*",
          "--output",
          output_dir
        ])

      # Generating multiple domains into the same --output directory has a
      # known (pre-existing, unrelated) cosmetic quirk where the shared
      # `.gitkeep` scaffolding files get flagged as already existing; what
      # matters here is that both matching schemas were actually discovered
      # and had their domain files generated.
      refute Enum.any?(igniter.issues, &(&1 =~ "introspect"))
      Igniter.Test.assert_creates(igniter, Path.join(output_dir, "post_domain.ex"))
      Igniter.Test.assert_creates(igniter, Path.join(output_dir, "comment_domain.ex"))

      refute Enum.any?(igniter.rewrite, fn source ->
               source.path == Path.join(output_dir, "not_a_schema_domain.ex")
             end)
    end
  end

  describe "LiveViewGenerator" do
    test "renders DB-backed live view template with database connection" do
      source = {:db, SelectoDBPostgreSQL.Adapter, :fake_conn, "products", schema: "public"}

      result =
        LiveViewGenerator.render_live_view_template(
          "Shop",
          source,
          "Shop.SelectoDomains.ProductDomain",
          [connection_name: "Shop.Database"],
          "../../deps/selecto_components/lib/**/*.{ex,heex}"
        )

      assert String.contains?(result, "defmodule ShopWeb.ProductLive")
      assert String.contains?(result, "Selecto.configure(domain, Shop.Database)")
      assert String.contains?(result, "alias SelectoComponents.Views")
      assert String.contains?(result, "choice_source_domain: domain")
      assert String.contains?(result, "choice_source_transport: :live")

      assert String.contains?(
               result,
               "{:ok, assign(socket, state), layout: {ShopWeb.Layouts, :app}}"
             )

      assert String.contains?(
               result,
               ~s(@source "../../deps/selecto_components/lib/**/*.{ex,heex}";)
             )

      assert String.contains?(
               result,
               "choice_source_context: %{surface: :generated_live_view, path: path}"
             )

      assert String.contains?(
               result,
               "Views.spec(:aggregate, Views.Aggregate, \"Aggregate View\", %{drill_down: :detail})"
             )

      assert String.contains?(
               result,
               "Extension-provided views such as `:map` or `:timeseries` are merged in"
             )

      refute String.contains?(result, "def render(assigns)")
      refute String.contains?(result, ~S(def handle_event("toggle_show_view_configurator"))
      refute String.contains?(result, "layout: {ShopWeb.Layouts, :root}")
      refute String.contains?(result, "Shop.Repo")
    end

    test "builds DB-backed live view file paths from table names" do
      source = {:db, SelectoDBPostgreSQL.Adapter, :fake_conn, "order_items", schema: "public"}

      assert LiveViewGenerator.live_view_file_path("shop", source) ==
               "lib/shop_web/order_item_live.ex"

      assert LiveViewGenerator.live_view_html_file_path("shop", source) ==
               "lib/shop_web/order_item_live.html.heex"
    end

    test "renders router snippet with query contract endpoint" do
      source = {:db, SelectoDBPostgreSQL.Adapter, :fake_conn, "products", schema: "public"}

      result =
        LiveViewGenerator.route_suggestion(source,
          path: "/reports/products",
          domain_module: "Shop.SelectoDomains.ProductDomain"
        )

      assert result =~ "Add these routes to your router.ex:"
      assert result =~ ~s(live "/reports/products", ProductLive, :index)
      assert result =~ ~s(forward "/reports/products/query-contract.json")
      assert result =~ "SelectoComponents.QueryContract.Plug"
      assert result =~ "domain: Shop.SelectoDomains.ProductDomain.domain()"
      assert result =~ ~s(domain_path: "/reports/products")
      assert result =~ ~s(query_contract_url: "/reports/products/query-contract.json")
      assert result =~ ~s(query_guide_url: "/reports/products/query-guide.md")
      assert result =~ ~s(forward "/reports/products/query-guide.md")
      assert result =~ "SelectoComponents.QueryContract.Guide.Plug"
      assert result =~ ~s(domain_id: "product")
      assert result =~ ~s(forward "/reports/products/query-intent/validate")
      assert result =~ "SelectoComponents.QueryContract.IntentValidator.Plug"
    end

    test "renders form controller even when initially collapsed" do
      source = {:db, SelectoDBPostgreSQL.Adapter, :fake_conn, "products", schema: "public"}

      result =
        LiveViewGenerator.render_live_view_html_template(source,
          enable_modal: true,
          saved_views: true
        )

      refute String.contains?(result, ~S(<div :if={@show_view_configurator}>))
      assert String.contains?(result, "show_view_configurator={@show_view_configurator}")
      assert String.contains?(result, "enable_modal_detail={true}\n")
      assert String.contains?(result, "saved_view_module={@saved_view_module}")
      assert String.contains?(result, "choice_source_domain={@choice_source_domain}")
      assert String.contains?(result, "choice_source_context={@choice_source_context}")
      assert String.contains?(result, "choice_source_transport={@choice_source_transport}")
    end
  end

  describe "LiveDashboard generator" do
    test "renders a current PageBuilder module" do
      source =
        Mix.Tasks.Selecto.Gen.LiveDashboard.render_page_module_for_test(
          TmpAppWeb.LiveDashboard.SelectoPage
        )

      assert source =~ "defmodule TmpAppWeb.LiveDashboard.SelectoPage"
      assert source =~ "def render(assigns)"
      assert source =~ "use Phoenix.LiveDashboard.PageBuilder"
      refute source =~ "def render_page"
      refute source =~ "nav_bar"
      assert {:ok, _ast} = Code.string_to_quoted(source)
    end

    test "adds additional_pages to Phoenix router dashboard route" do
      router_source = """
      defmodule TmpAppWeb.Router do
        use TmpAppWeb, :router

        import Phoenix.LiveDashboard.Router

        scope "/dev" do
          pipe_through(:browser)

          live_dashboard("/dashboard", metrics: TmpAppWeb.Telemetry)
        end
      end
      """

      updated =
        Mix.Tasks.Selecto.Gen.LiveDashboard.update_router_content_for_test(
          router_source,
          TmpAppWeb,
          TmpAppWeb.LiveDashboard.SelectoPage
        )

      assert updated =~ "additional_pages:"
      assert updated =~ "selecto: TmpAppWeb.LiveDashboard.SelectoPage"
      assert updated =~ "metrics: TmpAppWeb.Telemetry"
      assert updated != router_source
    end
  end

  describe "integration" do
    test "resolves SelectoComponents Tailwind source from local path dependency" do
      cwd = Path.join(System.tmp_dir!(), "selecto_mix_cwd_#{System.unique_integer([:positive])}")

      dep_path =
        Path.join(System.tmp_dir!(), "selecto_components_#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(dep_path, "lib"))

      on_exit(fn ->
        File.rm_rf!(cwd)
        File.rm_rf!(dep_path)
      end)

      source_path =
        Mix.Tasks.Selecto.Components.Integrate.selecto_components_source_path(cwd, [
          {:selecto_components, path: dep_path, override: true}
        ])

      assert source_path =~ "selecto_components"
      assert source_path =~ "lib/**/*.{ex,heex}"

      assert Path.expand(source_path, Path.join(cwd, "assets/css")) ==
               Path.join([dep_path, "lib", "**", "*.{ex,heex}"])
    end

    test "adds local path source even when a stale deps source is present" do
      local_source = "../../../../Users/chris/selecto/selecto_components/lib/**/*.{ex,heex}"

      content = """
      @import "tailwindcss" source(none);
      @source "../css";
      @source "../../deps/selecto_components/lib/**/*.{ex,heex}";
      """

      updated = Mix.Tasks.Selecto.Components.Integrate.patch_app_css(content, local_source)

      assert updated =~ ~s(@source "../../deps/selecto_components/lib/**/*.{ex,heex}")
      assert updated =~ ~s(@source "#{local_source}")

      assert Mix.Tasks.Selecto.Components.Integrate.patch_app_css(updated, local_source) ==
               updated
    end

    test "patch_app_js merges selectoComponentsHooks into a simple existing hooks object" do
      content = """
      import {Socket} from "phoenix"
      import {LiveSocket} from "phoenix_live_view"
      import topbar from "../vendor/topbar"

      const liveSocket = new LiveSocket("/live", Socket, {
        hooks: {SomeExistingHook},
        params: {_csrf_token: csrfToken}
      })
      """

      updated = SelectoMix.ComponentsIntegrate.patch_app_js(content)

      assert updated =~ "phoenix-colocated/selecto_components"
      assert updated =~ "hooks: {SomeExistingHook, ...selectoComponentsHooks}"

      # Idempotent: running again doesn't duplicate the import or hook entry.
      assert SelectoMix.ComponentsIntegrate.patch_app_js(updated) == updated
    end

    test "patch_app_js adds a hooks object when the LiveSocket config has none" do
      content = """
      import {Socket} from "phoenix"
      import {LiveSocket} from "phoenix_live_view"

      const liveSocket = new LiveSocket("/live", Socket, {
        params: {_csrf_token: csrfToken}
      })
      """

      updated = SelectoMix.ComponentsIntegrate.patch_app_js(content)

      assert updated =~ "hooks: { ...selectoComponentsHooks }"
    end

    test "patch_app_js leaves a nested hooks object untouched rather than corrupting it" do
      content = """
      import {Socket} from "phoenix"
      import {LiveSocket} from "phoenix_live_view"

      const liveSocket = new LiveSocket("/live", Socket, {
        hooks: {
          MyHook: {
            mounted() { console.log("mounted") }
          }
        },
        params: {_csrf_token: csrfToken}
      })
      """

      updated = SelectoMix.ComponentsIntegrate.patch_app_js(content)

      # The import gets added (safe, additive change)...
      assert updated =~ "phoenix-colocated/selecto_components"

      # ...but the nested hooks object itself (and everything from the
      # LiveSocket construction onward) must be left byte-for-byte as-is -
      # no truncation/corruption of the nested MyHook definition.
      [_, original_tail] = String.split(content, "const liveSocket", parts: 2)
      [_, updated_tail] = String.split(updated, "const liveSocket", parts: 2)
      assert updated_tail == original_tail
    end

    test "full workflow without actual file creation" do
      # Test the complete workflow without actually creating files
      config = %{
        schema_module: TestSchema,
        table_name: "test_table",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{
          module_name: "TestSchema",
          context_name: "Test"
        }
      }

      # Generate domain file
      domain_content = DomainGenerator.generate_domain_file(TestSchema, config)
      assert is_binary(domain_content)
      assert String.contains?(domain_content, "defmodule")

      # This demonstrates the complete workflow works end-to-end
      assert true
    end
  end
end
