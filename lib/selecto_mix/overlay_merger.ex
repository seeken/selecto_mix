defmodule SelectoMix.OverlayMerger do
  @moduledoc """
  Convenience module that delegates to `Selecto.Config.Overlay`.

  This module exists for backward compatibility and to provide a familiar
  namespace for selecto_mix users. All functionality has been moved to
  `Selecto.Config.Overlay` as the overlay system is a core Selecto feature,
  not specific to the Mix task generator.

  ## Migration

  If you're using this module directly, please update your code to use
  `Selecto.Config.Overlay` instead:

      # Old
      SelectoMix.OverlayMerger.merge(base, overlay)

      # New
      Selecto.Config.Overlay.merge(base, overlay)

  ## See Also

  - `Selecto.Config.Overlay` - The main implementation with full documentation
  """

  @doc """
  Merges a base domain configuration with an overlay configuration.

  Delegates to `Selecto.Config.Overlay.merge/2`.

  See `Selecto.Config.Overlay` for detailed documentation and examples.
  """
  defdelegate merge(base, overlay), to: Selecto.Config.Overlay
end
