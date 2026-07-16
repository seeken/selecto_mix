defmodule SelectoMix.DomainDiagram do
  @moduledoc """
  Renders Mermaid diagrams from Selecto domain inspection artifacts.

  The diagram input is the `selecto.domain_inspection` JSON artifact emitted by
  `mix selecto.domain.describe`, keeping diagram generation decoupled from the
  original domain module and normalized domain internals.
  """

  alias SelectoMix.ArtifactJSON

  @format "selecto.domain_inspection"
  @format_version 1

  @type diagram_error ::
          {:read_failed, Path.t(), term()}
          | {:decode_failed, Path.t(), term()}
          | :invalid_inspection_artifact
          | {:invalid_inspection_format, term()}
          | {:unsupported_inspection_version, term()}
          | :missing_inspection
          | {:invalid_inspection, term()}

  @spec render_file(Path.t()) :: {:ok, String.t()} | {:error, diagram_error()}
  def render_file(path) do
    with {:ok, contents} <- read_artifact(path),
         {:ok, artifact} <- decode_artifact(contents, path),
         :ok <- validate_artifact(artifact) do
      {:ok, render(artifact)}
    end
  end

  @spec render(map()) :: String.t()
  def render(%{} = artifact) do
    source = map_get(artifact, "source", %{})
    inspection = map_get(artifact, "inspection", %{})
    relationships = map_get(inspection, "source_relationships", []) |> list_or_empty()
    choice_sources = map_get(inspection, "choice_sources", []) |> list_or_empty()
    field_bindings = map_get(inspection, "field_choice_bindings", []) |> list_or_empty()
    capabilities = map_get(inspection, "capabilities", []) |> list_or_empty()
    capability_usage = map_get(inspection, "capability_usage", []) |> list_or_empty()
    security_review = map_get(inspection, "security_review", []) |> list_or_empty()

    [
      "flowchart LR",
      node("domain", domain_label(source, inspection)),
      node("source", source_label(inspection)),
      edge("domain", "source"),
      relationship_section(relationships),
      choice_source_section(choice_sources, relationships),
      field_binding_section(field_bindings, choice_sources),
      capability_section(capabilities, capability_usage),
      security_review_section(security_review),
      class_defs()
    ]
    |> List.flatten()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @spec format_error(diagram_error()) :: String.t()
  def format_error({:read_failed, path, reason}) do
    "Could not read normalized domain inspection JSON #{path}: #{inspect(reason)}"
  end

  def format_error({:decode_failed, path, reason}) do
    "Could not decode normalized domain inspection JSON #{path}: #{Exception.message(reason)}"
  end

  def format_error(:invalid_inspection_artifact) do
    "Normalized domain inspection artifact must be a JSON object"
  end

  def format_error({:invalid_inspection_format, format}) do
    "Unexpected normalized domain inspection format #{inspect(format)}"
  end

  def format_error({:unsupported_inspection_version, version}) do
    "Unsupported normalized domain inspection version #{inspect(version)}"
  end

  def format_error(:missing_inspection) do
    "Normalized domain inspection artifact is missing an inspection object"
  end

  def format_error({:invalid_inspection, inspection}) do
    "Normalized domain inspection must be an object, got: #{inspect(inspection)}"
  end

  defp read_artifact(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, {:read_failed, path, reason}}
    end
  end

  defp decode_artifact(contents, path) do
    case Jason.decode(contents) do
      {:ok, artifact} -> {:ok, artifact}
      {:error, reason} -> {:error, {:decode_failed, path, reason}}
    end
  end

  defp validate_artifact(%{} = artifact) do
    cond do
      map_get(artifact, "format") != @format ->
        {:error, {:invalid_inspection_format, map_get(artifact, "format")}}

      map_get(artifact, "format_version") != @format_version ->
        {:error, {:unsupported_inspection_version, map_get(artifact, "format_version")}}

      not Map.has_key?(artifact, "inspection") ->
        {:error, :missing_inspection}

      not is_map(map_get(artifact, "inspection")) ->
        {:error, {:invalid_inspection, map_get(artifact, "inspection")}}

      true ->
        :ok
    end
  end

  defp validate_artifact(_artifact), do: {:error, :invalid_inspection_artifact}

  defp relationship_section([]), do: []

  defp relationship_section(relationships) do
    nodes =
      relationships
      |> sort_by_id()
      |> Enum.map(fn relationship ->
        node(
          relationship_node_id(relationship),
          relationship_label(relationship),
          "    "
        )
      end)

    edges =
      relationships
      |> sort_by_id()
      |> Enum.map(fn relationship ->
        edge("domain", relationship_node_id(relationship), "relationship")
      end)

    ["", ~s(  subgraph source_relationships["Source Relationships"])] ++
      nodes ++ ["  end"] ++ edges
  end

  defp choice_source_section([], _relationships), do: []

  defp choice_source_section(choice_sources, relationships) do
    relationship_ids =
      relationships
      |> Enum.map(&to_string(map_get(&1, "id", "")))
      |> MapSet.new()

    nodes =
      choice_sources
      |> sort_by_id()
      |> Enum.map(fn choice_source ->
        node(choice_source_node_id(choice_source), choice_source_label(choice_source), "    ")
      end)

    edges =
      choice_sources
      |> sort_by_id()
      |> Enum.flat_map(fn choice_source ->
        choice_node = choice_source_node_id(choice_source)
        relationship_id = map_get(choice_source, "source_relationship")

        [
          edge("domain", choice_node, "choice source"),
          relationship_edge(choice_node, relationship_id, relationship_ids)
        ]
      end)

    ["", ~s(  subgraph choice_sources["Choice Sources"])] ++ nodes ++ ["  end"] ++ edges
  end

  defp field_binding_section([], _choice_sources), do: []

  defp field_binding_section(field_bindings, choice_sources) do
    choice_source_ids =
      choice_sources
      |> Enum.map(&to_string(map_get(&1, "id", "")))
      |> MapSet.new()

    nodes =
      field_bindings
      |> sort_by_field()
      |> Enum.map(fn binding ->
        node(field_binding_node_id(binding), field_binding_label(binding), "    ")
      end)

    edges =
      field_bindings
      |> sort_by_field()
      |> Enum.flat_map(fn binding ->
        binding_node = field_binding_node_id(binding)
        choice_source = map_get(binding, "choice_source")

        [
          edge("source", binding_node, "field"),
          choice_source_edge(binding_node, choice_source, choice_source_ids)
        ]
      end)

    ["", ~s(  subgraph field_bindings["Field Choice Bindings"])] ++ nodes ++ ["  end"] ++ edges
  end

  defp capability_section([], []), do: []

  defp capability_section(capabilities, capability_usage) do
    capability_ids =
      capabilities
      |> Enum.map(&map_get(&1, "id"))
      |> Kernel.++(Enum.map(capability_usage, &map_get(&1, "capability")))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq_by(&to_string/1)
      |> Enum.sort_by(&to_string/1)

    capability_nodes =
      capability_ids
      |> Enum.map(fn capability_id ->
        node(
          capability_node_id(capability_id),
          capability_label(capability_id, find_capability(capabilities, capability_id)),
          "    "
        )
      end)

    usage_nodes =
      capability_usage
      |> sort_by_path()
      |> Enum.map(fn usage ->
        node(capability_usage_node_id(usage), capability_usage_label(usage), "    ")
      end)

    usage_edges =
      capability_usage
      |> sort_by_path()
      |> Enum.map(fn usage ->
        edge(
          capability_usage_node_id(usage),
          capability_node_id(map_get(usage, "capability")),
          "requires"
        )
      end)

    ["", ~s(  subgraph capabilities["Capabilities"])] ++
      capability_nodes ++
      ["  end"] ++
      ["", ~s(  subgraph capability_usage["Capability Usage"])] ++
      usage_nodes ++
      ["  end"] ++
      usage_edges
  end

  defp security_review_section([]), do: []

  defp security_review_section(security_review) do
    nodes =
      security_review
      |> sort_by_section()
      |> Enum.map(fn review ->
        node(security_review_node_id(review), security_review_label(review), "    ")
      end)

    edges =
      security_review
      |> sort_by_section()
      |> Enum.map(fn review ->
        edge("domain", security_review_node_id(review), "review")
      end)

    ["", ~s(  subgraph security_review["Security Review"])] ++ nodes ++ ["  end"] ++ edges
  end

  defp relationship_edge(_choice_node, nil, _relationship_ids), do: nil

  defp relationship_edge(choice_node, relationship_id, relationship_ids) do
    if MapSet.member?(relationship_ids, to_string(relationship_id)) do
      edge(choice_node, node_id("rel", relationship_id), "uses")
    end
  end

  defp choice_source_edge(_binding_node, nil, _choice_source_ids), do: nil

  defp choice_source_edge(binding_node, choice_source, choice_source_ids) do
    if MapSet.member?(choice_source_ids, to_string(choice_source)) do
      edge(binding_node, node_id("choice", choice_source), "picker")
    end
  end

  defp domain_label(source, inspection) do
    name = map_get(source, "name") || map_get(inspection, "name") || "Selecto Domain"
    schema_version = map_get(source, "schema_version") || map_get(inspection, "schema_version")
    domain_version = map_get(source, "domain_version") || map_get(inspection, "domain_version")

    domain_fingerprint =
      map_get(source, "domain_fingerprint") || map_get(inspection, "domain_fingerprint")

    [
      "Domain: #{name}",
      schema_version && "schema v#{schema_version}",
      domain_version && "domain #{domain_version}",
      domain_fingerprint && "fingerprint #{domain_fingerprint}"
    ]
    |> compact_join()
  end

  defp source_label(inspection) do
    source_fields =
      inspection
      |> map_get("registries", %{})
      |> map_get("source_fields", [])
      |> list_or_empty()

    ["Source fields", format_list(source_fields)]
    |> compact_join()
  end

  defp relationship_label(relationship) do
    source_field = map_get(relationship, "source_field")
    target_field = map_get(relationship, "target_field")

    [
      "Source relationship: #{map_get(relationship, "id")}",
      map_get(relationship, "target_domain") &&
        "target: #{map_get(relationship, "target_domain")}",
      source_field && target_field && "#{source_field} -> #{target_field}",
      relationship_counts(relationship)
    ]
    |> compact_join()
  end

  defp relationship_counts(relationship) do
    virtual_join_count = numeric_value(map_get(relationship, "virtual_join_count"))
    filters_count = numeric_value(map_get(relationship, "filters_count"))

    if virtual_join_count > 0 or filters_count > 0 do
      "virtual joins: #{virtual_join_count}, filters: #{filters_count}"
    end
  end

  defp choice_source_label(choice_source) do
    [
      "Choice source: #{map_get(choice_source, "id")}",
      map_get(choice_source, "domain") && "domain: #{map_get(choice_source, "domain")}",
      map_get(choice_source, "value_field") && "value: #{map_get(choice_source, "value_field")}",
      map_get(choice_source, "label_field") && "label: #{map_get(choice_source, "label_field")}",
      choice_source_policy_label(choice_source),
      picker_label(choice_source),
      choice_source_counts(choice_source)
    ]
    |> compact_join()
  end

  defp choice_source_policy_label(choice_source) do
    choice_source
    |> map_get("constraint_policy", %{})
    |> format_constraint_policy()
    |> case do
      "" -> nil
      policy -> "policy: #{policy}"
    end
  end

  defp picker_label(choice_source) do
    control =
      choice_source
      |> map_get("presentation", %{})
      |> map_get("control")

    case control do
      nil -> "picker"
      "" -> "picker"
      control -> "picker: #{control}"
    end
  end

  defp choice_source_counts(choice_source) do
    filters_count = numeric_value(map_get(choice_source, "filters_count"))
    order_by_count = numeric_value(map_get(choice_source, "order_by_count"))

    if filters_count > 0 or order_by_count > 0 do
      "filters: #{filters_count}, order: #{order_by_count}"
    end
  end

  defp field_binding_label(binding) do
    [
      "Picker field: #{map_get(binding, "field")}",
      "choice source: #{map_get(binding, "choice_source")}",
      binding_mode(binding)
    ]
    |> compact_join()
  end

  defp binding_mode(binding) do
    modes =
      [
        truthy?(map_get(binding, "compact?")) && "compact",
        truthy?(map_get(binding, "reference?")) && "reference"
      ]
      |> Enum.reject(&is_nil/1)

    case modes do
      [] -> nil
      modes -> "mode: #{Enum.join(modes, ", ")}"
    end
  end

  defp node(id, label, indent \\ "  ") do
    ~s(#{indent}#{id}["#{escape_label(label)}"])
  end

  defp edge(from, to, label \\ nil)
  defp edge(_from, nil, _label), do: nil
  defp edge(nil, _to, _label), do: nil
  defp edge(from, to, nil), do: "  #{from} --> #{to}"
  defp edge(from, to, label), do: "  #{from} -. #{escape_edge_label(label)} .-> #{to}"

  defp relationship_node_id(relationship), do: node_id("rel", map_get(relationship, "id"))
  defp choice_source_node_id(choice_source), do: node_id("choice", map_get(choice_source, "id"))
  defp field_binding_node_id(binding), do: node_id("binding", map_get(binding, "field"))
  defp capability_node_id(capability), do: node_id("cap", capability)
  defp security_review_node_id(review), do: node_id("review", map_get(review, "section"))

  defp capability_usage_node_id(usage) do
    usage_path =
      usage
      |> map_get("path", [])
      |> list_or_empty()
      |> Enum.join("_")

    node_id("capuse", usage_path)
  end

  defp node_id(prefix, value) do
    suffix =
      value
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]+/, "_")
      |> String.trim("_")

    "#{prefix}_#{if suffix == "", do: "unknown", else: suffix}"
  end

  defp class_defs do
    [
      "",
      "  classDef domain fill:#f4f4f4,stroke:#555,color:#222",
      "  classDef source fill:#e8f3ff,stroke:#3d6f9f,color:#222",
      "  classDef relationship fill:#fff4d6,stroke:#9f7a24,color:#222",
      "  classDef choice fill:#e9f8ef,stroke:#3f8f5b,color:#222",
      "  classDef binding fill:#f4ecff,stroke:#7a4fb3,color:#222",
      "  classDef capability fill:#f8e8ed,stroke:#9b3954,color:#222",
      "  classDef usage fill:#f5f5f5,stroke:#777,color:#222",
      "  class domain domain",
      "  class source source"
    ]
  end

  defp sort_by_id(values) do
    Enum.sort_by(values, &to_string(map_get(&1, "id", "")))
  end

  defp sort_by_field(values) do
    Enum.sort_by(values, &to_string(map_get(&1, "field", "")))
  end

  defp sort_by_path(values) do
    Enum.sort_by(values, fn value ->
      value
      |> map_get("path", [])
      |> list_or_empty()
      |> Enum.map_join(".", &to_string/1)
    end)
  end

  defp sort_by_section(values) do
    Enum.sort_by(values, &to_string(map_get(&1, "section", "")))
  end

  defp capability_label(capability_id, capability) do
    operations =
      capability
      |> map_get("operations", [])
      |> list_or_empty()

    [
      "Capability: #{capability_id}",
      operations != [] && "operations: #{format_list(operations)}"
    ]
    |> compact_join()
  end

  defp capability_usage_label(usage) do
    [
      usage_role_label(map_get(usage, "role"), map_get(usage, "id") || map_get(usage, "field")),
      map_get(usage, "section") && "section: #{map_get(usage, "section")}",
      map_get(usage, "group") && "group: #{map_get(usage, "group")}"
    ]
    |> compact_join()
  end

  defp security_review_label(review) do
    [
      "Security review: #{map_get(review, "section")}",
      "count: #{map_get(review, "count", 0)}",
      "items: #{format_security_items(map_get(review, "items"))}",
      map_get(review, "reason")
    ]
    |> compact_join()
  end

  defp usage_role_label(role, nil), do: "Usage: #{role || "unknown"}"
  defp usage_role_label(role, value), do: "#{usage_role_title(role)}: #{value}"

  defp usage_role_title(role) do
    role
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp find_capability(capabilities, capability_id) do
    Enum.find(capabilities, fn capability ->
      to_string(map_get(capability, "id")) == to_string(capability_id)
    end)
  end

  defp compact_join(values) do
    values
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

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

  defp format_security_items(items) when is_map(items) do
    [
      {"operations", format_list(map_get(items, "operations", []))},
      {"fields", format_list(map_get(items, "fields", []))},
      {"relationships", format_list(map_get(items, "relationships", []))},
      {"transitions", format_list(map_get(items, "transitions", []))},
      {"validations", map_get(items, "validations_count", 0)},
      {"constraints", map_get(items, "constraints_count", 0)},
      {"scope", format_list(map_get(items, "scope", []))},
      {"hooks", format_list(map_get(items, "hooks", []))}
    ]
    |> Enum.reject(fn {_label, value} -> value in ["(none)", 0] end)
    |> Enum.map(fn {label, value} -> "#{label}: #{value}" end)
    |> Enum.join("; ")
  end

  defp format_security_items(items) when is_list(items), do: format_list(items)
  defp format_security_items(_items), do: "(none)"

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_value), do: []

  defp numeric_value(value) when is_integer(value), do: value
  defp numeric_value(value) when is_float(value), do: trunc(value)
  defp numeric_value(_value), do: 0

  defp truthy?(true), do: true
  defp truthy?(_value), do: false

  defp escape_label(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp escape_edge_label(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9 _-]+/, "")
  end

  defp map_get(map, key, default \\ nil), do: ArtifactJSON.map_get(map, key, default)
end
