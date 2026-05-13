defmodule SelectoMix.StudioArtifactsGenerator do
  @moduledoc """
  Generates host-app glue for preloaded Selecto Studio domain artifacts.

  The generated provider module deliberately depends only on core `Selecto`
  domain APIs. Host apps can register it with `SelectoStudio.DomainArtifacts`
  when they use Studio, while generated domains remain usable without taking a
  runtime dependency on Studio.
  """

  @doc """
  Returns the provider module name for a generated domain module.
  """
  @spec artifact_module_name(module() | String.t()) :: String.t()
  def artifact_module_name(domain_module) do
    "#{module_ref(domain_module)}Artifacts"
  end

  @doc """
  Renders a domain inspection provider module for host-app Studio registration.
  """
  @spec provider_module(module() | String.t()) :: String.t()
  def provider_module(domain_module) do
    domain_module = module_ref(domain_module)
    artifact_module = artifact_module_name(domain_module)

    """
    defmodule #{artifact_module} do
      @moduledoc \"\"\"
      Trusted Selecto domain artifact provider for #{domain_module}.

      Register `inspection_artifact/0` with `SelectoStudio.DomainArtifacts` when
      this host app wants Studio to preload this domain. The provider uses core
      `Selecto.Domain` APIs directly so the domain itself does not depend on
      SelectoStudio.
      \"\"\"

      @domain_module #{domain_module}
      @format_version 1
      @inspection_format_version 1

      @spec inspection_artifact() :: {:ok, map()} | {:error, term()}
      def inspection_artifact do
        with {:ok, normalized, _normalize_diagnostics} <-
               Selecto.Domain.normalize(@domain_module.domain()),
             {:ok, inspection, diagnostics} <- Selecto.Domain.describe(normalized) do
          domain = Map.get(normalized, :domain) || Map.get(normalized, "domain") || normalized
          source =
            %{
              "artifact_format" => "selecto.normalized_domain",
              "artifact_format_version" => @format_version,
              "domain_module" => inspect(@domain_module),
              "schema_version" => json_value(Map.get(normalized, :schema_version)),
              "name" => json_value(map_value(domain, :name))
            }
            |> maybe_put("domain_version", json_value(Map.get(normalized, :domain_version)))
            |> maybe_put("domain_fingerprint", json_value(Map.get(normalized, :domain_fingerprint)))

          {:ok,
           %{
             "format" => "selecto.domain_inspection",
             "format_version" => @inspection_format_version,
             "source" => source,
             "inspection" => json_value(inspection),
             "diagnostics" => json_value(diagnostics),
             "links" => %{}
           }}
        end
      end

      defp json_value(%_struct{} = value) do
        value
        |> Map.from_struct()
        |> json_value()
      end

      defp json_value(value) when is_map(value) do
        Map.new(value, fn {key, item} -> {json_key(key), json_value(item)} end)
      end

      defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
      defp json_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_value()

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

      defp maybe_put(map, _key, nil), do: map
      defp maybe_put(map, key, value), do: Map.put(map, key, value)

      defp atom_value(nil), do: nil
      defp atom_value(true), do: true
      defp atom_value(false), do: false
      defp atom_value(value), do: Atom.to_string(value)

      defp json_key(value) when is_atom(value), do: Atom.to_string(value)
      defp json_key(value) when is_binary(value), do: value
      defp json_key(value), do: inspect(value)

      defp term_type(value) when is_pid(value), do: :pid
      defp term_type(value) when is_port(value), do: :port
      defp term_type(value) when is_reference(value), do: :reference

      defp map_value(map, key, default \\\\ nil)

      defp map_value(map, key, default) when is_map(map) and is_atom(key) do
        string_key = Atom.to_string(key)

        cond do
          Map.has_key?(map, key) -> Map.get(map, key)
          Map.has_key?(map, string_key) -> Map.get(map, string_key)
          true -> default
        end
      end

      defp map_value(_map, _key, default), do: default
    end
    """
  end

  @doc """
  Renders the host-app config and router snippets for Studio artifact preloading.
  """
  @spec integration_guidance(keyword()) :: String.t()
  def integration_guidance(opts) do
    domain_id = Keyword.fetch!(opts, :domain_id)
    domain_name = Keyword.fetch!(opts, :domain_name)
    artifact_module = module_ref(Keyword.fetch!(opts, :artifact_module))

    """

    Studio host-app artifact registration:

      # config/config.exs
      config :selecto_studio, :domain_artifacts,
        default: "#{domain_id}",
        domains: [
          %{
            id: "#{domain_id}",
            name: "#{domain_name}",
            inspection: {#{artifact_module}, :inspection_artifact, []}
          }
        ]

      # lib/*_web/router.ex
      scope "/" do
        pipe_through :browser

        get "/studio/domain-inspection",
            SelectoStudioWeb.DomainInspectionController,
            :show

        get "/studio/domain-inspection/:domain_id",
            SelectoStudioWeb.DomainInspectionController,
            :show

        post "/studio/domain-inspection",
             SelectoStudioWeb.DomainInspectionController,
             :create
      end
    """
  end

  defp module_ref(module) do
    module
    |> to_string()
    |> String.trim_leading("Elixir.")
  end
end
