defmodule Mix.Tasks.Selecto.Gen.Save.Schema do
  @moduledoc "The hello mix task: `mix help hello`"
  use Mix.Task

  @doc """
  params:
    tablename
    modulename
    contextfield1:type contextfield2:type ...

  """

  # mix selecto.gen.save.schema SavedView saved_view

  # .repo
  # .module
  # .schema
  # .talename

  ### Generate schema file priv/templates/save.schema.ex
  ### Generate context file priv/templates/save.context.ex
  ### Generate migration file priv/templates/save.migration.ex

  ### Use these since we will pretty surely have them
  alias Mix.Phoenix.Schema
  alias Mix.Tasks.Phx.Gen


  @shortdoc "Generate Schema to save Selecto Views."
  def run(args) do

    {schema, migration, context} = build(args)

    inject_schema(schema)
    inject_migration(migration)
    inject_context(context)


  end

  defp build(args) do
    {opts, parsed, invalid} = OptionParser.parse(args, [])
    ## What is the project name?
    projname = Mix.Project.config()[:app]
    IO.inspect(projname)


    {"schema", "migration", "context"}
  end

  defp inject_schema(schema) do
    IO.puts "inject_schema"
  end

  defp inject_migration(migration) do
    IO.puts "inject_migration"
  end

  defp inject_context(context) do
    IO.puts "inject_context"
  end

end
