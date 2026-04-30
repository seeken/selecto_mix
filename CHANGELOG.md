CHANGES
=======

V 0.4.5
----------

- Updated generated LiveView route guidance to include a
  `SelectoComponents.QueryContract.Plug` `query-contract.json` endpoint beside
  the Explorer route.
- Fixed generated LiveView templates so the SelectoComponents form/controller
  is always rendered, with collapsed/expanded state passed into the component,
  instead of hiding the whole controller and leaving generated pages blank.
- Updated README dependency guidance for `selecto_mix >= 0.4.5`.
- Bump package version to `0.4.5`.

V 0.4.4
----------

- Updated installer and README dependency baselines for the coordinated point
  release: `selecto >= 0.4.5`, `selecto_db_postgresql >= 0.4.3`, and
  `selecto_components >= 0.4.7`.
- Fixed generated LiveView output to avoid duplicate `render/1` and
  `toggle_show_view_configurator` definitions, and to emit colocated HEEx
  templates beside the generated LiveView module so Phoenix can render them.
- Bump package version to `0.4.4`.

V 0.4.3
----------

- Fixed schema introspection and domain generation so `:binary_id` and `:uuid`
  fields stay UUID-aware instead of degrading to plain strings in generated
  Selecto configs.
- Added regression coverage for binary-id primary keys and UUID columns in the
  schema introspector and generated domain map output.
- Bump package version to `0.4.3`.

V 0.4.2
----------

- Added `mix selecto.gen.domain` support for `--view`,
  `--materialized-view`, `--primary-key`, and `--include-views` so existing DB
  views can be generated as read-only Selecto domain sources.
- Updated DB-backed domain generation to carry through relation metadata via
  `source_kind` and `readonly`, and to preserve explicit primary-key overrides
  for view-backed sources where the database may not expose a usable key.
- Added `mix selecto.gen.view` for dry-run publication of registered
  `published_views`, printing the compiled Selecto SQL and generated `CREATE
  VIEW` / `CREATE MATERIALIZED VIEW` DDL for inspection.
- Extended `mix selecto.gen.view` to generate Ecto migration files for
  published views, using the same validated DDL path for `up` and matching drop
  statements for `down`.
- Added published-view index suggestion rendering to `mix selecto.gen.view`
  dry-run output and generated migration comments so follow-up indexing guidance
  stays attached to the published view artifact.
- Updated generated domains to always emit a `functions: %{}` section so UDF
  registrations have an explicit home in the base domain config.
- Preserved existing base-domain `functions` registries during
  `mix selecto.gen.domain` regeneration instead of dropping custom UDF specs.
- Added commented `deffunction` examples to generated overlay templates for
  scalar and table UDF registrations.
- Updated installer dependency baselines and README guidance for the coordinated
  ecosystem release, keeping generated Selecto dependency ranges broad
  (`>= ... and < 0.5.0`) instead of pin-like exact versions.
- Bump package version to `0.4.2`.

V 0.4.1
--------

- Updated `mix selecto.gen.saved_view_configs` generated docs and templates to
  reflect the current SelectoComponents view-mode set, and added the generated
  `load_view_config/4` helper expected by current components code.
- Fixed raw saved view config context generation to emit `load_view_config/4`
  alongside the existing get/list/save/update/delete helpers.
- Updated generated LiveView templates to use the canonical
  `SelectoComponents.Views.spec/4` helper and document that extension-provided
  views such as `:map` and `:timeseries` are merged automatically.
- Updated `mix selecto.gen.exported_views` docs/templates to reflect the
  current exported view-mode set and clarify that `SelectoComponents.Form`
  renders the exported views manager automatically when configured.
- Updated `mix selecto.gen.filter_sets` guidance to reflect current
  `SelectoComponents.Form` integration, where assigning `filter_sets_adapter`
  is sufficient for the built-in filter sets UI.
- Updated `mix selecto.gen.live_dashboard` guidance to reflect current
  dashboard routing conventions and clarify which generated metrics/index
  sections are placeholders for app-specific data.
- Updated `mix selecto.add_timeouts` generated monitor output so it no longer
  references a nonexistent `Selecto.QueryTimeoutMonitor` helper module.
- Refreshed stale `selecto_mix` task documentation by removing the nonexistent
  `mix selecto.update` reference and listing the currently shipped generators.
- Fixed `mix selecto.gen.domain` auto-generation of saved views to stop passing
  an unsupported `--yes` flag.
- Bump package version to `0.4.1`.

V 0.4.0
--------

- Updated installer dependency baselines for the `0.4.0` ecosystem release.
- Updated generated install dependencies to include the external
  `selecto_db_postgresql` adapter package for the default PostgreSQL path.
- Updated `mix selecto.install` to add the `postgrex` database driver required
  by the default PostgreSQL adapter path, while preserving an existing app-level
  `postgrex` dependency declaration when present.
- Bump package version to `0.4.0`.

V 0.3.16
--------

- Raised the minimum supported Elixir version to `1.18`.
- Bump package version to `0.3.16`.

V 0.3.15
--------

- Updated `mix selecto.components.integrate` to treat Phoenix LiveView
  colocated hooks as the canonical SelectoComponents integration path, removing
  generated `./selecto_hooks`, `TreeBuilderHook`, and Alpine.js requirements.
- Updated integration patching/manual guidance so generated LiveSocket wiring
  uses only `phoenix-colocated/selecto_components` hooks plus the Tailwind
  `@source` entry for SelectoComponents.
- Bump package version to `0.3.15`.

V 0.3.14
--------

- Updated package metadata description to better reflect Selecto domain
  generation and validation responsibilities.
- Added package links for SQL pattern references and the hosted demo
  (`https://seeken.github.io/selecto-sql-patterns`,
  `https://testselecto.fly.dev`).
- Bump package version to `0.3.14`.

V 0.3.13
--------

- Added native `mix selecto.gen.api` scaffolding task in `selecto_mix` so
  Selecto API generation no longer requires a separate app-level
  `selecto_api` dependency declaration.
- Updated `mix selecto.gen.updato_api` to be a compatibility alias that
  delegates to `mix selecto.gen.api`.
- Updated README API scaffolding docs to prefer `mix selecto.gen.api`.
- Bump package version to `0.3.13`.

V 0.3.12
--------

- Updated installer dependency baselines in `mix selecto.install` to target
  current ecosystem releases (`selecto >= 0.3.10`,
  `selecto_components >= 0.3.12`).
- Updated README dependency guidance for the coordinated ecosystem release.
- Bump package version to `0.3.12`.

V 0.3.11
--------

- Added `mix selecto.gen.updato_api` wrapper task delegating to
  `mix selecto_api.gen.api`.
- Updated README wrapper docs to reflect `selecto_api` ownership for API
  scaffolding.
- Bump package version to `0.3.11`.

V 0.3.10
--------

- Fixed Northwind generation/introspection behavior in domain generator and
  Ecto introspection paths, with updated coverage in `selecto_mix` tests.
- Added StreamData-backed property coverage for parser/validator and
  config-merger robustness (`test/selecto_mix_property_test.exs`).
- Added README documentation for running the SelectoMix property suite.
- Bump package version to `0.3.10`.

V 0.3.9
-------

- Added `usage-rules.md` with focused package guidance for agentic workflows and
  dependency rule aggregation tooling.
- Added `MULTI_TENANT_USAGE_PATTERNS.md` with generator-focused guidance for
  tenant-aware domain overlays, join validation, and generated app wiring.
- Updated `mix selecto.gen.saved_views` generated context template to support
  map-style contexts and tenant-scoped context keys through
  `SelectoComponents.Tenant.scoped_context/3` when available.
- Updated `mix selecto.gen.filter_sets` generated context template to scope
  domain keys and create-path domain attrs for tenant-aware filter set
  persistence.
- Added generator coverage test ensuring `mix selecto.gen.filter_sets` emits
  tenant-scoped domain helpers in generated context modules.
- Bump package version to `0.3.9`.

V 0.3.8
-------

- Fixed installer task compilation in consuming apps by restoring `:igniter`
  dependency availability in all environments (not scoped to dev/test).
- Added `mix selecto.install` (Igniter task) to bootstrap Selecto dependencies,
  run components integration, and support development-mode vendor clones from
  a configurable GitHub source owner (`--development-mode --source your-fork`).
- Documented the recommended happy-path installation flow in README:
  `mix igniter.install selecto_mix`, then `cd assets && npm install`, then
  `mix assets.build`.
- Added `mix selecto_mix.install` as an alias to `mix selecto.install` for
  explicit package-scoped install UX.
- Fixed `mix selecto.install` dependency rewrites to preserve valid comma
  separation when appending/removing dependency lines in `mix.exs`.
- Fixed `mix igniter.install selecto_mix` installer dispatch for
  `mix selecto_mix.install` by defining `supports_umbrella?/0`.
- Fixed `mix igniter.install selecto_mix` compatibility by converting
  `mix selecto_mix.install` to an `Igniter.Mix.Task` alias implementation
  (resolves missing `parse_argv/1` runtime error).
- Bump package version to `0.3.8`.

V 0.3.7
-------

- Updated `mix selecto.components.integrate` to always print clear post-run
  asset steps: `cd assets && npm install` and `mix assets.build`.
- Bump package version to `0.3.7`.

V 0.3.6
-------

- Fixed a crash in `mix selecto.components.integrate` when updating existing
  `hooks: {...}` LiveSocket config blocks by switching to `Regex.replace/4`
  capture replacement.
- Bump package version to `0.3.6`.

V 0.3.5
-------

- Fixed `mix selecto.components.integrate` to use
  `phoenix-colocated/selecto_components` plus local `./selecto_hooks` imports
  instead of non-existent `selecto_components/assets/js/hooks` paths in Hex
  dependency installs.
- Added legacy import normalization when re-running
  `mix selecto.components.integrate`, so previously generated broken hooks
  import lines are auto-corrected.
- Bump package version to `0.3.5`.

V 0.3.4
-------

- Fixed generated saved-view dropdown links in `mix selecto.gen.domain` so
  `#{@path}`/`#{v}` interpolation renders correctly in HEEx.
- Replaced Alpine-only dropdown behavior with a native `<details>` menu in
  generated views, avoiding "stuck open" behavior when Alpine is absent.
- Updated `mix selecto.components.integrate` to detect `vendor/` vs `deps/`
  for JavaScript SelectoComponents import paths (CSS already did this).
- Fixed `mix selecto.components.integrate` to use
  `phoenix-colocated/selecto_components` + local `./selecto_hooks` imports
  instead of non-existent `selecto_components/assets/js/hooks` in Hex deps,
  and auto-normalize legacy broken import lines when re-run.
- Bump package version to `0.3.4`.

V 0.3.3
-------

- Added generated saved-view management functions in
  `mix selecto.gen.saved_views` context output:
  `list_views/1`, `rename_view/3`, and `delete_view/2`.
- Kept generated behavior compatibility with `SelectoComponents.SavedViews`
  while making richer saved-view UIs easier to build.
- Bump package version to `0.3.3`.
