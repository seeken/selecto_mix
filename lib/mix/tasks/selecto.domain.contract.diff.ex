defmodule Mix.Tasks.Selecto.Domain.Contract.Diff do
  @shortdoc "Diff two published domain contract snapshots"
  @moduledoc """
  Diff two published domain contract snapshots.

  ## Examples

      mix selecto.domain.contract.diff priv/selecto_contracts/billing.old.json priv/selecto_contracts/billing.new.json
  """

  use Mix.Task

  alias SelectoMix.DomainContractVerification

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {_opts, positional} = SelectoMix.CLI.parse!(args, strict: [])

    if length(positional) != 2 do
      Mix.raise("Usage: mix selecto.domain.contract.diff old.snapshot.json new.snapshot.json")
    else
      [left_path, right_path] = positional
      diff(left_path, right_path)
    end
  end

  defp diff(left_path, right_path) do
    case DomainContractVerification.diff_snapshot_files(left_path, right_path) do
      {:ok, diff} ->
        print_diff(diff)

      {:error, reason} ->
        Mix.raise(DomainContractVerification.format_error(reason))
    end
  end

  defp print_diff(diff) do
    Mix.shell().info("Domain contract snapshot diff")
    Mix.shell().info("Changed: #{Map.fetch!(diff, :changed?)}")
    Mix.shell().info("Breaking: #{Map.fetch!(diff, :breaking?)}")

    surfaces = Map.fetch!(diff, :surfaces)
    print_list("Added surfaces", Map.get(surfaces, :added, []), "+")
    print_list("Removed surfaces", Map.get(surfaces, :removed, []), "-")

    changed = Map.get(surfaces, :changed, [])
    Mix.shell().info("Changed surfaces:")

    if changed == [] do
      Mix.shell().info("  (none)")
    else
      Enum.each(changed, &print_surface_change/1)
    end
  end

  defp print_surface_change(change) do
    Mix.shell().info("  #{Map.fetch!(change, :contract)}: #{Map.fetch!(change, :classification)}")

    change
    |> Map.get(:changes, [])
    |> Enum.each(fn item ->
      Mix.shell().info("    - #{Map.get(item, :kind)}#{change_detail(item)}")
    end)
  end

  defp change_detail(item) do
    cond do
      Map.has_key?(item, :field) ->
        " #{Map.fetch!(item, :field)}"

      Map.has_key?(item, :value) ->
        " #{Map.fetch!(item, :value)}"

      true ->
        ""
    end
  end

  defp print_list(label, [], _prefix) do
    Mix.shell().info("#{label}: (none)")
  end

  defp print_list(label, values, prefix) do
    Mix.shell().info("#{label}:")
    Enum.each(values, &Mix.shell().info("  #{prefix} #{&1}"))
  end
end
