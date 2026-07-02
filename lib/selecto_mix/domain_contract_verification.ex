defmodule SelectoMix.DomainContractVerification do
  @moduledoc """
  Artifact-first helpers for Selecto domain contract verification.
  """

  alias SelectoMix.DomainExport

  @verifier Selecto.Domain.ContractVerification
  @snapshot_format "selecto.domain_contract_snapshot"
  @snapshot_format_version 1

  @type verification_error ::
          DomainExport.artifact_error()
          | :contract_verification_unavailable
          | :invalid_snapshot
          | {:invalid_snapshot_format, term()}
          | {:unsupported_snapshot_version, term()}
          | {:snapshot_read_failed, Path.t(), term()}
          | {:snapshot_decode_failed, Path.t(), term()}
          | {:write_failed, Path.t(), term()}

  @spec verify_files(Path.t(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, verification_error() | map()}
  def verify_files(provider_path, consumer_path, opts \\ []) do
    with {:ok, provider} <- DomainExport.check_file(provider_path, opts),
         {:ok, consumer} <- DomainExport.check_file(consumer_path, opts),
         :ok <- ensure_verifier(),
         result <- apply(@verifier, :verify, [provider.normalized, consumer.normalized, opts]) do
      result
    end
  end

  @spec snapshot_file(Path.t(), keyword()) ::
          {:ok, map()} | {:error, verification_error() | map()}
  def snapshot_file(provider_path, opts \\ []) do
    with {:ok, provider} <- DomainExport.check_file(provider_path, opts),
         :ok <- ensure_verifier(),
         {:ok, snapshot} <- apply(@verifier, :snapshot, [provider.normalized, opts]) do
      {:ok, DomainExport.json_safe(snapshot)}
    end
  end

  @spec write_snapshot_file(Path.t(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, verification_error() | map()}
  def write_snapshot_file(provider_path, output_path, opts \\ []) do
    with {:ok, snapshot} <- snapshot_file(provider_path, opts),
         :ok <- write_json(output_path, snapshot, opts) do
      {:ok, snapshot}
    end
  end

  @spec diff_snapshot_files(Path.t(), Path.t()) :: {:ok, map()} | {:error, verification_error()}
  def diff_snapshot_files(left_path, right_path) do
    with {:ok, left} <- read_snapshot(left_path),
         {:ok, right} <- read_snapshot(right_path),
         :ok <- ensure_verifier() do
      {:ok, apply(@verifier, :diff_snapshots, [left, right])}
    end
  end

  @spec format_error(verification_error() | map()) :: String.t()
  def format_error(:contract_verification_unavailable) do
    "Selecto.Domain.ContractVerification is unavailable. Add or load a Selecto version with contract verification support."
  end

  def format_error(:invalid_snapshot) do
    "Domain contract snapshot must be a JSON object"
  end

  def format_error({:invalid_snapshot_format, format}) do
    "Unexpected domain contract snapshot format #{inspect(format)}"
  end

  def format_error({:unsupported_snapshot_version, version}) do
    "Unsupported domain contract snapshot version #{inspect(version)}"
  end

  def format_error({:snapshot_read_failed, path, reason}) do
    "Could not read domain contract snapshot #{path}: #{inspect(reason)}"
  end

  def format_error({:snapshot_decode_failed, path, reason}) do
    "Could not decode domain contract snapshot #{path}: #{Exception.message(reason)}"
  end

  def format_error({:write_failed, path, reason}) do
    "Could not write domain contract snapshot #{path}: #{inspect(reason)}"
  end

  def format_error(%{errors: errors}) when is_list(errors) do
    "Domain contract verification failed with #{length(errors)} error(s)"
  end

  def format_error(reason), do: DomainExport.format_error(reason)

  defp ensure_verifier do
    if Code.ensure_loaded?(@verifier) and
         function_exported?(@verifier, :verify, 3) and
         function_exported?(@verifier, :snapshot, 2) and
         function_exported?(@verifier, :diff_snapshots, 2) do
      :ok
    else
      {:error, :contract_verification_unavailable}
    end
  end

  defp write_json(path, artifact, opts) do
    contents = DomainExport.encode!(artifact, pretty: Keyword.get(opts, :pretty, true))
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, contents) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  defp read_snapshot(path) do
    with {:ok, contents} <- read_file(path),
         {:ok, artifact} <- decode_json(contents, path),
         :ok <- validate_snapshot(artifact) do
      {:ok, artifact}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, {:snapshot_read_failed, path, reason}}
    end
  end

  defp decode_json(contents, path) do
    case Jason.decode(contents) do
      {:ok, artifact} -> {:ok, artifact}
      {:error, reason} -> {:error, {:snapshot_decode_failed, path, reason}}
    end
  end

  defp validate_snapshot(%{} = snapshot) do
    cond do
      Map.get(snapshot, "format") != @snapshot_format ->
        {:error, {:invalid_snapshot_format, Map.get(snapshot, "format")}}

      Map.get(snapshot, "format_version") != @snapshot_format_version ->
        {:error, {:unsupported_snapshot_version, Map.get(snapshot, "format_version")}}

      true ->
        :ok
    end
  end

  defp validate_snapshot(_snapshot), do: {:error, :invalid_snapshot}
end
