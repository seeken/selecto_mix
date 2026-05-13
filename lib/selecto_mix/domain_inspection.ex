defmodule SelectoMix.DomainInspection do
  @moduledoc """
  Builds Studio/tooling inspection JSON from normalized Selecto domain artifacts.

  This module keeps the same artifact-first workflow as export/check/inspect/diff
  and delegates the actual structured inspection to `Selecto.Domain.describe/1`
  at runtime.
  """

  alias SelectoMix.DomainExport

  @format "selecto.domain_inspection"
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

  @type inspection_error ::
          DomainExport.artifact_error()
          | :selecto_domain_describer_unavailable
          | {:inspection_failed, term()}
          | {:invalid_describer_result, term()}

  @spec describe_file(Path.t(), keyword()) :: {:ok, map()} | {:error, inspection_error()}
  def describe_file(path, opts \\ []) do
    with {:ok, check} <- DomainExport.check_file(path, opts),
         {:ok, inspection, diagnostics} <- describe_normalized(check, opts) do
      {:ok, inspection_artifact(check, inspection, diagnostics)}
    end
  end

  @spec encode!(map(), keyword()) :: String.t()
  def encode!(inspection_artifact, opts \\ []) do
    DomainExport.encode!(inspection_artifact, opts)
  end

  @spec format_error(inspection_error()) :: String.t()
  def format_error(:selecto_domain_describer_unavailable) do
    "Selecto.Domain.describe/1 is unavailable. Add or load a selecto version with domain inspection support."
  end

  def format_error({:inspection_failed, diagnostics}) do
    "Domain inspection failed: #{inspect(diagnostics)}"
  end

  def format_error({:invalid_describer_result, result}) do
    "Selecto.Domain.describe/1 returned an unexpected result: #{inspect(result)}"
  end

  def format_error(reason), do: DomainExport.format_error(reason)

  defp describe_normalized(check, opts) do
    describer = Keyword.get(opts, :describer, Selecto.Domain)
    normalized = Map.fetch!(check, :normalized)

    cond do
      not Code.ensure_loaded?(describer) or not function_exported?(describer, :describe, 1) ->
        {:error, :selecto_domain_describer_unavailable}

      true ->
        case apply(describer, :describe, [normalized]) do
          {:ok, inspection, diagnostics} when is_map(inspection) ->
            {:ok, inspection, diagnostics}

          {:error, diagnostics} ->
            {:error, {:inspection_failed, diagnostics}}

          other ->
            {:error, {:invalid_describer_result, other}}
        end
    end
  end

  defp inspection_artifact(check, inspection, diagnostics) do
    artifact = Map.fetch!(check, :artifact)
    summary = DomainExport.summary(check)
    inspection = put_security_review(inspection, Map.get(artifact, "domain", %{}))

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
      "source" => source,
      "inspection" => DomainExport.json_safe(inspection),
      "diagnostics" => DomainExport.json_safe(diagnostics)
    }
  end

  defp put_security_review(inspection, domain) do
    case map_get(inspection, "security_review") do
      nil -> Map.put(inspection, :security_review, security_review(domain))
      _security_review -> inspection
    end
  end

  defp security_review(domain) do
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
      |> sorted_keys()

    case items do
      [] ->
        nil

      items ->
        %{
          "section" => section,
          "count" => length(items),
          "items" => items,
          "reason" => Map.fetch!(@security_sensitive_sections, section)
        }
    end
  end

  defp security_writes(writes) when is_map(writes) do
    items =
      %{
        "operations" => writes |> map_get("operations", %{}) |> sorted_keys(),
        "fields" => writes |> map_get("fields", %{}) |> sorted_keys(),
        "transitions" => writes |> map_get("transitions", %{}) |> sorted_keys(),
        "validations_count" => writes |> map_get("validations", []) |> list_count(),
        "constraints_count" => writes |> map_get("constraints", []) |> list_count()
      }
      |> maybe_put_nonempty(
        "relationships",
        writes |> map_get("relationships", %{}) |> sorted_keys()
      )
      |> maybe_put_nonempty("scope", writes |> map_get("scope", %{}) |> sorted_keys())
      |> maybe_put_nonempty("hooks", writes |> map_get("hooks", %{}) |> sorted_keys())

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
        "section" => "writes",
        "count" => count,
        "items" => items,
        "reason" => Map.fetch!(@security_sensitive_sections, "writes")
      }
    end
  end

  defp security_writes(_writes), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_nonempty(map, _key, []), do: map
  defp maybe_put_nonempty(map, key, value), do: Map.put(map, key, value)

  defp sorted_keys(value) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp sorted_keys(_value), do: []

  defp list_count(value) when is_list(value), do: length(value)
  defp list_count(_value), do: 0

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
