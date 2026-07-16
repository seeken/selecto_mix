defmodule SelectoMix.DomainImport do
  @moduledoc """
  Builds import plans for normalized Selecto domain artifacts.

  Import starts with a checkable source preview. Writing is opt-in and guarded:
  the rendered module must parse, define the expected target module, expose
  `domain/0`, and contain no runtime placeholders.
  """

  alias SelectoMix.{ArtifactJSON, DomainExport}

  @format "selecto.domain_import_plan"
  @format_version 1

  @type import_error ::
          DomainExport.artifact_error()
          | {:source_preview_invalid, map()}
          | {:source_preview_not_write_ready, map()}
          | {:target_file_exists, Path.t()}
          | {:mkdir_failed, Path.t(), term()}
          | {:write_failed, Path.t(), term()}

  @known_sections [
    "source",
    "schemas",
    "joins",
    "filters",
    "functions",
    "query_members",
    "published_views",
    "detail_actions",
    "writes",
    "capabilities",
    "actions",
    "source_relationships",
    "choice_sources"
  ]

  @security_sensitive_sections %{
    "actions" => "business command definitions and execution surfaces",
    "capabilities" => "authorization capability catalog",
    "choice_sources" => "cross-domain choices and constraint policy",
    "detail_actions" => "user-visible detail actions",
    "source_relationships" => "cross-domain source bindings",
    "writes" =>
      "write operations, fields, relationships, scope, hooks, validations, constraints, and transitions"
  }

  @spec plan_file(Path.t(), keyword()) :: {:ok, map()} | {:error, DomainExport.artifact_error()}
  def plan_file(path, opts \\ []) do
    with {:ok, check} <- DomainExport.check_file(path, opts) do
      {:ok, plan(check, opts)}
    end
  end

  @spec write_file(Path.t(), keyword()) :: {:ok, map()} | {:error, import_error()}
  def write_file(path, opts \\ []) do
    with {:ok, plan} <- plan_file(path, opts),
         {:ok, write} <- write_plan(plan, opts) do
      {:ok, write_mode_plan(plan, write)}
    end
  end

  @spec write_plan(map(), keyword()) :: {:ok, map()} | {:error, import_error()}
  def write_plan(plan, opts \\ []) do
    source_preview = Map.fetch!(plan, "source_preview")
    content = Map.fetch!(source_preview, "content")
    target_file = Map.fetch!(source_preview, "target_file")
    target_module = Map.fetch!(source_preview, "target_module")
    existed? = File.exists?(target_file)

    with :ok <- ensure_write_ready(plan),
         :ok <- ensure_overwrite_allowed(target_file, opts),
         :ok <- mkdir_p(Path.dirname(target_file)),
         :ok <- write_source(target_file, content) do
      {:ok,
       %{
         "status" => "written",
         "message" => "Wrote validated normalized domain import preview.",
         "target_file" => target_file,
         "target_module" => target_module,
         "bytes" => byte_size(content),
         "overwrote" => existed?,
         "source_validation" => Map.fetch!(plan, "source_validation")
       }}
    end
  end

  @spec plan(map(), keyword()) :: map()
  def plan(%{artifact: artifact} = check, opts \\ []) do
    summary = DomainExport.summary(check)
    domain = Map.get(artifact, "domain", %{})
    runtime_placeholders = runtime_placeholders(domain)
    sections = sections(domain, summary, runtime_placeholders)
    preview = preview(summary, sections, runtime_placeholders, opts)
    source_preview = source_preview(domain, preview, runtime_placeholders)

    source =
      %{
        "path" => Map.get(check, :path),
        "artifact_format" => Map.get(artifact, "format"),
        "artifact_format_version" => Map.get(artifact, "format_version"),
        "domain_module" => Map.get(artifact, "domain_module"),
        "schema_version" => Map.get(artifact, "schema_version"),
        "name" => Map.get(summary, :name)
      }
      |> maybe_put("domain_version", Map.get(artifact, "domain_version"))
      |> maybe_put("domain_fingerprint", Map.get(artifact, "domain_fingerprint"))

    %{
      "format" => @format,
      "format_version" => @format_version,
      "mode" => "check",
      "source" => source,
      "preview" => preview,
      "source_preview" => source_preview,
      "source_validation" => source_validation(source_preview, runtime_placeholders),
      "sections" => sections,
      "runtime_placeholders" => runtime_placeholders,
      "diagnostics" => DomainExport.json_safe(Map.fetch!(summary, :diagnostics)),
      "write" => %{
        "status" => "check_only",
        "message" =>
          "No files are written by import --check. Use --write for validated, placeholder-free previews."
      }
    }
  end

  @spec encode!(map(), keyword()) :: String.t()
  def encode!(plan, opts \\ []) do
    DomainExport.encode!(plan, opts)
  end

  @spec format_error(import_error()) :: String.t()
  def format_error({:source_preview_invalid, validation}) do
    "Import source preview is invalid and was not written: #{format_validation_failure(validation)}"
  end

  def format_error({:source_preview_not_write_ready, validation}) do
    count = Map.get(validation, "runtime_placeholder_count", 0)

    "Import source preview is not write-ready because #{count} runtime placeholder(s) remain. Re-run --check to inspect partial sections and placeholders."
  end

  def format_error({:target_file_exists, path}) do
    "Import target file already exists: #{path}. Pass --force to overwrite it."
  end

  def format_error({:mkdir_failed, path, reason}) do
    "Could not create import target directory #{path}: #{inspect(reason)}"
  end

  def format_error({:write_failed, path, reason}) do
    "Could not write normalized domain import preview #{path}: #{inspect(reason)}"
  end

  def format_error(reason), do: DomainExport.format_error(reason)

  defp preview(summary, sections, runtime_placeholders, opts) do
    target_module = target_module(summary, opts)
    output_dir = opts[:output_dir] || "lib"
    target_file = opts[:target_file] || module_file(target_module, output_dir)
    blocked? = map_get(runtime_placeholders, "count", 0) > 0

    %{
      "status" => if(blocked?, do: "partial", else: "ready"),
      "target_module" => target_module,
      "target_file" => target_file,
      "domain_function" => "domain/0",
      "render_strategy" => "literal_domain_map",
      "write_enabled" => false,
      "blocked_by_runtime_placeholders" => blocked?,
      "reconstructable_sections" => sections_by_status(sections, "reconstructable"),
      "partial_sections" => sections_by_status(sections, "partial_runtime_placeholders"),
      "preserved_unmodeled_sections" => sections_by_status(sections, "preserved_unmodeled"),
      "security_sensitive_sections" => security_sensitive_sections(sections)
    }
  end

  defp security_sensitive_sections(sections) do
    sections
    |> Enum.filter(fn section ->
      Map.get(section, "present") and
        Map.has_key?(@security_sensitive_sections, Map.get(section, "name"))
    end)
    |> Enum.map(fn section ->
      name = Map.fetch!(section, "name")

      %{
        "name" => name,
        "status" => Map.fetch!(section, "status"),
        "reason" => Map.fetch!(@security_sensitive_sections, name)
      }
    end)
    |> Enum.sort_by(&Map.fetch!(&1, "name"))
  end

  defp source_preview(domain, preview, runtime_placeholders) do
    content = render_source(Map.fetch!(preview, "target_module"), domain)

    %{
      "status" => Map.fetch!(preview, "status"),
      "language" => "elixir",
      "target_module" => Map.fetch!(preview, "target_module"),
      "target_file" => Map.fetch!(preview, "target_file"),
      "domain_function" => Map.fetch!(preview, "domain_function"),
      "write_enabled" => false,
      "includes_runtime_placeholders" => map_get(runtime_placeholders, "count", 0) > 0,
      "line_count" => source_line_count(content),
      "content" => content
    }
  end

  defp render_source(target_module, domain) do
    domain_literal =
      domain
      |> inspect(pretty: true, limit: :infinity, printable_limit: :infinity, width: 98)
      |> indent(4)

    """
    defmodule #{module_name(target_module)} do
      @moduledoc \"\"\"
      Selecto domain import preview.

      Generated by `mix selecto.domain.import`.
      \"\"\"

      def domain do
    #{domain_literal}
      end
    end
    """
  end

  defp module_name(module) do
    module
    |> to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp indent(content, spaces) do
    padding = String.duplicate(" ", spaces)

    content
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end

  defp source_line_count(content) do
    content
    |> String.split("\n", trim: true)
    |> length()
  end

  defp source_validation(source_preview, runtime_placeholders) do
    content = Map.fetch!(source_preview, "content")
    target_module = module_name(Map.fetch!(source_preview, "target_module"))
    runtime_placeholder_count = map_get(runtime_placeholders, "count", 0)

    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        module = ast_module_name(ast)
        target_module_match? = module == target_module
        domain_function_present? = domain_function_present?(ast)
        valid? = target_module_match? and domain_function_present?

        %{
          "valid" => valid?,
          "syntax" => "ok",
          "error" => nil,
          "module" => module,
          "target_module" => target_module,
          "target_module_match" => target_module_match?,
          "domain_function_present" => domain_function_present?,
          "runtime_placeholders_blocking" => runtime_placeholder_count > 0,
          "runtime_placeholder_count" => runtime_placeholder_count,
          "write_ready" => valid? and runtime_placeholder_count == 0
        }

      {:error, reason} ->
        %{
          "valid" => false,
          "syntax" => "error",
          "error" => inspect(reason),
          "module" => nil,
          "target_module" => target_module,
          "target_module_match" => false,
          "domain_function_present" => false,
          "runtime_placeholders_blocking" => runtime_placeholder_count > 0,
          "runtime_placeholder_count" => runtime_placeholder_count,
          "write_ready" => false
        }
    end
  end

  defp ensure_write_ready(plan) do
    validation = Map.fetch!(plan, "source_validation")

    cond do
      Map.get(validation, "valid") != true ->
        {:error, {:source_preview_invalid, validation}}

      Map.get(validation, "write_ready") != true ->
        {:error, {:source_preview_not_write_ready, validation}}

      true ->
        :ok
    end
  end

  defp ensure_overwrite_allowed(target_file, opts) do
    if File.exists?(target_file) and not Keyword.get(opts, :force, false) do
      {:error, {:target_file_exists, target_file}}
    else
      :ok
    end
  end

  defp mkdir_p(directory) do
    case File.mkdir_p(directory) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, directory, reason}}
    end
  end

  defp write_source(target_file, content) do
    case File.write(target_file, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, target_file, reason}}
    end
  end

  defp write_mode_plan(plan, write) do
    plan
    |> Map.put("mode", "write")
    |> put_in(["preview", "write_enabled"], true)
    |> put_in(["source_preview", "write_enabled"], true)
    |> Map.put("write", write)
  end

  defp format_validation_failure(validation) do
    cond do
      Map.get(validation, "syntax") == "error" ->
        "syntax error #{Map.get(validation, "error")}"

      Map.get(validation, "target_module_match") != true ->
        "target module #{Map.get(validation, "target_module")} did not match rendered module #{Map.get(validation, "module") || "(unknown)"}"

      Map.get(validation, "domain_function_present") != true ->
        "domain/0 was not found"

      true ->
        inspect(validation)
    end
  end

  defp ast_module_name({:defmodule, _meta, [module_ast, _body]}) do
    ast_alias_name(module_ast)
  end

  defp ast_module_name(_ast), do: nil

  defp ast_alias_name({:__aliases__, _meta, parts}) do
    Enum.map_join(parts, ".", &to_string/1)
  end

  defp ast_alias_name(module) when is_atom(module), do: module_name(module)
  defp ast_alias_name(_module), do: nil

  defp domain_function_present?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        node, true ->
          {node, true}

        {:def, _meta, [{:domain, _fun_meta, args}, _body]} = node, false
        when args in [nil, []] ->
          {node, true}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp target_module(summary, opts) do
    opts[:target_module] ||
      Map.get(summary, :domain_module) ||
      "Imported.SelectoDomain"
  end

  defp module_file(module, output_dir) do
    module_path =
      module
      |> to_string()
      |> String.replace_prefix("Elixir.", "")
      |> Macro.underscore()

    Path.join(output_dir, "#{module_path}.ex")
  end

  defp sections_by_status(sections, status) do
    sections
    |> Enum.filter(&(Map.get(&1, "status") == status))
    |> Enum.map(&Map.fetch!(&1, "name"))
    |> Enum.sort()
  end

  defp sections(domain, summary, runtime_placeholders) do
    classes = section_classes(Map.fetch!(summary, :sections))

    @known_sections
    |> Enum.filter(&section_present?(domain, &1))
    |> Kernel.++(Map.keys(classes))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn section ->
      present? = section_present?(domain, section)
      count = section_count(domain, section)
      class = Map.get(classes, section, "unclassified")
      placeholder_count = section_placeholder_count(runtime_placeholders, section)

      %{
        "name" => section,
        "class" => class,
        "present" => present?,
        "count" => count,
        "runtime_placeholders" => placeholder_count,
        "status" => section_status(present?, class, placeholder_count)
      }
    end)
  end

  defp section_classes(sections) do
    Enum.reduce(["canonical", "projection", "proposed", "unknown"], %{}, fn class, acc ->
      sections
      |> map_get(class, [])
      |> list_or_empty()
      |> Enum.reduce(acc, fn section, class_acc ->
        Map.put(class_acc, to_string(section), class)
      end)
    end)
  end

  defp section_status(false, _class, _placeholder_count), do: "absent"
  defp section_status(true, "unknown", _placeholder_count), do: "preserved_unmodeled"
  defp section_status(true, _class, count) when count > 0, do: "partial_runtime_placeholders"
  defp section_status(true, _class, _placeholder_count), do: "reconstructable"

  defp section_present?(domain, "source"), do: is_map(map_get(domain, "source"))

  defp section_present?(domain, section) do
    case map_get(domain, section) do
      nil -> false
      value when is_map(value) -> map_size(value) > 0
      value when is_list(value) -> length(value) > 0
      _value -> true
    end
  end

  defp section_count(domain, "source") do
    if is_map(map_get(domain, "source")), do: 1, else: 0
  end

  defp section_count(domain, "query_members") do
    domain
    |> map_get("query_members", %{})
    |> count_query_members()
  end

  defp section_count(domain, section) do
    domain
    |> map_get(section)
    |> count_value()
  end

  defp count_query_members(query_members) when is_map(query_members) do
    query_members
    |> Map.values()
    |> Enum.reduce(0, fn
      members, count when is_map(members) -> count + map_size(members)
      members, count when is_list(members) -> count + length(members)
      _members, count -> count
    end)
  end

  defp count_query_members(_query_members), do: 0

  defp count_value(value) when is_map(value), do: map_size(value)
  defp count_value(value) when is_list(value), do: length(value)
  defp count_value(nil), do: 0
  defp count_value(_value), do: 1

  defp runtime_placeholders(domain) do
    placeholders =
      domain
      |> collect_placeholders(["domain"], [])
      |> Enum.sort_by(&Map.get(&1, "path"))

    by_type = placeholders |> Enum.map(& &1["type"]) |> frequencies()

    %{
      "count" => length(placeholders),
      "by_type" => by_type,
      "paths" => placeholders
    }
  end

  defp collect_placeholders(%{} = map, path, acc) do
    case map_get(map, "$selecto_export") do
      nil ->
        Enum.reduce(map, acc, fn {key, value}, path_acc ->
          collect_placeholders(value, path ++ [to_string(key)], path_acc)
        end)

      type ->
        [
          %{
            "path" => Enum.join(path, "."),
            "type" => to_string(type),
            "inspect" => map_get(map, "inspect")
          }
          | acc
        ]
    end
  end

  defp collect_placeholders(values, path, acc) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {value, index}, path_acc ->
      collect_placeholders(value, path ++ [Integer.to_string(index)], path_acc)
    end)
  end

  defp collect_placeholders(_value, _path, acc), do: acc

  defp frequencies(values) do
    Enum.reduce(values, %{}, fn value, acc ->
      Map.update(acc, value, 1, &(&1 + 1))
    end)
  end

  defp section_placeholder_count(runtime_placeholders, section) do
    section_path = "domain.#{section}"

    runtime_placeholders
    |> map_get("paths", [])
    |> Enum.count(fn placeholder ->
      path = map_get(placeholder, "path", "")

      path == section_path or String.starts_with?(path, "#{section_path}.")
    end)
  end

  defp map_get(map, key, default \\ nil), do: ArtifactJSON.map_get(map, key, default)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_value), do: []
end
