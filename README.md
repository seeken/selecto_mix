# SelectoMix

> Alpha software. Generation flows are usable but still evolving.

`selecto_mix` is the tooling package for setting up Selecto in an Elixir project.

Use it when you want to:

- generate domains from Ecto schemas
- generate overlays for app-specific customizations
- scaffold saved views, exported views, and filter sets
- install Selecto-related dependencies and front-end integration
- validate parameterized joins
- export normalized domain JSON artifacts
- check non-writing import plans for normalized domain JSON artifacts
- generate Studio/tooling inspection JSON from normalized artifacts
- generate Mermaid diagrams from domain inspection artifacts
- generate Markdown docs from normalized domain JSON artifacts
- generate host-app Studio artifact providers for trusted preloaded inspection

## Installation

```elixir
def deps do
  [
    {:selecto_mix, ">= 0.4.5 and < 0.6.0"},
    {:selecto, ">= 0.4.5 and < 0.6.0"},
    {:selecto_db_postgresql, ">= 0.4.3 and < 0.6.0"},
    {:postgrex, ">= 0.0.0"},
    {:ecto, "~> 3.10"}
  ]
end
```

Then run:

```bash
mix igniter.install selecto_mix
mix assets.build
```

For local multi-repo workspace development:

```bash
mix selecto.install --development-mode --source your-github-user
```

## Quick Start

Generate a domain from one schema:

```bash
mix selecto.gen.domain MyApp.Catalog.Product
```

Generate domains for all schemas:

```bash
mix selecto.gen.domain --all
```

Generate a domain plus LiveView wiring:

```bash
mix selecto.gen.domain MyApp.Catalog.Product --live
```

Generate a trusted provider module for Studio's host-app artifact registry:

```bash
mix selecto.gen.domain MyApp.Catalog.Product --studio-artifacts
```

The generated provider uses core `Selecto.Domain` inspection APIs. Register it
with `config :selecto_studio, :domain_artifacts` in the host app when you want
`SelectoStudioWeb.DomainInspectionController` to preload that domain.

The generated router notice includes the LiveView route plus optional
`SelectoComponents.QueryContract.Plug`,
`SelectoComponents.QueryContract.Guide.Plug`, and
`SelectoComponents.QueryContract.IntentValidator.Plug` routes for serving
`query-contract.json`, a compact Markdown `query-guide.md`, and a
non-executing query intent validator.

Generate an Updato API endpoint and control panel:

```bash
mix selecto.gen.api products --domain MyApp.SelectoDomains.ProductDomain --schema MyApp.Catalog.Product
```

Generated Updato control panels can render write fields backed by Selecto
`choice_sources`. To enable option loading and membership validation, assign
choice-source resolvers and scope from the LiveView socket or session:

```elixir
socket
|> assign(
  choice_source_domain: MyApp.SelectoDomains.ProductChoiceSources.domain(),
  choice_source_options_resolver: &MyApp.SelectoDomains.ProductChoiceSources.resolve_options/1,
  choice_source_membership_resolver: &MyApp.SelectoDomains.ProductChoiceSources.resolve_membership/1,
  choice_source_value_parser: &MyApp.SelectoDomains.ProductChoiceSources.parse_value/2,
  choice_source_scope: %{
    actor: socket.assigns.current_scope.user,
    tenant: socket.assigns.current_scope.user.account_id,
    context: %{surface: :updato_control_panel}
  }
)
```

Keep actor, tenant, and required domain filters server-owned. Browser payloads
may provide search text or a selected id, but they should not be trusted for
tenant or authorization scope.

For choice sources whose Domain-of-Interest filters are security-sensitive,
declare a fail-closed policy in the domain overlay:

```elixir
defchoice_source(:product_assignees, %{
  domain: :employees,
  value_field: :id,
  label_field: :full_name,
  constraint_policy: %{domain_of_interest: :fail_closed}
})
```

Resolvers should return a closed option/membership result when that policy is
present and any trusted filter cannot be enforced.

## Core Workflow

Recommended workflow:

1. Generate the base domain from your Ecto schema.
2. Keep schema-derived structure in the generated file.
3. Put custom filters, columns, and named functions in overlays when possible.
4. Re-run generation when schemas change.

That keeps generated structure and user-authored behavior separate.

## Common Tasks

- `mix selecto.gen.domain`
- `mix selecto.install`
- `mix selecto.gen.saved_views`
- `mix selecto.gen.saved_view_configs`
- `mix selecto.gen.exported_views`
- `mix selecto.gen.filter_sets`
- `mix selecto.gen.live_dashboard`
- `mix selecto.add_timeouts`
- `mix selecto.validate.parameterized_joins`
- `mix selecto.domain.export`
- `mix selecto.domain.check`
- `mix selecto.domain.import`
- `mix selecto.domain.inspect`
- `mix selecto.domain.describe`
- `mix selecto.domain.diagram`
- `mix selecto.domain.diff`
- `mix selecto.domain.docs`

After `mix selecto.gen.domain` creates a domain, it prints the matching
export/check/import/inspect/describe/diagram/docs follow-up commands with
suggested `priv/selecto/*.normalized.json`, `priv/selecto/*.inspection.json`,
and `docs/selecto/*.diagram.mmd` / `docs/selecto/*.md` artifact paths.

Export a normalized domain JSON artifact:

```bash
mix selecto.domain.export MyApp.SelectoDomains.ProductDomain --output priv/selecto/product.normalized.json
```

Runtime-only values such as function captures are emitted as explicit
placeholder metadata so the artifact remains JSON-safe for tools.

Check an exported artifact without loading the original domain module:

```bash
mix selecto.domain.check priv/selecto/product.normalized.json
```

Preview the current import/readback plan:

```bash
mix selecto.domain.import priv/selecto/product.normalized.json --check
```

The import check includes a generated-domain preview with the target module,
target file, reconstructed sections, and runtime placeholders that still need
manual handling. It also parses the source preview and checks that the target
module and `domain/0` are present without executing the code.

Add `--source` to print the would-be Elixir module source without writing it,
or use `--format json` to include the source preview in the import plan.

Write the generated module only after that preview is fully validated and has
no runtime placeholders:

```bash
mix selecto.domain.import priv/selecto/product.normalized.json --write --target-file lib/my_app/selecto_domains/product_domain.ex
```

Existing files are preserved by default; pass `--force` when you intentionally
want to overwrite the target.

Inspect the same artifact for a compact sections/counts/registries summary:

```bash
mix selecto.domain.inspect priv/selecto/product.normalized.json
```

Generate Studio/tooling inspection JSON from the same artifact:

```bash
mix selecto.domain.describe priv/selecto/product.normalized.json --output priv/selecto/product.inspection.json
```

Generate a Mermaid diagram from the inspection artifact:

```bash
mix selecto.domain.diagram priv/selecto/product.inspection.json --output docs/selecto/product.diagram.mmd
```

Generate Markdown docs from the same artifact, including capability usage
tables when the domain declares capability references:

```bash
mix selecto.domain.docs priv/selecto/product.normalized.json --output docs/selecto/product.md
```

Diff two artifacts:

```bash
mix selecto.domain.diff priv/selecto/old.normalized.json priv/selecto/new.normalized.json
```

## UDF Workflow

Generated domains include a stable `functions: %{}` section.

Generated overlays include `deffunction` examples so named function registrations can live outside regenerated files.

Recommended UDF pattern:

1. generate the domain
2. keep structural metadata in the generated domain file
3. add custom `deffunction` definitions in the overlay
4. regenerate safely as schemas evolve

## Status

Current `0.4.x` scope:

- domain generation is usable but not stable
- overlay-based customization is the supported path
- parameterized join validation exists and is still expanding
- runtime query helper generation is intentionally not part of the current scope

## Demos And Tutorials

- `selecto_livebooks`
- `selecto_northwind`
- hosted demo: `testselecto.fly.dev`
