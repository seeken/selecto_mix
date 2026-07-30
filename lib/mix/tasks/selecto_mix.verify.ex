defmodule Mix.Tasks.SelectoMix.Verify do
  use Mix.Task

  @shortdoc "Runs SelectoMix bounded formal verification"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [output: :string])
    if rest != [] or invalid != [], do: Mix.raise("usage: mix selecto_mix.verify [--output PATH]")

    reports = [SelectoMix.Verification.ArtifactDeterminism.verify()]

    artifact = %{
      format: "selecto.formal_verification_suite",
      format_version: 1,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      proved?: Enum.all?(reports, & &1.proved?),
      reports: reports
    }

    Enum.each(reports, fn report ->
      status = if report.proved?, do: "PROVED", else: "FAILED"

      Mix.shell().info(
        "#{status} #{report.model}: #{report.check_count} checks (proof=#{report.proof_level})"
      )
    end)

    if path = opts[:output], do: write(path, artifact)
    unless artifact.proved?, do: Mix.raise("SelectoMix verification found counterexamples")
  end

  defp write(path, artifact) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode_to_iodata!(artifact, pretty: true))
    Mix.shell().info("Wrote verification artifact to #{path}")
  end
end
