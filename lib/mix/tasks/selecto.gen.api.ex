defmodule Mix.Tasks.Selecto.Gen.Api do
  @moduledoc """
  Generates a Selecto API endpoint and LiveView control panel.

  The generator creates:

  - a domain-aware API module that maps JSON payloads to SelectoUpdato operations
  - Selecto-powered read/query handlers
  - a Phoenix controller for the API endpoint
  - a LiveView control panel for editing configuration and sending requests
  - choice-source picker hooks for write fields when the domain declares them

  ## Usage

      mix selecto.gen.api orders --domain MyApp.OrdersDomain

  ## Options

    * `--domain` - Domain module used by generated API module (default: inferred)
    * `--schema` - Ecto schema module used for write operations (default: inferred)
    * `--repo` - Repo module used for execution (default: `MyApp.Repo`)
    * `--api-path` - Route path used in controller docs (default: `/api/v1/updato/<name>`)
    * `--panel-path` - Route path used for the control panel (default: `/updato/<name>/control`)
    * `--panel-in-prod` - Include control panel route in production snippets (default: false)
    * `--force` - Overwrite generated files

  The task prints route snippets to add into your `router.ex`.

  For choice-backed write fields, keep option and membership validation
  resolvers server-owned. Assign `:choice_source_options_resolver`,
  `:choice_source_membership_resolver`, and `:choice_source_scope` from the
  generated LiveView using socket/session data rather than browser parameters.
  For HTTP writes, customize the generated controller's `api_config/1` hook with
  the same server-owned resolver and scope. For security-sensitive
  Domain-of-Interest filters, declare
  `constraint_policy: %{domain_of_interest: :fail_closed}` on the choice source
  in the domain overlay and have the resolver return a closed result when a
  trusted filter cannot be enforced.
  """

  use Mix.Task

  import Mix.Generator

  @shortdoc "Generates Selecto API + control panel"

  @switches [
    domain: :string,
    schema: :string,
    repo: :string,
    api_path: :string,
    panel_path: :string,
    panel_in_prod: :boolean,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    case invalid do
      [] -> :ok
      _ -> Mix.raise("Unknown options: #{inspect(invalid)}")
    end

    name = parse_name!(positional)
    app = Mix.Project.config()[:app] |> to_string()
    app_module = Macro.camelize(app)
    web_module = app_module <> "Web"
    name_module = name |> Macro.camelize() |> singularize()
    name_snake = Macro.underscore(name)

    config =
      %{
        app: app,
        app_module: app_module,
        web_module: web_module,
        name_module: name_module,
        name_snake: name_snake,
        domain_module: opts[:domain] || infer_domain_module(app_module, name_module),
        schema_module: opts[:schema] || infer_schema_module(app_module, name_module),
        repo_module: opts[:repo] || app_module <> ".Repo",
        api_path: opts[:api_path] || "/api/v1/updato/#{name_snake}",
        panel_path: opts[:panel_path] || "/updato/#{name_snake}/control",
        panel_in_prod?: !!opts[:panel_in_prod],
        force?: !!opts[:force]
      }

    Mix.shell().info("Generating Selecto API files for #{name}...")

    generate_files(config)
    print_router_snippet(config)
    print_next_steps(config)
  end

  defp parse_name!([name | _]) do
    value = String.trim(name)

    if value == "" do
      Mix.raise("Expected NAME (for example: mix selecto.gen.api orders)")
    end

    value
  end

  defp parse_name!([]) do
    Mix.raise("Missing NAME. Example: mix selecto.gen.api orders")
  end

  defp singularize(value) do
    case String.ends_with?(value, "s") do
      true -> String.slice(value, 0, max(String.length(value) - 1, 1))
      false -> value
    end
  end

  defp infer_domain_module(app_module, name_module) do
    app_module <> "." <> name_module <> "Domain"
  end

  defp infer_schema_module(app_module, name_module) do
    app_module <> ".Hierarchy." <> name_module
  end

  defp generate_files(config) do
    maybe_create(config_path(config, :api_module), api_module_template(config), config.force?)
    maybe_create(config_path(config, :controller), controller_template(config), config.force?)

    maybe_create(
      config_path(config, :control_panel_live),
      control_panel_template(config),
      config.force?
    )
  end

  defp maybe_create(path, content, true), do: create_file(path, content, force: true)
  defp maybe_create(path, content, false), do: create_file(path, content)

  defp config_path(config, :api_module) do
    "lib/#{config.app}/updato_api/#{config.name_snake}_api.ex"
  end

  defp config_path(config, :controller) do
    "lib/#{config.app}_web/controllers/#{config.name_snake}_api_controller.ex"
  end

  defp config_path(config, :control_panel_live) do
    "lib/#{config.app}_web/live/#{config.name_snake}_api_control_panel_live.ex"
  end

  defp api_module_template(config) do
    """
    defmodule #{config.app_module}.UpdatoApi.#{config.name_module}Api do
      @moduledoc \"\"\"
      Generated endpoint adapter for #{config.domain_module}.

      Expected write payload:

          %{
            "action" => "insert" | "update" | "upsert" | "delete",
            "attributes" => map(),
            "filters" => [ [field, value] | %{\"field\" => field, \"value\" => value} ],
            "confirm_bulk_delete" => boolean()
          }

      Expected read payload:

          %{
            "select" => ["id", "name"],
            "filters" => [["status", "active"]],
            "order_by" => [["inserted_at", "desc"]],
            "limit" => 50,
            "offset" => 0
          }
      \"\"\"

      alias Selecto
      alias SelectoUpdato
      alias SelectoUpdato.DomainContract

      @allowed_actions ["insert", "update", "upsert", "delete"]
      @operation_ids @allowed_actions

      @default_config %{
        name: "#{config.name_snake}",
        api_path: "#{config.api_path}",
        panel_path: "#{config.panel_path}",
        domain_module: #{config.domain_module},
        schema_module: #{config.schema_module},
        repo: #{config.repo_module}
      }

      def default_config, do: @default_config

      def choice_source_domain(config \\ @default_config), do: contract_domain(config)

      def write_contract(config \\\\ @default_config, opts \\\\ []) do
        config
        |> contract_domain()
        |> DomainContract.json_document(opts)
      end

      def write_contract_summary(config \\\\ @default_config) do
        case write_contract(config) do
          {:ok, contract, _diagnostics} ->
            %{
              operations: summarize_operation_contracts(Map.get(contract, "operations", [])),
              fields: summarize_field_contracts(Map.get(contract, "fields", [])),
              relationships:
                summarize_relationship_contracts(Map.get(contract, "relationships", [])),
              diagnostics: Map.get(contract, "diagnostics", %{})
            }

          {:error, diagnostics} ->
            %{operations: %{}, fields: %{}, relationships: %{}, diagnostics: diagnostics}
        end
      end

      def validate_intent(params, config \\\\ @default_config) when is_map(params) do
        result =
          DomainContract.validate_intent(
            contract_domain(config),
            normalize_intent(params),
            operation_options(config)
          )

        {:ok,
         DomainContract.json_safe(%{
           valid: Map.fetch!(result, :valid?),
           errors: Map.get(result, :errors, []),
           warnings: Map.get(result, :warnings, [])
         })}
      end

      def preview_domain_action(action, params, config \\\\ @default_config) when is_map(params) do
        with {:ok, plan} <- build_domain_action_plan(action, params, config) do
          {:ok, action_plan_payload(plan)}
        else
          {:error, error} when is_map(error) -> {:error, action_plan_error(error)}
          {:error, reason} -> {:error, reason}
        end
      end

      def apply_domain_action(action, params, config \\\\ @default_config) when is_map(params) do
        with {:ok, plan} <- build_domain_action_plan(action, params, config),
             {:ok, result} <- apply_action_plan(plan, params, config) do
          {:ok,
           %{
             action: plan.action,
             operation: plan.operation,
             preview: action_plan_payload(plan),
             result: result
           }}
        else
          {:error, error} when is_map(error) -> {:error, action_plan_error(error)}
          {:error, reason} -> {:error, reason}
        end
      end

      def write_template_operations(config \\\\ @default_config) do
        operations =
          config
          |> write_contract_summary()
          |> Map.get(:operations, %{})
          |> Enum.filter(fn {_operation, enabled} -> enabled == true end)
          |> Enum.map(fn {operation, _enabled} -> operation end)
          |> Enum.sort()

        case operations do
          [] -> @allowed_actions
          operations -> operations
        end
      end

      def write_request_template(operation \\\\ "insert", config \\\\ @default_config) do
        operation = normalize_action(operation)

        operation
        |> build_write_template(write_contract_summary(config))
        |> DomainContract.json_safe()
      end

      def write_request_template_json(operation \\\\ "insert", config \\\\ @default_config) do
        operation
        |> write_request_template(config)
        |> Jason.encode!(pretty: true)
      end

      def write_form_config(operation \\\\ "insert", config \\\\ @default_config) do
        operation = normalize_action(operation)
        summary = write_contract_summary(config)

        %{
          operation: operation,
          fields: form_field_entries(operation, summary.fields),
          filters: form_filter_entries(operation)
        }
        |> DomainContract.json_safe()
      end

      def write_request_from_form(operation, params, config \\\\ @default_config)
          when is_map(params) do
        operation = normalize_action(operation)
        form_config = write_form_config(operation, config)
        fields = map_value(params, :fields, %{})
        filters = map_value(params, :filters, %{})

        %{
          action: operation,
          filters: form_filter_values(map_value(form_config, :filters, []), filters)
        }
        |> maybe_put_template_attributes(
          operation,
          form_attribute_values(map_value(form_config, :fields, []), fields)
        )
        |> maybe_put_confirm_bulk_delete(operation)
        |> DomainContract.json_safe()
      end

      def validate_write_form(operation, params, config \\\\ @default_config) when is_map(params) do
        operation = normalize_action(operation)
        form_config = write_form_config(operation, config)
        request = write_request_from_form(operation, params, config)
        {:ok, contract_validation} = validate_intent(request, config)

        errors =
          form_required_errors(form_config, params) ++
            Map.get(contract_validation, "errors", [])

        field_errors = validation_errors_by(errors, "field")
        filter_errors = validation_errors_by(errors, "filter")

        %{
          valid: errors == [],
          errors: errors,
          warnings: Map.get(contract_validation, "warnings", []),
          field_errors: field_errors,
          filter_errors: filter_errors
        }
        |> DomainContract.json_safe()
      end

      def execute(params, config \\\\ @default_config) when is_map(params) do
        with :ok <- validate_write_params(params),
             :ok <- validate_choice_source_params(params, config),
             {:ok, operation} <- build_operation(params, config),
             {:ok, result} <- SelectoUpdato.execute(operation, config.repo) do
          {:ok, %{result: result, action: Map.get(params, "action", "insert")}}
        end
      end

      def query(params, config \\\\ @default_config) when is_map(params) do
        requested_limit = Map.get(params, "limit")
        query_params = apply_execution_limit(params, requested_limit)

        with :ok <- validate_query_params(params),
             {:ok, selecto} <- build_query(query_params, config),
             {:ok, {rows, columns, aliases}} <- Selecto.execute(selecto) do
          {rows, page_meta} = paginate_rows(rows, requested_limit, Map.get(params, "offset", 0))

          {:ok, %{rows: rows, columns: columns, aliases: aliases, page: page_meta}}
        end
      end

      def get_by_id(id, config \\\\ @default_config, opts \\\\ []) do
        with :ok <- validate_id(id) do
          primary_key = primary_key(config)

          params = %{
            "filters" => [[to_string(primary_key), id]],
            "limit" => 1,
            "select" => Keyword.get(opts, :select)
          }

          with {:ok, %{rows: rows, aliases: aliases}} <- query(params, config) do
            case rows do
              [row | _] -> {:ok, %{row: row, aliases: aliases}}
              _ -> {:error, :not_found}
            end
          end
        end
      end

      defp build_operation(params, config) do
        action = params |> Map.get("action", "insert") |> normalize_action()
        attributes = normalize_attributes(Map.get(params, "attributes", %{}), config)
        filters = normalize_filters(Map.get(params, "filters", []))
        domain = domain_for_write(config)

        operation =
          domain
          |> SelectoUpdato.new(operation_options(config))
          |> apply_filters(filters)
          |> apply_action(action, attributes, params)

        {:ok, operation}
      rescue
        error -> {:error, {:invalid_request, Exception.message(error)}}
      end

      defp build_domain_action_plan(action, params, config) do
        SelectoUpdato.plan_domain_action(contract_domain(config), domain_action_intent(action, params, config))
      end

      defp apply_action_plan(plan, params, config) do
        case SelectoUpdato.ActionExecutionAdapter.for_config(config) do
          {:ok, adapter} ->
            context = action_execution_context(params, config)

            if truthy?(map_value(params, :dry_run)) do
              SelectoUpdato.ActionExecutionAdapter.dry_run(adapter, plan, context)
            else
              SelectoUpdato.ActionExecutionAdapter.execute(adapter, plan, context)
            end

          {:error, reason} ->
            {:error, reason}

          :none ->
            with :ok <- ensure_action_dry_run_supported(params),
                 :ok <- ensure_action_apply_supported(plan),
                 {:ok, operation} <- operation_from_action_plan(plan, config) do
              SelectoUpdato.execute(operation, config.repo)
            end
        end
      end

      defp action_execution_context(params, config) do
        %{
          repo: map_value(config, :repo),
          params: params,
          contract_domain: contract_domain(config),
          write_domain: domain_for_write(config)
        }
        |> maybe_put(:actor, map_value(config, :actor))
        |> maybe_put(:tenant, map_value(config, :tenant))
        |> maybe_put(:scope, map_value(config, :action_scope))
      end

      defp ensure_action_dry_run_supported(params) do
        if truthy?(map_value(params, :dry_run)) do
          {:error,
           {:validation_error, "Action apply dry-run requires an action execution adapter.",
            DomainContract.json_safe(%{code: :unsupported_action_dry_run})}}
        else
          :ok
        end
      end

      defp ensure_action_apply_supported(plan) do
        if map_size(plan.collection_operations || %{}) > 0 do
          {:error,
           {:validation_error,
            "Action apply with collection operations requires an action execution adapter.",
            DomainContract.json_safe(%{
              code: :unsupported_action_collection_apply,
              collection_operations: plan.collection_operations
            })}}
        else
          :ok
        end
      end

      defp maybe_put(map, _key, nil), do: map
      defp maybe_put(map, _key, value) when value == %{}, do: map
      defp maybe_put(map, key, value), do: Map.put(map, key, value)

      defp operation_options(config) do
        scope = map_value(config, :choice_source_scope, %{})

        [
          actor:
            map_value(config, :actor, map_value(config, :choice_source_actor, map_value(scope, :actor))),
          tenant:
            map_value(config, :tenant, map_value(config, :choice_source_tenant, map_value(scope, :tenant))),
          choice_source_domain: map_value(config, :choice_source_domain),
          choice_source_membership_resolver: map_value(config, :choice_source_membership_resolver),
          choice_source_context: map_value(config, :choice_source_context, map_value(scope, :context, %{})),
          choice_source_filters: map_value(config, :choice_source_filters, map_value(scope, :filters, [])),
          choice_source_record: map_value(config, :choice_source_record, map_value(scope, :record)),
          choice_source_metadata: map_value(config, :choice_source_metadata, map_value(scope, :metadata, %{}))
        ]
        |> Enum.reject(fn
          {:choice_source_membership_resolver, resolver} -> not is_function(resolver, 1)
          {_key, value} -> value in [nil, %{}, []]
        end)
      end

      defp operation_from_action_plan(plan, config) do
        operation =
          config
          |> domain_for_write()
          |> SelectoUpdato.new(operation_options(config))
          |> apply_filters(plan.filters)
          |> apply_action(plan.operation, plan.changes, %{})
          |> maybe_set_returning(plan.returning)

        {:ok, operation}
      rescue
        error -> {:error, {:invalid_request, Exception.message(error)}}
      end

      defp domain_action_intent(action, params, config) do
        body =
          case Map.get(params, "intent") || Map.get(params, :intent) do
            %{} = intent -> intent
            _ -> params
          end

        action_id = normalize_domain_action(action || map_value(body, :action))
        filters = List.wrap(map_value(body, :filters, [])) ++ trusted_action_filters(action_id, body, config)

        body
        |> Map.drop(["_format", "action", :action])
        |> Map.put("action", action_id)
        |> Map.put("filters", filters)
      end

      defp trusted_action_filters(action, params, config) do
        source =
          Map.get(config, :action_scope_filters) ||
            Map.get(config, "action_scope_filters") ||
            Map.get(config, :trusted_action_filters) ||
            Map.get(config, "trusted_action_filters") ||
            []

        filters =
          cond do
            is_function(source, 3) -> source.(action, params, config)
            is_function(source, 2) -> source.(action, params)
            is_function(source, 1) -> source.(params)
            true -> source
          end

        List.wrap(filters)
      end

      defp action_plan_payload(plan) do
        %{
          valid: true,
          action: plan.action,
          capability: plan.capability,
          operation: plan.operation,
          operation_intent: plan.operation_intent,
          inputs: plan.inputs,
          variant: plan.variant,
          execution_case: plan.execution_case,
          target: plan.target,
          filters: Enum.map(plan.filters, &action_filter_payload/1),
          changes: plan.changes,
          collection_patches: plan.collection_patches,
          collection_operations: plan.collection_operations,
          returning: plan.returning,
          transition: plan.transition,
          preconditions: plan.preconditions,
          diagnostics: plan.diagnostics,
          operation_builder: operation_builder_payload(plan.operation_builder)
        }
        |> DomainContract.json_safe()
      end

      defp action_filter_payload({field, value}), do: %{field: field, comparator: "eq", value: value}
      defp action_filter_payload({field, comparator, value}), do: %{field: field, comparator: comparator, value: value}
      defp action_filter_payload(filter), do: filter

      defp operation_builder_payload(nil), do: nil

      defp operation_builder_payload(operation) do
        %{
          type: Map.get(operation, :type),
          filters: Map.get(operation, :filters, []),
          changes: Map.get(operation, :changes),
          attrs: Map.get(operation, :attrs),
          returning: Map.get(operation, :returning)
        }
      end

      defp action_plan_error(error) do
        {:validation_error, Map.get(error, :message, "action could not be planned"), DomainContract.json_safe(error)}
      end

      defp build_query(params, config) do
        domain = config.domain_module.domain()

        selecto =
          domain
          |> Selecto.configure(config.repo)
          |> maybe_select(Map.get(params, "select"))
          |> apply_query_filters(normalize_filters(Map.get(params, "filters", [])))
          |> apply_order_by(normalize_order_by(Map.get(params, "order_by", [])), config)
          |> maybe_limit(Map.get(params, "limit"))
          |> maybe_offset(Map.get(params, "offset"))

        {:ok, selecto}
      rescue
        error -> {:error, {:invalid_query, Exception.message(error)}}
      end

      defp normalize_action(value) when is_binary(value), do: String.downcase(value)
      defp normalize_action(value) when is_atom(value), do: value |> Atom.to_string() |> String.downcase()
      defp normalize_action(_), do: "insert"

      defp normalize_domain_action(value) when is_binary(value), do: String.downcase(value)
      defp normalize_domain_action(value) when is_atom(value), do: value |> Atom.to_string() |> String.downcase()
      defp normalize_domain_action(value), do: value |> to_string() |> String.downcase()

      defp validate_id(id) when id in [nil, ""], do: {:error, {:validation_error, "id is required"}}
      defp validate_id(_id), do: :ok

      defp validate_write_params(params) when is_map(params) do
        action = params |> Map.get("action", "insert") |> normalize_action()

        cond do
          action not in @allowed_actions ->
            {:error, {:validation_error, "action must be one of insert|update|upsert|delete"}}

          action in ["insert", "update", "upsert"] and not is_map(Map.get(params, "attributes", %{})) ->
            {:error, {:validation_error, "attributes must be a map for insert/update/upsert"}}

          action == "delete" and Map.has_key?(params, "confirm_bulk_delete") and
              not is_boolean(Map.get(params, "confirm_bulk_delete")) ->
            {:error, {:validation_error, "confirm_bulk_delete must be a boolean"}}

          Map.has_key?(params, "filters") and not is_list(Map.get(params, "filters")) ->
            {:error, {:validation_error, "filters must be a list"}}

          true ->
            :ok
        end
      end

      defp validate_query_params(params) when is_map(params) do
        cond do
          Map.has_key?(params, "filters") and not is_list(Map.get(params, "filters")) ->
            {:error, {:validation_error, "filters must be a list"}}

          Map.has_key?(params, "order_by") and not is_list(Map.get(params, "order_by")) ->
            {:error, {:validation_error, "order_by must be a list"}}

          Map.has_key?(params, "select") and not valid_select?(Map.get(params, "select")) ->
            {:error, {:validation_error, "select must be a string or list"}}

          Map.has_key?(params, "limit") and not valid_limit?(Map.get(params, "limit")) ->
            {:error, {:validation_error, "limit must be a positive integer"}}

          Map.has_key?(params, "offset") and not valid_offset?(Map.get(params, "offset")) ->
            {:error, {:validation_error, "offset must be a non-negative integer"}}

          true ->
            :ok
        end
      end

      defp valid_select?(value) when is_binary(value) or is_list(value), do: true
      defp valid_select?(_), do: false

      defp valid_limit?(value) when is_integer(value) and value > 0, do: true
      defp valid_limit?(_), do: false

      defp valid_offset?(value) when is_integer(value) and value >= 0, do: true
      defp valid_offset?(_), do: false

      defp apply_filters(operation, filters) do
        Enum.reduce(filters, operation, fn filter, op -> SelectoUpdato.filter(op, filter) end)
      end

      defp apply_action(operation, "insert", attributes, _params),
        do: SelectoUpdato.insert(operation, attributes)

      defp apply_action(operation, "update", attributes, _params),
        do: SelectoUpdato.update(operation, attributes)

      defp apply_action(operation, "upsert", attributes, params) do
        operation = SelectoUpdato.upsert(operation, attributes)

        case Map.get(params, "conflict_target") do
          nil -> operation
          target -> SelectoUpdato.conflict_target(operation, target)
        end
      end

      defp apply_action(operation, "delete", _attributes, params) do
        operation = SelectoUpdato.delete(operation)

        if Map.get(params, "confirm_bulk_delete", false) do
          SelectoUpdato.confirm_bulk_delete(operation, true)
        else
          operation
        end
      end

      defp apply_action(operation, _action, attributes, _params),
        do: SelectoUpdato.insert(operation, attributes)

      defp maybe_set_returning(operation, nil), do: operation
      defp maybe_set_returning(operation, []), do: operation
      defp maybe_set_returning(operation, "record"), do: SelectoUpdato.returning(operation, :record)
      defp maybe_set_returning(operation, "records"), do: SelectoUpdato.returning(operation, :records)
      defp maybe_set_returning(operation, "count"), do: SelectoUpdato.returning(operation, :count)
      defp maybe_set_returning(operation, "none"), do: SelectoUpdato.returning(operation, :none)
      defp maybe_set_returning(operation, returning), do: SelectoUpdato.returning(operation, returning)

      defp apply_query_filters(selecto, filters) do
        Enum.reduce(filters, selecto, fn {field, value}, query ->
          Selecto.filter(query, {field, value})
        end)
      end

      defp apply_order_by(selecto, orders, config) do
        case orders do
          [] -> Selecto.order_by(selecto, {to_string(primary_key(config)), :asc})

          _ ->
            Enum.reduce(orders, selecto, fn {field, dir}, query ->
              Selecto.order_by(query, {field, normalize_order_dir(dir)})
            end)
        end
      end

      defp maybe_select(selecto, nil), do: selecto
      defp maybe_select(selecto, []), do: selecto
      defp maybe_select(selecto, fields) when is_list(fields), do: Selecto.select(selecto, fields)
      defp maybe_select(selecto, field) when is_binary(field), do: Selecto.select(selecto, [field])
      defp maybe_select(selecto, _), do: selecto

      defp maybe_limit(selecto, value) when is_integer(value) and value > 0,
        do: Selecto.limit(selecto, value)

      defp maybe_limit(selecto, _), do: selecto

      defp maybe_offset(selecto, value) when is_integer(value) and value >= 0,
        do: Selecto.offset(selecto, value)

      defp maybe_offset(selecto, _), do: selecto

      defp normalize_order_by(orders) when is_list(orders) do
        orders
        |> Enum.map(&normalize_order_spec/1)
        |> Enum.reject(&is_nil/1)
      end

      defp normalize_order_by(_), do: []

      defp normalize_order_spec([field, dir]), do: {to_string(field), dir}
      defp normalize_order_spec({field, dir}), do: {to_string(field), dir}

      defp normalize_order_spec(%{"field" => field, "dir" => dir}),
        do: {to_string(field), dir}

      defp normalize_order_spec(_), do: nil

      defp normalize_order_dir(dir) when dir in [:asc, "asc", :ASC, "ASC"], do: :asc
      defp normalize_order_dir(_), do: :desc

      defp primary_key(config) do
        domain = config.domain_module.domain()

        source =
          case domain do
            %{source: source_map} when is_map(source_map) -> source_map
            _ -> %{}
          end

        source[:primary_key] || source["primary_key"] || :id
      end

      defp normalize_filters(filters) when is_list(filters) do
        filters
        |> Enum.map(&normalize_filter/1)
        |> Enum.reject(&is_nil/1)
      end

      defp normalize_filters(_), do: []

      defp normalize_filter([field, value]), do: {to_string(field), value}
      defp normalize_filter({field, value}), do: {to_string(field), value}

      defp normalize_filter(%{"field" => field, "value" => value}) do
        {to_string(field), value}
      end

      defp normalize_filter(_), do: nil

      defp apply_execution_limit(params, requested_limit)

      defp apply_execution_limit(params, requested_limit)
           when is_integer(requested_limit) and requested_limit > 0 do
        Map.put(params, "limit", requested_limit + 1)
      end

      defp apply_execution_limit(params, _), do: params

      defp paginate_rows(rows, requested_limit, offset)

      defp paginate_rows(rows, requested_limit, offset)
           when is_integer(requested_limit) and requested_limit > 0 do
        has_more = length(rows) > requested_limit
        page_rows = if has_more, do: Enum.take(rows, requested_limit), else: rows

        {page_rows,
         %{
           count: length(page_rows),
           limit: requested_limit,
           offset: normalize_offset(offset),
           has_more: has_more
         }}
      end

      defp paginate_rows(rows, _requested_limit, offset) do
        {rows,
         %{
           count: length(rows),
           limit: nil,
           offset: normalize_offset(offset),
           has_more: false
         }}
      end

      defp normalize_offset(value) when is_integer(value) and value >= 0, do: value
      defp normalize_offset(_), do: 0

      defp normalize_attributes(attrs, config) when is_map(attrs) do
        allowed_fields =
          config.domain_module.domain()
          |> Map.get(:source, %{})
          |> Map.get(:columns, %{})
          |> Map.keys()
          |> MapSet.new()

        Enum.reduce(attrs, %{}, fn {key, value}, acc ->
          key_string = to_string(key)
          key_atom = to_existing_atom_safe(key_string)

          if key_atom && MapSet.member?(allowed_fields, key_atom) do
            Map.put(acc, key_atom, value)
          else
            acc
          end
        end)
      end

      defp normalize_attributes(_, _), do: %{}

      defp normalize_intent(%{} = intent) do
        intent
        |> normalize_operation_alias()
        |> normalize_attribute_alias()
        |> normalize_record_fields()
      end

      defp normalize_operation_alias(intent) do
        cond do
          has_key?(intent, :operation) ->
            intent

          action = map_value(intent, :action) ->
            action_id = to_string(action)

            if action_id in @operation_ids do
              intent
              |> Map.delete(:action)
              |> Map.delete("action")
              |> put_intent_value(:operation, action_id)
            else
              intent
            end

          true ->
            intent
        end
      end

      defp normalize_attribute_alias(intent) do
        cond do
          has_key?(intent, :attrs) or has_key?(intent, :changes) or has_key?(intent, :set) ->
            intent

          attributes = map_value(intent, :attributes) ->
            put_intent_value(intent, :attrs, attributes)

          true ->
            intent
        end
      end

      defp normalize_record_fields(intent) do
        cond do
          has_key?(intent, :fields) or has_key?(intent, :attrs) or has_key?(intent, :changes) or
              has_key?(intent, :set) ->
            intent

          records = map_value(intent, :records) ->
            fields =
              records
              |> List.wrap()
              |> Enum.flat_map(fn
                record when is_map(record) -> Map.keys(record)
                _record -> []
              end)
              |> Enum.map(&to_string/1)
              |> Enum.uniq()

            put_intent_value(intent, :fields, fields)

          true ->
            intent
        end
      end

      defp put_intent_value(intent, key, value) do
        if Enum.any?(Map.keys(intent), &is_binary/1) do
          Map.put(intent, Atom.to_string(key), value)
        else
          Map.put(intent, key, value)
        end
      end

      defp has_key?(map, key) when is_map(map) and is_atom(key) do
        Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
      end

      defp map_value(map, key, default \\\\ nil)

      defp map_value(map, key, default) when is_map(map) and is_atom(key) do
        string_key = Atom.to_string(key)

        cond do
          Map.has_key?(map, key) -> Map.get(map, key)
          Map.has_key?(map, string_key) -> Map.get(map, string_key)
          true -> default
        end
      end

      defp map_value(_map, _key, default), do: default

      defp truthy?(value), do: value in [true, "true", 1, "1"]

      defp summarize_operation_contracts(operations) when is_list(operations) do
        Map.new(operations, fn operation ->
          {Map.get(operation, "id"), Map.get(operation, "enabled", true)}
        end)
      end

      defp summarize_operation_contracts(_operations), do: %{}

      defp summarize_field_contracts(fields) when is_list(fields) do
        Map.new(fields, fn field ->
          {Map.get(field, "id"),
           %{
             label: Map.get(field, "label"),
             type: Map.get(field, "type"),
             insertable: Map.get(field, "insertable"),
             updatable: Map.get(field, "updatable"),
             immutable: Map.get(field, "immutable"),
             write_once: Map.get(field, "write_once"),
             required_on_insert: "insert" in Map.get(field, "required_on", []),
             choice_source: Map.get(field, "choice_source"),
             reference: Map.get(field, "reference"),
             validators: Map.get(field, "validators", [])
           }
           |> compact_summary()}
        end)
      end

      defp summarize_field_contracts(_fields), do: %{}

      defp summarize_relationship_contracts(relationships) when is_list(relationships) do
        Map.new(relationships, fn relationship ->
          {Map.get(relationship, "id"),
           %{
             writable: Map.get(relationship, "writable"),
             cardinality: Map.get(relationship, "cardinality"),
             allowed_ops: Map.get(relationship, "allowed_ops", []),
             required: Map.get(relationship, "required"),
             min_items: Map.get(relationship, "min_items"),
             max_items: Map.get(relationship, "max_items")
           }
           |> compact_summary()}
        end)
      end

      defp summarize_relationship_contracts(_relationships), do: %{}

      defp compact_summary(map) when is_map(map) do
        map
        |> Enum.reject(fn
          {_key, nil} -> true
          {_key, []} -> true
          _entry -> false
        end)
        |> Map.new()
      end

      defp build_write_template(operation, summary) do
        %{action: operation, filters: default_template_filters(operation)}
        |> maybe_put_template_attributes(operation, template_attributes(operation, summary.fields))
        |> maybe_put_confirm_bulk_delete(operation)
      end

      defp default_template_filters(operation)
           when operation in ["update", "upsert", "delete", "soft_delete"] do
        [%{field: "id", value: ""}]
      end

      defp default_template_filters(_operation), do: []

      defp maybe_put_template_attributes(payload, operation, _attributes)
           when operation in ["delete", "soft_delete"] do
        payload
      end

      defp maybe_put_template_attributes(payload, _operation, attributes) do
        Map.put(payload, :attributes, attributes)
      end

      defp maybe_put_confirm_bulk_delete(payload, "delete") do
        Map.put(payload, :confirm_bulk_delete, false)
      end

      defp maybe_put_confirm_bulk_delete(payload, _operation), do: payload

      defp template_attributes(operation, fields) when is_map(fields) do
        fields
        |> template_fields(operation)
        |> Enum.reduce(%{}, fn {field, config}, acc ->
          value = sample_template_value(config)

          if blank_choice_source_value?(config, value) do
            acc
          else
            Map.put(acc, field, value)
          end
        end)
      end

      defp template_attributes(_operation, _fields), do: %{}

      defp template_fields(fields, operation)
           when operation in ["insert", "insert_all", "insert_from_query"] do
        required_fields =
          fields
          |> Enum.filter(fn {_field, config} ->
            Map.get(config, :insertable) == true and
              Map.get(config, :required_on_insert) == true
          end)
          |> sort_template_fields()

        case required_fields do
          [] -> fields |> writable_template_fields(:insertable) |> Enum.take(8)
          fields -> fields
        end
      end

      defp template_fields(fields, operation) when operation in ["update", "soft_delete"] do
        fields
        |> writable_template_fields(:updatable)
        |> Enum.take(8)
      end

      defp template_fields(fields, operation) when operation in ["upsert", "upsert_all"] do
        fields
        |> Enum.filter(fn {_field, config} ->
          Map.get(config, :insertable) == true or Map.get(config, :updatable) == true
        end)
        |> sort_template_fields()
        |> Enum.take(8)
      end

      defp template_fields(fields, _operation) do
        fields
        |> writable_template_fields(:insertable)
        |> Enum.take(8)
      end

      defp writable_template_fields(fields, flag) do
        fields
        |> Enum.filter(fn {_field, config} -> Map.get(config, flag) == true end)
        |> sort_template_fields()
      end

      defp sort_template_fields(fields) do
        Enum.sort_by(fields, fn {field, _config} -> to_string(field) end)
      end

      defp sample_template_value(%{} = config) do
        if choice_source_field?(config),
          do: "",
          else: sample_template_value(Map.get(config, :type))
      end

      defp sample_template_value(type) do
        case type && type |> to_string() |> String.downcase() do
          "integer" -> 0
          "float" -> 0.0
          "decimal" -> "0.0"
          "boolean" -> false
          _type -> ""
        end
      end

      defp form_field_entries(operation, fields) when is_map(fields) do
        fields
        |> template_fields(operation)
        |> Enum.map(fn {field, config} ->
          type = Map.get(config, :type)

          %{
            id: to_string(field),
            label: Map.get(config, :label, humanize_field(field)),
            type: type,
            input_type: input_type_for(type),
            required: field_required_for_operation?(operation, config),
            choice_source: Map.get(config, :choice_source),
            reference: Map.get(config, :reference),
            value: sample_template_value(config)
          }
          |> compact_summary()
        end)
      end

      defp form_field_entries(_operation, _fields), do: []

      defp form_filter_entries(operation) do
        operation
        |> default_template_filters()
        |> Enum.map(fn filter ->
          field = Map.get(filter, :field)

          %{
            field: field,
            label: humanize_field(field),
            input_type: "text",
            value: Map.get(filter, :value, "")
          }
        end)
      end

      defp form_attribute_values(fields, values) when is_list(fields) do
        Enum.reduce(fields, %{}, fn field, acc ->
          id = map_value(field, :id)
          value = value_for_key(values, id, map_value(field, :value, ""))

          if blank_choice_source_value?(field, value) do
            acc
          else
            Map.put(acc, id, coerce_form_value(value, map_value(field, :type)))
          end
        end)
      end

      defp form_attribute_values(_fields, _values), do: %{}

      defp form_filter_values(filters, values) when is_list(filters) do
        Enum.map(filters, fn filter ->
          field = map_value(filter, :field)

          %{
            field: field,
            value: value_for_key(values, field, map_value(filter, :value, ""))
          }
        end)
      end

      defp form_filter_values(_filters, _values), do: []

      defp form_required_errors(form_config, params) do
        field_values = map_value(params, :fields, %{})
        filter_values = map_value(params, :filters, %{})

        field_errors =
          form_config
          |> map_value(:fields, [])
          |> Enum.filter(&(map_value(&1, :required) == true))
          |> Enum.flat_map(fn field ->
            field_id = map_value(field, :id)

            if blank_form_value?(value_for_key(field_values, field_id, nil)) do
              [
                %{
                  code: "required_field_blank",
                  path: "fields",
                  field: field_id,
                  message: "\#{map_value(field, :label, field_id)} is required"
                }
              ]
            else
              []
            end
          end)

        filter_errors =
          form_config
          |> map_value(:filters, [])
          |> Enum.flat_map(fn filter ->
            field = map_value(filter, :field)

            if blank_form_value?(value_for_key(filter_values, field, nil)) do
              [
                %{
                  code: "required_filter_blank",
                  path: "filters",
                  filter: field,
                  message: "\#{map_value(filter, :label, field)} is required"
                }
              ]
            else
              []
            end
          end)

        field_errors ++ filter_errors
      end

      defp validate_choice_source_params(params, config) do
        case choice_source_param_errors(params, config) do
          [] -> :ok
          [error | _errors] -> {:error, {:validation_error, map_value(error, :message, "invalid choice")}}
        end
      end

      defp choice_source_param_errors(params, config) do
        case validate_intent(params, config) do
          {:ok, %{"errors" => errors}} when is_list(errors) ->
            Enum.filter(errors, &choice_source_error?/1)

          {:ok, %{errors: errors}} when is_list(errors) ->
            Enum.filter(errors, &choice_source_error?/1)

          _result ->
            []
        end
      end

      defp choice_source_field?(field) do
        case map_value(field, :choice_source) do
          value when is_binary(value) -> String.trim(value) != ""
          value when is_atom(value) -> not is_nil(value)
          _value -> false
        end
      end

      defp blank_choice_source_value?(field, value) do
        choice_source_field?(field) and blank_form_value?(value)
      end

      defp choice_source_error?(error) do
        error
        |> error_value("code", "")
        |> to_string()
        |> String.starts_with?("choice_source_")
      end

      defp validation_errors_by(errors, key) do
        errors
        |> Enum.reduce(%{}, fn error, acc ->
          case error_value(error, key) do
            nil ->
              acc

            id ->
              Map.update(acc, to_string(id), [error_value(error, "message", "invalid")], fn messages ->
                [error_value(error, "message", "invalid") | messages]
              end)
          end
        end)
        |> Map.new(fn {id, messages} -> {id, Enum.reverse(messages)} end)
      end

      defp error_value(error, key, default \\\\ nil)

      defp error_value(error, "field", default), do: map_value(error, :field, Map.get(error, "field", default))
      defp error_value(error, "filter", default), do: map_value(error, :filter, Map.get(error, "filter", default))
      defp error_value(error, "message", default), do: map_value(error, :message, Map.get(error, "message", default))
      defp error_value(error, "code", default), do: map_value(error, :code, Map.get(error, "code", default))
      defp error_value(error, key, default) when is_map(error), do: Map.get(error, key, default)

      defp blank_form_value?(nil), do: true
      defp blank_form_value?(""), do: true
      defp blank_form_value?(value) when is_binary(value), do: String.trim(value) == ""
      defp blank_form_value?(_value), do: false

      defp value_for_key(values, key, default) when is_map(values) do
        string_key = to_string(key)

        cond do
          Map.has_key?(values, key) -> Map.get(values, key)
          Map.has_key?(values, string_key) -> Map.get(values, string_key)
          true -> default
        end
      end

      defp value_for_key(_values, _key, default), do: default

      defp coerce_form_value(value, type) do
        case type && type |> to_string() |> String.downcase() do
          "integer" -> parse_integer(value)
          "float" -> parse_float(value)
          "boolean" -> value in [true, "true", "on", "1", 1]
          _type -> value
        end
      end

      defp parse_integer(value) when is_integer(value), do: value

      defp parse_integer(value) when is_binary(value) do
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> value
        end
      end

      defp parse_integer(value), do: value

      defp parse_float(value) when is_float(value), do: value
      defp parse_float(value) when is_integer(value), do: value * 1.0

      defp parse_float(value) when is_binary(value) do
        case Float.parse(value) do
          {float, ""} -> float
          _other -> value
        end
      end

      defp parse_float(value), do: value

      defp input_type_for(type) do
        case type && type |> to_string() |> String.downcase() do
          "integer" -> "number"
          "float" -> "number"
          "decimal" -> "number"
          "boolean" -> "checkbox"
          _type -> "text"
        end
      end

      defp field_required_for_operation?(operation, config)
           when operation in ["insert", "insert_all", "insert_from_query"] do
        Map.get(config, :required_on_insert) == true
      end

      defp field_required_for_operation?(_operation, _config), do: false

      defp humanize_field(field) do
        field
        |> to_string()
        |> String.replace("_", " ")
        |> String.capitalize()
      end

      defp to_existing_atom_safe(value) when is_binary(value) do
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError -> nil
        end
      end

      defp domain_for_write(config) do
        domain = config.domain_module.domain()
        source_map = Map.get(domain, :source, %{})
        columns = if is_map(source_map), do: Map.get(source_map, :columns, %{}), else: %{}

        domain
        |> Map.put(:source, config.schema_module)
        |> Map.put_new(:columns, columns)
      end

      defp contract_domain(config), do: config.domain_module.domain()
    end
    """
  end

  defp controller_template(config) do
    """
    defmodule #{config.web_module}.#{config.name_module}ApiController do
      use #{config.web_module}, :controller

      plug :reject_large_payload when action in [:create, :query, :preview_action, :apply_action]
      plug :throttle_requests when action in [:create, :query, :show, :preview_action, :apply_action]

      alias #{config.app_module}.UpdatoApi.#{config.name_module}Api

      def create(conn, params) do
        with :ok <- authorize_api_request(conn, :create),
             {:ok, payload} <- #{config.name_module}Api.execute(params, api_config(conn)) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
          end
      end

      def preview_action(conn, %{"action" => action} = params) do
        with :ok <- authorize_api_request(conn, {:preview_action, action}),
             {:ok, payload} <- #{config.name_module}Api.preview_domain_action(action, params, api_config(conn)) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      def apply_action(conn, %{"action" => action} = params) do
        with :ok <- authorize_api_request(conn, {:apply_action, action}),
             {:ok, payload} <- #{config.name_module}Api.apply_domain_action(action, params, api_config(conn)) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      def query(conn, params) do
        with :ok <- authorize_api_request(conn, :query),
             {:ok, payload} <- #{config.name_module}Api.query(params) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      def show(conn, %{"id" => id} = params) do
        opts = [select: Map.get(params, "select")]

        with :ok <- authorize_api_request(conn, :show),
             {:ok, payload} <-
               #{config.name_module}Api.get_by_id(
                 id,
                 #{config.name_module}Api.default_config(),
                 opts
               ) do
          json(conn, success_envelope(conn, payload))
        else
          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(error_envelope(conn, :not_found))

          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      def config(conn, _params) do
        with :ok <- authorize_api_request(conn, :config),
             {:ok, write_contract, _diagnostics} <- #{config.name_module}Api.write_contract() do
          json(
            conn,
            success_envelope(conn, %{
              config: #{config.name_module}Api.default_config(),
              write_contract: write_contract,
              capabilities: #{config.name_module}Api.write_contract_summary()
            })
          )
        else
          {:error, reason} ->
            conn
            |> put_status(status_for_reason(reason))
            |> json(error_envelope(conn, reason))
        end
      end

      defp authorize_api_request(_conn, _action), do: :ok

      defp api_config(_conn) do
        #{config.name_module}Api.default_config()
      end

      defp reject_large_payload(conn, _opts) do
        max_bytes = Application.get_env(:#{config.app}, :selecto_api_max_request_bytes, 200_000)

        case List.first(get_req_header(conn, "content-length")) do
          nil ->
            conn

          content_length ->
            case Integer.parse(content_length) do
              {size, _} when size > max_bytes ->
                conn
                |> put_status(:payload_too_large)
                |> json(error_envelope(conn, {:payload_too_large, max_bytes}))
                |> halt()

              _ ->
                conn
            end
        end
      end

      defp throttle_requests(conn, _opts) do
        case Application.get_env(:#{config.app}, :selecto_api_throttler) do
          nil ->
            conn

          throttler when is_atom(throttler) ->
            case throttler.allow?(conn) do
              :ok ->
                conn

              {:error, reason} ->
                conn
                |> put_status(:too_many_requests)
                |> json(error_envelope(conn, {:rate_limited, reason}))
                |> halt()
            end
        end
      end

      defp success_envelope(conn, payload) do
        %{ok: true, data: normalize_for_json(payload), meta: %{request_id: request_id(conn)}}
      end

      defp normalize_for_json(value) when is_list(value) do
        Enum.map(value, &normalize_for_json/1)
      end

      defp normalize_for_json(%_{} = value) do
        case Jason.encode(value) do
          {:ok, _} ->
            value

          {:error, %Protocol.UndefinedError{}} ->
            value
            |> Map.from_struct()
            |> Map.delete(:__meta__)
            |> normalize_for_json()

          {:error, _} ->
            value
            |> Map.from_struct()
            |> Map.delete(:__meta__)
            |> normalize_for_json()
        end
      end

      defp normalize_for_json(value) when is_map(value) do
        Map.new(value, fn {k, v} -> {k, normalize_for_json(v)} end)
      end

      defp normalize_for_json(value), do: value

      defp error_envelope(conn, {:validation_error, message}) do
        %{
          ok: false,
          error: %{code: "validation_error", message: message, details: nil},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:validation_error, message, details}) do
        %{
          ok: false,
          error: %{code: "validation_error", message: message, details: details},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:invalid_request, message}) do
        %{
          ok: false,
          error: %{code: "invalid_request", message: message, details: nil},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:invalid_query, message}) do
        %{
          ok: false,
          error: %{code: "invalid_query", message: message, details: nil},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, :not_found) do
        %{
          ok: false,
          error: %{code: "not_found", message: "not found", details: nil},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:payload_too_large, max_bytes}) do
        %{
          ok: false,
          error: %{code: "payload_too_large", message: "payload exceeds configured size limit", details: %{max_bytes: max_bytes}},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, {:rate_limited, reason}) do
        %{
          ok: false,
          error: %{code: "rate_limited", message: "rate limit exceeded", details: inspect(reason)},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp error_envelope(conn, reason) do
        %{
          ok: false,
          error: %{code: "execution_error", message: "request failed", details: inspect(reason)},
          meta: %{request_id: request_id(conn)}
        }
      end

      defp request_id(conn) do
        conn.assigns[:request_id] || List.first(get_resp_header(conn, "x-request-id"))
      end

      defp status_for_reason({:validation_error, _}), do: :bad_request
      defp status_for_reason({:validation_error, _, _}), do: :bad_request
      defp status_for_reason({:invalid_request, _}), do: :bad_request
      defp status_for_reason({:invalid_query, _}), do: :bad_request
      defp status_for_reason({:payload_too_large, _}), do: :payload_too_large
      defp status_for_reason({:rate_limited, _}), do: :too_many_requests
      defp status_for_reason(:not_found), do: :not_found
      defp status_for_reason(_), do: :unprocessable_entity
    end
    """
  end

  defp control_panel_template(config) do
    """
    defmodule #{config.web_module}.#{config.name_module}ApiControlPanelLive do
      use #{config.web_module}, :live_view
      use SelectoComponents.Form.EventHandlers.ChoiceSourceOperations

      import SelectoComponents.Form.FilterRendering, only: [choice_source_filter_input: 1]

      alias #{config.app_module}.UpdatoApi.#{config.name_module}Api

      @impl true
      def mount(_params, _session, socket) do
        query_json =
          Jason.encode!(%{
            select: [],
            filters: [],
            order_by: [],
            limit: 50,
            offset: 0
          }, pretty: true)

        write_contract = #{config.name_module}Api.write_contract()

        {:ok,
         socket
         |> assign(
           endpoint_config: #{config.name_module}Api.default_config(),
           write_contract_summary: #{config.name_module}Api.write_contract_summary(),
           write_contract_json: encode_contract_for_panel(write_contract),
           write_template_operations: #{config.name_module}Api.write_template_operations(),
           query_json: query_json,
           choice_source_domain: #{config.name_module}Api.choice_source_domain(),
           choice_source_context: %{
             surface: :updato_control_panel,
             path: "#{config.panel_path}"
           },
           last_result: nil,
           error: nil
         )
         |> assign_write_form("insert")}
      end

      @impl true
      def handle_event("request_changed", %{"request_json" => request_json}, socket) do
        {:noreply, assign(socket, request_json: request_json)}
      end

      def handle_event("use_write_template", %{"operation" => operation}, socket) do
        {:noreply, assign_write_form(socket, operation)}
      end

      def handle_event("write_form_changed", %{"write_form" => params}, socket) do
        operation = Map.get(params, "operation", socket.assigns.write_form_operation)
        request = #{config.name_module}Api.write_request_from_form(operation, params)
        validation = #{config.name_module}Api.validate_write_form(operation, params, write_api_config(socket))

        {:noreply,
         assign(socket,
           write_form_operation: operation,
           write_form_values: Map.get(params, "fields", %{}),
           write_form_display_values: Map.get(params, "field_displays", %{}),
           write_filter_values: Map.get(params, "filters", %{}),
           write_form_validation: validation,
           write_field_errors: Map.get(validation, "field_errors", %{}),
           write_filter_errors: Map.get(validation, "filter_errors", %{}),
           request_json: Jason.encode!(request, pretty: true),
           error: nil,
           last_result: nil
         )}
      end

      def handle_event("query_changed", %{"query_json" => query_json}, socket) do
        {:noreply, assign(socket, query_json: query_json)}
      end

      def handle_event("send_request", _params, socket) do
        with {:ok, payload} <- Jason.decode(socket.assigns.request_json),
             {:ok, result} <- #{config.name_module}Api.execute(payload, write_api_config(socket)) do
          {:noreply, assign(socket, last_result: Jason.encode!(result, pretty: true), error: nil)}
        else
          {:error, reason} ->
            {:noreply,
             assign(socket,
               error: format_reason(reason),
               last_result: nil
             )}
        end
      end

      def handle_event("validate_request", _params, socket) do
        with {:ok, payload} <- Jason.decode(socket.assigns.request_json),
             {:ok, result} <- #{config.name_module}Api.validate_intent(payload) do
          {:noreply, assign(socket, last_result: Jason.encode!(result, pretty: true), error: nil)}
        else
          {:error, reason} ->
            {:noreply,
             assign(socket,
               error: format_reason(reason),
               last_result: nil
             )}
        end
      end

      def handle_event("send_query", _params, socket) do
        with {:ok, payload} <- Jason.decode(socket.assigns.query_json),
             {:ok, result} <- #{config.name_module}Api.query(payload) do
          {:noreply, assign(socket, last_result: Jason.encode!(result, pretty: true), error: nil)}
        else
          {:error, reason} ->
            {:noreply, assign(socket, error: format_reason(reason), last_result: nil)}
        end
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <div class="min-h-screen bg-gradient-to-b from-amber-50 via-white to-sky-50 py-10">
          <div class="mx-auto max-w-6xl px-4 sm:px-8">
            <div class="rounded-3xl border border-slate-200 bg-white/85 p-8 shadow-xl backdrop-blur">
              <h1 class="text-3xl font-semibold tracking-tight text-slate-900">Updato API Control Panel</h1>
              <p class="mt-2 text-sm text-slate-600">
                Endpoint: <code class="rounded bg-slate-100 px-2 py-1 text-xs">{@endpoint_config.api_path}</code>
              </p>

              <section class="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                <h2 class="text-base font-medium text-slate-900">Endpoint Configuration</h2>
                <dl class="mt-4 space-y-2 text-sm text-slate-700">
                  <div><dt class="font-medium">Domain Module</dt><dd>{inspect(@endpoint_config.domain_module)}</dd></div>
                  <div><dt class="font-medium">Repo</dt><dd>{inspect(@endpoint_config.repo)}</dd></div>
                  <div><dt class="font-medium">Panel Path</dt><dd>{@endpoint_config.panel_path}</dd></div>
                </dl>
              </section>

              <section id="updato-write-contract" class="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <h2 class="text-base font-medium text-slate-900">Write Contract</h2>
                  <span class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-600">
                    {diagnostics_status(@write_contract_summary.diagnostics)}
                  </span>
                </div>

                <div class="mt-4">
                  <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500">Operations</h3>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <span
                      :for={{operation, enabled} <- Enum.sort_by(@write_contract_summary.operations, fn {operation, _enabled} -> to_string(operation) end)}
                      data-operation-id={operation}
                      class={[
                        "rounded-full px-3 py-1 text-xs font-medium",
                        if(enabled,
                          do: "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200",
                          else: "bg-slate-100 text-slate-500 ring-1 ring-slate-200"
                        )
                      ]}
                    >
                      {operation}
                    </span>
                  </div>
                </div>

                <div class="mt-5">
                  <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500">Writable Fields</h3>
                  <div class="mt-2 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                    <div
                      :for={{field, field_config} <- @write_contract_summary.fields |> Enum.sort_by(fn {field, _field_config} -> to_string(field) end) |> Enum.take(12)}
                      data-field-id={field}
                      class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-xs text-slate-700"
                    >
                      <div class="font-semibold text-slate-900">{field}</div>
                      <div class="mt-1 flex flex-wrap gap-1">
                        <span :if={field_config.insertable} class="rounded bg-emerald-100 px-1.5 py-0.5 text-emerald-700">insert</span>
                        <span :if={field_config.updatable} class="rounded bg-sky-100 px-1.5 py-0.5 text-sky-700">update</span>
                        <span :if={field_config.required_on_insert} class="rounded bg-amber-100 px-1.5 py-0.5 text-amber-700">required</span>
                      </div>
                    </div>
                  </div>
                </div>

                <details class="mt-5">
                  <summary class="cursor-pointer text-sm font-medium text-slate-700">Contract JSON</summary>
                  <pre id="updato-write-contract-json" class="mt-3 max-h-80 overflow-auto rounded-xl bg-slate-950 p-4 text-xs text-slate-100">{@write_contract_json}</pre>
                </details>
              </section>

              <section class="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                <h2 class="text-base font-medium text-slate-900">Write Composer</h2>
                <div id="updato-write-templates" class="mt-3 flex flex-wrap gap-2">
                  <button
                    :for={operation <- @write_template_operations}
                    type="button"
                    phx-click="use_write_template"
                    phx-value-operation={operation}
                    data-template-operation={operation}
                    class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-700 hover:bg-slate-200"
                  >
                    {operation}
                  </button>
                </div>

                <div
                  id="updato-write-validation"
                  data-validation-status={validation_status(@write_form_validation)}
                  class={[
                    "mt-4 rounded-xl border px-3 py-2 text-sm",
                    validation_status(@write_form_validation) == "valid" &&
                      "border-emerald-200 bg-emerald-50 text-emerald-700",
                    validation_status(@write_form_validation) == "invalid" &&
                      "border-rose-200 bg-rose-50 text-rose-700",
                    validation_status(@write_form_validation) == "pending" &&
                      "border-slate-200 bg-slate-50 text-slate-600"
                  ]}
                >
                  {validation_message(@write_form_validation)}
                </div>

                <form id="updato-write-form" class="mt-4 space-y-4" phx-change="write_form_changed">
                  <input type="hidden" name="write_form[operation]" value={@write_form_operation} />

                  <div :if={@write_form_filters != []}>
                    <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500">Target</h3>
                    <div class="mt-2 grid gap-3 sm:grid-cols-2">
                      <.input
                        :for={filter <- @write_form_filters}
                        id={"write-form-filter-\#{filter["field"]}"}
                        name={"write_form[filters][\#{filter["field"]}]"}
                        label={filter["label"]}
                        type={filter["input_type"]}
                        value={Map.get(@write_filter_values, filter["field"], filter["value"])}
                        errors={Map.get(@write_filter_errors, filter["field"], [])}
                      />
                    </div>
                  </div>

                  <div :if={@write_form_fields != []}>
                    <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500">Fields</h3>
                    <div class="mt-2 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                      <div
                        :for={field <- @write_form_fields}
                        data-write-field-id={field["id"]}
                        data-choice-source-id={field["choice_source"]}
                      >
                        <%= if choice_source_field?(field) do %>
                          <label
                            for={"write-form-field-\#{field["id"]}-display"}
                            class="block text-sm font-semibold leading-6 text-zinc-800"
                          >
                            {field["label"]}
                          </label>
                          <.choice_source_filter_input
                            uuid={field["id"]}
                            input_id={"write-form-field-\#{field["id"]}"}
                            display_input_id={"write-form-field-\#{field["id"]}-display"}
                            input_name={"write_form[fields][\#{field["id"]}]"}
                            display_input_name={"write_form[field_displays][\#{field["id"]}]"}
                            value={Map.get(@write_form_values, field["id"], field["value"])}
                            display_value={Map.get(@write_form_display_values, field["id"], "")}
                            metadata={write_choice_source_metadata(field)}
                            input_class="mt-2 block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 shadow-sm focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/20"
                          />
                          <p
                            :for={error <- Map.get(@write_field_errors, field["id"], [])}
                            class="mt-1 text-sm text-rose-600"
                          >
                            {error}
                          </p>
                        <% else %>
                          <.input
                            id={"write-form-field-\#{field["id"]}"}
                            name={"write_form[fields][\#{field["id"]}]"}
                            label={field["label"]}
                            type={field["input_type"]}
                            value={Map.get(@write_form_values, field["id"], field["value"])}
                            required={field["required"]}
                            errors={Map.get(@write_field_errors, field["id"], [])}
                          />
                        <% end %>
                      </div>
                    </div>
                  </div>
                </form>

                <h3 class="mt-5 text-sm font-medium text-slate-900">Write Request JSON</h3>
                <form phx-change="request_changed">
                  <textarea
                    name="request_json"
                    class="mt-3 h-80 w-full rounded-xl border border-slate-300 bg-slate-950 p-4 font-mono text-sm text-emerald-100 focus:border-emerald-500 focus:outline-none"
                  ><%= @request_json %></textarea>
                </form>

                <div class="mt-4 flex items-center gap-3">
                  <button
                    phx-click="validate_request"
                    class="inline-flex items-center rounded-xl bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
                  >
                    Validate Write Request
                  </button>

                  <button
                    phx-click="send_request"
                    class="inline-flex items-center rounded-xl bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700"
                  >
                    Send Write Request
                  </button>

                  <%= if @error do %>
                    <span class="text-sm font-medium text-rose-600">{@error}</span>
                  <% end %>
                </div>
              </section>

              <section class="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                <h2 class="text-base font-medium text-slate-900">Read Query JSON</h2>
                <form phx-change="query_changed">
                  <textarea
                    name="query_json"
                    class="mt-3 h-64 w-full rounded-xl border border-slate-300 bg-slate-900 p-4 font-mono text-sm text-sky-100 focus:border-sky-500 focus:outline-none"
                  ><%= @query_json %></textarea>
                </form>

                <div class="mt-4">
                  <button
                    phx-click="send_query"
                    class="inline-flex items-center rounded-xl bg-cyan-600 px-4 py-2 text-sm font-semibold text-white hover:bg-cyan-700"
                  >
                    Run Read Query
                  </button>
                </div>
              </section>

              <%= if @last_result do %>
                <section class="mt-6 rounded-2xl border border-slate-200 bg-slate-950 p-5">
                  <h2 class="text-base font-medium text-slate-100">Response</h2>
                  <pre class="mt-3 overflow-x-auto whitespace-pre-wrap text-sm text-emerald-100">{@last_result}</pre>
                </section>
              <% end %>
            </div>
          </div>
        </div>
        \"\"\"
      end

      defp assign_write_form(socket, operation) do
        form_config = #{config.name_module}Api.write_form_config(operation)

        assign(socket,
          write_form_operation: form_config["operation"],
          write_form_fields: Map.get(form_config, "fields", []),
          write_form_filters: Map.get(form_config, "filters", []),
          write_form_values: form_values(Map.get(form_config, "fields", []), "id"),
          write_form_display_values: form_display_values(Map.get(form_config, "fields", [])),
          write_filter_values: form_values(Map.get(form_config, "filters", []), "field"),
          write_form_validation: empty_form_validation(),
          write_field_errors: %{},
          write_filter_errors: %{},
          request_json: #{config.name_module}Api.write_request_template_json(operation),
          error: nil,
          last_result: nil
        )
      end

      defp write_api_config(socket) do
        #{config.name_module}Api.default_config()
        |> Map.merge(%{
          choice_source_domain: socket.assigns.choice_source_domain,
          choice_source_membership_resolver: socket.assigns[:choice_source_membership_resolver],
          choice_source_scope: socket.assigns[:choice_source_scope] || %{}
        })
      end

      defp choice_source_field?(%{"choice_source" => choice_source})
           when is_binary(choice_source) and choice_source != "",
           do: true

      defp choice_source_field?(_field), do: false

      defp write_choice_source_metadata(field) do
        %{
          "id" => Map.get(field, "choice_source"),
          "field" => Map.get(field, "id"),
          "transport" => "live",
          "presentation" => %{"control" => "autocomplete", "mode" => "async"},
          "label_field" => choice_source_label_field(field),
          "reference" => Map.get(field, "reference")
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, ""] or value == %{} end)
        |> Map.new()
      end

      defp choice_source_label_field(%{"reference" => %{"caption_source" => source}})
           when is_binary(source) do
        source
        |> String.split(".")
        |> List.last()
      end

      defp choice_source_label_field(_field), do: nil

      defp form_values(entries, id_key) do
        Map.new(entries, fn entry ->
          {Map.get(entry, id_key), Map.get(entry, "value", "")}
        end)
      end

      defp form_display_values(entries) do
        Map.new(entries, fn entry ->
          {Map.get(entry, "id"), ""}
        end)
      end

      defp empty_form_validation do
        %{"valid" => nil, "errors" => [], "warnings" => [], "field_errors" => %{}, "filter_errors" => %{}}
      end

      defp validation_status(%{"valid" => true}), do: "valid"
      defp validation_status(%{"valid" => false}), do: "invalid"
      defp validation_status(_validation), do: "pending"

      defp validation_message(%{"valid" => true}), do: "Composer payload matches the write contract."

      defp validation_message(%{"valid" => false, "errors" => errors}) do
        count = length(errors)
        "Composer payload has \#{count} contract \#{error_word(count)}."
      end

      defp validation_message(_validation), do: "Edit the generated inputs to check the payload."

      defp error_word(1), do: "issue"
      defp error_word(_count), do: "issues"

      defp encode_contract_for_panel({:ok, contract, _diagnostics}) do
        Jason.encode!(contract, pretty: true)
      end

      defp encode_contract_for_panel({:error, diagnostics}) do
        Jason.encode!(%{error: "write contract unavailable", diagnostics: inspect(diagnostics)}, pretty: true)
      end

      defp diagnostics_status(%{} = diagnostics) do
        Map.get(diagnostics, "status") || Map.get(diagnostics, :status) || "projected"
      end

      defp diagnostics_status(_diagnostics), do: "unavailable"

      defp format_reason(reason) when is_binary(reason), do: reason
      defp format_reason(reason), do: inspect(reason)
    end
    """
  end

  defp print_router_snippet(config) do
    Mix.shell().info("""

    Add these routes to your router:

        scope "/api", #{config.web_module} do
          pipe_through :api
          post "#{config.api_path |> String.replace_prefix("/api", "")}", #{config.name_module}ApiController, :create
          post "#{config.api_path |> String.replace_prefix("/api", "")}/actions/:action/preview", #{config.name_module}ApiController, :preview_action
          post "#{config.api_path |> String.replace_prefix("/api", "")}/actions/:action/apply", #{config.name_module}ApiController, :apply_action
          post "#{config.api_path |> String.replace_prefix("/api", "")}/query", #{config.name_module}ApiController, :query
          get "#{config.api_path |> String.replace_prefix("/api", "")}/config", #{config.name_module}ApiController, :config
          get "#{config.api_path |> String.replace_prefix("/api", "")}/:id", #{config.name_module}ApiController, :show
        end

    #{panel_route_snippet(config)}
    """)
  end

  defp panel_route_snippet(config) do
    if config.panel_in_prod? do
      """
          scope "/", #{config.web_module} do
            pipe_through :browser
            live "#{config.panel_path}", #{config.name_module}ApiControlPanelLive
          end
      """
    else
      """
          if Mix.env() != :prod do
            scope "/", #{config.web_module} do
              pipe_through :browser
              live "#{config.panel_path}", #{config.name_module}ApiControlPanelLive
            end
          end
      """
    end
  end

  defp print_next_steps(config) do
    Mix.shell().info("""

    Generated files:
      - #{config_path(config, :api_module)}
      - #{config_path(config, :controller)}
      - #{config_path(config, :control_panel_live)}

    Next steps:
      1. Wire routes in your router using the snippet above.
      2. Start your server and open #{config.panel_path}.
      3. For choice-backed write fields, assign choice-source options and membership resolvers in the generated LiveView.
         Derive actor, tenant, and required filters from socket/session state, not browser parameters.
      4. For security-sensitive choice filters, add constraint_policy: %{domain_of_interest: :fail_closed} in the domain overlay and make resolvers reject unenforced trusted filters.
      5. If the generated controller accepts choice-backed writes, customize api_config/1 with the same server-owned membership resolver and secure scope.
      6. If you expose action apply endpoints, customize authorize_api_request/2 and api_config/1 so actor, tenant, and trusted action filters come from conn/session state, not browser parameters.
    """)
  end
end
