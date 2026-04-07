defmodule Mix.Tasks.Selecto.Gen.View do
  @shortdoc "Generate SQL/DDL for a published Selecto view"
  @moduledoc """
  Generate SQL/DDL artifacts for a published view registered in a Selecto domain.

  ## Examples

      mix selecto.gen.view MyApp.ReportingDomain active_customers --dry-run

      mix selecto.gen.view MyApp.ReportingDomain active_customers --repo-module MyApp.Repo
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.gen.view MyApp.ReportingDomain active_customers --dry-run",
      positional: [:domain_module, :view_name],
      schema: [dry_run: :boolean, repo_module: :string],
      aliases: [d: :dry_run, r: :repo_module]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = Map.new(igniter.args.options)
    domain_arg = Map.get(igniter.args.positional, :domain_module)
    view_name = Map.get(igniter.args.positional, :view_name)
    dry_run? = Map.get(opts, :dry_run, false)
    repo_module = parse_module_name(Map.get(opts, :repo_module) || default_repo_module())

    cond do
      blank?(domain_arg) or blank?(view_name) ->
        Igniter.add_warning(
          igniter,
          "Usage: mix selecto.gen.view MyApp.ReportingDomain view_name --dry-run"
        )

      true ->
        generate_view(igniter, domain_arg, view_name, dry_run?, repo_module)
    end
  end

  @doc false
  def render_migration_for_test(config), do: render_migration_template(config)

  defp generate_view(igniter, domain_arg, view_name, dry_run?, repo_module) do
    domain_module = Module.concat([domain_arg])

    with true <- Code.ensure_loaded?(domain_module),
         true <- function_exported?(domain_module, :domain, 0),
         domain <- domain_module.domain(),
         published_views when is_map(published_views) <- Map.get(domain, :published_views, %{}),
         spec when is_map(spec) <-
           published_views[view_name] || published_views[String.to_atom(view_name)],
         {:ok, result} <- build_view_sql(domain, spec) do
      if dry_run? do
        IO.puts("""

        Selecto View Generation (DRY RUN)
        ================================

        Domain: #{inspect(domain_module)}
        View:   #{view_name}
        Kind:   #{result.kind}
        Name:   #{result.database_name}

        SQL:
        #{result.sql}

        DDL:
        #{result.ddl}

        Suggested indexes:
        #{render_index_suggestions(result.index_statements)}
        """)

        igniter
      else
        config = build_generation_config(domain_module, view_name, result, repo_module)

        igniter
        |> Igniter.create_new_file(migration_file_path(config), render_migration_template(config))
        |> Igniter.add_notice("Generated migration: #{migration_file_path(config)}")
        |> Igniter.add_notice(
          "Generated published view SQL for #{view_name}. Re-run with --dry-run to inspect the compiled DDL output."
        )
      end
    else
      false ->
        Igniter.add_warning(igniter, "Domain module #{domain_arg} could not be loaded")

      nil ->
        Igniter.add_warning(
          igniter,
          "Published view #{view_name} was not found in #{domain_arg}.domain().published_views"
        )

      {:error, reasons} when is_list(reasons) ->
        Igniter.add_warning(igniter, Enum.join(reasons, "\n"))

      _ ->
        Igniter.add_warning(
          igniter,
          "Unable to generate published view for #{domain_arg}.#{view_name}"
        )
    end
  end

  defp build_view_sql(domain, spec) do
    if Code.ensure_loaded?(Selecto.ViewPublisher) and
         function_exported?(Selecto.ViewPublisher, :build_sql, 2) do
      apply(Selecto.ViewPublisher, :build_sql, [domain, spec])
    else
      {:error, ["Selecto.ViewPublisher.build_sql/2 is unavailable in the current project"]}
    end
  end

  defp build_generation_config(domain_module, view_name, result, repo_module) do
    %{
      domain_module: domain_module,
      view_name: view_name,
      kind: result.kind,
      database_name: result.database_name,
      ddl: result.ddl,
      index_statements: result.index_statements,
      repo_module: repo_module,
      timestamp: timestamp(),
      migration_name: "publish_#{Macro.underscore(view_name)}"
    }
  end

  defp migration_file_path(config) do
    "priv/repo/migrations/#{config.timestamp}_#{config.migration_name}.exs"
  end

  defp render_migration_template(config) do
    migration_module =
      Module.concat([
        "#{config.repo_module}.Migrations.#{Macro.camelize(config.migration_name)}"
      ])

    ddl = indent_sql(config.ddl, 6)
    drop_sql = drop_statement(config.kind, config.database_name) |> indent_sql(6)
    index_comments = render_index_comment_block(Map.get(config, :index_statements, []))
    triple_quote = ~s(\"\"\")

    [
      "defmodule #{inspect(migration_module)} do",
      "  use Ecto.Migration",
      "",
      "  def up do",
      "    execute(#{triple_quote}",
      ddl,
      "    #{triple_quote})",
      "  end",
      "",
      "  def down do",
      "    execute(#{triple_quote}",
      drop_sql,
      "    #{triple_quote})",
      "  end",
      index_comments,
      "end",
      ""
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp render_index_comment_block([]), do: ""

  defp render_index_comment_block(index_statements) do
    [
      "",
      "  # Suggested follow-up indexes for this published view:",
      Enum.map(index_statements, &"  # execute(\"#{&1}\")")
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp render_index_suggestions([]), do: "  (none)"

  defp render_index_suggestions(index_statements) do
    index_statements
    |> Enum.map_join("\n", &"  - #{&1}")
  end

  defp drop_statement(:materialized_view, database_name),
    do: "DROP MATERIALIZED VIEW IF EXISTS #{database_name};"

  defp drop_statement(_kind, database_name), do: "DROP VIEW IF EXISTS #{database_name};"

  defp indent_sql(sql, spaces) do
    padding = String.duplicate(" ", spaces)

    sql
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end

  defp default_repo_module do
    Mix.Project.config()[:app]
    |> to_string()
    |> Macro.camelize()
    |> Kernel.<>(".Repo")
  end

  defp parse_module_name(module_string) when is_binary(module_string),
    do: Module.concat([module_string])

  defp parse_module_name(module) when is_atom(module), do: module

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()
    "#{year}#{pad(month)}#{pad(day)}#{pad(hour)}#{pad(minute)}#{pad(second)}"
  end

  defp pad(number) when number < 10, do: "0#{number}"
  defp pad(number), do: to_string(number)

  defp blank?(value), do: is_nil(value) or value == ""
end
