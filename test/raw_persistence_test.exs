defmodule SelectoMix.RawPersistenceTest do
  use ExUnit.Case, async: true

  alias SelectoMix.RawPersistence

  describe "parse_adapter/1" do
    test "parses supported adapter names" do
      assert {:ok, :ecto} = RawPersistence.parse_adapter(nil)
      assert {:ok, :postgresql} = RawPersistence.parse_adapter("postgresql")
      assert {:ok, :postgresql} = RawPersistence.parse_adapter("postgres")
      assert {:ok, :sqlite} = RawPersistence.parse_adapter("sqlite")
    end

    test "rejects unsupported adapter names" do
      assert {:error, reason} = RawPersistence.parse_adapter("mysql")
      assert reason =~ "unsupported raw persistence adapter"
    end
  end

  describe "saved views generation" do
    test "renders SQLite saved views SQL and context" do
      config = %{
        adapter_mode: :sqlite,
        table_name: "saved_views",
        context_module: "TmpApp.SavedViewContext",
        connection_name: "TmpApp.Database"
      }

      sql = RawPersistence.saved_views_sql(config)
      context = RawPersistence.saved_views_context(config)

      assert sql =~ "CREATE TABLE IF NOT EXISTS saved_views"
      assert sql =~ "id INTEGER PRIMARY KEY AUTOINCREMENT"
      assert sql =~ "params TEXT NOT NULL DEFAULT '{}'"
      assert sql =~ "CURRENT_TIMESTAMP"

      assert context =~ "defmodule TmpApp.SavedViewContext"
      assert context =~ "SelectoDBSQLite.Adapter"
      assert context =~ "CURRENT_TIMESTAMP"
      assert context =~ "Jason.decode"
    end

    test "renders PostgreSQL saved views SQL" do
      config = %{adapter_mode: :postgresql, table_name: "saved_views"}

      sql = RawPersistence.saved_views_sql(config)

      assert sql =~ "id BIGSERIAL PRIMARY KEY"
      assert sql =~ "params JSONB NOT NULL DEFAULT '{}'"
      assert sql =~ "NOW()"
    end
  end

  describe "saved view config generation" do
    test "renders PostgreSQL saved view config SQL and context" do
      config = %{
        adapter_mode: :postgresql,
        table_name: "saved_view_configs",
        context_module: "TmpApp.SavedViewConfigContext",
        connection_name: "TmpApp.Database"
      }

      sql = RawPersistence.saved_view_configs_sql(config)
      context = RawPersistence.saved_view_configs_context(config)

      assert sql =~ "view_type VARCHAR(50) NOT NULL"
      assert sql =~ "params JSONB NOT NULL DEFAULT '{}'"
      assert sql =~ "NOW()"

      assert context =~ "defmodule TmpApp.SavedViewConfigContext"
      assert context =~ "SelectoDBPostgreSQL.Adapter"
      assert context =~ "def get_view_config(name, context, view_type, opts \\ [])"
      assert context =~ "def decode_view_config(view_config)"
    end
  end

  describe "filter set generation" do
    test "renders SQLite filter set SQL and context" do
      config = %{
        adapter_mode: :sqlite,
        table: "filter_sets",
        context_module: "TmpApp.FilterSets",
        connection_name: "TmpApp.Database"
      }

      sql = RawPersistence.filter_sets_sql(config)
      context = RawPersistence.filter_sets_context(config)

      assert sql =~ "CREATE TABLE IF NOT EXISTS filter_sets"
      assert sql =~ "filters TEXT NOT NULL DEFAULT '{}'"
      assert sql =~ "is_default INTEGER NOT NULL DEFAULT 0"

      assert context =~ "defmodule TmpApp.FilterSets"
      assert context =~ "SelectoDBSQLite.Adapter"
      assert context =~ "def duplicate_filter_set(id, new_name, user_id)"
      assert context =~ "Base.url_encode64"
    end
  end
end
