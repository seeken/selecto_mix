defmodule SelectoMix.Gen.Api.RouterNotice do
  @moduledoc false

  alias SelectoMix.Gen.Api.Paths

  def print_router_snippet(config) do
    Mix.shell().info("""

    Add these routes to your router:

        scope "/api", #{config.web_module} do
          pipe_through :api
          post "#{config.api_path |> String.replace_prefix("/api", "")}", #{config.name_module}ApiController, :create
          post "#{config.api_path |> String.replace_prefix("/api", "")}/actions/:action/preview", #{config.name_module}ApiController, :preview_action
          post "#{config.api_path |> String.replace_prefix("/api", "")}/actions/:action/apply", #{config.name_module}ApiController, :apply_action
          post "#{config.api_path |> String.replace_prefix("/api", "")}/query", #{config.name_module}ApiController, :query
          get "#{config.api_path |> String.replace_prefix("/api", "")}/config", #{config.name_module}ApiController, :config
          get "#{config.api_path |> String.replace_prefix("/api", "")}/:id", #{config.name_module}ApiController, :show
        end

    #{panel_route_snippet(config)}
    """)
  end

  defp panel_route_snippet(config) do
    if config.panel_in_prod? do
      """
          scope "/", #{config.web_module} do
            pipe_through :browser
            live "#{config.panel_path}", #{config.name_module}ApiControlPanelLive
          end
      """
    else
      """
          if Mix.env() != :prod do
            scope "/", #{config.web_module} do
              pipe_through :browser
              live "#{config.panel_path}", #{config.name_module}ApiControlPanelLive
            end
          end
      """
    end
  end

  def print_next_steps(config) do
    Mix.shell().info("""

    Generated files:
      - #{Paths.for(config, :api_module)}
      - #{Paths.for(config, :controller)}
      - #{Paths.for(config, :control_panel_live)}

    Next steps:
      1. Wire routes in your router using the snippet above.
      2. Start your server and open #{config.panel_path}.
      3. For choice-backed write fields, assign choice-source options and membership resolvers in the generated LiveView.
         Derive actor, tenant, and required filters from socket/session state, not browser parameters.
      4. For security-sensitive choice filters, add constraint_policy: %{domain_of_interest: :fail_closed} in the domain overlay and make resolvers reject unenforced trusted filters.
      5. If the generated controller accepts choice-backed writes, customize api_config/1 with the same server-owned membership resolver and secure scope.
      6. If you expose action preview/apply or query endpoints, customize authorize_api_request/2 and api_config/1 so actor, tenant, capability_resolver, and trusted action filters come from conn/session state, not browser parameters.
         Set require_capability_resolver: true when capability-declared actions and query requests must fail closed without a resolver.
    """)
  end
end
