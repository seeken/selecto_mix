defmodule SelectoMix.Gen.DomainPaths do
  @moduledoc """
  Path and display-name helpers for `mix selecto.gen.domain` generated
  artifacts (domain files, Studio artifacts, docs/inspection/diagram paths).
  """

  alias SelectoMix.LiveViewGenerator

  def get_output_directory(igniter, custom_output) do
    case custom_output do
      nil ->
        app_name = Igniter.Project.Application.app_name(igniter)
        "lib/#{app_name}/selecto_domains"

      custom ->
        custom
    end
  end

  def display_source({:db, _adapter, _conn, table, _opts}), do: table
  def display_source({:db, _adapter, _conn, table}), do: table
  def display_source(source) when is_binary(source), do: source
  def display_source(source), do: inspect(source)
  def source_basename({:db, _adapter, _conn, table, _opts}), do: Macro.underscore(table)
  def source_basename({:db, _adapter, _conn, table}), do: Macro.underscore(table)
  def source_basename(source) when is_binary(source), do: Macro.underscore(source)

  def source_basename(source) do
    source
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
  end

  def source_display_name(source) do
    source
    |> LiveViewGenerator.source_live_name()
    |> Macro.underscore()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def domain_file_path(output_dir, source) do
    Path.join([output_dir, "#{source_basename(source)}_domain.ex"])
  end

  def studio_artifacts_file_path(output_dir, source) do
    Path.join([output_dir, "#{source_basename(source)}_domain_artifacts.ex"])
  end

  def domain_artifact_path(source) do
    Path.join(["priv", "selecto", "#{source_basename(source)}.normalized.json"])
  end

  def domain_docs_path(source) do
    Path.join(["docs", "selecto", "#{source_basename(source)}.md"])
  end

  def domain_inspection_path(source) do
    Path.join(["priv", "selecto", "#{source_basename(source)}.inspection.json"])
  end

  def domain_diagram_path(source) do
    Path.join(["docs", "selecto", "#{source_basename(source)}.diagram.mmd"])
  end

  def default_docs_path(artifact_path) do
    artifact_name = Path.basename(artifact_path, ".normalized.json")
    Path.join(["docs", "selecto", "#{artifact_name}.md"])
  end

  def default_inspection_path(artifact_path) do
    artifact_name = Path.basename(artifact_path, ".normalized.json")
    Path.join(["priv", "selecto", "#{artifact_name}.inspection.json"])
  end

  def default_diagram_path(artifact_path) do
    artifact_name = Path.basename(artifact_path, ".normalized.json")
    Path.join(["docs", "selecto", "#{artifact_name}.diagram.mmd"])
  end
end
