defmodule SelectoMix.Verification.ArtifactDeterminismTest do
  use ExUnit.Case, async: true

  test "proves artifact determinism across the complete key-shape model" do
    report = SelectoMix.Verification.ArtifactDeterminism.verify()

    assert report.state_count == 8
    assert report.invariant_count == 2
    assert report.check_count == 16
    assert report.proved?, inspect(report.counterexamples, pretty: true)
  end
end
