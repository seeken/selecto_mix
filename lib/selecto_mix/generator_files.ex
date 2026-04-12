defmodule SelectoMix.GeneratorFiles do
  @moduledoc false

  def existing_migration_file(migration_dir, migration_name) do
    migration_dir
    |> Path.join("*_#{migration_name}.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> List.first()
  end
end
