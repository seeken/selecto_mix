defmodule Mix.Tasks.Selecto.Gen.View do
  @shortdoc "Generate SQL/DDL for a published Selecto view"
  @moduledoc """
  Generate dry-run SQL and DDL for a published view registered in a Selecto domain.

  ## Examples

      mix selecto.gen.view MyApp.ReportingDomain active_customers --dry-run
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.gen.view MyApp.ReportingDomain active_customers --dry-run",
      positional: [:domain_module, :view_name],
      schema: [dry_run: :boolean],
      aliases: [d: :dry_run]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = Map.new(igniter.args.options)
    domain_arg = Map.get(igniter.args.positional, :domain_module)
    view_name = Map.get(igniter.args.positional, :view_name)
    dry_run? = Map.get(opts, :dry_run, false)

    cond do
      blank?(domain_arg) or blank?(view_name) ->
        Igniter.add_warning(
          igniter,
          "Usage: mix selecto.gen.view MyApp.ReportingDomain view_name --dry-run"
        )

      true ->
        generate_view(igniter, domain_arg, view_name, dry_run?)
    end
  end

  defp generate_view(igniter, domain_arg, view_name, dry_run?) do
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
        """)

        igniter
      else
        Igniter.add_notice(
          igniter,
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

  defp blank?(value), do: is_nil(value) or value == ""
end
