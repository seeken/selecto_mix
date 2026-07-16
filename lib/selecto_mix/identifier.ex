defmodule SelectoMix.Identifier do
  @moduledoc false

  @elixir_identifier_regex ~r/^[A-Za-z_][A-Za-z0-9_]*$/
  @sql_identifier_regex ~r/^[A-Za-z_][A-Za-z0-9_]*$/
  @max_sql_identifier_bytes 63

  @doc """
  Returns true if `name` is a syntactically valid Elixir identifier
  (variable/atom/module-segment charset), e.g. matches `~r/^[A-Za-z_][A-Za-z0-9_]*$/`.
  """
  @spec valid_elixir_identifier?(term()) :: boolean()
  def valid_elixir_identifier?(name) when is_binary(name) do
    Regex.match?(@elixir_identifier_regex, name)
  end

  def valid_elixir_identifier?(_name), do: false

  @doc """
  Returns true if `name` is a safe SQL identifier: same charset as an Elixir
  identifier, and no more than 63 bytes (the PostgreSQL identifier limit).
  """
  @spec valid_sql_identifier?(term()) :: boolean()
  def valid_sql_identifier?(name) when is_binary(name) do
    Regex.match?(@sql_identifier_regex, name) and byte_size(name) <= @max_sql_identifier_bytes
  end

  def valid_sql_identifier?(_name), do: false

  @doc """
  Validates that `name` (a binary or atom) is a safe SQL identifier.

  Returns `{:ok, name}` (as a binary) or `{:error, message}`.
  """
  @spec validate_sql_identifier(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_sql_identifier(name) when is_binary(name) do
    if valid_sql_identifier?(name) do
      {:ok, name}
    else
      {:error, "invalid SQL identifier: #{inspect(name)}"}
    end
  end

  def validate_sql_identifier(name) when is_atom(name) and not is_nil(name) do
    validate_sql_identifier(Atom.to_string(name))
  end

  def validate_sql_identifier(name) do
    {:error, "invalid SQL identifier: #{inspect(name)}"}
  end

  @doc """
  Same as `validate_sql_identifier/1`, but raises `ArgumentError` on failure
  and returns the validated binary directly.
  """
  @spec validate_sql_identifier!(term()) :: String.t()
  def validate_sql_identifier!(name) do
    case validate_sql_identifier(name) do
      {:ok, valid} -> valid
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Converts a DB/CLI-derived value to an atom, validating it first.

  Atoms pass through unchanged. Binaries are validated as safe SQL
  identifiers before being converted with `String.to_atom/1`. Anything else
  (or an invalid binary) raises `ArgumentError`.
  """
  @spec to_atom!(term()) :: atom()
  def to_atom!(value) when is_atom(value) and not is_nil(value), do: value

  def to_atom!(value) when is_binary(value) do
    value
    |> validate_sql_identifier!()
    |> String.to_atom()
  end

  def to_atom!(value) do
    raise ArgumentError, "cannot convert #{inspect(value)} to an atom identifier"
  end

  @doc """
  Same as `to_atom!/1`, but returns `{:ok, atom} | {:error, message}` instead
  of raising.
  """
  @spec to_atom(term()) :: {:ok, atom()} | {:error, String.t()}
  def to_atom(value) when is_atom(value) and not is_nil(value), do: {:ok, value}

  def to_atom(value) when is_binary(value) do
    case validate_sql_identifier(value) do
      {:ok, valid} -> {:ok, String.to_atom(valid)}
      {:error, reason} -> {:error, reason}
    end
  end

  def to_atom(value), do: {:error, "cannot convert #{inspect(value)} to an atom identifier"}
end
