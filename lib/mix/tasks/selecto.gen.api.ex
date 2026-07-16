defmodule Mix.Tasks.Selecto.Gen.Api do
  @moduledoc """
  Generates a Selecto API endpoint and LiveView control panel.

  The generator creates:

  - a domain-aware API module that maps JSON payloads to SelectoUpdato operations
  - Selecto-powered read/query handlers
  - a Phoenix controller for the API endpoint
  - a LiveView control panel for editing configuration and sending requests
  - choice-source picker hooks for write fields when the domain declares them

  ## Usage

      mix selecto.gen.api orders --domain MyApp.OrdersDomain

  ## Options

    * `--domain` - Domain module used by generated API module (default: inferred)
    * `--schema` - Ecto schema module used for write operations (default: inferred)
    * `--repo` - Repo module used for execution (default: `MyApp.Repo`)
    * `--api-path` - Route path used in controller docs (default: `/api/v1/updato/<name>`)
    * `--panel-path` - Route path used for the control panel (default: `/updato/<name>/control`)
    * `--panel-in-prod` - Include control panel route in production snippets (default: false)
    * `--force` - Overwrite generated files

  The task prints route snippets to add into your `router.ex`.

  For choice-backed write fields, keep option and membership validation
  resolvers server-owned. Assign `:choice_source_options_resolver`,
  `:choice_source_membership_resolver`, and `:choice_source_scope` from the
  generated LiveView using socket/session data rather than browser parameters.
  For HTTP writes, customize the generated controller's `api_config/1` hook with
  the same server-owned resolver and scope. For security-sensitive
  Domain-of-Interest filters, declare
  `constraint_policy: %{domain_of_interest: :fail_closed}` on the choice source
  in the domain overlay and have the resolver return a closed result when a
  trusted filter cannot be enforced.

  For domain-authored actions with capabilities, assign `:capability_resolver`
  in `api_config/1` and `write_api_config/1`. Set
  `:require_capability_resolver` to true when capability-declared action
  preview/apply and generated query endpoints should fail closed without a
  resolver. Query capability enforcement uses `SelectoComponents.QueryContract`
  when that dependency is available in the generated host app.
  """

  use Mix.Task

  import Mix.Generator

  alias SelectoMix.Gen.Api.{ApiModule, Controller, Live, Paths, RouterNotice}

  @shortdoc "Generates Selecto API + control panel"

  @switches [
    domain: :string,
    schema: :string,
    repo: :string,
    api_path: :string,
    panel_path: :string,
    panel_in_prod: :boolean,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = SelectoMix.CLI.parse!(args, strict: @switches)

    name = parse_name!(positional)
    app = Mix.Project.config()[:app] |> to_string()
    app_module = Macro.camelize(app)
    web_module = app_module <> "Web"
    name_module = name |> Macro.camelize() |> SelectoMix.Inflect.singularize()
    name_snake = Macro.underscore(name)

    config =
      %{
        app: app,
        app_module: app_module,
        web_module: web_module,
        name_module: name_module,
        name_snake: name_snake,
        domain_module: opts[:domain] || infer_domain_module(app_module, name_module),
        schema_module: opts[:schema] || infer_schema_module(app_module, name_module),
        repo_module: opts[:repo] || app_module <> ".Repo",
        api_path: opts[:api_path] || "/api/v1/updato/#{name_snake}",
        panel_path: opts[:panel_path] || "/updato/#{name_snake}/control",
        panel_in_prod?: !!opts[:panel_in_prod],
        force?: !!opts[:force]
      }

    Mix.shell().info("Generating Selecto API files for #{name}...")

    generate_files(config)
    RouterNotice.print_router_snippet(config)
    RouterNotice.print_next_steps(config)
  end

  defp parse_name!([name | _]) do
    value = String.trim(name)

    if value == "" do
      Mix.raise("Expected NAME (for example: mix selecto.gen.api orders)")
    end

    value
  end

  defp parse_name!([]) do
    Mix.raise("Missing NAME. Example: mix selecto.gen.api orders")
  end

  defp infer_domain_module(app_module, name_module) do
    app_module <> "." <> name_module <> "Domain"
  end

  defp infer_schema_module(app_module, name_module) do
    app_module <> ".Hierarchy." <> name_module
  end

  defp generate_files(config) do
    maybe_create(Paths.for(config, :api_module), ApiModule.render(config), config.force?)
    maybe_create(Paths.for(config, :controller), Controller.render(config), config.force?)

    maybe_create(
      Paths.for(config, :control_panel_live),
      Live.render(config),
      config.force?
    )
  end

  defp maybe_create(path, content, true), do: create_file(path, content, force: true)
  defp maybe_create(path, content, false), do: create_file(path, content)
end
