# SelectoMix

## Local document schema artifacts

The document lifecycle uses the Selecto runtime supplied by the host project.
It reads local JSON fixtures and never starts the host application, opens a
database connection, or grants write authority from inference. Every output
must be a new file; existing artifacts are never overwritten.

```sh
mix selecto.document.inspect fixture.json --output report.json
mix selecto.document.draft report.json --authoring authored-shape.json --output draft.json
mix selecto.document.check draft.json
mix selecto.document.approve draft.json --reviewer reviewer-name --output release.json
mix selecto.document.diff release.json report.json --output drift.json
```

`fixture.json` is an array of document objects. Inference emits structural
evidence without source values. `--max-documents N` can reduce its sample;
`--excluded-paths exclusions.json` accepts a JSON array of parsed paths such as
`[["private_payload"]]`. Inputs are regular files capped at 8 MB, and inference
also enforces its document, byte, depth, field, array, and time limits.

`authored-shape.json` explicitly declares source identity, trusted tenant path,
version, fields, virtual relations, variants, and access requirements. The draft
preserves this authored policy and attaches inference evidence. Approval
validates and fingerprints the draft; it does not alter source validators,
sample more records, or enable writes. Invalid or mutated artifacts fail checks.

The document CLI integration tests use the real host runtime or an explicitly
selected sibling checkout through `SELECTO_LIVE_SELECTO`. In a tooling-only
checkout without that runtime, lifecycle tests are skipped while file/argument
safety tests still run.

> Alpha software. Generation flows are usable but still evolving.

`selecto_mix` is the tooling package for setting up Selecto in an Elixir project.

Use it when you want to:

- generate domains from Ecto schemas or existing database relations
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
- prove normalized artifact determinism with `mix selecto_mix.verify`

`mix selecto_mix.verify --output PATH` exhaustively checks the built-in finite
model for atom/string key equivalence, construction-order independence, and
JSON round-trip preservation. It exits non-zero with reproducible
counterexamples when an invariant fails.

## Installation

```elixir
def deps do
  [
    {:selecto_mix, ">= 0.5.0 and < 0.6.0"},
    {:selecto, ">= 0.5.0 and < 0.6.0"},
    {:selecto_db_postgresql, ">= 0.5.0 and < 0.6.0"},
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

### Database Adapters

Direct-database features (`--adapter` on `gen.domain`/`gen.saved_views`/etc.,
and `mix selecto.setup`) need the matching `selecto_db_*` adapter package
added to your deps:

| `--adapter` value            | Hex package               |
| ----------------------------- | -------------------------- |
| `postgres` / `postgresql`     | `selecto_db_postgresql`    |
| `mysql`                       | `selecto_db_mysql`         |
| `mariadb`                     | `selecto_db_mariadb`       |
| `sqlite`                      | `selecto_db_sqlite`        |
| `duckdb`                      | `selecto_db_duckdb`        |
| `mssql` / `sqlserver`         | `selecto_db_mssql`         |

If the adapter module isn't loaded, SelectoMix's error/warning messages name
the exact package to add (e.g. `{:selecto_db_postgresql, ">= 0.0.0"}`) so you
can add it to `mix.exs` and run `mix deps.get`.

## Quick Start

Generate a domain from one schema:

```bash
mix selecto.gen.domain MyApp.Catalog.Product
```

Generate domains for all schemas:

```bash
mix selecto.gen.domain --all
```

Generate domains for schemas under a module prefix (wildcard):

```bash
mix selecto.gen.domain MyApp.Catalog.*
```

Generate a domain plus LiveView wiring:

```bash
mix selecto.gen.domain MyApp.Catalog.Product --live
```

Generated domain modules are trusted single-domain registries with a stable
`domain_id/0` and opaque `domain_ref/0`. Their `new/2`, LiveView, query-contract
routes, and generated API reads use `Selecto.configure_registered/3`; authored
domain maps remain inside server-owned modules instead of crossing request or
component boundaries.

### Generate a working LiveView without Ecto

Database-backed generation can introspect an existing table and generate the
domain, overlay, and SelectoComponents LiveView together:

```bash
mix selecto.gen.domain \
  --adapter postgresql \
  --table equipment \
  --database-url postgres://postgres:postgres@localhost/forge_works_dev \
  --connection-name ForgeWorks.Database \
  --live
```

The generated LiveView includes Aggregate, Detail, and Graph views. Database
credentials are used only during generation and are never copied into
generated source. At runtime, supervise a connection under the module name
passed with `--connection-name`:

```elixir
# config/dev.exs
config :forge_works, :database,
  hostname: "localhost",
  database: "forge_works_dev",
  username: "postgres",
  password: "postgres"
```

```elixir
# lib/forge_works/application.ex
database_options = Application.fetch_env!(:forge_works, :database)

children = [
  {Postgrex, Keyword.put(database_options, :name, ForgeWorks.Database)},
  ForgeWorksWeb.Endpoint
]
```

If `--connection-name` is omitted, the generator uses
`<ApplicationModule>.Database` and prints the exact expected runtime name.
Use `--live --saved-views` to generate adapter-backed saved-view persistence
alongside the DB-backed LiveView when the selected adapter supports it.

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
mix selecto.gen.api products \
  --domain MyApp.SelectoDomains.ProductDomain \
  --adapter postgresql \
  --connection MyApp.SelectoPostgreSQL
```

Generated reads use the explicitly selected adapter and named connection.
Generated writes fail closed until
`api_config/1` or the control-panel socket provides a server-owned
`%Selecto{}` configured with `SelectoDBPostgreSQL.Adapter`. No Ecto schema,
Repo target, or `:ecto_repos` configuration is required for the write path.

Generated Updato control panels can render write fields backed by Selecto
`choice_sources`. To enable option loading and membership validation, assign
choice-source resolvers and scope from the LiveView socket or session:

```elixir
socket
|> assign(
  choice_source_domain: MyApp.SelectoDomains.ProductChoiceSources.domain_ref(),
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

1. Generate the base domain from an Ecto schema or database relation.
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

Generated domains include a stable `functions: %{}` section with a commented,
editable draft for connected-verification metadata. The generator does not
invent a function registration: choose the real SQL name, signature, adapter,
requirements, volatility, and minimum database version before uncommenting it.

Generated overlays include `deffunction` examples so named function registrations can live outside regenerated files.

Recommended UDF pattern:

1. generate the domain
2. keep structural metadata in the generated domain file
3. add custom `deffunction` definitions in the overlay
4. add a `database` map when the signature should be checked against a connected database
5. run `mix selecto.functions.verify --domain MyApp.SelectoDomain --strict`
6. regenerate safely as schemas evolve

Static registry validation proves the Selecto declaration is coherent. The
verification task asks the configured adapter to resolve the declared database
signature without executing it. Application-owned semantic fixtures remain a
separate live test layer for representative inputs, nulls, empty sets, boundary
values, and other behavior that matters to the application.

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
