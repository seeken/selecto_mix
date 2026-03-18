defmodule SelectoMix.SqlRunner do
  @moduledoc false

  def run_sql_directory(adapter, conn, dir, opts \\ []) do
    pattern = Keyword.get(opts, :pattern, "*.sql")

    sql_files =
      Path.join(dir, pattern)
      |> Path.wildcard()
      |> Enum.sort()

    if Enum.empty?(sql_files) do
      {:ok, :no_files}
    else
      results = Enum.map(sql_files, &run_sql_file(adapter, conn, &1))
      errors = Enum.filter(results, &match?({:error, _, _}, &1))

      if Enum.empty?(errors) do
        {:ok, length(sql_files)}
      else
        {:error, errors}
      end
    end
  end

  def run_sql_file(adapter, conn, file_path) do
    case File.read(file_path) do
      {:ok, sql} -> run_sql_string(adapter, conn, sql, file_path)
      {:error, reason} -> {:error, file_path, {:file_read_error, reason}}
    end
  end

  def run_sql_string(adapter, conn, sql, label \\ "inline") do
    statements = split_sql_statements(sql)

    results =
      Enum.map(statements, fn stmt ->
        case adapter.execute(conn, stmt, [], prepared: false) do
          {:ok, result} -> {:ok, result}
          {:error, error} -> {:error, label, error}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if Enum.empty?(errors) do
      {:ok, label, length(statements)}
    else
      List.first(errors)
    end
  end

  defp split_sql_statements(sql) when is_binary(sql) do
    sql
    |> parse_sql(:normal, [], [])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_sql(<<>>, _state, current, statements),
    do: maybe_append_statement(statements, current)

  defp parse_sql(<<";", rest::binary>>, :normal, current, statements) do
    statement = current |> Enum.reverse() |> IO.iodata_to_binary()
    parse_sql(rest, :normal, [], [statement | statements])
  end

  defp parse_sql(<<"--", rest::binary>>, :normal, current, statements),
    do: parse_sql(rest, :line_comment, ["--" | current], statements)

  defp parse_sql(<<"/*", rest::binary>>, :normal, current, statements),
    do: parse_sql(rest, {:block_comment, 1}, ["/*" | current], statements)

  defp parse_sql(binary, :normal, current, statements) do
    case dollar_quote_delimiter(binary) do
      {:ok, delimiter} ->
        size = byte_size(delimiter)
        <<prefix::binary-size(size), rest::binary>> = binary
        parse_sql(rest, {:dollar_quote, delimiter}, [prefix | current], statements)

      :error ->
        <<char::utf8, rest::binary>> = binary

        next_state =
          case char do
            ?' -> :single_quote
            ?" -> :double_quote
            _ -> :normal
          end

        parse_sql(rest, next_state, [<<char::utf8>> | current], statements)
    end
  end

  defp parse_sql(<<"''", rest::binary>>, :single_quote, current, statements),
    do: parse_sql(rest, :single_quote, ["''" | current], statements)

  defp parse_sql(<<"'", rest::binary>>, :single_quote, current, statements),
    do: parse_sql(rest, :normal, ["'" | current], statements)

  defp parse_sql(<<char::utf8, rest::binary>>, :single_quote, current, statements),
    do: parse_sql(rest, :single_quote, [<<char::utf8>> | current], statements)

  defp parse_sql(<<"\"\"", rest::binary>>, :double_quote, current, statements),
    do: parse_sql(rest, :double_quote, ["\"\"" | current], statements)

  defp parse_sql(<<"\"", rest::binary>>, :double_quote, current, statements),
    do: parse_sql(rest, :normal, ["\"" | current], statements)

  defp parse_sql(<<char::utf8, rest::binary>>, :double_quote, current, statements),
    do: parse_sql(rest, :double_quote, [<<char::utf8>> | current], statements)

  defp parse_sql(<<"\n", rest::binary>>, :line_comment, current, statements),
    do: parse_sql(rest, :normal, ["\n" | current], statements)

  defp parse_sql(<<char::utf8, rest::binary>>, :line_comment, current, statements),
    do: parse_sql(rest, :line_comment, [<<char::utf8>> | current], statements)

  defp parse_sql(<<"/*", rest::binary>>, {:block_comment, depth}, current, statements),
    do: parse_sql(rest, {:block_comment, depth + 1}, ["/*" | current], statements)

  defp parse_sql(<<"*/", rest::binary>>, {:block_comment, 1}, current, statements),
    do: parse_sql(rest, :normal, ["*/" | current], statements)

  defp parse_sql(<<"*/", rest::binary>>, {:block_comment, depth}, current, statements),
    do: parse_sql(rest, {:block_comment, depth - 1}, ["*/" | current], statements)

  defp parse_sql(<<char::utf8, rest::binary>>, {:block_comment, depth}, current, statements),
    do: parse_sql(rest, {:block_comment, depth}, [<<char::utf8>> | current], statements)

  defp parse_sql(binary, {:dollar_quote, delimiter}, current, statements) do
    size = byte_size(delimiter)

    if byte_size(binary) >= size and binary_part(binary, 0, size) == delimiter do
      <<matched::binary-size(size), rest::binary>> = binary
      parse_sql(rest, :normal, [matched | current], statements)
    else
      <<char::utf8, rest::binary>> = binary
      parse_sql(rest, {:dollar_quote, delimiter}, [<<char::utf8>> | current], statements)
    end
  end

  defp maybe_append_statement(statements, current) do
    statement = current |> Enum.reverse() |> IO.iodata_to_binary()

    if String.trim(statement) == "" do
      Enum.reverse(statements)
    else
      Enum.reverse([statement | statements])
    end
  end

  defp dollar_quote_delimiter(binary) do
    case Regex.run(~r/^\$[a-zA-Z0-9_]*\$/, binary) do
      [delimiter] -> {:ok, delimiter}
      _ -> :error
    end
  end
end
