# Multi-Tenant Usage Patterns for SelectoMix

## Purpose

Define how SelectoMix generators and validation tasks should support
multi-tenant projects without requiring repeated manual patching after
regeneration.

## Design Goals

1. Preserve tenant customizations during `mix selecto.gen.domain` reruns.
2. Keep tenant logic in overlays/custom sections, not in generated core blocks.
3. Validate parameterized join references in tenant-sensitive joins.

## Recommended Generation Strategy

### 1) Base Domain + Overlay Split

- Keep generated domain as neutral schema description.
- Inject tenant constraints through overlays referenced by generated modules.
- Prefer runtime overlay merge keyed by tenant context.

### 2) Saved Views and Filter Sets

- When generating saved-view/filter-set support, include tenant-aware context
  keying patterns in generated docs/comments.
- Avoid globally shared lookup keys in generated code examples.

### 3) Parameterized Joins

- Use parameterized joins for tenant-specific cross-schema relationships where
  static joins are insufficient.
- Run `mix selecto.validate.parameterized_joins` after join template updates.

## Generator Roadmap (Tenant Support)

1. Add optional `--tenant-field` guidance output for shared-table models.
2. Add optional overlay scaffold helper for tenant required filters.
3. Add generated docs snippet for schema-prefix and dedicated-db modes.
4. Add generator tests that assert custom tenant overlay blocks are preserved
   after regeneration.

## Project-Level Checklist

- [ ] generated domain merged with tenant overlay.
- [ ] tenant filters not stored as user-editable UI defaults.
- [ ] parameterized joins validated after tenant-related edits.
- [ ] saved-view/filter-set adapters include tenant namespace.
