defmodule SelectoMix.DomainDocs do
  @moduledoc """
  Renders Markdown documentation from normalized Selecto domain artifacts.

  The docs renderer consumes the same checked artifact shape used by
  `selecto.domain.check`, `inspect`, and `diff`, so it documents the portable
  normalized JSON artifact rather than requiring the original domain module.
  """

  alias SelectoMix.DomainExport

  @section_order [:canonical, :projection, :proposed, :unknown]
  @count_order [
    :source_fields,
    :source_columns,
    :schemas,
    :joins,
    :filters,
    :functions,
    :query_members,
    :published_views,
    :detail_actions,
    :write_operations,
    :write_fields,
    :write_transitions,
    :write_validations,
    :write_constraints,
    :actions,
    :capabilities,
    :source_relationships,
    :choice_sources
  ]

  @registry_sections [
    {"Joins", "joins"},
    {"Filters", "filters"},
    {"Functions", "functions"},
    {"Published Views", "published_views"},
    {"Detail Actions", "detail_actions"},
    {"Writes", "writes"},
    {"Capabilities", "capabilities"},
    {"Actions", "actions"},
    {"Source Relationships", "source_relationships"},
    {"Choice Sources", "choice_sources"}
  ]

  @spec render_file(Path.t(), keyword()) ::
          {:ok, String.t()} | {:error, DomainExport.artifact_error()}
  def render_file(path, opts \\ []) do
    with {:ok, check} <- DomainExport.check_file(path, opts) do
      {:ok, render_check(check)}
    end
  end

  @spec render_check(map()) :: String.t()
  def render_check(%{artifact: artifact} = check) do
    summary = DomainExport.summary(check)
    domain = Map.get(artifact, "domain", %{})

    render(summary, domain)
  end

  @spec render(map(), map()) :: String.t()
  def render(summary, domain) do
    [
      "# #{heading(summary)}",
      "",
      "Generated from a normalized Selecto domain artifact.",
      "",
      artifact_section(summary),
      sections_section(summary),
      counts_section(summary),
      source_section(domain),
      schemas_section(domain),
      registries_section(domain),
      choice_source_details_section(domain),
      security_review_section(summary),
      query_members_section(domain),
      capability_usage_section(domain),
      diagnostics_section(summary)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp artifact_section(summary) do
    [
      "## Artifact",
      "",
      "| Key | Value |",
      "| --- | --- |",
      table_row("Path", Map.get(summary, :path) || "(unknown)"),
      table_row("Format", "#{Map.get(summary, :format)} v#{Map.get(summary, :format_version)}"),
      table_row("Domain module", Map.get(summary, :domain_module) || "(unknown)"),
      table_row("Schema version", Map.get(summary, :schema_version) || "(unknown)"),
      table_row("Domain version", Map.get(summary, :domain_version) || "(unversioned)"),
      table_row(
        "Domain fingerprint",
        Map.get(summary, :domain_fingerprint) || "(unfingerprinted)"
      ),
      ""
    ]
  end

  defp sections_section(summary) do
    sections = Map.fetch!(summary, :sections)

    [
      "## Sections",
      "",
      "| Class | Sections |",
      "| --- | --- |"
    ] ++
      Enum.map(@section_order, fn section_class ->
        table_row(format_key(section_class), format_list(Map.get(sections, section_class, [])))
      end) ++
      [""]
  end

  defp counts_section(summary) do
    counts = Map.fetch!(summary, :counts)

    [
      "## Counts",
      "",
      "| Item | Count |",
      "| --- | --- |"
    ] ++
      Enum.map(@count_order, fn count_key ->
        table_row(format_key(count_key), Map.get(counts, count_key, 0))
      end) ++
      [""]
  end

  defp source_section(domain) do
    source = map_get(domain, "source", %{})
    columns = map_get(source, "columns", %{})

    [
      "## Source",
      "",
      "| Key | Value |",
      "| --- | --- |",
      table_row("Table", source_table(source)),
      table_row("Primary key", map_get(source, "primary_key") || "(unknown)"),
      table_row("Fields", format_list(map_get(source, "fields", []))),
      ""
    ] ++ source_columns_section(columns)
  end

  defp source_columns_section(columns) when is_map(columns) and map_size(columns) > 0 do
    [
      "### Source Columns",
      "",
      "| Field | Type | Label |",
      "| --- | --- | --- |"
    ] ++
      Enum.map(sorted_entries(columns), fn {field, column} ->
        table_row([
          field,
          column_value(column, "type"),
          label_value(column)
        ])
      end) ++
      [""]
  end

  defp source_columns_section(_columns), do: []

  defp schemas_section(domain) do
    schemas = map_get(domain, "schemas", %{})

    if is_map(schemas) and map_size(schemas) > 0 do
      [
        "## Schemas",
        "",
        "| Schema | Table | Columns |",
        "| --- | --- | --- |"
      ] ++
        Enum.map(sorted_entries(schemas), fn {schema_id, schema} ->
          columns = map_get(schema, "columns", %{})

          table_row([
            schema_id,
            source_table(schema),
            if(is_map(columns), do: map_size(columns), else: 0)
          ])
        end) ++
        [""]
    else
      ["## Schemas", "", "(none)", ""]
    end
  end

  defp registries_section(domain) do
    sections =
      @registry_sections
      |> Enum.flat_map(fn {title, key} ->
        registry_section(title, map_get(domain, key, %{}))
      end)

    case sections do
      [] ->
        ["## Registries", "", "(none)", ""]

      sections ->
        ["## Registries", ""] ++ sections
    end
  end

  defp registry_section(_title, registry) when not is_map(registry), do: []
  defp registry_section(_title, registry) when map_size(registry) == 0, do: []

  defp registry_section(title, registry) do
    [
      "### #{title}",
      "",
      "| Id | Label | Kind | Target |",
      "| --- | --- | --- | --- |"
    ] ++
      Enum.map(sorted_entries(registry), fn {id, spec} ->
        table_row([
          id,
          label_value(spec),
          first_value(spec, ["kind", "type", "source", "mode"]),
          first_value(spec, ["field", "relation", "source_table", "table", "target"])
        ])
      end) ++
      [""]
  end

  defp choice_source_details_section(domain) do
    choice_sources = map_get(domain, "choice_sources", %{})

    if is_map(choice_sources) and map_size(choice_sources) > 0 do
      [
        "## Choice Source Details",
        "",
        "| Choice Source | Domain | Value | Label | Constraint Policy |",
        "| --- | --- | --- | --- | --- |"
      ] ++
        Enum.map(sorted_entries(choice_sources), fn {id, choice_source} ->
          table_row([
            id,
            map_get(choice_source, "domain"),
            map_get(choice_source, "value_field"),
            map_get(choice_source, "label_field"),
            format_constraint_policy(map_get(choice_source, "constraint_policy", %{}))
          ])
        end) ++
        [""]
    else
      []
    end
  end

  defp query_members_section(domain) do
    query_members = map_get(domain, "query_members", %{})

    if is_map(query_members) and map_size(query_members) > 0 do
      [
        "## Query Members",
        "",
        "| Group | Member | Label | Kind |",
        "| --- | --- | --- | --- |"
      ] ++
        Enum.flat_map(sorted_entries(query_members), fn {group, members} ->
          query_member_rows(group, members)
        end) ++
        [""]
    else
      []
    end
  end

  defp query_member_rows(group, members) when is_map(members) do
    Enum.map(sorted_entries(members), fn {member_id, spec} ->
      table_row([
        group,
        member_id,
        label_value(spec),
        first_value(spec, ["kind", "type", "source"])
      ])
    end)
  end

  defp query_member_rows(group, members) when is_list(members) do
    Enum.map(members, fn member_id ->
      table_row([group, member_id, "", ""])
    end)
  end

  defp query_member_rows(_group, _members), do: []

  defp security_review_section(summary) do
    security_review = Map.get(summary, :security_review, [])

    if security_review == [] do
      []
    else
      [
        "## Security Review",
        "",
        "| Section | Count | Items | Reason |",
        "| --- | ---: | --- | --- |"
      ] ++
        Enum.map(security_review, fn section ->
          table_row([
            Map.fetch!(section, :section),
            Map.fetch!(section, :count),
            format_security_items(Map.fetch!(section, :items)),
            Map.fetch!(section, :reason)
          ])
        end) ++
        [""]
    end
  end

  defp capability_usage_section(domain) do
    usage = capability_usage(domain)

    if usage == [] do
      []
    else
      [
        "## Capability Usage",
        "",
        "| Capability | Role | Section | Target | Path |",
        "| --- | --- | --- | --- | --- |"
      ] ++
        Enum.map(usage, fn entry ->
          table_row([
            map_get(entry, "capability"),
            map_get(entry, "role"),
            map_get(entry, "section"),
            map_get(entry, "target"),
            format_path(map_get(entry, "path", []))
          ])
        end) ++
        [""]
    end
  end

  defp capability_usage(domain) do
    []
    |> Kernel.++(relation_capability_usage("source", map_get(domain, "source"), ["source"]))
    |> Kernel.++(schema_capability_usage(map_get(domain, "schemas")))
    |> Kernel.++(
      capability_section_usage(
        "custom_columns",
        map_get(domain, "custom_columns"),
        "custom column",
        ["custom_columns"]
      )
    )
    |> Kernel.++(
      capability_section_usage("filters", map_get(domain, "filters"), "query filter", [
        "filters"
      ])
    )
    |> Kernel.++(
      capability_section_usage("functions", map_get(domain, "functions"), "query function", [
        "functions"
      ])
    )
    |> Kernel.++(query_member_capability_usage(map_get(domain, "query_members")))
    |> Kernel.++(
      capability_section_usage(
        "published_views",
        map_get(domain, "published_views"),
        "published view",
        ["published_views"]
      )
    )
    |> Kernel.++(
      capability_section_usage(
        "detail_actions",
        map_get(domain, "detail_actions"),
        "detail action",
        ["detail_actions"]
      )
    )
    |> Kernel.++(
      capability_section_usage("actions", map_get(domain, "actions"), "action", ["actions"])
    )
    |> Kernel.++(
      capability_section_usage(
        "choice_sources",
        map_get(domain, "choice_sources"),
        "choice source",
        ["choice_sources"]
      )
    )
    |> Enum.sort_by(fn entry ->
      {to_string(map_get(entry, "capability")), format_path(map_get(entry, "path", []))}
    end)
  end

  defp schema_capability_usage(schemas) when is_map(schemas) do
    schemas
    |> sorted_entries()
    |> Enum.flat_map(fn {schema_id, schema} ->
      relation_capability_usage("schemas", schema, ["schemas", schema_id])
    end)
  end

  defp schema_capability_usage(_schemas), do: []

  defp relation_capability_usage(section, relation, path_prefix) when is_map(relation) do
    case map_get(relation, "columns", %{}) do
      columns when is_map(columns) ->
        columns
        |> sorted_entries()
        |> Enum.flat_map(fn {field, column} ->
          capability_usage_entries(map_get(column, "capability"), %{
            "section" => section,
            "role" => "field",
            "target" => field,
            "path" => path_prefix ++ ["columns", field, "capability"]
          })
        end)

      _columns ->
        []
    end
  end

  defp relation_capability_usage(_section, _relation, _path_prefix), do: []

  defp capability_section_usage(section, registry, role, path_prefix) when is_map(registry) do
    registry
    |> sorted_entries()
    |> Enum.flat_map(fn {id, spec} ->
      capability_usage_entries(map_get(spec, "capability"), %{
        "section" => section,
        "role" => role,
        "target" => id,
        "path" => path_prefix ++ [id, "capability"]
      })
    end)
  end

  defp capability_section_usage(_section, _registry, _role, _path_prefix), do: []

  defp query_member_capability_usage(query_members) when is_map(query_members) do
    query_members
    |> sorted_entries()
    |> Enum.flat_map(fn {group, members} ->
      query_member_group_capability_usage(group, members)
    end)
  end

  defp query_member_capability_usage(_query_members), do: []

  defp query_member_group_capability_usage(group, members) when is_map(members) do
    members
    |> sorted_entries()
    |> Enum.flat_map(fn {id, spec} ->
      capability_usage_entries(map_get(spec, "capability"), %{
        "section" => "query_members",
        "role" => "query member",
        "target" => "#{group}.#{id}",
        "path" => ["query_members", group, id, "capability"]
      })
    end)
  end

  defp query_member_group_capability_usage(_group, _members), do: []

  defp capability_usage_entries(capability, attrs)
       when not is_nil(capability) and (is_atom(capability) or is_binary(capability)) do
    [Map.put(attrs, "capability", capability)]
  end

  defp capability_usage_entries(_capability, _attrs), do: []

  defp diagnostics_section(summary) do
    diagnostics = Map.fetch!(summary, :diagnostics)

    [
      "## Diagnostics",
      "",
      "| Scope | Errors | Warnings | Error Codes | Warning Codes |",
      "| --- | ---: | ---: | --- | --- |",
      diagnostic_row("Artifact", Map.fetch!(diagnostics, :artifact)),
      diagnostic_row("Current", Map.fetch!(diagnostics, :current)),
      ""
    ]
  end

  defp diagnostic_row(label, diagnostics) do
    table_row([
      label,
      Map.get(diagnostics, :errors, 0),
      Map.get(diagnostics, :warnings, 0),
      format_list(Map.get(diagnostics, :error_codes, [])),
      format_list(Map.get(diagnostics, :warning_codes, []))
    ])
  end

  defp heading(summary), do: Map.get(summary, :name) || "Selecto Domain"

  defp source_table(source) do
    map_get(source, "source_table") ||
      map_get(source, "table_name") ||
      map_get(source, "name") ||
      "(unknown)"
  end

  defp label_value(spec) do
    first_value(spec, ["label", "name", "title", "display_name", "display"])
  end

  defp column_value(column, key), do: first_value(column, [key])

  defp first_value(spec, keys) when is_map(spec) do
    Enum.find_value(keys, fn key ->
      case map_get(spec, key) do
        nil -> nil
        "" -> nil
        value -> value
      end
    end) || ""
  end

  defp first_value(_spec, _keys), do: ""

  defp sorted_entries(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
  end

  defp table_row(label, value), do: table_row([label, value])

  defp table_row(values) do
    cells =
      values
      |> Enum.map(&format_cell/1)
      |> Enum.join(" | ")

    "| #{cells} |"
  end

  defp format_cell(nil), do: ""
  defp format_cell(value) when is_binary(value), do: escape_markdown(value)
  defp format_cell(value) when is_atom(value), do: value |> Atom.to_string() |> escape_markdown()
  defp format_cell(value) when is_integer(value), do: Integer.to_string(value)
  defp format_cell(value) when is_float(value), do: Float.to_string(value)

  defp format_cell(%{"$selecto_export" => type} = value) do
    [type, map_get(value, "inspect")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> escape_markdown()
  end

  defp format_cell(%{} = value) do
    value
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
    |> Enum.join(", ")
    |> escape_markdown()
  end

  defp format_cell(value) when is_list(value), do: value |> format_list() |> escape_markdown()
  defp format_cell(value), do: value |> inspect() |> escape_markdown()

  defp format_list([]), do: "(none)"

  defp format_list(values) when is_list(values) do
    values
    |> Enum.map(&format_value/1)
    |> Enum.join(", ")
  end

  defp format_list(%{} = value) when map_size(value) == 0, do: "(none)"
  defp format_list(%{} = value), do: value |> Map.keys() |> format_list()
  defp format_list(value), do: format_value(value)

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value), do: inspect(value)

  defp format_security_items(items) when is_map(items) do
    [
      {"operations", format_list(Map.get(items, "operations", []))},
      {"fields", format_list(Map.get(items, "fields", []))},
      {"relationships", format_list(Map.get(items, "relationships", []))},
      {"transitions", format_list(Map.get(items, "transitions", []))},
      {"validations", Map.get(items, "validations_count", 0)},
      {"constraints", Map.get(items, "constraints_count", 0)},
      {"scope", format_list(Map.get(items, "scope", []))},
      {"hooks", format_list(Map.get(items, "hooks", []))}
    ]
    |> Enum.reject(fn {_label, value} -> value in ["(none)", 0] end)
    |> Enum.map(fn {label, value} -> "#{label}: #{value}" end)
    |> Enum.join("; ")
  end

  defp format_security_items(items), do: format_list(items)

  defp format_path(path) when is_list(path) do
    Enum.map_join(path, ".", &to_string/1)
  end

  defp format_path(path), do: to_string(path)

  defp format_constraint_policy(policy) when is_map(policy) do
    policy
    |> Enum.map(fn {key, value} ->
      "#{format_policy_part(key)}=#{format_policy_part(value)}"
    end)
    |> Enum.sort()
    |> Enum.join(", ")
  end

  defp format_constraint_policy(_policy), do: ""

  defp format_policy_part(value) when is_binary(value), do: value
  defp format_policy_part(value) when is_atom(value), do: Atom.to_string(value)
  defp format_policy_part(value), do: inspect(value)

  defp format_key(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
  end

  defp escape_markdown(value) do
    value
    |> String.replace("|", "\\|")
    |> String.replace("\n", " ")
  end

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map) and is_binary(key) do
    atom_key = existing_atom(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      atom_key && Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> default
    end
  end

  defp map_get(map, key, default) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _key, default), do: default

  defp existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
