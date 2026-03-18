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
