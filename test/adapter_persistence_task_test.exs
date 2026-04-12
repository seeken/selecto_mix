defmodule SelectoMix.AdapterPersistenceTaskTest do
  use ExUnit.Case, async: false

  test "saved_views task supports SQLite dry run" do
    {output, 0} =
      System.cmd(
        "mix",
        ["selecto.gen.saved_views", "TmpApp", "--adapter", "sqlite", "--dry-run"],
        stderr_to_stdout: true
      )

    assert output =~ "Selecto SavedViews Generation (DRY RUN)"
    assert output =~ "Adapter: sqlite"
    assert output =~ "priv/sql/create_saved_views.sql"
    assert output =~ "lib/tmp_app/saved_view_context.ex"
  end

  test "saved_views task reuses an existing migration for the same table" do
    in_tmp_dir("selecto_mix_saved_views_idempotent", fn ->
      File.write!(".formatter.exs", "[inputs: []]\n")
      Mix.Task.reenable("selecto.gen.saved_views")

      Mix.Task.run("selecto.gen.saved_views", [
        "TmpApp",
        "--yes",
        "--context-module",
        "TmpApp.SavedViewContextA",
        "--schema-module",
        "TmpApp.SavedViewA"
      ])

      initial_migrations = Path.wildcard("priv/repo/migrations/*_create_saved_views.exs")
      assert length(initial_migrations) == 1

      Mix.Task.reenable("selecto.gen.saved_views")

      Mix.Task.run("selecto.gen.saved_views", [
        "TmpApp",
        "--yes",
        "--context-module",
        "TmpApp.SavedViewContextB",
        "--schema-module",
        "TmpApp.SavedViewB"
      ])

      assert Path.wildcard("priv/repo/migrations/*_create_saved_views.exs") == initial_migrations
    end)
  end

  test "saved_view_configs task supports PostgreSQL dry run" do
    {output, 0} =
      System.cmd(
        "mix",
        ["selecto.gen.saved_view_configs", "TmpApp", "--adapter", "postgresql", "--dry-run"],
        stderr_to_stdout: true
      )

    assert output =~ "Selecto SavedViewConfigs Generation (DRY RUN)"
    assert output =~ "Adapter: postgresql"
    assert output =~ "priv/sql/create_saved_view_configs.sql"
    assert output =~ "lib/tmp_app/saved_view_config_context.ex"
  end

  test "exported_views task supports dry run" do
    {output, 0} =
      System.cmd(
        "mix",
        ["selecto.gen.exported_views", "TmpApp", "--dry-run"],
        stderr_to_stdout: true
      )

    assert output =~ "Selecto ExportedViews Generation (DRY RUN)"
    assert output =~ "priv/repo/migrations/"
    assert output =~ "lib/tmp_app/exported_view.ex"
    assert output =~ "lib/tmp_app/exported_view_context.ex"
  end

  test "gen.view task validates usage on dry run" do
    {output, 0} =
      System.cmd(
        "mix",
        ["selecto.gen.view", "TmpApp.ReportingDomain", "active_customers", "--dry-run"],
        stderr_to_stdout: true
      )

    assert output =~ "could not be loaded"
  end

  test "gen.view task renders migration template for published view ddl" do
    migration =
      Mix.Tasks.Selecto.Gen.View.render_migration_for_test(%{
        repo_module: TmpApp.Repo,
        migration_name: "publish_active_customers",
        kind: :view,
        database_name: "reporting.active_customers",
        ddl: "CREATE VIEW reporting.active_customers AS\nselect 1;",
        index_statements: [
          "CREATE INDEX active_customers_id_idx ON reporting.active_customers (id);"
        ]
      })

    assert migration =~ "defmodule TmpApp.Repo.Migrations.PublishActiveCustomers"
    assert migration =~ "CREATE VIEW reporting.active_customers AS"
    assert migration =~ "DROP VIEW IF EXISTS reporting.active_customers;"
    assert migration =~ "# Suggested follow-up indexes for this published view:"

    assert migration =~
             "# execute(\"CREATE INDEX active_customers_id_idx ON reporting.active_customers (id);\")"
  end

  test "filter_sets task generates SQLite raw persistence files" do
    in_tmp_dir("selecto_mix_filter_sets_sqlite", fn ->
      Mix.Task.reenable("selecto.gen.filter_sets")
      Mix.Tasks.Selecto.Gen.FilterSets.run(["TmpApp", "--adapter", "sqlite", "--no-tests"])

      sql_path = Path.join(["priv", "sql", "create_filter_sets.sql"])
      context_path = Path.join(["lib", "tmp_app", "tmp_app", "filter_sets.ex"])

      sql = File.read!(sql_path)
      context = File.read!(context_path)

      assert sql =~ "CREATE TABLE IF NOT EXISTS filter_sets"
      assert sql =~ "filters TEXT NOT NULL DEFAULT '{}'"
      assert context =~ "SelectoDBSQLite.Adapter"

      refute File.exists?(
               Path.join(["lib", "tmp_app", "tmp_app", "filter_sets", "filter_set.ex"])
             )
    end)
  end

  test "filter_sets task generates PostgreSQL raw persistence files" do
    in_tmp_dir("selecto_mix_filter_sets_postgresql", fn ->
      Mix.Task.reenable("selecto.gen.filter_sets")
      Mix.Tasks.Selecto.Gen.FilterSets.run(["TmpApp", "--adapter", "postgresql", "--no-tests"])

      sql_path = Path.join(["priv", "sql", "create_filter_sets.sql"])
      context_path = Path.join(["lib", "tmp_app", "tmp_app", "filter_sets.ex"])

      sql = File.read!(sql_path)
      context = File.read!(context_path)

      assert sql =~ "filters JSONB NOT NULL DEFAULT '{}'"
      assert sql =~ "NOW()"
      assert context =~ "SelectoDBPostgreSQL.Adapter"
    end)
  end

  test "filter_sets task reuses an existing migration for the same table" do
    in_tmp_dir("selecto_mix_filter_sets_idempotent", fn ->
      Mix.Task.reenable("selecto.gen.filter_sets")

      Mix.Tasks.Selecto.Gen.FilterSets.run([
        "TmpApp",
        "--context-module",
        "TmpApp.FilterSetsA",
        "--schema-module",
        "TmpApp.FilterSets.FilterSetA",
        "--no-tests"
      ])

      initial_migrations = Path.wildcard("priv/repo/migrations/*_create_filter_sets.exs")
      assert length(initial_migrations) == 1

      Mix.Task.reenable("selecto.gen.filter_sets")

      Mix.Tasks.Selecto.Gen.FilterSets.run([
        "TmpApp",
        "--context-module",
        "TmpApp.FilterSetsB",
        "--schema-module",
        "TmpApp.FilterSets.FilterSetB",
        "--no-tests"
      ])

      assert Path.wildcard("priv/repo/migrations/*_create_filter_sets.exs") == initial_migrations
    end)
  end

  defp in_tmp_dir(prefix, fun) do
    base_tmp = System.tmp_dir!()
    tmp_dir = Path.join(base_tmp, "#{prefix}_#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    try do
      File.cd!(tmp_dir, fun)
    after
      File.rm_rf!(tmp_dir)
    end
  end
end
