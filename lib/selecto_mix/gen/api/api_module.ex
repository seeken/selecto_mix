defmodule SelectoMix.Gen.Api.ApiModule do
  @moduledoc false

  def render(config) do
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

      def choice_source_domain(config \\\\ @default_config), do: contract_domain(config)

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
        with {:ok, plan} <- build_domain_action_plan(action, params, config),
             :ok <- authorize_action_plan(plan, :preview, action_execution_context(params, config), config) do
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
             :ok <- authorize_query_intent(query_params, config),
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

      defp authorize_query_intent(params, config) do
        cond do
          capability_resolver(config) ->
            validate_query_capabilities(params, config)

          require_capability_resolver?(config) ->
            {:error,
             {:validation_error, "Query capability enforcement requires a host capability resolver.",
              DomainContract.json_safe(%{code: :missing_query_capability_resolver})}}

          true ->
            :ok
        end
      end

      defp validate_query_capabilities(params, config) do
        query_contract_module = Module.concat([SelectoComponents, QueryContract])

        if Code.ensure_loaded?(query_contract_module) and
             function_exported?(query_contract_module, :validate_intent, 3) do
          validation =
            apply(query_contract_module, :validate_intent, [
              contract_domain(config),
              query_capability_intent(params),
              query_capability_opts(config)
            ])

          if map_value(validation, :valid?) do
            :ok
          else
            {:error,
             {:validation_error, "Query capability policy denied the requested query.",
              DomainContract.json_safe(%{
                code: :query_capability_denied,
                errors: map_value(validation, :errors, []),
                warnings: map_value(validation, :warnings, [])
              })}}
          end
        else
          {:error,
           {:validation_error,
            "Query capability enforcement requires SelectoComponents.QueryContract.",
            DomainContract.json_safe(%{code: :query_capability_contract_unavailable})}}
        end
      end

      defp query_capability_opts(config) do
        [
          actor: map_value(config, :actor),
          tenant: map_value(config, :tenant),
          domain: map_value(config, :capability_domain, contract_domain(config)),
          capability_resolver: capability_resolver(config),
          resolver_context: map_value(config, :capability_resolver_context, %{}),
          context:
            %{
              surface: :generated_query_api,
              api_path: map_value(config, :api_path),
              action: :query
            }
            |> Map.merge(map_value(config, :capability_context, %{}))
        ]
        |> Enum.reject(fn {_key, value} -> value in [nil, %{}, []] end)
      end

      defp query_capability_intent(params) do
        %{
          "view_mode" => "detail",
          "select" => Map.get(params, "select", []),
          "filters" =>
            params
            |> Map.get("filters", [])
            |> normalize_filters()
            |> Enum.map(&query_filter_intent/1),
          "order_by" => params |> Map.get("order_by", []) |> normalize_order_by()
        }
      end

      defp query_filter_intent({field, comparator, value}) do
        %{"field" => to_string(field), "comparator" => to_string(comparator), "value" => value}
      end

      defp query_filter_intent({field, value}) do
        %{"field" => to_string(field), "comparator" => "eq", "value" => value}
      end

      defp query_filter_intent(filter), do: filter

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
            context = action_execution_context(params, config)

            with :ok <- authorize_action_plan(plan, action_phase(params), context, config),
                 :ok <- ensure_action_dry_run_supported(params),
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
        |> maybe_put(:capability_resolver, capability_resolver(config))
      end

      defp authorize_action_plan(%{capability: nil}, _phase, _context, _config), do: :ok

      defp authorize_action_plan(plan, phase, context, config) do
        cond do
          resolver = capability_resolver(config) ->
            plan
            |> SelectoUpdato.CapabilityResolver.authorize_action(phase, context,
              capability_resolver: resolver
            )
            |> normalize_action_authorization()

          require_capability_resolver?(config) ->
            plan
            |> SelectoUpdato.CapabilityResolver.authorize_action(phase, context)
            |> normalize_action_authorization()

          true ->
            :ok
        end
      end

      defp normalize_action_authorization({:ok, _decision}), do: :ok
      defp normalize_action_authorization(:ok), do: :ok
      defp normalize_action_authorization({:error, reason}), do: {:error, reason}

      defp capability_resolver(config) do
        map_value(config, :capability_resolver) || map_value(config, :action_capability_resolver)
      end

      defp require_capability_resolver?(config) do
        truthy?(map_value(config, :require_capability_resolver)) ||
          truthy?(map_value(config, :strict_capabilities))
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

      defp action_phase(params) do
        if truthy?(map_value(params, :dry_run)), do: :preview, else: :execute
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
end
