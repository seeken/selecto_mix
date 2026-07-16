defmodule SelectoMix.ArtifactJSON do
  @moduledoc false

  @doc """
  Looks up `key` in `map`, trying both the given key and its string/atom
  counterpart.

  Domain artifacts are decoded from JSON (string keys) but also constructed
  in-memory with atom keys, so callers need to look up a value regardless of
  which form the map happens to use. Falls back to `default` if neither form
  is present.
  """
  @spec map_get(map(), String.t() | atom(), term()) :: term()
  def map_get(map, key, default \\ nil)

  def map_get(map, key, default) when is_map(map) and is_binary(key) do
    atom_key = existing_atom(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      atom_key && Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> default
    end
  end

  def map_get(map, key, default) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  def map_get(_map, _key, default), do: default

  @doc """
  Converts `value` to an existing atom, returning `nil` instead of raising if
  no such atom exists.
  """
  @spec existing_atom(String.t()) :: atom() | nil
  def existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
