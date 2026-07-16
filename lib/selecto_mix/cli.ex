defmodule SelectoMix.CLI do
  @moduledoc false

  @doc """
  Parses `args` with `OptionParser.parse/2`, raising via `Mix.raise/1` if any
  switches are invalid (unknown or wrongly typed).

  `parser_opts` is passed through to `OptionParser.parse/2` as-is (e.g.
  `strict: [...], aliases: [...]`).

  Returns `{opts, positional}` on success, omitting the (always empty on
  success) invalid-switches list that `OptionParser.parse/2` returns.
  """
  @spec parse!(OptionParser.argv(), keyword()) :: {keyword(), [String.t()]}
  def parse!(args, parser_opts) do
    case OptionParser.parse(args, parser_opts) do
      {opts, positional, []} ->
        {opts, positional}

      {_opts, _positional, invalid} ->
        Mix.raise("Invalid option(s): #{format_invalid_options(invalid)}")
    end
  end

  @doc """
  Formats a list of `{switch, value}` pairs (as returned in the `invalid`
  position of `OptionParser.parse/2`, or as an `opts` keyword list) into a
  human-readable string for error messages.
  """
  @spec format_invalid_options([{String.t() | atom(), term()}]) :: String.t()
  def format_invalid_options(invalid) do
    invalid
    |> Enum.map(fn
      {switch, nil} -> switch
      {switch, value} -> "#{switch} #{value}"
    end)
    |> Enum.join(", ")
  end
end
