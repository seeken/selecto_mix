defmodule SelectoMix.Inflect do
  @moduledoc false

  @doc """
  Singularizes a word (typically a table name) using simple suffix-based
  heuristics.

  ## Examples

      iex> SelectoMix.Inflect.singularize("categories")
      "category"

      iex> SelectoMix.Inflect.singularize("addresses")
      "address"

      iex> SelectoMix.Inflect.singularize("users")
      "user"

      iex> SelectoMix.Inflect.singularize("class")
      "class"
  """
  @spec singularize(String.t()) :: String.t()
  def singularize(word) when is_binary(word) do
    cond do
      String.ends_with?(word, "ies") ->
        String.replace_suffix(word, "ies", "y")

      String.ends_with?(word, "sses") ->
        String.replace_suffix(word, "sses", "ss")

      String.ends_with?(word, "ses") ->
        String.replace_suffix(word, "ses", "s")

      String.ends_with?(word, "s") and not String.ends_with?(word, "ss") ->
        String.replace_suffix(word, "s", "")

      true ->
        word
    end
  end
end
