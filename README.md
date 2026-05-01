# SelectoMix

> Alpha software. Generation flows are usable but still evolving.

`selecto_mix` is the tooling package for setting up Selecto in an Elixir project.

Use it when you want to:

- generate domains from Ecto schemas
- generate overlays and preserve customizations across refreshes
- scaffold saved views, exported views, and filter sets
- install Selecto-related dependencies and front-end integration
- validate parameterized joins

## Installation

```elixir
def deps do
  [
    {:selecto_mix, ">= 0.4.5 and < 0.5.0"},
    {:selecto, ">= 0.4.5 and < 0.5.0"},
    {:selecto_db_postgresql, ">= 0.4.3 and < 0.5.0"},
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

The generated router notice includes the LiveView route plus optional
`SelectoComponents.QueryContract.Plug` and
`SelectoComponents.QueryContract.Guide.Plug` routes for serving
`query-contract.json` and a compact Markdown `query-guide.md`.

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
- customization preservation is a core goal and supported path
- parameterized join validation exists and is still expanding
- runtime query helper generation is intentionally not part of the current scope

## Demos And Tutorials

- `selecto_livebooks`
- `selecto_northwind`
- hosted demo: `testselecto.fly.dev`
