CHANGES
=======

V NEXT
------

- Added `mix selecto.gen.updato_api` wrapper task delegating to
  `mix selecto_api.gen.api`.
- Updated README wrapper docs to reflect `selecto_api` ownership for API
  scaffolding.

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
