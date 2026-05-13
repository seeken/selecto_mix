unless Code.ensure_loaded?(Selecto) do
  defmodule Selecto do
    def configure(domain, _connection, _opts \\ []), do: {:configured, domain}
    def from_ecto(repo, schema, opts \\ []), do: {:from_ecto, repo, schema, opts}
    def select(selecto, _fields), do: selecto
    def filter(selecto, _filter), do: selecto
    def execute(_selecto), do: {:ok, []}
    def execute_one(_selecto), do: {:ok, nil}
  end
end

unless Code.ensure_loaded?(Selecto.Config.Overlay) do
  defmodule Selecto.Config.Overlay do
    def merge(domain, overlay) when is_map(domain) and is_map(overlay),
      do: Map.merge(domain, overlay)
  end
end

unless Code.ensure_loaded?(Selecto.DomainValidator) do
  defmodule Selecto.DomainValidator do
    def validate_domain(_domain), do: :ok
  end
end

unless Code.ensure_loaded?(Selecto.DomainValidator.ValidationError) do
  defmodule Selecto.DomainValidator.ValidationError do
    defexception [:errors]

    @impl Exception
    def message(%{errors: errors}), do: "Selecto domain validation failed: #{inspect(errors)}"
  end
end

unless Code.ensure_loaded?(Selecto.Domain) do
  defmodule Selecto.Domain do
    def normalize(domain) when is_map(domain) do
      schema_version = Map.get(domain, :schema_version) || Map.get(domain, "schema_version") || 1
      domain_version = Map.get(domain, :domain_version) || Map.get(domain, "domain_version")

      domain_fingerprint =
        Map.get(domain, :domain_fingerprint) || Map.get(domain, "domain_fingerprint")

      {:ok,
       %{
         schema_version: schema_version,
         domain_version: domain_version,
         domain_fingerprint: domain_fingerprint,
         domain: domain
       },
       %{
         errors: [],
         warnings: [],
         schema_version: schema_version,
         schema_version_inferred: false,
         canonical_sections: [:source, :schemas, :joins, :filters, :functions, :published_views],
         projection_sections: [],
         proposed_sections: [],
         unknown_sections: []
       }}
    end

    def normalize(_domain) do
      {:error, %{errors: [%{code: :invalid_domain}], warnings: []}}
    end

    def describe(%{schema_version: schema_version, domain: domain}) when is_map(domain) do
      domain_version = Map.get(domain, :domain_version) || Map.get(domain, "domain_version")

      domain_fingerprint =
        Map.get(domain, :domain_fingerprint) || Map.get(domain, "domain_fingerprint")

      source = map_get(domain, "source", %{})
      filters = map_get(domain, "filters", %{})
      functions = map_get(domain, "functions", %{})
      joins = map_get(domain, "joins", %{})
      source_relationships = map_get(domain, "source_relationships", %{})
      choice_sources = map_get(domain, "choice_sources", %{})

      {:ok,
       %{
         schema_version: schema_version,
         domain_version: domain_version,
         domain_fingerprint: domain_fingerprint,
         name: map_get(domain, "name"),
         sections: %{
           canonical: [:source, :schemas, :joins, :filters, :functions, :published_views],
           projection: [],
           proposed: [],
           unknown: []
         },
         diagnostics: %{
           error_count: 0,
           warning_count: 0,
           error_codes: [],
           warning_codes: [],
           schema_version_inferred: false
         },
         projections: [:query, :write, :ui, :api, :query_contract],
         counts: %{
           source_fields: source |> map_get("fields", []) |> length_or_zero(),
           schemas: domain |> map_get("schemas", %{}) |> map_size_or_zero(),
           joins: map_size_or_zero(joins),
           filters: map_size_or_zero(filters),
           functions: map_size_or_zero(functions),
           query_members: 0,
           custom_columns: 0,
           writes: %{operations: 0, fields: 0, transitions: 0, validations: 0, constraints: 0},
           actions: domain |> map_get("actions", %{}) |> map_size_or_zero(),
           capabilities: domain |> map_get("capabilities", %{}) |> map_size_or_zero(),
           source_relationships: map_size_or_zero(source_relationships),
           choice_sources: map_size_or_zero(choice_sources),
           field_choice_bindings: 0,
           warnings: 0,
           errors: 0
         },
         registries: %{
           source_fields: source |> map_get("fields", []) |> string_list(),
           schemas: domain |> map_get("schemas", %{}) |> sorted_keys(),
           schema_fields: %{},
           joins: sorted_keys(joins),
           filters: sorted_keys(filters),
           functions: sorted_keys(functions),
           query_members: [],
           custom_columns: [],
           actions: domain |> map_get("actions", %{}) |> sorted_keys(),
           capabilities: domain |> map_get("capabilities", %{}) |> sorted_keys(),
           source_relationships: sorted_keys(source_relationships),
           choice_sources: sorted_keys(choice_sources)
         },
         writes: %{
           operations: [],
           fields: [],
           transitions: [],
           validations_count: 0,
           constraints_count: 0
         },
         actions: [],
         capabilities: [],
         source_relationships: [],
         choice_sources: [],
         field_choice_bindings: []
       },
       %{errors: [], warnings: [], schema_version: schema_version, schema_version_inferred: false}}
    end

    def describe(domain) when is_map(domain) do
      with {:ok, normalized, _diagnostics} <- normalize(domain) do
        describe(normalized)
      end
    end

    def describe(_domain) do
      {:error, %{errors: [%{code: :invalid_domain}], warnings: []}}
    end

    defp map_get(map, key, default \\ nil)

    defp map_get(map, key, default) when is_map(map) and is_binary(key) do
      atom_key = existing_atom(key)

      cond do
        Map.has_key?(map, key) -> Map.get(map, key)
        atom_key && Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
        true -> default
      end
    end

    defp map_get(map, key, default) when is_map(map) and is_atom(key) do
      string_key = Atom.to_string(key)

      cond do
        Map.has_key?(map, key) -> Map.get(map, key)
        Map.has_key?(map, string_key) -> Map.get(map, string_key)
        true -> default
      end
    end

    defp map_get(_map, _key, default), do: default

    defp sorted_keys(value) when is_map(value) do
      value
      |> Map.keys()
      |> string_list()
    end

    defp sorted_keys(_value), do: []

    defp string_list(values) when is_list(values) do
      values
      |> Enum.map(&to_string/1)
      |> Enum.sort()
    end

    defp string_list(_values), do: []

    defp length_or_zero(value) when is_list(value), do: length(value)
    defp length_or_zero(_value), do: 0

    defp map_size_or_zero(value) when is_map(value), do: map_size(value)
    defp map_size_or_zero(_value), do: 0

    defp existing_atom(value) do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> nil
    end
  end
end

defmodule SelectoMix.DomainExportTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias SelectoMix.DomainGenerator

  defmodule DemoDomain do
    def domain do
      %{
        schema_version: 1,
        domain_version: "0.5.0",
        domain_fingerprint: "sha256:demo",
        name: "Demo Items",
        source: %{
          source_table: "demo_items",
          primary_key: :id,
          fields: [:id, :name],
          columns: %{
            id: %{type: :integer, name: "ID"},
            name: %{type: :string, name: "Name"}
          }
        },
        schemas: %{
          customers: %{
            source_table: "customers",
            columns: %{id: %{type: :integer}, name: %{type: :string}}
          }
        },
        joins: %{customer: %{name: "Customer"}},
        filters: %{name: %{type: :string}},
        functions: %{name_lower: %{kind: :scalar}},
        published_views: %{
          "demo_rollup" => %{
            kind: :view,
            query: fn domain -> domain end
          }
        }
      }
    end
  end

  defmodule PlainDomain do
    def domain do
      %{
        schema_version: 1,
        name: "Plain Items",
        source: %{
          source_table: "plain_items",
          primary_key: :id,
          fields: [:id, :name],
          columns: %{
            id: %{type: :integer, name: "ID"},
            name: %{type: :string, name: "Name"}
          }
        },
        schemas: %{},
        joins: %{},
        filters: %{name: %{type: :string}},
        functions: %{}
      }
    end
  end

  defmodule CapabilityDocsDomain do
    def domain do
      PlainDomain.domain()
      |> put_in([:source, :columns, :name, :capability], "item.name")
      |> Map.merge(%{
        name: "Capability Items",
        domain_fingerprint: "sha256:capability",
        filters: %{name: %{type: :string, capability: "item.filter"}},
        functions: %{name_lower: %{kind: :scalar, capability: "item.rank"}},
        query_members: %{
          values: %{
            status_lookup: %{
              columns: [:status, :label],
              rows: [["active", "Active"]],
              capability: "item.member"
            }
          }
        },
        published_views: %{items_rollup: %{kind: :view, capability: "item.view"}},
        detail_actions: %{profile: %{type: :external_link, capability: "item.view"}},
        writes: %{
          operations: %{update: %{fields: [:name]}},
          fields: %{name: %{updatable: true}},
          relationships: %{audit_log: %{writable: true, cardinality: :many}},
          scope: %{tenant: %{required: true, field: :id, satisfied_by: [:trusted_context]}},
          hooks: %{before_validate: [{__MODULE__, :before_validate}]},
          transitions: %{status: %{"active" => ["archived"]}},
          validations: [%{field: :name}],
          constraints: [%{field: :name}]
        },
        actions: %{archive: %{type: :transition, capability: "item.archive"}},
        capabilities: %{
          "item.archive" => %{operations: [:action]},
          "item.filter" => %{operations: [:filter]},
          "item.member" => %{operations: [:query_member]},
          "item.name" => %{operations: [:select]},
          "item.rank" => %{operations: [:select]},
          "item.view" => %{operations: [:select, :detail]}
        },
        choice_sources: %{
          owner_choices: %{
            domain: :users,
            value_field: :id,
            label_field: :name,
            constraint_policy: %{domain_of_interest: :fail_closed}
          }
        }
      })
    end
  end

  test "exports a normalized domain JSON artifact to stdout" do
    Mix.Task.reenable("selecto.domain.export")

    output =
      capture_io(fn ->
        Mix.Tasks.Selecto.Domain.Export.run([inspect(DemoDomain)])
      end)

    artifact = Jason.decode!(output)

    assert artifact["format"] == "selecto.normalized_domain"
    assert artifact["format_version"] == 1
    assert artifact["domain_module"] == inspect(DemoDomain)
    assert artifact["schema_version"] == 1
    assert artifact["domain_version"] == "0.5.0"
    assert artifact["domain_fingerprint"] == "sha256:demo"
    assert artifact["domain"]["domain_version"] == "0.5.0"
    assert artifact["domain"]["domain_fingerprint"] == "sha256:demo"
    assert artifact["diagnostics"]["errors"] == []
    assert artifact["domain"]["source"]["primary_key"] == "id"
    assert artifact["domain"]["source"]["fields"] == ["id", "name"]

    assert artifact["domain"]["published_views"]["demo_rollup"]["query"]["$selecto_export"] ==
             "function"
  end

  test "writes a normalized domain JSON artifact to --output" do
    in_tmp_dir("selecto_mix_domain_export", fn ->
      Mix.Task.reenable("selecto.domain.export")

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Export.run([
            inspect(DemoDomain),
            "--output",
            "priv/selecto/demo.normalized.json"
          ])
        end)

      assert output =~ "Wrote normalized domain JSON"

      artifact =
        "priv/selecto/demo.normalized.json"
        |> File.read!()
        |> Jason.decode!()

      assert artifact["domain"]["name"] == "Demo Items"
      assert artifact["domain"]["source"]["columns"]["id"]["type"] == "integer"
    end)
  end

  test "checks an exported normalized domain JSON artifact" do
    in_tmp_dir("selecto_mix_domain_check", fn ->
      Mix.Task.reenable("selecto.domain.check")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(DemoDomain)
      File.write!("demo.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Check.run(["demo.normalized.json"])
        end)

      assert output =~ "Checked normalized domain JSON: demo.normalized.json"
      assert output =~ "Format: selecto.normalized_domain v1"
      assert output =~ "Domain module: #{inspect(DemoDomain)}"
      assert output =~ "Schema version: 1"
      assert output =~ "Domain version: 0.5.0"
      assert output =~ "Domain fingerprint: sha256:demo"
      assert output =~ "Diagnostics: 0 errors, 0 warnings"
    end)
  end

  test "checks a non-writing import plan for an exported normalized domain JSON artifact" do
    in_tmp_dir("selecto_mix_domain_import_check", fn ->
      Mix.Task.reenable("selecto.domain.import")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(DemoDomain)
      File.write!("demo.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Import.run(["demo.normalized.json", "--check"])
        end)

      assert output =~ "Checked normalized domain import plan: demo.normalized.json"
      assert output =~ "Mode: check (no files written)"
      assert output =~ "Name: Demo Items"
      assert output =~ "Generated-domain preview:"
      assert output =~ "status: partial"
      assert output =~ "target module: #{inspect(DemoDomain)}"
      assert output =~ "target file: lib/selecto_mix/domain_export_task_test/demo_domain.ex"
      assert output =~ "domain function: domain/0"
      assert output =~ "render strategy: literal_domain_map"
      assert output =~ "write enabled: false"
      assert output =~ "reconstructable sections: filters, functions, joins, schemas, source"
      assert output =~ "partial sections: published_views"
      assert output =~ "security review sections: (none)"
      assert output =~ "source preview:"
      assert output =~ "Source preview validation:"
      assert output =~ "syntax: ok"
      assert output =~ "module: #{inspect(DemoDomain)}"
      assert output =~ "target module match: true"
      assert output =~ "domain/0 present: true"
      assert output =~ "runtime placeholders blocking: true (1)"
      assert output =~ "write ready: false"
      refute output =~ "defmodule #{inspect(DemoDomain)} do"
      assert output =~ "source: 1 (reconstructable)"
      assert output =~ "published_views: 1 (partial_runtime_placeholders)"
      assert output =~ "Runtime placeholders: 1"
      assert output =~ "function: 1"
      assert output =~ "domain.published_views.demo_rollup.query (function)"
      assert output =~ "artifact: 0 errors, 0 warnings"
      assert output =~ "current: 0 errors, 0 warnings"
      assert output =~ "Write status: check_only"

      json_output =
        capture_io(fn ->
          Mix.Task.reenable("selecto.domain.import")

          Mix.Tasks.Selecto.Domain.Import.run([
            "demo.normalized.json",
            "--check",
            "--format",
            "json",
            "--target-module",
            "Preview.TargetDomain",
            "--output-dir",
            "tmp/imported"
          ])
        end)

      plan = Jason.decode!(json_output)

      assert plan["format"] == "selecto.domain_import_plan"
      assert plan["mode"] == "check"
      assert plan["source"]["name"] == "Demo Items"
      assert plan["preview"]["status"] == "partial"
      assert plan["preview"]["target_module"] == "Preview.TargetDomain"
      assert plan["preview"]["target_file"] == "tmp/imported/preview/target_domain.ex"
      assert plan["preview"]["domain_function"] == "domain/0"
      assert plan["preview"]["partial_sections"] == ["published_views"]
      assert plan["preview"]["security_sensitive_sections"] == []
      assert plan["source_preview"]["language"] == "elixir"
      assert plan["source_preview"]["target_module"] == "Preview.TargetDomain"
      assert plan["source_preview"]["includes_runtime_placeholders"] == true
      assert plan["source_preview"]["content"] =~ "defmodule Preview.TargetDomain do"
      assert plan["source_preview"]["content"] =~ "def domain do"
      assert plan["source_preview"]["content"] =~ ~s("$selecto_export" => "function")
      assert plan["source_validation"]["valid"] == true
      assert plan["source_validation"]["syntax"] == "ok"
      assert plan["source_validation"]["module"] == "Preview.TargetDomain"
      assert plan["source_validation"]["target_module_match"] == true
      assert plan["source_validation"]["domain_function_present"] == true
      assert plan["source_validation"]["runtime_placeholders_blocking"] == true
      assert plan["source_validation"]["runtime_placeholder_count"] == 1
      assert plan["source_validation"]["write_ready"] == false
      assert plan["runtime_placeholders"]["count"] == 1
      assert plan["write"]["status"] == "check_only"

      source_output =
        capture_io(fn ->
          Mix.Task.reenable("selecto.domain.import")

          Mix.Tasks.Selecto.Domain.Import.run([
            "demo.normalized.json",
            "--check",
            "--source",
            "--target-module",
            "Preview.TargetDomain",
            "--target-file",
            "tmp/imported/preview_target.ex"
          ])
        end)

      assert source_output =~ "Elixir source preview:"
      assert source_output =~ "target file: tmp/imported/preview_target.ex"
      assert source_output =~ "defmodule Preview.TargetDomain do"
      assert source_output =~ "Selecto domain import preview."
      assert source_output =~ ~s("name" => "Demo Items")
      assert source_output =~ ~s("$selecto_export" => "function")
    end)
  end

  test "flags security-sensitive sections in normalized domain import previews" do
    in_tmp_dir("selecto_mix_domain_import_security_review", fn ->
      Mix.Task.reenable("selecto.domain.import")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(CapabilityDocsDomain)
      File.write!("capability.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Import.run(["capability.normalized.json", "--check"])
        end)

      assert output =~
               "security review sections: actions (reconstructable), capabilities (reconstructable), choice_sources (reconstructable), detail_actions (reconstructable), writes (reconstructable)"

      json_output =
        capture_io(fn ->
          Mix.Task.reenable("selecto.domain.import")

          Mix.Tasks.Selecto.Domain.Import.run([
            "capability.normalized.json",
            "--check",
            "--format",
            "json"
          ])
        end)

      plan = Jason.decode!(json_output)

      assert plan["preview"]["security_sensitive_sections"] == [
               %{
                 "name" => "actions",
                 "status" => "reconstructable",
                 "reason" => "business command definitions and execution surfaces"
               },
               %{
                 "name" => "capabilities",
                 "status" => "reconstructable",
                 "reason" => "authorization capability catalog"
               },
               %{
                 "name" => "choice_sources",
                 "status" => "reconstructable",
                 "reason" => "cross-domain choices and constraint policy"
               },
               %{
                 "name" => "detail_actions",
                 "status" => "reconstructable",
                 "reason" => "user-visible detail actions"
               },
               %{
                 "name" => "writes",
                 "status" => "reconstructable",
                 "reason" =>
                   "write operations, fields, relationships, scope, hooks, validations, constraints, and transitions"
               }
             ]
    end)
  end

  test "requires an explicit normalized domain import mode" do
    in_tmp_dir("selecto_mix_domain_import_refuses_writes", fn ->
      Mix.Task.reenable("selecto.domain.import")
      File.write!("demo.normalized.json", Jason.encode!(%{}))

      assert_raise Mix.Error, ~r/--check or --write/, fn ->
        Mix.Tasks.Selecto.Domain.Import.run(["demo.normalized.json"])
      end
    end)
  end

  test "refuses normalized domain import writes with runtime placeholders" do
    in_tmp_dir("selecto_mix_domain_import_write_placeholders", fn ->
      Mix.Task.reenable("selecto.domain.import")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(DemoDomain)
      File.write!("demo.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      assert_raise Mix.Error, ~r/runtime placeholder\(s\) remain/, fn ->
        Mix.Tasks.Selecto.Domain.Import.run([
          "demo.normalized.json",
          "--write",
          "--target-module",
          "Preview.DemoDomain",
          "--target-file",
          "lib/preview/demo_domain.ex"
        ])
      end

      refute File.exists?("lib/preview/demo_domain.ex")
    end)
  end

  test "writes validated normalized domain import previews" do
    in_tmp_dir("selecto_mix_domain_import_write", fn ->
      Mix.Task.reenable("selecto.domain.import")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(PlainDomain)
      File.write!("plain.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Import.run([
            "plain.normalized.json",
            "--write",
            "--target-module",
            "Preview.PlainDomain",
            "--target-file",
            "lib/preview/plain_domain.ex"
          ])
        end)

      assert output =~ "Wrote normalized domain import preview: lib/preview/plain_domain.ex"
      assert output =~ "Target module: Preview.PlainDomain"
      assert output =~ "Source validation: ok"
      assert output =~ "domain/0 present: true"
      assert output =~ "Runtime placeholders: 0"
      assert output =~ "Overwrote: false"

      source = File.read!("lib/preview/plain_domain.ex")
      assert source =~ "defmodule Preview.PlainDomain do"
      assert source =~ "def domain do"
      assert source =~ ~s("name" => "Plain Items")
      refute source =~ "$selecto_export"

      Mix.Task.reenable("selecto.domain.import")

      assert_raise Mix.Error, ~r/already exists/, fn ->
        Mix.Tasks.Selecto.Domain.Import.run([
          "plain.normalized.json",
          "--write",
          "--target-module",
          "Preview.PlainDomain",
          "--target-file",
          "lib/preview/plain_domain.ex"
        ])
      end

      force_output =
        capture_io(fn ->
          Mix.Task.reenable("selecto.domain.import")

          Mix.Tasks.Selecto.Domain.Import.run([
            "plain.normalized.json",
            "--write",
            "--force",
            "--target-module",
            "Preview.PlainDomain",
            "--target-file",
            "lib/preview/plain_domain.ex"
          ])
        end)

      assert force_output =~ "Overwrote: true"
    end)
  end

  test "round-trips written normalized domain import previews" do
    in_tmp_dir("selecto_mix_domain_import_write_round_trip", fn ->
      suffix = System.unique_integer([:positive])
      target_module = "Preview.ImportedPlain#{suffix}"
      target_module_atom = Module.concat([target_module])
      target_file = "lib/preview/imported_plain_#{suffix}.ex"

      Mix.Task.reenable("selecto.domain.import")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(PlainDomain)
      File.write!("plain.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      write_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Import.run([
            "plain.normalized.json",
            "--write",
            "--format",
            "json",
            "--target-module",
            target_module,
            "--target-file",
            target_file
          ])
        end)

      write_plan = Jason.decode!(write_output)

      assert write_plan["mode"] == "write"
      assert write_plan["preview"]["write_enabled"] == true
      assert write_plan["source_preview"]["write_enabled"] == true
      assert write_plan["write"]["status"] == "written"
      assert write_plan["write"]["target_file"] == target_file
      assert write_plan["write"]["target_module"] == target_module

      compiled_modules =
        target_file
        |> Code.compile_file()
        |> Enum.map(fn {module, _bytecode} -> module end)

      assert target_module_atom in compiled_modules
      assert function_exported?(target_module_atom, :domain, 0)

      assert {:ok, round_trip_artifact} = SelectoMix.DomainExport.export(target_module_atom)
      assert round_trip_artifact["domain"]["name"] == "Plain Items"

      File.write!(
        "round_trip.normalized.json",
        SelectoMix.DomainExport.encode!(round_trip_artifact)
      )

      Mix.Task.reenable("selecto.domain.check")

      check_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Check.run(["round_trip.normalized.json"])
        end)

      assert check_output =~ "Checked normalized domain JSON: round_trip.normalized.json"
      assert check_output =~ "Domain module: #{target_module}"
    end)
  end

  test "inspects an exported normalized domain JSON artifact" do
    in_tmp_dir("selecto_mix_domain_inspect", fn ->
      Mix.Task.reenable("selecto.domain.inspect")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(DemoDomain)
      File.write!("demo.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Inspect.run(["demo.normalized.json"])
        end)

      assert output =~ "Normalized domain artifact: demo.normalized.json"
      assert output =~ "Name: Demo Items"
      assert output =~ "Sections:"
      assert output =~ "canonical: source, schemas, joins, filters, functions, published_views"
      assert output =~ "source fields: 2"
      assert output =~ "schemas: 1"
      assert output =~ "joins: customer"
      assert output =~ "filters: name"
      assert output =~ "functions: name_lower"
      assert output =~ "published views: demo_rollup"
      assert output =~ "artifact: 0 errors, 0 warnings"
      assert output =~ "current: 0 errors, 0 warnings"
    end)
  end

  test "inspects operational counts from a normalized domain JSON artifact" do
    in_tmp_dir("selecto_mix_domain_inspect_operational", fn ->
      Mix.Task.reenable("selecto.domain.inspect")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(CapabilityDocsDomain)
      File.write!("capability.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Inspect.run(["capability.normalized.json"])
        end)

      assert output =~ "Name: Capability Items"
      assert output =~ "detail actions: 1"
      assert output =~ "write operations: 1"
      assert output =~ "write fields: 1"
      assert output =~ "write relationships: 1"
      assert output =~ "write transitions: 1"
      assert output =~ "write validations: 1"
      assert output =~ "write constraints: 1"
      assert output =~ "write scope: 1"
      assert output =~ "write hooks: 1"
      assert output =~ "actions: 1"
      assert output =~ "capabilities: 6"
      assert output =~ "detail actions: profile"
      assert output =~ "write operations: update"
      assert output =~ "write fields: name"
      assert output =~ "write relationships: audit_log"
      assert output =~ "write transitions: status"
      assert output =~ "write scope: tenant"
      assert output =~ "write hooks: before_validate"
      assert output =~ "actions: archive"

      assert output =~
               "capabilities: item.archive, item.filter, item.member, item.name, item.rank, item.view"

      assert output =~ "Security Review:"
      assert output =~ "actions: 1 (archive)"
      assert output =~ "choice_sources: 1 (owner_choices)"

      assert output =~
               "writes: 8 (operations: update; fields: name; relationships: audit_log; transitions: status; validations: 1; constraints: 1; scope: tenant; hooks: before_validate)"
    end)
  end

  test "generates Markdown docs from an exported normalized domain JSON artifact" do
    in_tmp_dir("selecto_mix_domain_docs", fn ->
      Mix.Task.reenable("selecto.domain.docs")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(DemoDomain)
      File.write!("demo.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Docs.run([
            "demo.normalized.json",
            "--output",
            "docs/selecto/demo.md"
          ])
        end)

      assert output =~ "Wrote normalized domain Markdown docs: docs/selecto/demo.md"

      docs = File.read!("docs/selecto/demo.md")

      assert docs =~ "# Demo Items"
      assert docs =~ "| Domain module | #{inspect(DemoDomain)} |"
      assert docs =~ "## Source"
      assert docs =~ "| Table | demo_items |"
      assert docs =~ "| id | integer | ID |"
      assert docs =~ "| name | string | Name |"
      assert docs =~ "## Registries"
      assert docs =~ "### Filters"
      assert docs =~ "| name |  | string |  |"
      assert docs =~ "### Published Views"
      assert docs =~ "| demo_rollup |  | view |  |"
      assert docs =~ "## Diagnostics"
      assert docs =~ "| Current | 0 | 0 | (none) | (none) |"
    end)
  end

  test "generates Markdown capability usage docs from a normalized domain JSON artifact" do
    in_tmp_dir("selecto_mix_domain_docs_capabilities", fn ->
      Mix.Task.reenable("selecto.domain.docs")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(CapabilityDocsDomain)
      File.write!("capability.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Docs.run([
            "capability.normalized.json",
            "--output",
            "docs/selecto/capability.md"
          ])
        end)

      assert output =~ "Wrote normalized domain Markdown docs: docs/selecto/capability.md"

      docs = File.read!("docs/selecto/capability.md")

      assert docs =~ "# Capability Items"
      assert docs =~ "| Domain fingerprint | sha256:capability |"
      assert docs =~ "## Choice Source Details"
      assert docs =~ "| owner_choices | users | id | name | domain_of_interest=fail_closed |"
      assert docs =~ "## Security Review"

      assert docs =~
               "| choice_sources | 1 | owner_choices | cross-domain choices and constraint policy |"

      assert docs =~
               "| writes | 8 | operations: update; fields: name; relationships: audit_log; transitions: status; validations: 1; constraints: 1; scope: tenant; hooks: before_validate | write operations, fields, relationships, scope, hooks, validations, constraints, and transitions |"

      assert docs =~ "## Capability Usage"
      assert docs =~ "| Capability | Role | Section | Target | Path |"
      assert docs =~ "| item.name | field | source | name | source.columns.name.capability |"
      assert docs =~ "| item.filter | query filter | filters | name | filters.name.capability |"

      assert docs =~
               "| item.rank | query function | functions | name_lower | functions.name_lower.capability |"

      assert docs =~
               "| item.member | query member | query_members | values.status_lookup | query_members.values.status_lookup.capability |"

      assert docs =~
               "| item.view | published view | published_views | items_rollup | published_views.items_rollup.capability |"

      assert docs =~
               "| item.view | detail action | detail_actions | profile | detail_actions.profile.capability |"

      assert docs =~ "| item.archive | action | actions | archive | actions.archive.capability |"
    end)
  end

  test "generates Studio inspection JSON from an exported normalized domain JSON artifact" do
    in_tmp_dir("selecto_mix_domain_describe", fn ->
      Mix.Task.reenable("selecto.domain.describe")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(DemoDomain)
      File.write!("demo.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Describe.run([
            "demo.normalized.json",
            "--output",
            "priv/selecto/demo.inspection.json"
          ])
        end)

      assert output =~
               "Wrote normalized domain inspection JSON: priv/selecto/demo.inspection.json"

      inspection =
        "priv/selecto/demo.inspection.json"
        |> File.read!()
        |> Jason.decode!()

      assert inspection["format"] == "selecto.domain_inspection"
      assert inspection["format_version"] == 1
      assert inspection["source"]["path"] == "demo.normalized.json"
      assert inspection["source"]["domain_module"] == inspect(DemoDomain)
      assert inspection["source"]["name"] == "Demo Items"
      assert inspection["source"]["domain_version"] == "0.5.0"
      assert inspection["source"]["domain_fingerprint"] == "sha256:demo"
      assert inspection["inspection"]["name"] == "Demo Items"
      assert inspection["inspection"]["domain_version"] == "0.5.0"
      assert inspection["inspection"]["domain_fingerprint"] == "sha256:demo"
      assert inspection["inspection"]["counts"]["source_fields"] == 2
      assert inspection["inspection"]["counts"]["filters"] == 1
      assert inspection["inspection"]["registries"]["filters"] == ["name"]
      assert inspection["inspection"]["security_review"] == []

      assert inspection["inspection"]["projections"] == [
               "query",
               "write",
               "ui",
               "api",
               "query_contract"
             ]

      assert inspection["diagnostics"]["errors"] == []
      assert inspection["diagnostics"]["schema_version"] == 1
    end)
  end

  test "generates Studio inspection security review metadata" do
    in_tmp_dir("selecto_mix_domain_describe_security_review", fn ->
      Mix.Task.reenable("selecto.domain.describe")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(CapabilityDocsDomain)
      File.write!("capability.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Describe.run([
            "capability.normalized.json",
            "--output",
            "priv/selecto/capability.inspection.json"
          ])
        end)

      assert output =~
               "Wrote normalized domain inspection JSON: priv/selecto/capability.inspection.json"

      inspection =
        "priv/selecto/capability.inspection.json"
        |> File.read!()
        |> Jason.decode!()

      assert inspection["inspection"]["security_review"] == [
               %{
                 "section" => "actions",
                 "count" => 1,
                 "items" => ["archive"],
                 "reason" => "business command definitions and execution surfaces"
               },
               %{
                 "section" => "capabilities",
                 "count" => 6,
                 "items" => [
                   "item.archive",
                   "item.filter",
                   "item.member",
                   "item.name",
                   "item.rank",
                   "item.view"
                 ],
                 "reason" => "authorization capability catalog"
               },
               %{
                 "section" => "choice_sources",
                 "count" => 1,
                 "items" => ["owner_choices"],
                 "reason" => "cross-domain choices and constraint policy"
               },
               %{
                 "section" => "detail_actions",
                 "count" => 1,
                 "items" => ["profile"],
                 "reason" => "user-visible detail actions"
               },
               %{
                 "section" => "writes",
                 "count" => 8,
                 "items" => %{
                   "operations" => ["update"],
                   "fields" => ["name"],
                   "relationships" => ["audit_log"],
                   "transitions" => ["status"],
                   "validations_count" => 1,
                   "constraints_count" => 1,
                   "scope" => ["tenant"],
                   "hooks" => ["before_validate"]
                 },
                 "reason" =>
                   "write operations, fields, relationships, scope, hooks, validations, constraints, and transitions"
               }
             ]
    end)
  end

  test "generates Mermaid diagram from a Studio inspection JSON artifact" do
    in_tmp_dir("selecto_mix_domain_diagram", fn ->
      Mix.Task.reenable("selecto.domain.diagram")

      inspection_artifact = %{
        "format" => "selecto.domain_inspection",
        "format_version" => 1,
        "source" => %{
          "path" => "demo.normalized.json",
          "domain_module" => inspect(DemoDomain),
          "schema_version" => 1,
          "domain_version" => "0.5.0",
          "domain_fingerprint" => "sha256:demo",
          "name" => "Demo Items"
        },
        "inspection" => %{
          "schema_version" => 1,
          "domain_version" => "0.5.0",
          "domain_fingerprint" => "sha256:demo",
          "name" => "Demo Items",
          "registries" => %{
            "source_fields" => ["customer_id", "id", "status"]
          },
          "source_relationships" => [
            %{
              "id" => "customer",
              "target_domain" => "customers",
              "source_field" => "customer_id",
              "target_field" => "id",
              "virtual_join_count" => 1,
              "filters_count" => 1
            }
          ],
          "choice_sources" => [
            %{
              "id" => "customer_choices",
              "domain" => "customers",
              "source_relationship" => "customer",
              "value_field" => "id",
              "label_field" => "name",
              "constraint_policy" => %{"domain_of_interest" => "fail_closed"},
              "filters_count" => 1,
              "order_by_count" => 1,
              "presentation" => %{"control" => "select"}
            }
          ],
          "field_choice_bindings" => [
            %{
              "field" => "customer_id",
              "choice_source" => "customer_choices",
              "compact?" => true,
              "reference?" => true
            }
          ],
          "capabilities" => [
            %{
              "id" => "customer.choose",
              "operations" => ["choice_source"]
            }
          ],
          "capability_usage" => [
            %{
              "capability" => "customer.choose",
              "section" => "choice_sources",
              "role" => "choice_source",
              "id" => "customer_choices",
              "path" => ["choice_sources", "customer_choices", "capability"]
            }
          ],
          "security_review" => [
            %{
              "section" => "choice_sources",
              "count" => 1,
              "items" => ["customer_choices"],
              "reason" => "cross-domain choices and constraint policy"
            }
          ]
        },
        "diagnostics" => %{"errors" => [], "warnings" => []}
      }

      File.write!("demo.inspection.json", Jason.encode!(inspection_artifact, pretty: true))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Diagram.run([
            "demo.inspection.json",
            "--output",
            "docs/selecto/demo.diagram.mmd"
          ])
        end)

      assert output =~ "Wrote normalized domain Mermaid diagram: docs/selecto/demo.diagram.mmd"

      diagram = File.read!("docs/selecto/demo.diagram.mmd")

      assert diagram =~ "flowchart LR"
      assert diagram =~ "Domain: Demo Items\\nschema v1\\ndomain 0.5.0\\nfingerprint sha256:demo"
      assert diagram =~ "Source relationship: customer"
      assert diagram =~ "customer_id -> id"
      assert diagram =~ "Choice source: customer_choices"
      assert diagram =~ "policy: domain_of_interest=fail_closed"
      assert diagram =~ "picker: select"
      assert diagram =~ "Picker field: customer_id"
      assert diagram =~ "choice_customer_choices -. uses .-> rel_customer"
      assert diagram =~ "binding_customer_id -. picker .-> choice_customer_choices"
      assert diagram =~ ~s(subgraph capabilities["Capabilities"])
      assert diagram =~ "Capability: customer.choose\\noperations: choice_source"
      assert diagram =~ ~s(subgraph capability_usage["Capability Usage"])
      assert diagram =~ "Choice source: customer_choices\\nsection: choice_sources"

      assert diagram =~
               "capuse_choice_sources_customer_choices_capability -. requires .-> cap_customer_choose"

      assert diagram =~ ~s(subgraph security_review["Security Review"])
      assert diagram =~ "Security review: choice_sources"
      assert diagram =~ "items: customer_choices"
      assert diagram =~ "cross-domain choices and constraint policy"
      assert diagram =~ "domain -. review .-> review_choice_sources"
    end)
  end

  test "diffs exported normalized domain JSON artifacts" do
    in_tmp_dir("selecto_mix_domain_diff", fn ->
      Mix.Task.reenable("selecto.domain.diff")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(DemoDomain)

      changed_artifact =
        artifact
        |> update_in(["domain", "filters"], &Map.put(&1, "status", %{"type" => "string"}))
        |> update_in(["domain", "joins"], &Map.delete(&1, "customer"))
        |> update_in(["diagnostics", "unknown_sections"], &["future_section" | &1])
        |> update_in(["diagnostics", "warnings"], &[%{"code" => "unknown_sections"} | &1])

      File.write!("left.normalized.json", SelectoMix.DomainExport.encode!(artifact))
      File.write!("right.normalized.json", SelectoMix.DomainExport.encode!(changed_artifact))

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Diff.run([
            "left.normalized.json",
            "right.normalized.json"
          ])
        end)

      assert output =~ "Normalized domain artifact diff"
      assert output =~ "Left: left.normalized.json"
      assert output =~ "Right: right.normalized.json"
      assert output =~ "filters: 1 -> 2 (+1)"
      assert output =~ "joins: 1 -> 0 (-1)"
      assert output =~ "+ future_section"
      assert output =~ "+ status"
      assert output =~ "- customer"
      assert output =~ "warnings: 0 -> 1 (+1)"
      assert output =~ "+ unknown_sections"
    end)
  end

  test "diffs operational sections in normalized domain JSON artifacts" do
    in_tmp_dir("selecto_mix_domain_diff_operational", fn ->
      Mix.Task.reenable("selecto.domain.diff")
      assert {:ok, artifact} = SelectoMix.DomainExport.export(CapabilityDocsDomain)

      changed_artifact =
        artifact
        |> update_in(["domain", "detail_actions"], &Map.delete(&1, "profile"))
        |> update_in(["domain", "writes", "operations"], &Map.put(&1, "insert", %{}))
        |> update_in(["domain", "writes", "fields"], &Map.delete(&1, "name"))
        |> update_in(["domain", "writes", "transitions"], fn transitions ->
          Map.put(transitions, "phase", %{"draft" => ["ready"]})
        end)
        |> update_in(["domain", "writes", "validations"], &[%{"field" => "status"} | &1])
        |> put_in(["domain", "writes", "constraints"], [])
        |> update_in(["domain", "actions"], &Map.put(&1, "publish", %{}))
        |> update_in(["domain", "capabilities"], &Map.delete(&1, "item.rank"))
        |> put_in(
          ["domain", "choice_sources", "owner_choices", "constraint_policy"],
          %{"domain_of_interest" => "best_effort"}
        )

      File.write!("left.normalized.json", SelectoMix.DomainExport.encode!(artifact))
      File.write!("right.normalized.json", SelectoMix.DomainExport.encode!(changed_artifact))

      assert {:ok, diff} =
               SelectoMix.DomainExport.diff_files(
                 "left.normalized.json",
                 "right.normalized.json"
               )

      assert diff.choice_source_policies.changed == [
               %{
                 id: "owner_choices",
                 left: "domain_of_interest=fail_closed",
                 right: "domain_of_interest=best_effort"
               }
             ]

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Diff.run([
            "left.normalized.json",
            "right.normalized.json"
          ])
        end)

      assert output =~ "detail actions: 1 -> 0 (-1)"
      assert output =~ "write operations: 1 -> 2 (+1)"
      assert output =~ "write fields: 1 -> 0 (-1)"
      assert output =~ "write transitions: 1 -> 2 (+1)"
      assert output =~ "write validations: 1 -> 2 (+1)"
      assert output =~ "write constraints: 1 -> 0 (-1)"
      assert output =~ "actions: 1 -> 2 (+1)"
      assert output =~ "capabilities: 6 -> 5 (-1)"
      assert output =~ "detail actions:"
      assert output =~ "- profile"
      assert output =~ "write operations:"
      assert output =~ "+ insert"
      assert output =~ "write fields:"
      assert output =~ "- name"
      assert output =~ "write transitions:"
      assert output =~ "+ phase"
      assert output =~ "actions:"
      assert output =~ "+ publish"
      assert output =~ "capabilities:"
      assert output =~ "- item.rank"
      assert output =~ "Choice Source Policies:"

      assert output =~
               "owner_choices: domain_of_interest=fail_closed -> domain_of_interest=best_effort"
    end)
  end

  test "generated domain files round-trip through export check inspect and diff artifacts" do
    in_tmp_dir("selecto_mix_generated_domain_round_trip", fn ->
      suffix = System.unique_integer([:positive])
      schema_module = Module.concat(["GeneratedRoundTrip#{suffix}"])

      domain_module =
        Module.concat(["TmpRoundTrip.SelectoDomains.GeneratedRoundTrip#{suffix}Domain"])

      overlay_module =
        Module.concat([
          "TmpRoundTrip.SelectoDomains.Overlays.GeneratedRoundTrip#{suffix}DomainOverlay"
        ])

      config = %{
        schema_module: schema_module,
        table_name: "round_trip_items",
        primary_key: :id,
        fields: [:id, :name, :status],
        field_types: %{id: :integer, name: :string, status: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{"status" => %{type: :string}},
          default_order: []
        },
        metadata: %{
          module_name: "GeneratedRoundTrip#{suffix}",
          context_name: "RoundTrip"
        }
      }

      generated =
        DomainGenerator.generate_domain_file(schema_module, config, app_name: "TmpRoundTrip")

      Code.compile_string("""
      defmodule #{inspect(overlay_module)} do
        def overlay, do: %{}
      end
      """)

      Code.compile_string(generated)
      assert function_exported?(domain_module, :domain, 0)

      Mix.Task.reenable("selecto.domain.check")
      Mix.Task.reenable("selecto.domain.import")
      Mix.Task.reenable("selecto.domain.inspect")
      Mix.Task.reenable("selecto.domain.diff")
      Mix.Task.reenable("selecto.domain.docs")
      Mix.Task.reenable("selecto.domain.describe")
      Mix.Task.reenable("selecto.domain.diagram")

      assert {:ok, artifact} = SelectoMix.DomainExport.export(domain_module)
      File.write!("generated.normalized.json", SelectoMix.DomainExport.encode!(artifact))

      check_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Check.run(["generated.normalized.json"])
        end)

      assert check_output =~ "Checked normalized domain JSON: generated.normalized.json"
      assert check_output =~ "Schema version: 1"
      assert check_output =~ "Domain version: 0.1.0"
      assert check_output =~ "Domain fingerprint: (unfingerprinted)"

      import_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Import.run(["generated.normalized.json", "--check"])
        end)

      assert import_output =~ "Checked normalized domain import plan: generated.normalized.json"
      assert import_output =~ "Domain version: 0.1.0"
      assert import_output =~ "Domain fingerprint: (unfingerprinted)"
      assert import_output =~ "Name: GeneratedRoundTrip#{suffix} Domain"
      assert import_output =~ "Generated-domain preview:"
      assert import_output =~ "target module: #{inspect(domain_module)}"
      assert import_output =~ "source: 1 (reconstructable)"

      inspect_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Inspect.run(["generated.normalized.json"])
        end)

      assert inspect_output =~ "Name: GeneratedRoundTrip#{suffix} Domain"
      assert inspect_output =~ "Domain version: 0.1.0"
      assert inspect_output =~ "Domain fingerprint: (unfingerprinted)"
      assert inspect_output =~ "source fields: 3"
      assert inspect_output =~ "filters: status"

      docs_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Docs.run([
            "generated.normalized.json",
            "--output",
            "docs/selecto/generated.md"
          ])
        end)

      assert docs_output =~ "Wrote normalized domain Markdown docs: docs/selecto/generated.md"

      generated_docs = File.read!("docs/selecto/generated.md")

      assert generated_docs =~ "# GeneratedRoundTrip#{suffix} Domain"
      assert generated_docs =~ "| Fields | id, name, status |"
      assert generated_docs =~ "### Filters"
      assert generated_docs =~ "| status |  | string |  |"

      describe_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Describe.run([
            "generated.normalized.json",
            "--output",
            "priv/selecto/generated.inspection.json"
          ])
        end)

      assert describe_output =~
               "Wrote normalized domain inspection JSON: priv/selecto/generated.inspection.json"

      generated_inspection =
        "priv/selecto/generated.inspection.json"
        |> File.read!()
        |> Jason.decode!()

      assert generated_inspection["format"] == "selecto.domain_inspection"
      assert generated_inspection["inspection"]["name"] == "GeneratedRoundTrip#{suffix} Domain"
      assert generated_inspection["inspection"]["counts"]["source_fields"] == 3

      diagram_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Diagram.run([
            "priv/selecto/generated.inspection.json",
            "--output",
            "docs/selecto/generated.diagram.mmd"
          ])
        end)

      assert diagram_output =~
               "Wrote normalized domain Mermaid diagram: docs/selecto/generated.diagram.mmd"

      generated_diagram = File.read!("docs/selecto/generated.diagram.mmd")

      assert generated_diagram =~ "flowchart LR"
      assert generated_diagram =~ "Domain: GeneratedRoundTrip#{suffix} Domain"
      assert generated_diagram =~ "Source fields"

      changed_artifact =
        update_in(artifact, ["domain", "filters"], fn filters ->
          Map.put(filters, "priority", %{"type" => "integer"})
        end)

      File.write!(
        "generated.changed.normalized.json",
        SelectoMix.DomainExport.encode!(changed_artifact)
      )

      diff_output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Domain.Diff.run([
            "generated.normalized.json",
            "generated.changed.normalized.json"
          ])
        end)

      assert diff_output =~ "filters: 1 -> 2 (+1)"
      assert diff_output =~ "+ priority"
    end)
  end

  test "raises a clear error for an unexpected artifact format" do
    in_tmp_dir("selecto_mix_domain_check_bad_format", fn ->
      Mix.Task.reenable("selecto.domain.check")
      File.write!("bad.json", Jason.encode!(%{"format" => "other", "format_version" => 1}))

      assert_raise Mix.Error, ~r/Unexpected normalized domain artifact format "other"/, fn ->
        Mix.Tasks.Selecto.Domain.Check.run(["bad.json"])
      end
    end)
  end

  test "raises a clear error when the domain module cannot be loaded" do
    Mix.Task.reenable("selecto.domain.export")

    assert_raise Mix.Error, ~r/Domain module Missing.Domain could not be loaded/, fn ->
      Mix.Tasks.Selecto.Domain.Export.run(["Missing.Domain"])
    end
  end

  defp in_tmp_dir(prefix, fun) do
    base_tmp = System.tmp_dir!()
    tmp_dir = Path.join(base_tmp, "#{prefix}_#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    try do
      File.cd!(tmp_dir, fun)
    after
      File.rm_rf!(tmp_dir)
    end
  end
end
