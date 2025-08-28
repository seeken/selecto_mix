defmodule Mix.Tasks.Selecto.Gen.ParameterizedJoin do
  @shortdoc "Generate parameterized join configuration templates"
  @moduledoc """
  Generate parameterized join configuration templates for Selecto domains.

  This task helps create parameterized joins that accept runtime parameters,
  enabling dynamic query behavior based on user input or application state.

  ## Examples

      # Generate a basic parameterized join template
      mix selecto.gen.parameterized_join products category:string active:boolean

      # Generate with field specifications
      mix selecto.gen.parameterized_join products category:string,required active:boolean,default=true --fields name:string,price:decimal

      # Generate with join condition template
      mix selecto.gen.parameterized_join discounts category:string --condition "discounts.category = :category AND discounts.active = :active"

  ## Syntax

  Parameter format: `name:type[,options]`
  
  Types: string, integer, float, boolean, date, datetime
  Options: required, default=value, description="text"

  ## Options

    * `--fields` - Comma-separated list of fields available from this join (field:type format)
    * `--condition` - SQL join condition template with parameter placeholders
    * `--source-table` - Override the source table name (defaults to join name)
    * `--output` - Output file path (defaults to stdout)

  ## Generated Configuration

  Outputs a parameterized join configuration that you can copy into your domain:

      products: %{
        name: "Products",
        type: :left,
        source_table: "products",
        parameters: [
          %{name: :category, type: :string, required: true},
          %{name: :active, type: :boolean, required: false, default: true}
        ],
        fields: %{
          name: %{type: :string},
          price: %{type: :decimal}
        },
        join_condition: "products.category = :category AND products.active = :active"
      }

  ## Usage in Queries

  Use dot notation to reference parameterized fields:

      # Basic parameterized field reference
      "products:electronics.name"

      # Multiple parameters
      "products:electronics:true.price"

      # String parameters with spaces (quoted)
      "products:'consumer electronics':true.price"
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, [join_name | parameters], _} = 
      OptionParser.parse(args, strict: [
        fields: :string,
        condition: :string,
        source_table: :string,
        output: :string
      ])

    if join_name == nil or parameters == [] do
      Mix.shell().error("""
      Usage: mix selecto.gen.parameterized_join JOIN_NAME PARAM1:TYPE PARAM2:TYPE [options]

      Examples:
        mix selecto.gen.parameterized_join products category:string active:boolean
        mix selecto.gen.parameterized_join discounts type:string amount:float,required --fields discount_percent:float
      """)
      exit({:shutdown, 1})
    end

    case generate_parameterized_join_config(join_name, parameters, opts) do
      {:ok, config_text} ->
        case opts[:output] do
          nil -> 
            Mix.shell().info("Generated parameterized join configuration:")
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
    parameters = 
      Enum.map(parameter_specs, fn spec ->
        case parse_parameter_spec(spec) do
          {:ok, param} -> param
          {:error, error} -> throw({:error, "Invalid parameter spec '#{spec}': #{error}"})
        end
      end)
    
    {:ok, parameters}
  catch
    {:error, error} -> {:error, error}
  end

  defp parse_parameter_spec(spec) do
    case String.split(spec, ":") do
      [name, type_and_opts] ->
        {type, opts} = parse_type_and_options(type_and_opts)
        
        param = %{name: String.to_atom(name), type: type}
        param = if opts[:required], do: Map.put(param, :required, true), else: param
        param = if opts[:default], do: Map.put(param, :default, opts[:default]), else: param
        param = if opts[:description], do: Map.put(param, :description, opts[:description]), else: param
        
        {:ok, param}
      
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
      "float" -> :float
      "decimal" -> :decimal
      "boolean" -> :boolean
      "bool" -> :boolean
      "date" -> :date
      "datetime" -> :datetime
      "utc_datetime" -> :utc_datetime
      _ -> :string  # Default fallback
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
        
        _ -> acc
      end
    end)
  end

  defp parse_default_value(value) do
    case value do
      "true" -> true
      "false" -> false
      "nil" -> nil
      "null" -> nil
      _ ->
        # Try to parse as integer or float, fallback to string
        case Integer.parse(value) do
          {int_val, ""} -> int_val
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
            field_name = String.to_atom(String.trim(name))
            field_type = parse_type(String.trim(type))
            Map.put(acc, field_name, %{type: field_type})
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
      source_table: opts[:source_table] || join_name,
      parameters: parameters,
      fields: fields
    }
    
    config = case opts[:condition] do
      nil -> config
      condition -> Map.put(config, :join_condition, condition)
    end
    
    {:ok, config}
  end

  defp format_join_config(join_name, config) do
    formatted_parameters = format_parameters_list(config.parameters)
    formatted_fields = format_fields_map(config.fields)
    
    base_config = """
    #{join_name}: %{
      name: "#{config.name}",
      type: #{inspect(config.type)},
      source_table: "#{config.source_table}",
      
      # Runtime parameters - these values will be provided when using the join
      parameters: #{formatted_parameters},
      
      # Available fields from this parameterized join
      fields: #{formatted_fields}
    """

    condition_config = case Map.get(config, :join_condition) do
      nil -> ""
      condition -> ",\n      \n      # Join condition template (use :parameter_name for substitution)\n      join_condition: \"#{condition}\""
    end

    usage_examples = generate_usage_examples(join_name, config.parameters)

    base_config <> condition_config <> "\n    }" <> usage_examples
  end

  defp format_parameters_list(parameters) do
    if Enum.empty?(parameters) do
      "[]"
    else
      formatted_params = 
        parameters
        |> Enum.map(fn param ->
          lines = ["        %{name: #{inspect(param.name)}, type: #{inspect(param.type)}"]
          
          lines = if Map.get(param, :required), do: lines ++ [", required: true"], else: lines
          lines = if Map.get(param, :default), do: lines ++ [", default: #{inspect(param.default)}"], else: lines
          lines = if Map.get(param, :description), do: lines ++ [", description: \"#{param.description}\""], else: lines
          
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
          "        #{inspect(field_name)} => %{type: #{inspect(field_config.type)}}"
        end)
        |> Enum.join(",\n")
      
      "%{\n#{formatted_fields}\n      }"
    end
  end

  defp generate_usage_examples(join_name, parameters) do
    if Enum.empty?(parameters) do
      ""
    else
      # Generate example parameter values
      example_values = 
        parameters
        |> Enum.map(fn param ->
          example_value = case param.type do
            :string -> "electronics"
            :integer -> "100"
            :float -> "25.5"
            :boolean -> "true"
            :date -> "2023-01-01"
            _ -> "value"
          end
          {param.name, example_value}
        end)
      
      # Generate dot notation examples
      param_signature = example_values |> Enum.map(fn {_, value} -> value end) |> Enum.join(":")
      
      examples = [
        "#{join_name}:#{param_signature}.field_name",
        "#{join_name}:#{param_signature}.another_field"
      ]
      
      "\n\n    # Usage Examples:\n" <>
      "    # \n" <>
      "    # Use dot notation with parameters to reference fields:\n" <>
      (examples |> Enum.map(fn ex -> "    #   \"#{ex}\"" end) |> Enum.join("\n")) <>
      "\n    #\n" <>
      "    # Parameter format: join:param1:param2:...param_n.field\n" <>
      "    # String parameters with special characters should be quoted:\n" <>
      "    #   \"#{join_name}:'consumer electronics':true.name\"\n"
    end
  end

  defp humanize_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end