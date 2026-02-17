defmodule SelectoMix.ParameterizedJoinsValidatorTest do
  use ExUnit.Case, async: true

  alias SelectoMix.ParameterizedJoinsValidator

  describe "parse_field_reference/1" do
    test "parses dot notation references" do
      assert {:ok, parsed} = ParameterizedJoinsValidator.parse_field_reference("products.name")
      assert parsed.type == :dot_notation
      assert parsed.join == "products"
      assert parsed.field == "name"
      assert parsed.parameters == []
    end

    test "parses parameterized references with typed values" do
      assert {:ok, parsed} =
               ParameterizedJoinsValidator.parse_field_reference(
                 "products:'consumer electronics':true:12.5.price"
               )

      assert parsed.type == :parameterized
      assert parsed.join == "products"
      assert parsed.field == "price"
      assert parsed.parameters == ["consumer electronics", true, 12.5]
    end

    test "returns error for invalid reference syntax" do
      assert {:error, _reason} = ParameterizedJoinsValidator.parse_field_reference("products_only")
    end
  end

  describe "validate_domain_content/1" do
    test "validates a domain with a valid parameterized join" do
      content = """
      defmodule DemoDomain do
        def domain do
          %{
            joins: %{
              products: %{
                parameters: [
                  %{name: :category, type: :string, required: true},
                  %{name: :active, type: :boolean, default: true}
                ],
                fields: %{
                  name: %{type: :string},
                  price: %{type: :decimal}
                },
                join_condition: "products.category = :category AND products.active = :active"
              }
            }
          }
        end
      end
      """

      assert {:ok, result} = ParameterizedJoinsValidator.validate_domain_content(content)
      assert result.parameterized_joins == ["products"]
      assert result.validation_checks.syntax_valid
      assert result.validation_checks.parameters_valid
      assert result.validation_checks.field_types_valid
      assert result.validation_checks.join_conditions_valid
      assert result.validation_checks.issues == []
    end

    test "flags unknown join condition placeholders" do
      content = """
      defmodule DemoDomain do
        def domain do
          %{
            joins: %{
              products: %{
                parameters: [%{name: :category, type: :string}],
                fields: %{name: %{type: :string}},
                join_condition: "products.category = :missing"
              }
            }
          }
        end
      end
      """

      assert {:ok, result} = ParameterizedJoinsValidator.validate_domain_content(content)
      refute result.validation_checks.join_conditions_valid
      assert Enum.any?(result.validation_checks.issues, &String.contains?(&1, "unknown parameter"))
    end

    test "flags invalid parameter definitions" do
      content = """
      defmodule DemoDomain do
        def domain do
          %{
            joins: %{
              products: %{
                parameters: [
                  %{name: :category, type: :unsupported_type},
                  %{name: :category, type: :string}
                ],
                fields: %{name: %{type: :string}}
              }
            }
          }
        end
      end
      """

      assert {:ok, result} = ParameterizedJoinsValidator.validate_domain_content(content)
      refute result.validation_checks.parameters_valid
      assert Enum.any?(result.validation_checks.issues, &String.contains?(&1, "unsupported type"))
      assert Enum.any?(result.validation_checks.issues, &String.contains?(&1, "duplicate parameter"))
    end
  end
end

defmodule Mix.Tasks.Selecto.Validate.ParameterizedJoinsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "--test-references validates and prints parsed references" do
    output =
      capture_io(fn ->
        Mix.Task.reenable("selecto.validate.parameterized_joins")

        Mix.Tasks.Selecto.Validate.ParameterizedJoins.run([
          "--test-references",
          "products:electronics:true.name,invalid_reference"
        ])
      end)

    assert output =~ "Valid syntax"
    refute output =~ "not yet implemented"
  end

  test "validates a specific domain file" do
    temp_file =
      Path.join(
        System.tmp_dir!(),
        "selecto_mix_parameterized_domain_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(temp_file, """
    defmodule DemoDomain do
      def domain do
        %{
          joins: %{
            products: %{
              parameters: [%{name: :category, type: :string}],
              fields: %{name: %{type: :string}},
              join_condition: "products.category = :category"
            }
          }
        }
      end
    end
    """)

    output =
      capture_io(fn ->
        Mix.Task.reenable("selecto.validate.parameterized_joins")
        Mix.Tasks.Selecto.Validate.ParameterizedJoins.run([temp_file])
      end)

    assert output =~ "Found 1 parameterized join"
    assert output =~ "All validation checks passed"

    File.rm(temp_file)
  end
end
