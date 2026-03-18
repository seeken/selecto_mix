defmodule SelectoMix.SqlRunnerTest do
  use ExUnit.Case, async: true

  alias SelectoMix.SqlRunner

  defmodule RecordingAdapter do
    def execute(agent, stmt, _params, _opts) do
      Agent.update(agent, &[stmt | &1])
      {:ok, %{rows: [], columns: []}}
    end
  end

  test "run_sql_string keeps semicolons inside quoted text comments and dollar strings" do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    sql = """
    insert into demos(text) values ('alpha;beta');
    -- semicolon in comment ; should not split
    do $$ begin perform 1; perform 2; end $$;
    select \"semi;colon\" from demos;
    """

    assert {:ok, "inline", 3} = SqlRunner.run_sql_string(RecordingAdapter, agent, sql)

    statements = agent |> Agent.get(&Enum.reverse/1) |> Enum.map(&String.trim/1)

    assert Enum.at(statements, 0) == "insert into demos(text) values ('alpha;beta')"
    assert Enum.at(statements, 1) =~ "perform 1; perform 2;"
    assert Enum.at(statements, 2) == ~s(select "semi;colon" from demos)
  end
end
