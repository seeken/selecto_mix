defmodule SelectoMix.Verification.BoundedModel do
  @moduledoc false

  def check(model, states, invariants) do
    states = Enum.to_list(states)

    counterexamples =
      for {state, state_index} <- Enum.with_index(states),
          {invariant, invariant_index} <- Enum.with_index(invariants),
          result = safe_check(invariant, state),
          result not in [:ok, true],
          do: %{
            invariant: to_string(elem(invariant, 0)),
            invariant_index: invariant_index,
            state_index: state_index,
            state: portable(state),
            reason: portable(result)
          }

    %{
      format: "selecto.formal_verification",
      format_version: 1,
      proof_level: :bounded_exhaustive,
      model: to_string(model),
      state_count: length(states),
      invariant_count: length(invariants),
      check_count: length(states) * length(invariants),
      proved?: counterexamples == [],
      counterexamples: counterexamples
    }
  end

  defp safe_check({_name, invariant}, state) do
    try do
      invariant.(state)
    rescue
      exception -> {:exception, inspect(exception.__struct__), Exception.message(exception)}
    end
  end

  defp portable(value)
       when is_nil(value) or is_boolean(value) or is_binary(value) or is_number(value) or
              is_atom(value),
       do: value

  defp portable(value) when is_list(value), do: Enum.map(value, &portable/1)

  defp portable(value) when is_tuple(value),
    do: %{tuple: value |> Tuple.to_list() |> Enum.map(&portable/1)}

  defp portable(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), portable(item)} end)

  defp portable(value), do: inspect(value)
end
