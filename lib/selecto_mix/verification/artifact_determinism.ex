defmodule SelectoMix.Verification.ArtifactDeterminism do
  @moduledoc """
  Bounded verification of normalized-domain artifact determinism.
  """

  alias SelectoMix.DomainExport
  alias SelectoMix.Verification.BoundedModel

  def verify do
    baseline = encode(:string, :string, :forward)

    states =
      for envelope_keys <- [:atom, :string],
          domain_keys <- [:atom, :string],
          construction <- [:forward, :reverse] do
        %{
          envelope_keys: envelope_keys,
          domain_keys: domain_keys,
          construction: construction,
          encoded: encode(envelope_keys, domain_keys, construction),
          baseline: baseline
        }
      end

    BoundedModel.check("selecto_mix.artifact_determinism.v1", states, [
      {"equivalent_artifacts_encode_identically", &encodes_identically/1},
      {"encoded_artifact_round_trips", &round_trips/1}
    ])
  end

  defp encodes_identically(state) do
    if state.encoded == state.baseline,
      do: :ok,
      else: {:error, :non_deterministic_encoding}
  end

  defp round_trips(state) do
    case Jason.decode(state.encoded) do
      {:ok, %{"format" => "selecto.normalized_domain", "domain" => %{"name" => "Orders"}}} ->
        :ok

      other ->
        {:error, {:invalid_round_trip, other}}
    end
  end

  defp encode(envelope_keys, domain_keys, construction) do
    domain =
      [
        pair(domain_keys, :name, "Orders"),
        pair(domain_keys, :source, map(domain_keys, id: "orders", fields: ["id", "status"])),
        pair(
          domain_keys,
          :capabilities,
          map(domain_keys, read: %{operations: ["select"]})
        )
      ]
      |> construct(construction)

    [
      pair(envelope_keys, :format, "selecto.normalized_domain"),
      pair(envelope_keys, :format_version, 1),
      pair(envelope_keys, :domain_module, "Example.Orders"),
      pair(envelope_keys, :domain, domain)
    ]
    |> construct(construction)
    |> DomainExport.encode!(pretty: false)
  end

  defp map(style, pairs) do
    pairs
    |> Enum.map(fn {key, value} -> pair(style, key, value) end)
    |> Map.new()
  end

  defp pair(:atom, key, value), do: {key, value}
  defp pair(:string, key, value), do: {Atom.to_string(key), value}

  defp construct(pairs, :forward), do: Map.new(pairs)
  defp construct(pairs, :reverse), do: pairs |> Enum.reverse() |> Map.new()
end
