defmodule SelectoMix.ComponentsDeprecation do
  @moduledoc false

  # selecto_components is replaced by selecto_views. Generators whose output
  # still targets selecto_components keep working for existing hosts and say so.

  @doc """
  Deprecation text for a task whose output targets selecto_components.
  """
  def message(task) do
    """
    warning: mix #{task} is deprecated. It generates code for selecto_components,
    which is replaced by selecto_views. The generated code only works in a host
    that still depends on selecto_components.
    """
  end

  @doc """
  Prints the deprecation text for `task` on standard error.
  """
  def warn(task), do: Mix.shell().error(message(task))
end
