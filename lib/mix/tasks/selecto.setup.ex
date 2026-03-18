defmodule Mix.Tasks.Selecto.Setup do
  @shortdoc "Run generated SQL setup files through a Selecto adapter"
  @moduledoc """
  Execute generated SQL files from `priv/sql/` using an explicit Selecto DB adapter.

  Examples:

      mix selecto.setup --adapter postgresql
      mix selecto.setup --adapter postgresql --database-url postgres://user:pass@localhost/mydb
      mix selecto.setup --adapter sqlite --file priv/sql/create_filter_sets.sql
      mix selecto.setup --adapter postgresql --dry-run
  """

  use Igniter.Mix.Task

  alias SelectoMix.{AdapterResolver, Connection, ConnectionOpts, SqlRunner}

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :selecto,
      example: "mix selecto.setup --adapter postgresql",
      schema:
        ConnectionOpts.connection_schema() ++
          [
            file: :string,
            sql_dir: :string,
            dry_run: :boolean
          ],
      aliases:
        ConnectionOpts.connection_aliases() ++
          [
            f: :file,
            d: :dry_run
          ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    parsed_args = Map.new(igniter.args.options)
    sql_dir = parsed_args[:sql_dir] || "priv/sql"

    with {:ok, adapter} <- resolve_adapter(parsed_args[:adapter]),
         {:ok, conn_opts} <- resolve_connection_opts(parsed_args) do
      if parsed_args[:dry_run] do
        show_dry_run(sql_dir, parsed_args[:file])
        igniter
      else
        case run_setup(adapter, conn_opts, sql_dir, parsed_args[:file]) do
          {:ok, msg} -> Igniter.add_notice(igniter, msg)
          {:error, msg} -> Igniter.add_warning(igniter, msg)
        end
      end
    else
      {:error, msg} -> Igniter.add_warning(igniter, msg)
    end
  end

  defp resolve_adapter(nil),
    do: {:error, "--adapter is required (for example: --adapter postgresql)"}

  defp resolve_adapter(adapter_name) do
    case AdapterResolver.resolve(adapter_name) do
      {:ok, adapter} -> {:ok, adapter}
      {:error, _} -> {:error, "Unsupported adapter #{inspect(adapter_name)}"}
    end
  end

  defp resolve_connection_opts(parsed_args) do
    conn_opts = ConnectionOpts.from_parsed_args(parsed_args)

    if conn_opts == [] do
      {:error,
       "No database connection configured. Provide DATABASE_URL or explicit connection flags."}
    else
      {:ok, conn_opts}
    end
  end

  defp show_dry_run(sql_dir, specific_file) do
    if specific_file do
      IO.puts("\nDRY RUN: Would execute SQL file: #{specific_file}")
    else
      files =
        Path.join(sql_dir, "*.sql")
        |> Path.wildcard()
        |> Enum.sort()

      if Enum.empty?(files) do
        IO.puts("\nDRY RUN: No SQL files found in #{sql_dir}/")
      else
        IO.puts("\nDRY RUN: Would execute #{length(files)} SQL file(s) from #{sql_dir}/:")
        Enum.each(files, &IO.puts("  * #{&1}"))
      end
    end
  end

  defp run_setup(adapter, conn_opts, sql_dir, specific_file) do
    if specific_file do
      run_single_file(adapter, conn_opts, specific_file)
    else
      run_all_files(adapter, conn_opts, sql_dir)
    end
  end

  defp run_single_file(adapter, conn_opts, file_path) do
    unless File.exists?(file_path) do
      {:error, "SQL file not found: #{file_path}"}
    else
      case Connection.with_connection(adapter, conn_opts, fn conn ->
             SqlRunner.run_sql_file(adapter, conn, file_path)
           end) do
        {:ok, {:ok, _label, count}} ->
          {:ok, "Successfully executed #{count} statement(s) from #{file_path}"}

        {:ok, {:error, _label, error}} ->
          {:error, "Error executing #{file_path}: #{inspect(error)}"}

        {:error, reason} ->
          {:error, "Error connecting to database: #{inspect(reason)}"}
      end
    end
  end

  defp run_all_files(adapter, conn_opts, sql_dir) do
    unless File.dir?(sql_dir) do
      {:error,
       "SQL directory not found: #{sql_dir}. Run a gen task first (e.g., mix selecto.gen.saved_views MyApp --adapter postgresql)"}
    else
      case Connection.with_connection(adapter, conn_opts, fn conn ->
             SqlRunner.run_sql_directory(adapter, conn, sql_dir)
           end) do
        {:ok, {:ok, :no_files}} ->
          {:error, "No SQL files found in #{sql_dir}/. Run a gen task first."}

        {:ok, {:ok, count}} ->
          {:ok, "Successfully executed #{count} SQL file(s) from #{sql_dir}/"}

        {:ok, {:error, errors}} ->
          error_msgs =
            Enum.map(errors, fn {:error, file, err} -> "  #{file}: #{inspect(err)}" end)

          {:error, "Errors executing SQL files:\n#{Enum.join(error_msgs, "\n")}"}

        {:error, reason} ->
          {:error, "Error connecting to database: #{inspect(reason)}"}
      end
    end
  end
end
