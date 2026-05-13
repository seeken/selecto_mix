defmodule SelectoMix.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SelectoMix.ParameterizedJoinsValidator

  property "parse_field_reference parses generated parameterized references" do
    check all(
            join <- identifier_generator(),
            field <- identifier_generator(),
            params <- list_of(parameter_value_generator(), max_length: 4)
          ) do
      rendered_params = Enum.map(params, &render_param/1)

      reference =
        case rendered_params do
          [] -> "#{join}.#{field}"
          _ -> "#{join}:#{Enum.join(rendered_params, ":")}.#{field}"
        end

      assert {:ok, parsed} = ParameterizedJoinsValidator.parse_field_reference(reference)
      assert parsed.join == join
      assert parsed.field == field
      assert parsed.parameters == params
    end
  end

  property "parse_field_reference rejects references without field separator" do
    check all(join <- identifier_generator()) do
      assert {:error, _reason} = ParameterizedJoinsValidator.parse_field_reference(join)
    end
  end

  property "validate_domain_content handles arbitrary input without raising" do
    check all(content <- string(:printable, max_length: 500)) do
      result = ParameterizedJoinsValidator.validate_domain_content(content)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  defp identifier_generator do
    string(:alphanumeric, min_length: 1, max_length: 12)
    |> map(&String.downcase/1)
    |> map(fn value ->
      if Regex.match?(~r/^[a-z_]/, value) do
        value
      else
        "a_#{value}"
      end
    end)
  end

  defp parameter_value_generator do
    one_of([
      integer(-1000..1000),
      boolean(),
      constant(nil),
      string(:alphanumeric, min_length: 1, max_length: 12)
    ])
  end

  defp render_param(value) when is_integer(value), do: Integer.to_string(value)

  defp render_param(true), do: "true"
  defp render_param(false), do: "false"
  defp render_param(nil), do: "nil"
  defp render_param(value) when is_binary(value), do: "'#{value}'"
end
