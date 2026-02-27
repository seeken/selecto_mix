CHANGES
=======

V 0.3.4
-------

- Fixed generated saved-view dropdown links in `mix selecto.gen.domain` so
  `#{@path}`/`#{v}` interpolation renders correctly in HEEx.
- Replaced Alpine-only dropdown behavior with a native `<details>` menu in
  generated views, avoiding "stuck open" behavior when Alpine is absent.
- Updated `mix selecto.components.integrate` to detect `vendor/` vs `deps/`
  for JavaScript SelectoComponents import paths (CSS already did this).
- Bump package version to `0.3.4`.

V 0.3.3
-------

- Added generated saved-view management functions in
  `mix selecto.gen.saved_views` context output:
  `list_views/1`, `rename_view/3`, and `delete_view/2`.
- Kept generated behavior compatibility with `SelectoComponents.SavedViews`
  while making richer saved-view UIs easier to build.
- Bump package version to `0.3.3`.
