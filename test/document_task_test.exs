# These integration tests use the real host runtime, never a normalization stub.
# A tooling-only checkout can run the safety tests without an installed Selecto.
document_runtime_path =
  System.get_env("SELECTO_LIVE_SELECTO", Path.expand("../../selecto", __DIR__))

unless Code.ensure_loaded?(Selecto.Document.Draft) do
  files = ~w(
    missing canonical path numeric object_id native_inference_report inference_report
    inference shape_release fixtures draft drift
  )

  if Enum.all?(
       files,
       &File.regular?(Path.join([document_runtime_path, "lib/selecto/document", &1 <> ".ex"]))
     ) do
    Enum.each(files, fn name ->
      Code.require_file(Path.join([document_runtime_path, "lib/selecto/document", name <> ".ex"]))
    end)
  end
end

defmodule SelectoMix.DocumentTaskTest do
  use ExUnit.Case, async: false

  @runtime_available Code.ensure_loaded?(Selecto.Document.Draft)

  setup do
    directory =
      Path.join(System.tmp_dir!(), "selecto-document-cli-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, directory: directory}
  end

  defp json(directory, name, value) do
    path = Path.join(directory, name)
    File.write!(path, Jason.encode!(value))
    path
  end

  defp runtime(function), do: apply(Selecto.Document.Fixtures, function, [])

  @tag skip: not @runtime_available
  test "complete inspect, authored draft, check, approve and drift lifecycle uses real runtime",
       %{directory: dir} do
    fixture = json(dir, "fixture.json", runtime(:work_orders))
    authoring = json(dir, "authoring.json", runtime(:shape))
    report = Path.join(dir, "report.json")
    draft = Path.join(dir, "draft.json")
    release = Path.join(dir, "release.json")
    drift = Path.join(dir, "drift.json")

    Mix.Tasks.Selecto.Document.Inspect.run([fixture, "--output", report])
    report_value = report |> File.read!() |> Jason.decode!()
    refute File.read!(report) =~ "Replace pump"
    assert :ok = apply(Selecto.Document.InferenceReport, :validate, [report_value])

    Mix.Tasks.Selecto.Document.Draft.run([report, "--authoring", authoring, "--output", draft])
    Mix.Tasks.Selecto.Document.Check.run([draft])
    assert (draft |> File.read!() |> Jason.decode!())["status"] == "draft"

    Mix.Tasks.Selecto.Document.Approve.run([
      draft,
      "--reviewer",
      "fixture-reviewer",
      "--output",
      release
    ])

    approved = release |> File.read!() |> Jason.decode!()
    assert approved["status"] == "approved"
    assert approved["approval"]["approved_by"] == "fixture-reviewer"

    assert :ok =
             apply(Selecto.Document.ShapeRelease, :validate, [approved, [require_approved: true]])

    Mix.Tasks.Selecto.Document.Check.run([release])
    Mix.Tasks.Selecto.Document.Diff.run([release, report, "--output", drift])
    assert is_map(drift |> File.read!() |> Jason.decode!())
    assert File.read!(authoring) == Jason.encode!(runtime(:shape))
  end

  @tag skip: not @runtime_available
  test "explicit path exclusions remove field evidence and values", %{directory: dir} do
    fixture = json(dir, "fixture.json", [%{"id" => "a", "secret" => "private-value"}])
    excludes = json(dir, "excludes.json", [["secret"]])
    report = Path.join(dir, "report.json")

    Mix.Tasks.Selecto.Document.Inspect.run([
      fixture,
      "--output",
      report,
      "--excluded-paths",
      excludes,
      "--max-documents",
      "1"
    ])

    refute File.read!(report) =~ "private-value"
    value = report |> File.read!() |> Jason.decode!()
    refute Enum.any?(value["paths"], &(&1["path"] == ["secret"]))
  end

  test "unknown options, missing arguments and existing artifacts are rejected", %{directory: dir} do
    existing = json(dir, "existing.json", %{"keep" => true})
    assert_raise Mix.Error, fn -> Mix.Tasks.Selecto.Document.Inspect.run([]) end
    assert_raise Mix.Error, fn -> Mix.Tasks.Selecto.Document.Check.run([existing, "--force"]) end

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Selecto.Document.Inspect.run([existing, "--output", existing])
    end

    assert File.read!(existing) == ~s({"keep":true})

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Selecto.Document.Approve.run([existing, "--output", "new.json"])
    end
  end

  test "invalid JSON, directories and oversized files fail before runtime dispatch", %{
    directory: dir
  } do
    output = Path.join(dir, "output.json")
    invalid = Path.join(dir, "invalid.json")
    File.write!(invalid, "not json")

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Selecto.Document.Inspect.run([invalid, "--output", output])
    end

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Selecto.Document.Inspect.run([dir, "--output", output])
    end

    large = Path.join(dir, "large.json")
    File.write!(large, :binary.copy(" ", 8_000_001))

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Selecto.Document.Inspect.run([large, "--output", output])
    end

    refute File.exists?(output)
  end

  @tag skip: not @runtime_available
  test "approval rejects tampering and inference does not grant authoring policy", %{
    directory: dir
  } do
    forged = runtime(:release) |> Map.put("digest", String.duplicate("0", 64))
    path = json(dir, "forged.json", forged)
    output = Path.join(dir, "output.json")
    assert_raise Mix.Error, fn -> Mix.Tasks.Selecto.Document.Check.run([path]) end

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Selecto.Document.Approve.run([path, "--reviewer", "reviewer", "--output", output])
    end

    refute File.exists?(output)
  end
end
