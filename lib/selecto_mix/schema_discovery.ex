defmodule SelectoMix.SchemaDiscovery do
  @moduledoc """
  Schema/table discovery and CLI pattern parsing for `mix selecto.gen.domain`.

  Handles `--all`/wildcard Ecto schema discovery (with a real `use Ecto.Schema`
  AST check), `Foo.*` pattern expansion, exclude-pattern filtering, database
  relation discovery, and `--expand-schemas`/`--expand-tag`/`--expand-star`/
  `--expand-lookup`/`--expand-polymorphic` option parsing.
  """

  alias SelectoMix.ConnectionOpts

  def discover_all_relations(adapter, conn, db_schema, opts) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        []

      function_exported?(adapter, :list_relations, 2) ->
        case adapter.list_relations(conn,
               schema: db_schema,
               include_views: opts[:include_views] || false
             ) do
          {:ok, relations} ->
            relations
            |> Enum.reject(&(&1.name in ConnectionOpts.system_tables()))

          {:error, _reason} ->
            []
        end

      not function_exported?(adapter, :list_tables, 2) ->
        []

      true ->
        case adapter.list_tables(conn, schema: db_schema) do
          {:ok, tables} ->
            tables
            |> Enum.reject(&(&1 in ConnectionOpts.system_tables()))
            |> Enum.map(&%{name: &1, source_kind: :table})

          {:error, _reason} ->
            []
        end
    end
  end

  def discover_all_schemas(igniter) do
    # Use Igniter to find all Ecto schema modules in the project, checking
    # every candidate module's AST for a real `use Ecto.Schema`. A name-based
    # heuristic (e.g. requiring "Schema" or "Store" in the module name) would
    # incorrectly exclude ordinarily-named schemas like `MyApp.Post`, so the
    # real `module_uses_ecto_schema?/2` check below is the sole criterion.
    {_igniter, modules} =
      Igniter.Project.Module.find_all_matching_modules(igniter, fn module_name, _zipper ->
        module_uses_ecto_schema?(igniter, module_name)
      end)

    modules
  end

  # Checks whether `module_name` is defined in the project and its body uses
  # `Ecto.Schema` (via `use Ecto.Schema` or `use Ecto.Schema, ...`).
  defp module_uses_ecto_schema?(igniter, module_name) do
    case Igniter.Project.Module.find_module(igniter, module_name) do
      {:ok, {_igniter, _source, zipper}} -> zipper_uses_ecto_schema?(zipper)
      {:error, _igniter} -> false
    end
  end

  # Walks the module's AST (starting from either the module zipper or its
  # do-block zipper) looking for a `use Ecto.Schema` call.
  defp zipper_uses_ecto_schema?(zipper) do
    {_zipper, found?} =
      Sourceror.Zipper.traverse(zipper, false, fn z, found? ->
        cond do
          found? ->
            {z, found?}

          match?({:use, _, [{:__aliases__, _, [:Ecto, :Schema]} | _]}, z.node) ->
            {z, true}

          true ->
            {z, found?}
        end
      end)

    found?
  end

  def parse_schema_patterns(igniter, schemas_arg) do
    patterns =
      schemas_arg
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))

    expand_patterns(igniter, patterns)
  end

  # Expands `Foo.*`-style wildcard patterns into the set of discovered Ecto
  # schema modules whose name starts with the given prefix, and resolves
  # exact module names via `Module.concat/1`. Raises via `Mix.raise/1` on
  # syntactically invalid module names.
  defp expand_patterns(igniter, patterns) do
    {wildcards, exact} = Enum.split_with(patterns, &String.ends_with?(&1, ".*"))

    exact_modules = Enum.map(exact, &resolve_exact_module_name/1)

    wildcard_modules =
      case wildcards do
        [] ->
          []

        _ ->
          all_schemas = discover_all_schemas(igniter)

          prefixes =
            Enum.map(wildcards, fn pattern ->
              pattern
              |> String.trim_trailing(".*")
              |> then(&(&1 <> "."))
            end)

          Enum.filter(all_schemas, fn module ->
            module_string = to_string(module) |> String.trim_leading("Elixir.")
            Enum.any?(prefixes, &String.starts_with?(module_string, &1))
          end)
      end

    (exact_modules ++ wildcard_modules)
    |> Enum.uniq()
  end

  defp resolve_exact_module_name(pattern) do
    segments = String.split(pattern, ".")

    if Enum.all?(segments, &valid_module_segment?/1) do
      Module.concat(segments)
    else
      Mix.raise("Invalid schema module name: #{inspect(pattern)}")
    end
  end

  defp valid_module_segment?(segment) do
    segment != "" and Regex.match?(~r/^[A-Z][A-Za-z0-9_]*$/, segment)
  end

  def parse_exclude_patterns(exclude_arg) do
    exclude_arg
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  def parse_expand_schemas(expand_arg) when is_list(expand_arg) do
    # Already a list from :keep option - just return it
    expand_arg
    |> Enum.flat_map(fn item ->
      # Each item might still be comma-separated
      item
      |> String.split(",")
      |> Enum.map(&String.trim/1)
    end)
    |> Enum.filter(&(&1 != ""))
  end

  def parse_expand_schemas(expand_arg) when is_binary(expand_arg) do
    # Single string - split by comma
    expand_arg
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  def parse_expand_schemas(_), do: []

  @mode_types %{
    expand_tag: :tag,
    expand_star: :star,
    expand_lookup: :lookup,
    expand_polymorphic: :polymorphic
  }

  # Parse expand mode parameters like --expand-tag Tags:name --expand-star Category:category_name
  # Returns a map like: %{"Tags" => {:tag, "name"}, "Category" => {:star, "category_name"}}
  def parse_expand_modes(parsed_args) do
    Enum.reduce(Map.keys(@mode_types), %{}, fn mode, acc ->
      mode_type = Map.fetch!(@mode_types, mode)

      case Map.get(parsed_args, mode) do
        nil ->
          acc

        specs when is_list(specs) ->
          # :keep option returns a list of all occurrences
          Enum.reduce(specs, acc, fn spec, mode_acc ->
            parse_expand_mode_spec(spec, mode_type, mode_acc)
          end)

        spec when is_binary(spec) ->
          parse_expand_mode_spec(spec, mode_type, acc)

        _ ->
          acc
      end
    end)
  end

  defp parse_expand_mode_spec(spec, mode_type, acc) do
    cond do
      # Polymorphic format: field_name:type_field,id_field:Type1,Type2,Type3
      mode_type == :polymorphic ->
        case String.split(spec, ":") do
          [field_name, fields, types] ->
            case String.split(fields, ",") do
              [type_field, id_field] ->
                entity_types = String.split(types, ",") |> Enum.map(&String.trim/1)

                poly_config = %{
                  field_name: String.trim(field_name),
                  type_field: String.trim(type_field),
                  id_field: String.trim(id_field),
                  entity_types: entity_types
                }

                # Use field_name as the key
                Map.put(acc, String.trim(field_name), {:polymorphic, poly_config})

              _ ->
                acc
            end

          _ ->
            acc
        end

      # Standard format for tag/star/lookup: TableName:display_field
      true ->
        case String.split(spec, ":") do
          [table_name, display_field] ->
            # Store both singular and plural forms to match flexibly
            table_key = String.trim(table_name)
            Map.put(acc, table_key, {mode_type, String.trim(display_field)})

          _ ->
            # Invalid format, skip
            acc
        end
    end
  end

  def schema_matches_exclude?(schema, exclude_patterns) do
    schema_str = to_string(schema)

    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(schema_str, pattern)
    end)
  end

  def table_matches_exclude?(table, exclude_patterns) do
    table_name = table |> to_string() |> String.downcase()

    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(table_name, String.downcase(pattern))
    end)
  end
end
