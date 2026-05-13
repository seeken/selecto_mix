defmodule Mix.Tasks.Selecto.Gen.ApiTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "generated API surfaces the domain-authored Updato write contract" do
    in_tmp_dir("selecto_mix_gen_api_contract", fn ->
      Mix.Task.reenable("selecto.gen.api")

      output =
        capture_io(fn ->
          Mix.Tasks.Selecto.Gen.Api.run([
            "orders",
            "--domain",
            "Shop.SelectoDomains.OrderDomain",
            "--schema",
            "Shop.Orders.Order",
            "--repo",
            "Shop.Repo",
            "--api-path",
            "/api/v1/updato/orders",
            "--panel-path",
            "/updato/orders/control"
          ])
        end)

      api_module = File.read!("lib/selecto_mix/updato_api/orders_api.ex")
      controller = File.read!("lib/selecto_mix_web/controllers/orders_api_controller.ex")
      control_panel = File.read!("lib/selecto_mix_web/live/orders_api_control_panel_live.ex")

      assert api_module =~ "alias SelectoUpdato.DomainContract"
      assert api_module =~ "def choice_source_domain(config"
      assert api_module =~ "def write_contract(config \\\\ @default_config, opts \\\\ [])"
      assert api_module =~ "def write_contract_summary(config \\\\ @default_config)"
      assert api_module =~ "def validate_intent(params, config \\\\ @default_config)"
      assert api_module =~ "DomainContract.validate_intent("
      assert api_module =~ "operation_options(config)"

      assert api_module =~
               "def preview_domain_action(action, params, config \\\\ @default_config)"

      assert api_module =~ "def apply_domain_action(action, params, config \\\\ @default_config)"
      assert api_module =~ "SelectoUpdato.plan_domain_action(contract_domain(config)"
      assert api_module =~ "trusted_action_filters(action_id, body, config)"
      assert api_module =~ "def write_template_operations(config \\\\ @default_config)"

      assert api_module =~
               "def write_request_template(operation \\\\ \"insert\", config \\\\ @default_config)"

      assert api_module =~
               "def write_form_config(operation \\\\ \"insert\", config \\\\ @default_config)"

      assert api_module =~
               "def write_request_from_form(operation, params, config \\\\ @default_config)"

      assert api_module =~
               "def validate_write_form(operation, params, config \\\\ @default_config)"

      assert api_module =~ "field_errors: field_errors"
      assert api_module =~ "validate_choice_source_params(params, config)"
      refute api_module =~ "Choices.validate_choice"
      assert api_module =~ "SelectoUpdato.new(operation_options(config))"
      assert api_module =~ "defp operation_options(config)"
      assert api_module =~ "choice_source_domain: map_value(config, :choice_source_domain)"
      assert api_module =~ "choice_source_filters: map_value(config, :choice_source_filters"
      assert api_module =~ "choice_source_record: map_value(config, :choice_source_record"
      assert api_module =~ "choice_source_metadata: map_value(config, :choice_source_metadata"
      assert api_module =~ "choice_source: Map.get(field, \"choice_source\")"
      assert api_module =~ "choice_source: Map.get(config, :choice_source)"
      assert api_module =~ "defp sample_template_value(%{} = config)"
      assert api_module =~ "blank_choice_source_value?(field, value)"
      assert api_module =~ "choice_source_filters"
      assert api_module =~ "value when is_atom(value) -> not is_nil(value)"
      assert api_module =~ "|> DomainContract.json_document(opts)"

      assert controller =~ "write_contract: write_contract"
      assert controller =~ "capabilities: OrderApi.write_contract_summary()"
      assert controller =~ "OrderApi.execute(params, api_config(conn))"
      assert controller =~ "def preview_action(conn, %{\"action\" => action} = params)"
      assert controller =~ "OrderApi.preview_domain_action(action, params, api_config(conn))"
      assert controller =~ "def apply_action(conn, %{\"action\" => action} = params)"
      assert controller =~ "OrderApi.apply_domain_action(action, params, api_config(conn))"
      assert controller =~ "defp api_config(_conn)"
      assert api_module =~ "ensure_action_apply_supported(plan)"
      assert api_module =~ "ActionExecutionAdapter.for_config(config)"
      assert api_module =~ "ensure_action_dry_run_supported(params)"
      assert api_module =~ "preconditions: plan.preconditions"
      assert api_module =~ "unsupported_action_collection_apply"
      assert api_module =~ "unsupported_action_dry_run"

      assert control_panel =~ ~s(id="updato-write-contract")
      assert control_panel =~ ~s(id="updato-write-templates")
      assert control_panel =~ "OrderApi.write_contract()"
      assert control_panel =~ "assign_write_form(\"insert\")"
      assert control_panel =~ ~s(id="updato-write-form")
      assert control_panel =~ ~s(id="updato-write-validation")
      assert control_panel =~ "use SelectoComponents.Form.EventHandlers.ChoiceSourceOperations"

      assert control_panel =~
               "import SelectoComponents.Form.FilterRendering, only: [choice_source_filter_input: 1]"

      assert control_panel =~ "choice_source_domain: OrderApi.choice_source_domain()"
      assert control_panel =~ "write_api_config(socket)"
      assert control_panel =~ ~s(data-choice-source-id={field["choice_source"]})
      assert control_panel =~ ~s(<.choice_source_filter_input)
      assert control_panel =~ ~s(input_name={"write_form[fields][\#{field["id"]}]"})
      assert control_panel =~ ~s(phx-change="write_form_changed")
      assert control_panel =~ "OrderApi.write_request_from_form(operation, params)"

      assert control_panel =~
               "OrderApi.validate_write_form(operation, params, write_api_config(socket))"

      assert control_panel =~ "OrderApi.execute(payload, write_api_config(socket))"
      assert control_panel =~ ~s(phx-click="use_write_template")
      assert control_panel =~ ~s(phx-click="validate_request")

      config_index = output_index(output, ~s(get "/v1/updato/orders/config"))
      show_index = output_index(output, ~s(get "/v1/updato/orders/:id"))

      assert is_integer(config_index)
      assert is_integer(show_index)
      assert config_index < show_index
      assert output =~ ~s(post "/v1/updato/orders/actions/:action/preview")
      assert output =~ ~s(post "/v1/updato/orders/actions/:action/apply")
      assert output =~ "For choice-backed write fields"
      assert output =~ "socket/session state, not browser parameters"
      assert output =~ "constraint_policy: %{domain_of_interest: :fail_closed}"
      assert output =~ "reject unenforced trusted filters"
      assert output =~ "trusted action filters come from conn/session state"
    end)
  end

  defp in_tmp_dir(prefix, fun) do
    tmp_dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    try do
      File.cd!(tmp_dir, fun)
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp output_index(output, value) do
    case :binary.match(output, value) do
      {index, _length} -> index
      :nomatch -> nil
    end
  end
end
