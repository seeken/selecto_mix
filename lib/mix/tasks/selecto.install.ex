defmodule Mix.Tasks.Selecto.Install do
  @shortdoc "Install Selecto dependencies and integrate assets"
  @moduledoc """
  Install Selecto ecosystem dependencies and run SelectoComponents asset integration.

  This task updates `mix.exs` dependencies, optionally sets up development-mode
  path dependencies in `vendor/`, and runs `mix selecto.components.integrate`.

  ## Examples

      mix selecto.install
      mix selecto.install --postgis
      mix selecto.install --development-mode --source my-github-user
      mix selecto.install --check

  ## Options

    * `--postgis` - Include `selecto_postgis`
    * `--development-mode` - Use local `vendor/` path dependencies and clone repos
    * `--source` - GitHub owner for development mode clones (default: `selecto-elixir`)
    * `--check` - Show what would change without writing files
  """

  use Igniter.Mix.Task

  @default_source "selecto-elixir"

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.install --development-mode --source my-fork",
      schema: [
        postgis: :boolean,
        development_mode: :boolean,
        source: :string,
        check: :boolean
      ],
      aliases: [
        p: :postgis,
        d: :development_mode,
        s: :source,
        c: :check
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options
    check? = opts[:check] == true
    postgis? = opts[:postgis] == true
    development_mode? = opts[:development_mode] == true
    source = opts[:source] || @default_source

    dep_specs = dependency_specs(development_mode?, postgis?)

    igniter =
      case update_mix_deps(dep_specs, check?) do
        :ok ->
          igniter

        {:error, reason} ->
          Igniter.add_warning(igniter, "Could not update mix.exs deps: #{reason}")
      end

    igniter =
      if development_mode? do
        clone_vendor_repos(dep_specs, source, check?)
        Igniter.add_notice(igniter, "Development mode enabled (source: #{source})")
      else
        igniter
      end

    if check? do
      Mix.Task.run("selecto.components.integrate", ["--check"])
      Igniter.add_notice(igniter, "Check complete. No files were modified.")
    else
      Mix.Task.run("selecto.components.integrate", [])

      Igniter.add_notice(
        igniter,
        """
        Selecto install complete.

        Next steps:
          1. Run `mix deps.get`
          2. Run `cd assets && npm install`
          3. Run `mix assets.build`
        """
      )
    end
  end

  defp dependency_specs(development_mode?, postgis?) do
    base_specs =
      if development_mode? do
        [
          %{
            app: :selecto,
            repo: "selecto",
            dep: "{:selecto, path: \"./vendor/selecto\", override: true}"
          },
          %{
            app: :selecto_components,
            repo: "selecto_components",
            dep: "{:selecto_components, path: \"./vendor/selecto_components\", override: true}"
          }
        ]
      else
        [
          %{
            app: :selecto,
            repo: nil,
            dep: "{:selecto, \">= 0.3.3 and < 0.4.0\", override: true}"
          },
          %{
            app: :selecto_components,
            repo: nil,
            dep: "{:selecto_components, \">= 0.3.7 and < 0.4.0\", override: true}"
          }
        ]
      end

    if postgis? do
      postgis_spec =
        if development_mode? do
          %{
            app: :selecto_postgis,
            repo: "selecto_postgis",
            dep: "{:selecto_postgis, path: \"./vendor/selecto_postgis\", override: true}"
          }
        else
          %{
            app: :selecto_postgis,
            repo: nil,
            dep: "{:selecto_postgis, \"~> 0.1\", override: true}"
          }
        end

      base_specs ++ [postgis_spec]
    else
      base_specs
    end
  end

  defp update_mix_deps(specs, check?) do
    mix_file = "mix.exs"

    with {:ok, content} <- File.read(mix_file),
         {:ok, updated} <- rewrite_deps_content(content, specs) do
      if check? do
        if updated == content do
          Mix.shell().info("✓ mix.exs dependencies already configured")
        else
          Mix.shell().info("⚠ mix.exs would be updated with Selecto dependencies")
        end

        :ok
      else
        if updated == content do
          Mix.shell().info("✓ mix.exs dependencies already configured")
          :ok
        else
          File.write!(mix_file, updated)
          Mix.shell().info("✓ Updated mix.exs dependencies")
          :ok
        end
      end
    else
      {:error, _} = error -> error
    end
  end

  defp rewrite_deps_content(content, specs) do
    regex = ~r/(defp\s+deps\s+do\s*\n\s*\[)([\s\S]*?)(\n\s*\]\s*\n\s*end)/m

    case Regex.run(regex, content, capture: :all_but_first) do
      [prefix, body, suffix] ->
        apps = Enum.map(specs, & &1.app)

        filtered_body_lines =
          body
          |> String.split("\n")
          |> Enum.reject(&dep_line_matches_apps?(&1, apps))
          |> Enum.reject(&(String.trim(&1) == ""))

        new_dep_lines = Enum.map(specs, fn spec -> "      #{spec.dep}," end)

        combined_lines =
          (filtered_body_lines ++ new_dep_lines)
          |> Enum.map(&normalize_dep_line/1)

        new_body =
          case combined_lines do
            [] ->
              ""

            lines ->
              "\n" <> Enum.join(lines, "\n")
          end

        updated = Regex.replace(regex, content, "#{prefix}#{new_body}#{suffix}", global: false)
        {:ok, updated}

      _ ->
        {:error, "Could not locate `defp deps do ... end` block"}
    end
  end

  defp dep_line_matches_apps?(line, apps) do
    Enum.any?(apps, fn app ->
      String.contains?(line, "{:#{app},")
    end)
  end

  defp normalize_dep_line(line) do
    trimmed_trailing = String.trim_trailing(line)
    trimmed = String.trim(trimmed_trailing)

    cond do
      trimmed == "" ->
        ""

      String.starts_with?(trimmed, "#") ->
        trimmed_trailing

      String.starts_with?(trimmed, "{:") and not String.ends_with?(trimmed, ",") ->
        trimmed_trailing <> ","

      true ->
        trimmed_trailing
    end
  end

  defp clone_vendor_repos(specs, source, check?) do
    File.mkdir_p!("vendor")

    specs
    |> Enum.filter(&(is_binary(&1.repo) and &1.repo != ""))
    |> Enum.each(fn spec ->
      dest = Path.join("vendor", spec.repo)
      repo_url = "https://github.com/#{source}/#{spec.repo}.git"

      cond do
        File.dir?(dest) ->
          Mix.shell().info("✓ #{dest} already exists")

        check? ->
          Mix.shell().info("⚠ would clone #{repo_url} into #{dest}")

        true ->
          case System.cmd("git", ["clone", repo_url, dest], stderr_to_stdout: true) do
            {_out, 0} ->
              Mix.shell().info("✓ cloned #{repo_url} -> #{dest}")

            {out, code} ->
              Mix.shell().error("✗ failed to clone #{repo_url} (exit #{code})\n#{out}")
          end
      end
    end)
  end
end
