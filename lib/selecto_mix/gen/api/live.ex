defmodule SelectoMix.Gen.Api.Live do
  @moduledoc false

  def render(config) do
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
end
