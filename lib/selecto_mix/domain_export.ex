defmodule SelectoMix.DomainExport do
  @moduledoc """
  Builds JSON-ready artifacts for normalized Selecto domains.

  The exporter intentionally calls into `Selecto.Domain.normalize/1` at runtime
  so `selecto_mix` can stay a tooling package while host projects provide the
  Selecto version they are using.
  """

  alias SelectoMix.ArtifactJSON

  @format "selecto.normalized_domain"
  @format_version 1
  @security_sensitive_sections %{
    "actions" => "business command definitions and execution surfaces",
    "capabilities" => "authorization capability catalog",
    "choice_sources" => "cross-domain choices and constraint policy",
    "detail_actions" => "user-visible detail actions",
    "source_relationships" => "cross-domain source bindings",
    "writes" =>
      "write operations, fields, relationships, scope, hooks, validations, constraints, and transitions"
  }

  @type export_error ::
          :selecto_domain_unavailable
          | {:module_not_loaded, module()}
          | {:missing_domain_function, module()}
          | {:normalization_failed, term()}
          | {:invalid_normalizer_result, term()}

  @type artifact_error ::
          export_error()
          | {:read_failed, Path.t(), term()}
          | {:decode_failed, Path.t(), term()}
          | :invalid_artifact
          | {:invalid_artifact_format, term()}
          | {:unsupported_artifact_version, term()}
          | :missing_artifact_domain
          | {:invalid_artifact_domain, term()}

  @spec export(String.t() | module(), keyword()) :: {:ok, map()} | {:error, artifact_error()}
  def export(domain_module, opts \\ []) do
    normalizer = Keyword.get(opts, :normalizer, Selecto.Domain)

    with {:ok, module} <- domain_module(domain_module),
         :ok <- ensure_domain_module(module),
         {:ok, domain} <- domain_from_module(module),
         {:ok, normalized, diagnostics} <- normalize_domain(domain, normalizer),
         artifact <- artifact(module, normalized, diagnostics),
         {:ok, _check} <- round_trip_artifact(artifact, normalizer) do
      {:ok, artifact}
    end
  end

  @spec check_file(Path.t(), keyword()) :: {:ok, map()} | {:error, artifact_error()}
  def check_file(path, opts \\ []) do
    with {:ok, contents} <- read_artifact(path),
         {:ok, artifact} <- decode_artifact(contents, path),
         {:ok, check} <- check_artifact(artifact, opts) do
      {:ok, Map.put(check, :path, path)}
    end
  end

  @spec check_artifact(map(), keyword()) :: {:ok, map()} | {:error, artifact_error()}
  def check_artifact(artifact, opts \\ []) do
    normalizer = Keyword.get(opts, :normalizer, Selecto.Domain)

    with :ok <- validate_artifact_envelope(artifact),
         {:ok, domain} <- artifact_domain(artifact),
         {:ok, normalized, diagnostics} <- normalize_domain(domain, normalizer) do
      {:ok,
       %{
         artifact: artifact,
         domain_module: Map.get(artifact, "domain_module"),
         schema_version: Map.get(artifact, "schema_version"),
         domain_version:
           Map.get(artifact, "domain_version") || Map.get(normalized, :domain_version),
         domain_fingerprint:
           Map.get(artifact, "domain_fingerprint") || Map.get(normalized, :domain_fingerprint),
         normalized: normalized,
         diagnostics: diagnostics
       }}
    end
  end

  @spec summary_file(Path.t(), keyword()) :: {:ok, map()} | {:error, artifact_error()}
  def summary_file(path, opts \\ []) do
    with {:ok, check} <- check_file(path, opts) do
      {:ok, summary(check)}
    end
  end

  @spec summary(map()) :: map()
  def summary(%{artifact: artifact, diagnostics: current_diagnostics} = check) do
    domain = Map.get(artifact, "domain", %{})
    artifact_diagnostics = Map.get(artifact, "diagnostics", %{})

    %{
      path: Map.get(check, :path),
      format: Map.get(artifact, "format"),
      format_version: Map.get(artifact, "format_version"),
      domain_module: Map.get(artifact, "domain_module"),
      schema_version: Map.get(artifact, "schema_version"),
      domain_version: Map.get(artifact, "domain_version") || map_get(domain, "domain_version"),
      domain_fingerprint:
        Map.get(artifact, "domain_fingerprint") || map_get(domain, "domain_fingerprint"),
      name: map_get(domain, "name"),
      sections: sections_summary(artifact_diagnostics, current_diagnostics),
      counts: counts_summary(domain),
      registries: registries_summary(domain),
      security_review: security_review_summary(domain),
      choice_source_policies: choice_source_policy_summary(domain),
      diagnostics: %{
        artifact: diagnostics_summary(artifact_diagnostics),
        current: diagnostics_summary(current_diagnostics)
      }
    }
  end

  @spec diff_files(Path.t(), Path.t(), keyword()) :: {:ok, map()} | {:error, artifact_error()}
  def diff_files(left_path, right_path, opts \\ []) do
    with {:ok, left} <- summary_file(left_path, opts),
         {:ok, right} <- summary_file(right_path, opts) do
      {:ok, diff(left, right)}
    end
  end

  @spec diff(map(), map()) :: map()
  def diff(left, right) do
    sections = diff_group(Map.fetch!(left, :sections), Map.fetch!(right, :sections))
    counts = count_diff(Map.fetch!(left, :counts), Map.fetch!(right, :counts))
    registries = diff_group(Map.fetch!(left, :registries), Map.fetch!(right, :registries))

    choice_source_policies =
      choice_source_policy_diff(
        Map.get(left, :choice_source_policies, %{}),
        Map.get(right, :choice_source_policies, %{})
      )

    diagnostics = %{
      artifact:
        diagnostic_summary_diff(
          get_in(left, [:diagnostics, :artifact]) || %{},
          get_in(right, [:diagnostics, :artifact]) || %{}
        ),
      current:
        diagnostic_summary_diff(
          get_in(left, [:diagnostics, :current]) || %{},
          get_in(right, [:diagnostics, :current]) || %{}
        )
    }

    diff = %{
      left: diff_identity(left),
      right: diff_identity(right),
      sections: sections,
      counts: counts,
      registries: registries,
      choice_source_policies: choice_source_policies,
      diagnostics: diagnostics
    }

    Map.put(diff, :changed?, diff_changed?(diff))
  end

  @spec encode!(map(), keyword()) :: String.t()
  def encode!(artifact, opts \\ []) do
    pretty? = Keyword.get(opts, :pretty, true)
    Jason.encode!(artifact, pretty: pretty?)
  end

  @spec json_safe(term()) :: term()
  def json_safe(value), do: json_value(value)

  @spec format_error(artifact_error()) :: String.t()
  def format_error(:selecto_domain_unavailable) do
    "Selecto.Domain.normalize/1 is unavailable. Add or load the selecto dependency for this project."
  end

  def format_error({:module_not_loaded, module}) do
    "Domain module #{inspect(module)} could not be loaded"
  end

  def format_error({:missing_domain_function, module}) do
    "Domain module #{inspect(module)} must export domain/0"
  end

  def format_error({:normalization_failed, diagnostics}) do
    "Domain normalization failed: #{inspect(diagnostics)}"
  end

  def format_error({:invalid_normalizer_result, result}) do
    "Selecto.Domain.normalize/1 returned an unexpected result: #{inspect(result)}"
  end

  def format_error({:read_failed, path, reason}) do
    "Could not read normalized domain JSON #{path}: #{inspect(reason)}"
  end

  def format_error({:decode_failed, path, reason}) do
    "Could not decode normalized domain JSON #{path}: #{Exception.message(reason)}"
  end

  def format_error(:invalid_artifact) do
    "Normalized domain JSON artifact must be a JSON object"
  end

  def format_error({:invalid_artifact_format, format}) do
    "Unexpected normalized domain artifact format #{inspect(format)}"
  end

  def format_error({:unsupported_artifact_version, version}) do
    "Unsupported normalized domain artifact version #{inspect(version)}"
  end

  def format_error(:missing_artifact_domain) do
    "Normalized domain JSON artifact is missing a domain object"
  end

  def format_error({:invalid_artifact_domain, domain}) do
    "Normalized domain JSON artifact domain must be an object, got: #{inspect(domain)}"
  end

  defp domain_module(module) when is_atom(module), do: {:ok, module}

  defp domain_module(module) when is_binary(module) do
    {:ok, Module.concat([module])}
  end

  defp ensure_domain_module(module) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, {:module_not_loaded, module}}
    end
  end

  defp domain_from_module(module) do
    if function_exported?(module, :domain, 0) do
      {:ok, apply(module, :domain, [])}
    else
      {:error, {:missing_domain_function, module}}
    end
  end

  defp normalize_domain(domain, normalizer) do
    cond do
      not Code.ensure_loaded?(normalizer) or not function_exported?(normalizer, :normalize, 1) ->
        {:error, :selecto_domain_unavailable}

      true ->
        case apply(normalizer, :normalize, [domain]) do
          {:ok, normalized, diagnostics} when is_map(normalized) ->
            {:ok, normalized, diagnostics}

          {:error, diagnostics} ->
            {:error, {:normalization_failed, diagnostics}}

          other ->
            {:error, {:invalid_normalizer_result, other}}
        end
    end
  end

  defp artifact(module, normalized, diagnostics) do
    domain = Map.get(normalized, :domain) || Map.get(normalized, "domain") || normalized
    schema_version = Map.get(normalized, :schema_version) || Map.get(normalized, "schema_version")
    domain_version = Map.get(normalized, :domain_version) || map_get(domain, "domain_version")

    domain_fingerprint =
      Map.get(normalized, :domain_fingerprint) || map_get(domain, "domain_fingerprint")

    %{
      "format" => @format,
      "format_version" => @format_version,
      "domain_module" => inspect(module),
      "schema_version" => json_value(schema_version),
      "domain" => json_value(domain),
      "diagnostics" => json_value(diagnostics)
    }
    |> maybe_put("domain_version", json_value(domain_version))
    |> maybe_put("domain_fingerprint", json_value(domain_fingerprint))
  end

  defp round_trip_artifact(artifact, normalizer) do
    with {:ok, encoded} <- Jason.encode(artifact),
         {:ok, decoded} <- Jason.decode(encoded),
         {:ok, check} <- check_artifact(decoded, normalizer: normalizer) do
      {:ok, check}
    else
      {:error, reason} -> {:error, reason}
    end
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

  defp validate_artifact_envelope(%{} = artifact) do
    cond do
      Map.get(artifact, "format") != @format ->
        {:error, {:invalid_artifact_format, Map.get(artifact, "format")}}

      Map.get(artifact, "format_version") != @format_version ->
        {:error, {:unsupported_artifact_version, Map.get(artifact, "format_version")}}

      true ->
        :ok
    end
  end

  defp validate_artifact_envelope(_artifact), do: {:error, :invalid_artifact}

  defp artifact_domain(artifact) do
    case Map.fetch(artifact, "domain") do
      {:ok, domain} when is_map(domain) -> {:ok, domain}
      {:ok, domain} -> {:error, {:invalid_artifact_domain, domain}}
      :error -> {:error, :missing_artifact_domain}
    end
  end

  defp sections_summary(artifact_diagnostics, current_diagnostics) do
    %{
      canonical: diagnostic_list(artifact_diagnostics, :canonical_sections, current_diagnostics),
      projection:
        diagnostic_list(artifact_diagnostics, :projection_sections, current_diagnostics),
      proposed: diagnostic_list(artifact_diagnostics, :proposed_sections, current_diagnostics),
      unknown: diagnostic_list(artifact_diagnostics, :unknown_sections, current_diagnostics)
    }
  end

  defp diagnostic_list(diagnostics, key, fallback_diagnostics) do
    case diagnostic_value(diagnostics, key, nil) do
      nil -> diagnostic_value(fallback_diagnostics, key, [])
      value -> value
    end
    |> list_or_empty()
    |> Enum.map(&to_string/1)
  end

  defp counts_summary(domain) do
    query_members = map_get(domain, "query_members", %{})
    writes = map_get(domain, "writes", %{})

    %{
      source_fields: domain |> map_get("source", %{}) |> map_get("fields", []) |> count_list(),
      source_columns: domain |> map_get("source", %{}) |> map_get("columns", %{}) |> count_map(),
      schemas: domain |> map_get("schemas", %{}) |> count_map(),
      joins: domain |> map_get("joins", %{}) |> count_map(),
      filters: domain |> map_get("filters", %{}) |> count_map(),
      functions: domain |> map_get("functions", %{}) |> count_map(),
      query_members: count_query_members(query_members),
      published_views: domain |> map_get("published_views", %{}) |> count_map(),
      detail_actions: domain |> map_get("detail_actions", %{}) |> count_map(),
      write_operations: writes |> map_get("operations", %{}) |> count_map(),
      write_fields: writes |> map_get("fields", %{}) |> count_map(),
      write_relationships: writes |> map_get("relationships", %{}) |> count_map(),
      write_transitions: writes |> map_get("transitions", %{}) |> count_map(),
      write_validations: writes |> map_get("validations", []) |> count_list(),
      write_constraints: writes |> map_get("constraints", []) |> count_list(),
      write_scope: writes |> map_get("scope", %{}) |> count_map(),
      write_hooks: writes |> map_get("hooks", %{}) |> count_map(),
      actions: domain |> map_get("actions", %{}) |> count_map(),
      capabilities: domain |> map_get("capabilities", %{}) |> count_map(),
      source_relationships: domain |> map_get("source_relationships", %{}) |> count_map(),
      choice_sources: domain |> map_get("choice_sources", %{}) |> count_map()
    }
  end

  defp registries_summary(domain) do
    writes = map_get(domain, "writes", %{})

    %{
      joins: registry_names(domain, "joins"),
      filters: registry_names(domain, "filters"),
      functions: registry_names(domain, "functions"),
      query_members: query_member_names(map_get(domain, "query_members", %{})),
      published_views: registry_names(domain, "published_views"),
      detail_actions: registry_names(domain, "detail_actions"),
      write_operations: registry_names(writes, "operations"),
      write_fields: registry_names(writes, "fields"),
      write_relationships: registry_names(writes, "relationships"),
      write_transitions: registry_names(writes, "transitions"),
      write_scope: registry_names(writes, "scope"),
      write_hooks: registry_names(writes, "hooks"),
      actions: registry_names(domain, "actions"),
      capabilities: registry_names(domain, "capabilities"),
      source_relationships: registry_names(domain, "source_relationships"),
      choice_sources: registry_names(domain, "choice_sources")
    }
  end

  defp choice_source_policy_summary(domain) do
    case map_get(domain, "choice_sources", %{}) do
      choice_sources when is_map(choice_sources) ->
        choice_sources
        |> Enum.map(fn {id, choice_source} ->
          {to_string(id), choice_source_policy(choice_source)}
        end)
        |> Map.new()

      _choice_sources ->
        %{}
    end
  end

  defp choice_source_policy(choice_source) when is_map(choice_source) do
    choice_source
    |> map_get("constraint_policy", %{})
    |> format_policy()
  end

  defp choice_source_policy(_choice_source), do: ""

  defp security_review_summary(domain) do
    [
      security_registry("actions", domain),
      security_registry("capabilities", domain),
      security_registry("choice_sources", domain),
      security_registry("detail_actions", domain),
      security_registry("source_relationships", domain),
      security_writes(map_get(domain, "writes", %{}))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp security_registry(section, domain) do
    items =
      domain
      |> map_get(section, %{})
      |> registry_names()

    case items do
      [] ->
        nil

      items ->
        %{
          section: section,
          count: length(items),
          items: items,
          reason: Map.fetch!(@security_sensitive_sections, section)
        }
    end
  end

  defp security_writes(writes) when is_map(writes) do
    items =
      %{
        "operations" => registry_names(writes, "operations"),
        "fields" => registry_names(writes, "fields"),
        "transitions" => registry_names(writes, "transitions"),
        "validations_count" => writes |> map_get("validations", []) |> count_list(),
        "constraints_count" => writes |> map_get("constraints", []) |> count_list()
      }
      |> maybe_put_nonempty("relationships", registry_names(writes, "relationships"))
      |> maybe_put_nonempty("scope", registry_names(writes, "scope"))
      |> maybe_put_nonempty("hooks", registry_names(writes, "hooks"))

    count =
      length(Map.fetch!(items, "operations")) +
        length(Map.fetch!(items, "fields")) +
        length(Map.get(items, "relationships", [])) +
        length(Map.fetch!(items, "transitions")) +
        Map.fetch!(items, "validations_count") +
        Map.fetch!(items, "constraints_count") +
        length(Map.get(items, "scope", [])) +
        length(Map.get(items, "hooks", []))

    if count > 0 do
      %{
        section: "writes",
        count: count,
        items: items,
        reason: Map.fetch!(@security_sensitive_sections, "writes")
      }
    end
  end

  defp security_writes(_writes), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_nonempty(map, _key, []), do: map
  defp maybe_put_nonempty(map, key, value), do: Map.put(map, key, value)

  defp diagnostics_summary(diagnostics) do
    errors = diagnostic_items(diagnostics, :errors)
    warnings = diagnostic_items(diagnostics, :warnings)

    %{
      errors: length(errors),
      warnings: length(warnings),
      error_codes: diagnostic_codes(errors),
      warning_codes: diagnostic_codes(warnings)
    }
  end

  defp diagnostic_items(diagnostics, key) do
    diagnostics
    |> diagnostic_value(key, [])
    |> list_or_empty()
  end

  defp diagnostic_codes(diagnostics) do
    diagnostics
    |> Enum.map(&diagnostic_value(&1, :code, nil))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp diagnostic_value(%_struct{} = value, key, default) do
    value
    |> Map.from_struct()
    |> diagnostic_value(key, default)
  end

  defp diagnostic_value(value, key, default), do: map_get(value, Atom.to_string(key), default)

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

  defp query_member_names(query_members) when is_map(query_members) do
    query_members
    |> Enum.flat_map(fn {group, members} ->
      members
      |> registry_names()
      |> Enum.map(&"#{group}.#{&1}")
    end)
    |> Enum.sort()
  end

  defp query_member_names(_query_members), do: []

  defp registry_names(domain, key) when is_map(domain) do
    domain
    |> map_get(key, %{})
    |> registry_names()
  end

  defp registry_names(registry) when is_map(registry) do
    registry
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp registry_names(_registry), do: []

  defp count_map(value) when is_map(value), do: map_size(value)
  defp count_map(_value), do: 0

  defp count_list(value) when is_list(value), do: length(value)
  defp count_list(_value), do: 0

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_value), do: []

  defp diff_identity(summary) do
    %{
      path: Map.get(summary, :path),
      domain_module: Map.get(summary, :domain_module),
      schema_version: Map.get(summary, :schema_version),
      domain_version: Map.get(summary, :domain_version),
      domain_fingerprint: Map.get(summary, :domain_fingerprint),
      name: Map.get(summary, :name)
    }
  end

  defp diff_group(left, right) do
    left
    |> diff_keys(right)
    |> Map.new(fn key ->
      {key, list_diff(Map.get(left, key, []), Map.get(right, key, []))}
    end)
  end

  defp count_diff(left, right) do
    left
    |> diff_keys(right)
    |> Map.new(fn key ->
      left_value = numeric_value(Map.get(left, key, 0))
      right_value = numeric_value(Map.get(right, key, 0))

      {key, %{left: left_value, right: right_value, delta: right_value - left_value}}
    end)
  end

  defp diagnostic_summary_diff(left, right) do
    %{
      errors: count_item_diff(left, right, :errors),
      warnings: count_item_diff(left, right, :warnings),
      error_codes: list_diff(Map.get(left, :error_codes, []), Map.get(right, :error_codes, [])),
      warning_codes:
        list_diff(Map.get(left, :warning_codes, []), Map.get(right, :warning_codes, []))
    }
  end

  defp choice_source_policy_diff(left, right) do
    common_ids =
      left
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(right |> Map.keys() |> MapSet.new())
      |> MapSet.to_list()
      |> Enum.sort()

    changed =
      Enum.flat_map(common_ids, fn id ->
        left_policy = Map.get(left, id, "")
        right_policy = Map.get(right, id, "")

        if left_policy == right_policy do
          []
        else
          [%{id: id, left: left_policy, right: right_policy}]
        end
      end)

    %{changed: changed}
  end

  defp count_item_diff(left, right, key) do
    left_value = numeric_value(Map.get(left, key, 0))
    right_value = numeric_value(Map.get(right, key, 0))

    %{left: left_value, right: right_value, delta: right_value - left_value}
  end

  defp list_diff(left, right) do
    left_values = normalize_diff_list(left)
    right_values = normalize_diff_list(right)

    %{
      added: right_values -- left_values,
      removed: left_values -- right_values
    }
  end

  defp normalize_diff_list(values) do
    values
    |> list_or_empty()
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp diff_keys(left, right) do
    left
    |> Map.keys()
    |> Kernel.++(Map.keys(right))
    |> Enum.uniq()
    |> Enum.sort_by(&to_string/1)
  end

  defp numeric_value(value) when is_number(value), do: value
  defp numeric_value(_value), do: 0

  defp format_policy(policy) when is_map(policy) do
    policy
    |> Enum.map(fn {key, value} -> "#{format_policy_part(key)}=#{format_policy_part(value)}" end)
    |> Enum.sort()
    |> Enum.join(", ")
  end

  defp format_policy(_policy), do: ""

  defp format_policy_part(value) when is_binary(value), do: value
  defp format_policy_part(value) when is_atom(value), do: Atom.to_string(value)
  defp format_policy_part(value), do: inspect(value)

  defp diff_changed?(diff) do
    changed_diff_group?(Map.fetch!(diff, :sections)) or
      changed_count_diff?(Map.fetch!(diff, :counts)) or
      changed_diff_group?(Map.fetch!(diff, :registries)) or
      changed_choice_source_policy_diff?(Map.fetch!(diff, :choice_source_policies)) or
      changed_diagnostics_diff?(Map.fetch!(diff, :diagnostics))
  end

  defp changed_choice_source_policy_diff?(%{changed: changed}), do: changed != []

  defp changed_diff_group?(group) do
    Enum.any?(group, fn {_key, %{added: added, removed: removed}} ->
      added != [] or removed != []
    end)
  end

  defp changed_count_diff?(counts) do
    Enum.any?(counts, fn {_key, %{delta: delta}} -> delta != 0 end)
  end

  defp changed_diagnostics_diff?(diagnostics) do
    Enum.any?(diagnostics, fn {_kind, diff} ->
      changed_count_diff?(Map.take(diff, [:errors, :warnings])) or
        changed_diff_group?(Map.take(diff, [:error_codes, :warning_codes]))
    end)
  end

  defp json_value(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> json_value()
  end

  defp json_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, value} -> {json_key(key), json_value(value)} end)
    |> Enum.into(%{})
  end

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> json_value()
  end

  defp json_value(value) when is_function(value) do
    function_info =
      value
      |> Function.info()
      |> Map.new()
      |> Map.take([:module, :name, :arity, :type])

    %{
      "$selecto_export" => "function",
      "inspect" => inspect(value),
      "function" => json_value(function_info)
    }
  end

  defp json_value(value) when is_pid(value) or is_port(value) or is_reference(value) do
    %{
      "$selecto_export" => "term",
      "type" => value |> term_type() |> Atom.to_string(),
      "inspect" => inspect(value)
    }
  end

  defp json_value(value) when is_atom(value), do: atom_value(value)
  defp json_value(value), do: value

  defp atom_value(nil), do: nil
  defp atom_value(true), do: true
  defp atom_value(false), do: false
  defp atom_value(value), do: Atom.to_string(value)

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)

  defp map_get(map, key, default \\ nil), do: ArtifactJSON.map_get(map, key, default)

  defp term_type(value) when is_pid(value), do: :pid
  defp term_type(value) when is_port(value), do: :port
  defp term_type(value) when is_reference(value), do: :reference
end
