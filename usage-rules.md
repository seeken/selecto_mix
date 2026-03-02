# SelectoMix Usage Rules

## Generation Workflow
- Use `mix selecto.gen.domain` as the primary generation entrypoint.
- Prefer regeneration-safe patterns: keep user customization in overlays and custom sections.
- After generation, compile immediately and run focused tests.

## Related Tasks
- Use `mix selecto.components.integrate` when wiring generated LiveView assets/hooks.
- Use `mix selecto.validate.parameterized_joins` after touching parameterized join definitions.
- For saved configuration persistence, use generators for saved views/filter sets where applicable.

## Safe Regeneration
- Preserve existing custom filters, custom columns, and domain defaults during refreshes.
- Avoid destructive rewrites unless explicitly requested.
- Keep generated output aligned with current package APIs and documented examples.
