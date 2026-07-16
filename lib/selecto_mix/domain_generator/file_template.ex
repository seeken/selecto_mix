defmodule SelectoMix.DomainGenerator.FileTemplate do
  @moduledoc false

  alias SelectoMix.DomainGenerator.MapBuilder

  @doc """
  Renders the full generated domain module source for `schema_module`/`config`.
  """
  def render(schema_module, config, opts \\ []) do
    module_name = get_domain_module_name(schema_module, config, opts)
    overlay_module_name = SelectoMix.OverlayGenerator.overlay_module_name(module_name)
    saved_views_use = generate_saved_views_use(opts)
    kind = source_kind(schema_module, config)
    source_label = source_label(schema_module, config)
    generation_description = generation_description(kind)
    usage_examples = usage_examples(kind, schema_module, module_name)
    regeneration_command = regeneration_command(kind, schema_module, config)

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      Selecto domain configuration for #{source_label}.

      This file was automatically generated from #{generation_description}.

      ## Customization with Overlay Files

      This domain uses an overlay configuration system for customization.
      Instead of editing this file directly, customize the domain by editing:

          lib/*/selecto_domains/overlays/*_overlay.ex

      The overlay file allows you to:
      - Customize column display properties (labels, formats, aggregations)
      - Add redaction to sensitive fields
      - Define custom filters
      - Define write contracts, actions, and capabilities
      - Add domain-specific validations (future)

      Overlay customizations are preserved when you regenerate this file.

      ## Usage

      #{usage_examples}

      ## Parameterized Joins
      
      This domain supports parameterized joins that accept runtime parameters:
      
      ```elixir
      joins: %{
        products: %{
          type: :left,
          name: "Products",
          parameters: [
            %{name: :category, type: :string, required: true},
            %{name: :active, type: :boolean, required: false, default: true}
          ],
          fields: %{
            name: %{type: :string},
            price: %{type: :decimal}
          }
        }
      }
      ```
      
      Use dot notation to reference parameterized fields:
      - `products:electronics.name` - Products in electronics category
      - `products:electronics:true.price` - Active products in electronics
      
      ## Regeneration
      
      To regenerate this file after schema changes:
      
          #{regeneration_command}
          
      Additional options:
      
          # Force regenerate the generated base file
          #{regeneration_command} --force
          
          # Preview changes without writing files
          #{regeneration_command} --dry-run
          
          # Include associations as joins
          #{regeneration_command} --include-associations
          
          # Generate with LiveView files
          #{regeneration_command} --live
          
          # Generate with saved views support
          #{regeneration_command} --live --saved-views
          
          # Expand specific associated schemas with full columns/associations
          #{regeneration_command} --expand-schemas categories,tags
          
      Keep app-specific customizations in the overlay module so regeneration can
      replace this generated base file intentionally.
      \"\"\"
    #{saved_views_use}
      @doc \"\"\"
      Returns the Selecto domain configuration for #{source_label}.

      This merges the base domain configuration with any overlay customizations.
      \"\"\"
      def domain do
        base_domain()
        |> Selecto.Config.Overlay.merge(overlay())
      end

      @doc \"\"\"
      Returns the base domain configuration (without overlay customizations).
      \"\"\"
      def base_domain do
        #{MapBuilder.generate_domain_map(config)}
      end

      @doc \"\"\"
      Returns the overlay configuration if available.

      The overlay file is located at:
      lib/*/selecto_domains/overlays/*_overlay.ex
      \"\"\"
      def overlay do
        if Code.ensure_loaded?(#{overlay_module_name}) do
          #{overlay_module_name}.overlay()
        else
          %{}
        end
      end

      #{generate_helper_functions(schema_module, config)}
    end
    """
  end

  def get_domain_module_name(schema_module, config, opts) do
    base_name =
      config[:metadata][:module_name] ||
        fallback_module_name(schema_module)

    _context_name = config[:metadata][:context_name] || "Domains"

    # Generate appropriate module name - use schema module as source of truth
    # KEY FIX: Use schema module
    app_name =
      opts[:app_name] ||
        Application.get_env(:selecto_mix, :app_name) ||
        infer_app_name_from_schema(schema_module) ||
        "MyApp"

    "#{app_name}.SelectoDomains.#{base_name}Domain"
  end

  defp generate_helper_functions(schema_module, config) do
    suggested_queries = generate_suggested_queries(config)
    kind = source_kind(schema_module, config)
    source_helpers = source_specific_helper_functions(kind, schema_module, config)

    [
      "@doc \"Create a new Selecto instance configured with this domain.\"",
      "def new(connection, opts \\\\ []) do",
      "  # Enable validation by default in development and test environments",
      "  validate = Keyword.get(opts, :validate, Mix.env() in [:dev, :test])",
      "  opts = Keyword.put(opts, :validate, validate)",
      "  ",
      "  Selecto.configure(domain(), connection, opts)",
      "end",
      "",
      "@doc \"Validate the domain configuration (Selecto 0.3.0+).\"",
      "def validate_domain! do",
      "  case Selecto.DomainValidator.validate_domain(domain()) do",
      "    :ok -> ",
      "      :ok",
      "    {:error, errors} ->",
      "      raise Selecto.DomainValidator.ValidationError, errors: errors",
      "  end",
      "end",
      "",
      "@doc \"Check if the domain configuration is valid.\"",
      "def valid_domain? do",
      "  case Selecto.DomainValidator.validate_domain(domain()) do",
      "    :ok -> true",
      "    {:error, _} -> false",
      "  end",
      "end",
      "",
      source_helpers,
      "@doc \"Get available fields (derived from columns to avoid duplication).\"",
      "def available_fields do",
      "  domain().source.columns |> Map.keys()",
      "end",
      "",
      "@doc \"Common query: get all records with default selection.\"",
      "def all(repo, opts \\\\ []) do",
      "  new(repo, opts)",
      "  |> Selecto.select(domain().default_selected)",
      "  |> Selecto.execute()",
      "end",
      "",
      "@doc \"Common query: find by primary key.\"",
      "def find(repo, id, opts \\\\ []) do",
      "  primary_key = domain().source.primary_key",
      "  ",
      "  new(repo, opts)",
      "  |> Selecto.select(domain().default_selected)",
      "  |> Selecto.filter({to_string(primary_key), id})",
      "  |> Selecto.execute_one()",
      "end"
    ]
    |> List.flatten()
    |> Enum.join("\n    ")
    |> Kernel.<>("#{suggested_queries}")
  end

  defp generate_suggested_queries(config) do
    # Generate some suggested query functions based on the schema
    filters = config[:suggested_defaults][:default_filters] || %{}

    filter_queries =
      filters
      |> MapBuilder.sorted_pairs()
      # Limit to avoid too many generated functions
      |> Enum.take(2)
      |> Enum.map(fn {filter_name, _filter_config} ->
        function_name = filter_name |> String.replace(" ", "_") |> String.downcase()

        [
          "",
          "@doc \"Common query: filter by #{filter_name}.\"",
          "def by_#{function_name}(repo, value, opts \\\\ []) do",
          "  new(repo, opts)",
          "  |> Selecto.select(domain().default_selected)",
          "  |> Selecto.filter({\"#{filter_name}\", value})",
          "  |> Selecto.execute()",
          "end"
        ]
        |> Enum.join("\n    ")
      end)
      |> Enum.join("")

    filter_queries
  end

  defp source_specific_helper_functions(:ecto, schema_module, _config) do
    [
      "@doc \"Create a Selecto instance using Ecto integration.\"",
      "def from_ecto(repo, opts \\\\ []) do",
      "  Selecto.from_ecto(repo, #{inspect(schema_module)}, opts)",
      "end",
      "",
      "@doc \"Get the schema module this domain represents.\"",
      "def schema_module, do: #{inspect(schema_module)}",
      ""
    ]
  end

  defp source_specific_helper_functions(:db, _schema_module, config) do
    source_table =
      config[:table_name] ||
        raise(ArgumentError, "domain config is missing :table_name")

    adapter = inspect(config[:adapter] || get_in(config, [:metadata, :adapter]))

    [
      "@doc \"Get the source table this domain represents.\"",
      "def source_table, do: #{inspect(source_table)}",
      "",
      "@doc \"Get the adapter used to introspect this domain.\"",
      "def adapter_module, do: #{adapter}",
      ""
    ]
  end

  defp source_kind(source, config) do
    cond do
      config[:source_type] == :db -> :db
      match?({:db, _, _, _}, source) -> :db
      match?({:db, _, _, _, _}, source) -> :db
      match?({:postgrex, _, _}, source) -> :db
      match?({:postgrex, _, _, _}, source) -> :db
      is_binary(source) -> :db
      true -> :ecto
    end
  end

  defp source_label(source, config) do
    case source_kind(source, config) do
      :db -> inspect(config[:table_name] || source)
      :ecto -> inspect(source)
    end
  end

  defp generation_description(:db), do: "database introspection"
  defp generation_description(:ecto), do: "the Ecto schema"

  defp usage_examples(:db, _source, module_name) do
    """
          # Basic usage
          selecto = Selecto.configure(#{module_name}.domain(), MyApp.Database)

          # Execute queries
          {:ok, {rows, columns, aliases}} = Selecto.execute(selecto)
    """
  end

  defp usage_examples(:ecto, source, module_name) do
    """
          # Basic usage
          selecto = Selecto.configure(#{module_name}.domain(), MyApp.Repo)

          # With Ecto integration
          selecto = Selecto.from_ecto(MyApp.Repo, #{inspect(source)})

          # Execute queries
          {:ok, {rows, columns, aliases}} = Selecto.execute(selecto)
    """
  end

  defp regeneration_command(:db, _source, config) do
    table_name = config[:table_name] || "table_name"
    adapter_name = adapter_cli_name(config[:adapter])
    "mix selecto.gen.domain --adapter #{adapter_name} --table #{table_name}"
  end

  defp regeneration_command(:ecto, source, _config) do
    "mix selecto.gen.domain #{inspect(source)}"
  end

  def generated_from_label(config) do
    cond do
      config[:source_type] == :db ->
        relation_label(config[:source_kind], config[:table_name])

      config[:schema_module] ->
        inspect(config[:schema_module])

      config[:table_name] ->
        "table #{config[:table_name]}"

      true ->
        "unknown source"
    end
  end

  defp relation_label(:view, table_name), do: "view #{table_name}"
  defp relation_label(:materialized_view, table_name), do: "materialized view #{table_name}"
  defp relation_label(_, table_name), do: "table #{table_name}"

  defp fallback_module_name(schema_module) when is_atom(schema_module) do
    schema_module |> Module.split() |> List.last()
  end

  defp fallback_module_name(schema_module) when is_binary(schema_module) do
    schema_module
    |> SelectoMix.Inflect.singularize()
    |> Macro.camelize()
  end

  defp fallback_module_name({:db, _adapter, _conn, table_name}) do
    fallback_module_name(table_name)
  end

  defp fallback_module_name({:db, _adapter, _conn, table_name, _opts}) do
    fallback_module_name(table_name)
  end

  defp fallback_module_name(other), do: other |> to_string() |> Macro.camelize()

  defp adapter_cli_name(nil), do: "postgresql"

  defp adapter_cli_name(adapter) when is_atom(adapter) do
    cond do
      Code.ensure_loaded?(adapter) and function_exported?(adapter, :name, 0) ->
        adapter.name() |> to_string()

      true ->
        adapter
        |> Module.split()
        |> Enum.at(-2, "PostgreSQL")
        |> String.replace_prefix("SelectoDB", "")
        |> normalize_adapter_cli_name()
    end
  end

  defp normalize_adapter_cli_name("PostgreSQL"), do: "postgresql"
  defp normalize_adapter_cli_name("MSSQL"), do: "mssql"
  defp normalize_adapter_cli_name(name), do: Macro.underscore(name)

  # New helper functions for advanced Selecto features

  defp generate_saved_views_use(opts) do
    if opts[:saved_views] do
      app_name = opts[:app_name] || infer_app_name_from_schema(opts[:schema_module])
      saved_view_context = "#{app_name}.SavedViewContext"
      "\n      use #{saved_view_context}\n"
    else
      ""
    end
  end

  defp infer_app_name_from_schema(schema_module) when is_atom(schema_module) do
    schema_module
    |> Module.split()
    |> List.first()
  end

  defp infer_app_name_from_schema({:db, _adapter, _conn, _table_name}), do: "MyApp"
  defp infer_app_name_from_schema({:db, _adapter, _conn, _table_name, _opts}), do: "MyApp"

  defp infer_app_name_from_schema(_), do: "MyApp"
end
