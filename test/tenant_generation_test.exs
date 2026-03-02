defmodule SelectoMix.TenantGenerationTest do
  use ExUnit.Case, async: false

  test "filter_sets generator emits tenant-scoped domain helpers" do
    base_tmp = System.tmp_dir!()
    tmp_dir = Path.join(base_tmp, "selecto_mix_tenant_gen_#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      Mix.Task.reenable("selecto.gen.filter_sets")
      Mix.Tasks.Selecto.Gen.FilterSets.run(["TmpApp", "--no-migration", "--no-tests"])

      context_path = Path.join(["lib", "tmp_app", "tmp_app", "filter_sets.ex"])
      context_source = File.read!(context_path)

      assert context_source =~ "defp scoped_domain(domain)"
      assert context_source =~ "SelectoComponents.Tenant.scoped_context"
      assert context_source =~ "defp scope_attrs_domain(attrs)"
    end)

    File.rm_rf!(tmp_dir)
  end
end
