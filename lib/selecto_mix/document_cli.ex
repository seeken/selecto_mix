defmodule SelectoMix.DocumentCLI do
  @moduledoc """
  Local JSON artifact lifecycle for reviewed document schemas.

  The host provides its Selecto runtime. Commands never open database connections,
  start the host application, sample a live source, or overwrite existing artifacts.
  Inputs are regular local files bounded to 8 MB; inference applies its own tighter
  structural and time budgets. Reports never collect source values.
  """

  @max_bytes 8_000_000
  @switches [
    output: :string,
    authoring: :string,
    reviewer: :string,
    max_documents: :integer,
    excluded_paths: :string
  ]

  def run(operation, args) when operation in [:inspect, :draft, :check, :approve, :diff] do
    {opts, positional} = SelectoMix.CLI.parse!(args, strict: @switches)
    validate_args!(operation, opts, positional)
    result = execute(operation, positional, opts)

    case result do
      {:ok, artifact} ->
        write_new!(Keyword.fetch!(opts, :output), artifact)

      :ok ->
        Mix.shell().info("Document release is valid: #{List.first(positional)}")

      {:error, reason} ->
        Mix.raise(
          "Document #{operation} failed: #{inspect(reason, limit: 20, printable_limit: 1000)}"
        )
    end
  end

  defp execute(:inspect, [path], opts) do
    documents = read_json!(path)
    unless is_list(documents), do: Mix.raise("Document fixture must be a JSON array")
    inference_opts = Keyword.take(opts, [:max_documents])

    exclusions =
      case Keyword.get(opts, :excluded_paths) do
        nil -> []
        path -> read_json!(path)
      end

    runtime(Selecto.Document.Inference, :run, [
      documents,
      Keyword.put(inference_opts, :excluded_paths, exclusions)
    ])
  end

  defp execute(:draft, [path], opts) do
    report = read_json!(path)
    authoring = read_json!(Keyword.fetch!(opts, :authoring))
    runtime(Selecto.Document.Draft, :build, [report, authoring])
  end

  defp execute(:check, [path], _opts),
    do: runtime(Selecto.Document.ShapeRelease, :validate, [read_json!(path)])

  defp execute(:approve, [path], opts),
    do:
      runtime(Selecto.Document.ShapeRelease, :approve, [
        read_json!(path),
        [approved_by: Keyword.fetch!(opts, :reviewer)]
      ])

  defp execute(:diff, [release, report], _opts),
    do: runtime(Selecto.Document.Drift, :compare, [read_json!(release), read_json!(report)])

  defp runtime(module, function, args) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)) do
      apply(module, function, args)
    else
      Mix.raise(
        "This command requires a host Selecto runtime providing #{inspect(module)}.#{function}/#{length(args)}"
      )
    end
  end

  defp validate_args!(operation, opts, positional) do
    expected_count = if operation == :diff, do: 2, else: 1

    allowed =
      case operation do
        :inspect -> [:output, :max_documents, :excluded_paths]
        :draft -> [:output, :authoring]
        :approve -> [:output, :reviewer]
        :check -> []
        :diff -> [:output]
      end

    required =
      case operation do
        :draft -> [:output, :authoring]
        :approve -> [:output, :reviewer]
        :check -> []
        _ -> [:output]
      end

    unless length(positional) == expected_count and
             Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and
             Enum.all?(required, &(is_binary(opts[&1]) and opts[&1] != "")) do
      Mix.raise(
        "Usage: mix selecto.document.#{operation} INPUT#{if operation == :diff, do: " REPORT", else: ""}#{if :output in required, do: " --output NEW_FILE", else: ""}#{if operation == :draft, do: " --authoring AUTHORING_JSON", else: ""}#{if operation == :approve, do: " --reviewer REVIEWER", else: ""}"
      )
    end

    if Keyword.has_key?(opts, :output) and File.exists?(opts[:output]),
      do: Mix.raise("Refusing to overwrite existing artifact: #{opts[:output]}")
  end

  defp read_json!(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size <= @max_bytes ->
        :ok

      {:ok, _} ->
        Mix.raise(
          "Input must be a regular local file no larger than #{@max_bytes} bytes: #{path}"
        )

      {:error, reason} ->
        Mix.raise("Cannot read artifact #{path}: #{:file.format_error(reason)}")
    end

    contents =
      case File.open(path, [:read, :binary], &IO.binread(&1, @max_bytes + 1)) do
        {:ok, bytes} when is_binary(bytes) and byte_size(bytes) <= @max_bytes -> bytes
        _ -> Mix.raise("Unable to read bounded artifact: #{path}")
      end

    case Jason.decode(contents) do
      {:ok, value} -> value
      {:error, _} -> Mix.raise("Artifact is not valid JSON: #{path}")
    end
  end

  defp write_new!(path, artifact) do
    contents = Jason.encode!(artifact, pretty: true) <> "\n"
    if byte_size(contents) > @max_bytes, do: Mix.raise("Output exceeds the artifact size limit")

    case File.write(path, contents, [:exclusive]) do
      :ok ->
        Mix.shell().info("Wrote document artifact: #{path}")

      {:error, :eexist} ->
        Mix.raise("Refusing to overwrite existing artifact: #{path}")

      {:error, reason} ->
        Mix.raise("Cannot write artifact #{path}: #{:file.format_error(reason)}")
    end
  end
end
