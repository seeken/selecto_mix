defmodule Mix.Tasks.Selecto.Gen.ParameterizedJoin do
  @shortdoc "Generate existing-join parameterization fragments"
  @moduledoc """
  Generate existing-join parameterization fragments for Selecto domains.

  This task helps add runtime parameters to an existing Selecto join. The join
  name must already be present in the domain's `joins` map, usually because it
  was generated from an Ecto association.

  ## Examples

      # Generate a basic existing-join parameterization fragment
      mix selecto.gen.parameterized_join customer country:string,required

      # Generate with field specifications
      mix selecto.gen.parameterized_join customer country:string,required --fields company_name:string,country:string

      # Generate with join condition template
      mix selecto.gen.parameterized_join customer country:string --condition "customers.country = :country"

  ## Syntax

  Parameter format: `name:type[,options]`

  Types: string, integer, number, numeric, decimal, float, boolean, date, datetime
  Options: required, default=value, description="text"

  ## Options

    * `--fields` - Comma-separated list of fields available from this join (field:type format)
    * `--condition` - SQL join condition template with parameter placeholders
    * `--source-table` - Deprecated; existing joins already define their source
    * `--output` - Output file path (defaults to stdout)

  ## Generated Configuration

  Outputs a fragment that you copy into an existing join entry:

      # Add these keys to the existing :customer join.
      # Keep the generated join's name, type, source, and on keys.
      parameters: [
        %{name: :country, type: :string, required: true}
      ],
      filters: %{
        "country" => %{name: "Country", type: :string}
      },
      fields: %{
        company_name: %{type: :string},
        country: %{type: :string}
      }

  For runtime queries, call `Selecto.join_parameterize/4`:

      selecto
      |> Selecto.join_parameterize(:customer, "usa", country: "USA")
      |> Selecto.select(["customer:usa.company_name"])

  Do not add a brand-new top-level join only for parameterization. Selecto
  validates top-level joins against the parent schema's associations.

  ## Usage in Queries

  Use dot notation to reference parameterized fields:

      # Basic parameterized field reference
      "customer:USA.company_name"

      # Multiple parameters
      "customer:USA:true.company_name"

      # String parameters with spaces (quoted)
      "customer:'United States'.company_name"
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, positional} =
      SelectoMix.CLI.parse!(args,
        strict: [
          fields: :string,
          condition: :string,
          source_table: :string,
          output: :string
        ]
      )

    {join_name, parameters} =
      case positional do
        [name | params] -> {name, params}
        _ -> {nil, []}
      end

    if join_name == nil or parameters == [] do
      Mix.shell().error("""
      Usage: mix selecto.gen.parameterized_join JOIN_NAME PARAM1:TYPE PARAM2:TYPE [options]

      Examples:
        mix selecto.gen.parameterized_join customer country:string,required
        mix selecto.gen.parameterized_join customer country:string,required --fields company_name:string,country:string
      """)

      exit({:shutdown, 1})
    end

    case generate_parameterized_join_config(join_name, parameters, opts) do
      {:ok, config_text} ->
        case opts[:output] do
          nil ->
            Mix.shell().info("Generated existing-join parameterization fragment:")
            Mix.shell().info("")
            Mix.shell().info(config_text)

          output_file ->
            File.write!(output_file, config_text)
            Mix.shell().info("Parameterized join configuration written to #{output_file}")
        end

      {:error, error} ->
        Mix.shell().error("Error generating parameterized join: #{error}")
        exit({:shutdown, 1})
    end
  end

  # Private implementation

  defp generate_parameterized_join_config(join_name, parameter_specs, opts) do
    with {:ok, parameters} <- parse_parameters(parameter_specs),
         {:ok, fields} <- parse_fields(opts[:fields]),
         {:ok, config} <- build_join_config(join_name, parameters, fields, opts) do
      {:ok, format_join_config(join_name, config)}
    end
  end

  defp parse_parameters(parameter_specs) do
    parameter_specs
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, acc} ->
      case parse_parameter_spec(spec) do
        {:ok, param} ->
          {:cont, {:ok, [param | acc]}}

        {:error, error} ->
          {:halt, {:error, "Invalid parameter spec '#{spec}': #{error}"}}
      end
    end)
    |> case do
      {:ok, params} -> {:ok, Enum.reverse(params)}
      {:error, _reason} = error -> error
    end
  end

  defp parse_parameter_spec(spec) do
    case String.split(spec, ":") do
      [name, type_and_opts] ->
        {type, opts} = parse_type_and_options(type_and_opts)

        with {:ok, param_name} <- normalize_identifier(name) do
          param = %{name: param_name, type: type}
          param = if opts[:required], do: Map.put(param, :required, true), else: param

          param =
            if Map.has_key?(opts, :default),
              do: Map.put(param, :default, opts[:default]),
              else: param

          param =
            if opts[:description],
              do: Map.put(param, :description, opts[:description]),
              else: param

          {:ok, param}
        end

      _ ->
        {:error, "Expected format NAME:TYPE[,options]"}
    end
  end

  defp parse_type_and_options(type_and_opts) do
    case String.split(type_and_opts, ",", parts: 2) do
      [type] ->
        {parse_type(type), %{}}

      [type, opts_str] ->
        opts = parse_parameter_options(opts_str)
        {parse_type(type), opts}
    end
  end

  defp parse_type(type_str) do
    case String.downcase(String.trim(type_str)) do
      "string" -> :string
      "integer" -> :integer
      "int" -> :integer
      "number" -> :decimal
      "numeric" -> :decimal
      "float" -> :float
      "decimal" -> :decimal
      "boolean" -> :boolean
      "bool" -> :boolean
      "date" -> :date
      "datetime" -> :datetime
      "utc_datetime" -> :utc_datetime
      # Default fallback
      _ -> :string
    end
  end

  defp parse_parameter_options(opts_str) do
    opts_str
    |> String.split(",")
    |> Enum.reduce(%{}, fn opt, acc ->
      case String.trim(opt) do
        "required" ->
          Map.put(acc, :required, true)

        "default=" <> default_value ->
          parsed_value = parse_default_value(String.trim(default_value))
          Map.put(acc, :default, parsed_value)

        "description=" <> description ->
          cleaned_desc = description |> String.trim() |> String.trim("\"") |> String.trim("'")
          Map.put(acc, :description, cleaned_desc)

        _ ->
          acc
      end
    end)
  end

  defp parse_default_value(value) do
    case value do
      "true" ->
        true

      "false" ->
        false

      "nil" ->
        nil

      "null" ->
        nil

      _ ->
        # Try to parse as integer or float, fallback to string
        case Integer.parse(value) do
          {int_val, ""} ->
            int_val

          _ ->
            case Float.parse(value) do
              {float_val, ""} -> float_val
              _ -> String.trim(value, "\"'")
            end
        end
    end
  end

  defp parse_fields(nil), do: {:ok, %{}}
  defp parse_fields(""), do: {:ok, %{}}

  defp parse_fields(fields_str) do
    fields =
      fields_str
      |> String.split(",")
      |> Enum.reduce(%{}, fn field_spec, acc ->
        case String.split(String.trim(field_spec), ":") do
          [name, type] ->
            case normalize_identifier(name) do
              {:ok, field_name} ->
                field_type = parse_type(String.trim(type))
                Map.put(acc, field_name, %{type: field_type})

              {:error, _reason} ->
                acc
            end

          _ ->
            acc
        end
      end)

    {:ok, fields}
  end

  defp build_join_config(join_name, parameters, fields, opts) do
    config = %{
      name: humanize_name(join_name),
      type: :left,
      parameters: parameters,
      filters: build_filters(parameters),
      fields: fields
    }

    config =
      case opts[:condition] do
        nil -> config
        condition -> Map.put(config, :join_condition, condition)
      end

    {:ok, config}
  end

  defp format_join_config(join_name, config) do
    formatted_parameters = format_parameters_list(config.parameters)
    formatted_filters = format_filters_map(config.filters)
    formatted_fields = format_fields_map(config.fields)

    base_config = """
    # Existing join parameterization for :#{join_name}
    #
    # Copy the keys below into the existing :#{join_name} entry in your domain's
    # joins map. Keep that generated join's name, type, source, and on keys.

    # Static parameter metadata for validation and join:param.field references.
    parameters: #{formatted_parameters},

    # Runtime filters used by Selecto.join_parameterize/4.
    filters: #{formatted_filters},

    # Fields exposed by this parameterized join.
    fields: #{formatted_fields}
    """

    condition_config =
      case Map.get(config, :join_condition) do
        nil ->
          ""

        condition ->
          ",\n\n    # Optional join condition template for validators that inspect parameter placeholders.\n    join_condition: \"#{condition}\""
      end

    usage_examples =
      generate_usage_examples(join_name, config.parameters, Map.keys(config.fields))

    base_config <> condition_config <> usage_examples
  end

  defp build_filters(parameters) do
    Enum.into(parameters, %{}, fn param ->
      {to_string(param.name), %{name: humanize_name(param.name), type: param.type}}
    end)
  end

  defp format_parameters_list(parameters) do
    if Enum.empty?(parameters) do
      "[]"
    else
      formatted_params =
        parameters
        |> Enum.map(fn param ->
          lines = [
            "        %{name: #{format_atom_literal(param.name)}, type: #{inspect(param.type)}"
          ]

          lines = if Map.get(param, :required), do: lines ++ [", required: true"], else: lines

          lines =
            if Map.has_key?(param, :default),
              do: lines ++ [", default: #{inspect(param.default)}"],
              else: lines

          lines =
            if Map.get(param, :description),
              do: lines ++ [", description: \"#{param.description}\""],
              else: lines

          Enum.join(lines) <> "}"
        end)
        |> Enum.join(",\n")

      "[\n#{formatted_params}\n      ]"
    end
  end

  defp format_fields_map(fields) do
    if Enum.empty?(fields) do
      "%{}"
    else
      formatted_fields =
        fields
        |> Enum.map(fn {field_name, field_config} ->
          "        #{format_atom_literal(field_name)} => %{type: #{inspect(field_config.type)}}"
        end)
        |> Enum.join(",\n")

      "%{\n#{formatted_fields}\n      }"
    end
  end

  defp format_filters_map(filters) do
    if Enum.empty?(filters) do
      "%{}"
    else
      formatted_filters =
        filters
        |> Enum.map(fn {filter_name, filter_config} ->
          "        #{inspect(filter_name)} => #{inspect(filter_config, pretty: true, width: 80)}"
        end)
        |> Enum.join(",\n")

      "%{\n#{formatted_filters}\n      }"
    end
  end

  defp generate_usage_examples(join_name, parameters, fields) do
    if Enum.empty?(parameters) do
      ""
    else
      # Generate example parameter values
      example_values =
        parameters
        |> Enum.map(fn param ->
          {param.name, example_value(param)}
        end)

      # Generate dot notation examples
      param_signature = example_values |> Enum.map(fn {_, value} -> value end) |> Enum.join(":")
      example_fields = example_fields(fields)

      examples = [
        "#{join_name}:#{param_signature}.#{Enum.at(example_fields, 0)}",
        "#{join_name}:#{param_signature}.#{Enum.at(example_fields, 1)}"
      ]

      "\n\n    # Usage Examples:\n" <>
        "    #\n" <>
        "    # Runtime query usage:\n" <>
        "    #   selecto\n" <>
        "    #   |> Selecto.join_parameterize(:#{join_name}, \"#{List.first(example_values) |> elem(1)}\", #{runtime_options_example(example_values)})\n" <>
        "    #   |> Selecto.select([\"#{List.first(examples)}\"])\n" <>
        "    #\n" <>
        "    # Static field reference validation:\n" <>
        (examples |> Enum.map(fn ex -> "    #   \"#{ex}\"" end) |> Enum.join("\n")) <>
        "\n    #\n" <>
        "    # Parameter format: existing_join:param1:param2:...param_n.field\n" <>
        "    # String parameters with special characters should be quoted:\n" <>
        "    #   \"#{join_name}:'United States'.#{List.first(example_fields)}\"\n"
    end
  end

  defp example_fields([]), do: ["field_name", "another_field"]

  defp example_fields(fields) do
    field_names = Enum.map(fields, &to_string/1)

    case field_names do
      [single] -> [single, single]
      [first, second | _] -> [first, second]
    end
  end

  defp runtime_options_example(example_values) do
    example_values
    |> Enum.map(fn {name, value} -> "#{name}: #{inspect(value)}" end)
    |> Enum.join(", ")
  end

  defp example_value(%{name: name, type: :string}) do
    if String.contains?(to_string(name), "country"), do: "USA", else: "example"
  end

  defp example_value(%{type: :integer}), do: "100"
  defp example_value(%{type: :decimal}), do: "25.5"
  defp example_value(%{type: :float}), do: "25.5"
  defp example_value(%{type: :boolean}), do: "true"
  defp example_value(%{type: :date}), do: "2023-01-01"
  defp example_value(_param), do: "value"

  defp humanize_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp normalize_identifier(name) when is_binary(name) do
    trimmed = String.trim(name)

    if String.match?(trimmed, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/) do
      {:ok, trimmed}
    else
      {:error, "Invalid identifier #{inspect(name)}"}
    end
  end

  defp format_atom_literal(name) when is_binary(name), do: ":#{name}"
end
