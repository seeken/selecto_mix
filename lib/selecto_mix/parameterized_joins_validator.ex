defmodule SelectoMix.ParameterizedJoinsValidator do
  @moduledoc """
  Validation and parsing helpers for parameterized Selecto joins.
  """

  @allowed_parameter_types [
    :string,
    :integer,
    :float,
    :decimal,
    :boolean,
    :date,
    :datetime,
    :utc_datetime,
    :naive_datetime
  ]

  @allowed_field_types [
    :string,
    :integer,
    :float,
    :decimal,
    :boolean,
    :date,
    :datetime,
    :utc_datetime,
    :naive_datetime,
    :json,
    :jsonb,
    :array
  ]

  @doc """
  Parse a parameterized (or plain) dot-notation field reference.

  Examples:
  - `products.name`
  - `products:electronics:true.name`
  - `products:'consumer electronics'.name`
  """
  def parse_field_reference(reference) when is_binary(reference) do
    with {:ok, {join_segment, field}} <- split_reference(reference),
         {:ok, {join, parameters}} <- parse_join_segment(join_segment) do
      type = if parameters == [], do: :dot_notation, else: :parameterized

      {:ok,
       %{
         type: type,
         join: join,
         field: field,
         parameters: parameters
       }}
    end
  end

  @doc """
  Validate a domain file's content and return join validation details.
  """
  def validate_domain_content(content) when is_binary(content) do
    with {:ok, joins_map} <- extract_joins_from_content(content) do
      {:ok, validate_joins_config(joins_map)}
    end
  end

  @doc """
  Validate a literal joins map.
  """
  def validate_joins_config(joins_map) when is_map(joins_map) do
    {parameterized_joins, traversal_issues} = collect_parameterized_joins(joins_map)

    validation_issues =
      parameterized_joins
      |> Enum.flat_map(&validate_parameterized_join/1)
      |> Kernel.++(traversal_issues)

    %{
      parameterized_joins: Enum.map(parameterized_joins, & &1.path),
      parameterized_join_details: parameterized_joins,
      validation_checks: %{
        syntax_valid: no_issues_for?(validation_issues, :syntax_valid),
        parameters_valid: no_issues_for?(validation_issues, :parameters_valid),
        field_types_valid: no_issues_for?(validation_issues, :field_types_valid),
        join_conditions_valid: no_issues_for?(validation_issues, :join_conditions_valid),
        issues: Enum.map(validation_issues, & &1.message)
      }
    }
  end

  @doc """
  Extract a literal joins map from domain file content.
  """
  def extract_joins_from_content(content) when is_binary(content) do
    with {:ok, ast} <- Code.string_to_quoted(content),
         {:ok, joins_ast} <- find_joins_ast(ast),
         {:ok, joins_map} <- ast_to_term(joins_ast),
         true <- is_map(joins_map) do
      {:ok, joins_map}
    else
      _ ->
        extract_joins_from_regex_fallback(content)
    end
  end

  defp extract_joins_from_regex_fallback(content) do
    case Regex.run(~r/joins:\s*(%\{.*\})/sU, content, capture: :all_but_first) do
      [joins_src] ->
        with {:ok, joins_ast} <- Code.string_to_quoted(joins_src),
             {:ok, joins_map} <- ast_to_term(joins_ast),
             true <- is_map(joins_map) do
          {:ok, joins_map}
        else
          _ -> {:error, :joins_parse_failed}
        end

      _ ->
        {:ok, %{}}
    end
  end

  defp find_joins_ast(ast) do
    {_walked, found_joins} =
      Macro.prewalk(ast, nil, fn
        {:%{}, _meta, pairs} = node, nil ->
          case find_joins_pair(pairs) do
            nil -> {node, nil}
            {_key, joins_ast} -> {node, joins_ast}
          end

        node, acc ->
          {node, acc}
      end)

    case found_joins do
      nil -> {:error, :joins_not_found}
      joins_ast -> {:ok, joins_ast}
    end
  end

  defp find_joins_pair(pairs) when is_list(pairs) do
    Enum.find(pairs, fn
      {key, _value} -> map_key(key) == :joins
      _ -> false
    end)
  end

  defp map_key(key) when is_atom(key), do: key
  defp map_key(_), do: nil

  defp ast_to_term(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_atom(value) or
              is_nil(value) do
    {:ok, value}
  end

  defp ast_to_term({:%{}, _meta, pairs}) when is_list(pairs) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn
      {k_ast, v_ast}, {:ok, acc} ->
        with {:ok, key} <- ast_to_term(k_ast),
             {:ok, value} <- ast_to_term(v_ast) do
          {:cont, {:ok, Map.put(acc, key, value)}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _, _ ->
        {:halt, {:error, :non_literal_map}}
    end)
  end

  defp ast_to_term(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn item_ast, {:ok, acc} ->
      case ast_to_term(item_ast) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ast_to_term({:{}, _meta, tuple_items}) when is_list(tuple_items) do
    case ast_to_term(tuple_items) do
      {:ok, items} -> {:ok, List.to_tuple(items)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ast_to_term(_), do: {:error, :non_literal_value}

  defp collect_parameterized_joins(joins_map) do
    do_collect_parameterized_joins(joins_map, [])
  end

  defp do_collect_parameterized_joins(joins_map, path) when is_map(joins_map) do
    Enum.reduce(joins_map, {[], []}, fn {join_name, join_config}, {joins_acc, issues_acc} ->
      join_name_str = join_name_to_string(join_name)
      current_path = path ++ [join_name_str]
      current_path_str = Enum.join(current_path, ".")

      case join_config do
        config when is_map(config) ->
          parameterized_entry =
            if Map.has_key?(config, :parameters) do
              [
                %{
                  name: join_name,
                  path: current_path_str,
                  parameters: Map.get(config, :parameters),
                  fields: Map.get(config, :fields, %{}),
                  join_condition: Map.get(config, :join_condition)
                }
              ]
            else
              []
            end

          nested_joins = Map.get(config, :joins, %{})

          {nested_parameterized, nested_issues} =
            case nested_joins do
              %{} = nested_map ->
                do_collect_parameterized_joins(nested_map, current_path)

              _other ->
                {[],
                 [
                   issue(
                     :syntax_valid,
                     "Join '#{current_path_str}' has invalid nested joins configuration (expected map)"
                   )
                 ]}
            end

          {parameterized_entry ++ nested_parameterized ++ joins_acc, nested_issues ++ issues_acc}

        _ ->
          {joins_acc,
           [issue(:syntax_valid, "Join '#{current_path_str}' configuration is not a map") | issues_acc]}
      end
    end)
    |> then(fn {joins, issues} -> {Enum.reverse(joins), Enum.reverse(issues)} end)
  end

  defp validate_parameterized_join(join_detail) do
    []
    |> validate_parameters(join_detail)
    |> validate_fields(join_detail)
    |> validate_join_condition(join_detail)
  end

  defp validate_parameters(issues, %{path: path, parameters: parameters}) when is_list(parameters) do
    name_values =
      Enum.map(parameters, fn
        %{} = param -> Map.get(param, :name)
        _ -> nil
      end)

    issues =
      Enum.reduce(Enum.with_index(parameters), issues, fn {param, index}, acc ->
        validate_parameter_entry(acc, path, param, index)
      end)

    duplicate_names =
      name_values
      |> Enum.reject(&is_nil/1)
      |> Enum.group_by(& &1)
      |> Enum.filter(fn {_name, entries} -> length(entries) > 1 end)
      |> Enum.map(fn {name, _entries} -> name end)

    Enum.reduce(duplicate_names, issues, fn dup_name, acc ->
      [issue(:parameters_valid, "Join '#{path}' defines duplicate parameter '#{dup_name}'") | acc]
    end)
  end

  defp validate_parameters(issues, %{path: path}) do
    [issue(:parameters_valid, "Join '#{path}' has invalid parameters (expected list)") | issues]
  end

  defp validate_parameter_entry(issues, path, %{} = param, index) do
    name = Map.get(param, :name)
    type = Map.get(param, :type)
    required = Map.get(param, :required, false)

    issues =
      if is_atom(name) do
        issues
      else
        [issue(:parameters_valid, "Join '#{path}' parameter #{index + 1} is missing an atom :name") | issues]
      end

    issues =
      if is_atom(type) and type in @allowed_parameter_types do
        issues
      else
        [issue(:parameters_valid, "Join '#{path}' parameter '#{inspect(name)}' has unsupported type #{inspect(type)}") | issues]
      end

    if is_boolean(required) do
      issues
    else
      [issue(:parameters_valid, "Join '#{path}' parameter '#{inspect(name)}' has non-boolean :required") | issues]
    end
  end

  defp validate_parameter_entry(issues, path, _param, index) do
    [issue(:parameters_valid, "Join '#{path}' parameter #{index + 1} is not a map") | issues]
  end

  defp validate_fields(issues, %{path: path, fields: fields}) when is_map(fields) do
    if map_size(fields) == 0 do
      [issue(:field_types_valid, "Join '#{path}' should define at least one field in :fields") | issues]
    else
      Enum.reduce(fields, issues, fn {field_name, field_config}, acc ->
        validate_field_entry(acc, path, field_name, field_config)
      end)
    end
  end

  defp validate_fields(issues, %{path: path}) do
    [issue(:field_types_valid, "Join '#{path}' has invalid :fields (expected map)") | issues]
  end

  defp validate_field_entry(issues, path, field_name, %{} = field_config) do
    case Map.get(field_config, :type) do
      type when is_atom(type) and type in @allowed_field_types ->
        issues

      type ->
        [issue(:field_types_valid, "Join '#{path}' field '#{inspect(field_name)}' has unsupported type #{inspect(type)}") | issues]
    end
  end

  defp validate_field_entry(issues, path, field_name, _field_config) do
    [issue(:field_types_valid, "Join '#{path}' field '#{inspect(field_name)}' config is not a map") | issues]
  end

  defp validate_join_condition(issues, %{join_condition: nil}), do: issues

  defp validate_join_condition(issues, %{path: path, join_condition: condition, parameters: parameters})
       when is_binary(condition) and is_list(parameters) do
    param_names = Enum.map(parameters, &Map.get(&1, :name))

    placeholders =
      Regex.scan(~r/:([a-zA-Z_][a-zA-Z0-9_]*)/, condition)
      |> Enum.map(fn [_full, placeholder] -> String.to_atom(placeholder) end)
      |> Enum.uniq()

    Enum.reduce(placeholders, issues, fn placeholder, acc ->
      if placeholder in param_names do
        acc
      else
        [issue(:join_conditions_valid, "Join '#{path}' join_condition references unknown parameter :#{placeholder}") | acc]
      end
    end)
  end

  defp validate_join_condition(issues, %{path: path}) do
    [issue(:join_conditions_valid, "Join '#{path}' has invalid :join_condition (expected string)") | issues]
  end

  defp split_reference(reference) do
    case split_last_unquoted(reference, ".") do
      {join_segment, field} when join_segment != "" and field != "" ->
        if valid_identifier?(field) do
          {:ok, {join_segment, field}}
        else
          {:error, "Invalid field identifier '#{field}'"}
        end

      _ ->
        {:error, "Expected format join.field or join:param1:param2.field"}
    end
  end

  defp parse_join_segment(join_segment) do
    case split_unquoted(join_segment, ":") do
      [join] ->
        if valid_identifier?(join), do: {:ok, {join, []}}, else: {:error, "Invalid join identifier '#{join}'"}

      [join | params] ->
        with true <- valid_identifier?(join) or {:error, "Invalid join identifier '#{join}'"},
             {:ok, parsed_params} <- parse_parameter_values(params) do
          {:ok, {join, parsed_params}}
        end
    end
  end

  defp parse_parameter_values(params) do
    Enum.reduce_while(params, {:ok, []}, fn raw_param, {:ok, acc} ->
      case parse_parameter_value(raw_param) do
        {:ok, parsed} -> {:cont, {:ok, acc ++ [parsed]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_parameter_value(raw_param) do
    param = String.trim(raw_param)

    cond do
      param == "" ->
        {:error, "Empty parameter value"}

      quoted_string?(param) ->
        {:ok, String.slice(param, 1, String.length(param) - 2)}

      param == "true" ->
        {:ok, true}

      param == "false" ->
        {:ok, false}

      param in ["nil", "null"] ->
        {:ok, nil}

      Regex.match?(~r/^-?\d+$/, param) ->
        {int_value, ""} = Integer.parse(param)
        {:ok, int_value}

      Regex.match?(~r/^-?\d+\.\d+$/, param) ->
        {float_value, ""} = Float.parse(param)
        {:ok, float_value}

      true ->
        {:ok, param}
    end
  end

  defp split_unquoted(value, separator) when is_binary(value) and is_binary(separator) do
    separator_char = String.to_charlist(separator) |> hd()
    chars = String.to_charlist(value)
    do_split_unquoted(chars, separator_char, nil, [], [], [])
  end

  defp split_last_unquoted(value, separator) when is_binary(value) and is_binary(separator) do
    separator_char = String.to_charlist(separator) |> hd()
    chars = String.to_charlist(value)

    {last_index, _quote_state, _index} =
      Enum.reduce(chars, {nil, nil, 0}, fn char, {last_seen, quote_state, index} ->
        cond do
          quote_state == nil and char in [?', ?"] ->
            {last_seen, char, index + 1}

          quote_state != nil and char == quote_state ->
            {last_seen, nil, index + 1}

          quote_state == nil and char == separator_char ->
            {index, quote_state, index + 1}

          true ->
            {last_seen, quote_state, index + 1}
        end
      end)

    case last_index do
      nil ->
        nil

      index ->
        left = String.slice(value, 0, index) |> String.trim()
        right = String.slice(value, index + 1, String.length(value) - index - 1) |> String.trim()
        {left, right}
    end
  end

  defp do_split_unquoted([], _separator, _quote, current, segments, _buffer) do
    segment = current |> Enum.reverse() |> to_string() |> String.trim()
    Enum.reverse([segment | segments])
  end

  defp do_split_unquoted([char | rest], separator, nil, current, segments, buffer)
       when char in [?', ?"] do
    do_split_unquoted(rest, separator, char, [char | current], segments, [char | buffer])
  end

  defp do_split_unquoted([char | rest], separator, quote, current, segments, buffer)
       when char == quote do
    do_split_unquoted(rest, separator, nil, [char | current], segments, [char | buffer])
  end

  defp do_split_unquoted([char | rest], separator, nil, current, segments, _buffer)
       when char == separator do
    segment = current |> Enum.reverse() |> to_string() |> String.trim()
    do_split_unquoted(rest, separator, nil, [], [segment | segments], [])
  end

  defp do_split_unquoted([char | rest], separator, quote, current, segments, buffer) do
    do_split_unquoted(rest, separator, quote, [char | current], segments, [char | buffer])
  end

  defp quoted_string?(param) do
    (String.starts_with?(param, "'") and String.ends_with?(param, "'")) or
      (String.starts_with?(param, "\"") and String.ends_with?(param, "\""))
  end

  defp valid_identifier?(identifier) do
    String.match?(identifier, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)
  end

  defp join_name_to_string(name) when is_atom(name), do: Atom.to_string(name)
  defp join_name_to_string(name) when is_binary(name), do: name
  defp join_name_to_string(name), do: inspect(name)

  defp no_issues_for?(issues, category) do
    not Enum.any?(issues, &(&1.category == category))
  end

  defp issue(category, message), do: %{category: category, message: message}
end
