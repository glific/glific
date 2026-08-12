defmodule Glific.Templates.CustomUi do
  @moduledoc """
  Envelope + block-schema validation for Custom UI interactive messages.

  Custom UI templates ride one envelope contract (see
  `plans/web-channel/custom-ui-contract.md` §2, §6, §7 for the frozen wire shape this module
  implements): a `version` + `component` + `props` + `fallback` + optional `context` map goes
  out to the widget; a `message_id` + `component` + `values` + `summary` + optional `context`
  map comes back.

  Two tiers, split by namespace on `component`:

    * `glific/*` — the **published catalog** below. Glific renders these natively, so both
      `props` (at template save) and `values` (on response receipt) are schema-checked against
      the block's published shape.
    * any other namespace (e.g. `tap/*`) — **opaque**. Only the envelope itself is validated;
      `props`/`values` are org-owned and never interpreted here.

  Block schemas are kept data-driven (`@catalog`) so adding a `glific/*` block is a data
  change, not a new code path.
  """

  @component_regex ~r/^[a-z0-9_]+\/[a-z0-9_]+$/

  @outbound_max_bytes 64 * 1024
  @inbound_max_bytes 16 * 1024
  @summary_max_length 500
  @max_json_depth 10

  @type envelope :: map()
  @type response :: map()
  @type block_name :: String.t()

  # ---------------------------------------------------------------------------
  # Published `glific/*` catalog
  # ---------------------------------------------------------------------------

  @catalog %{
    "glific/image_panel" => %{
      required_props: ["id", "options"],
      optional_props: ["body"],
      validate_props: :validate_image_panel_props,
      validate_values: :validate_single_select_values,
      option_key: "options",
      auto_summary: :auto_summary_single_select
    },
    "glific/carousel" => %{
      required_props: ["id", "cards"],
      optional_props: ["body"],
      validate_props: :validate_carousel_props,
      validate_values: :validate_single_select_values,
      option_key: "cards",
      auto_summary: :auto_summary_single_select
    },
    "glific/form" => %{
      required_props: ["fields"],
      optional_props: ["id", "body", "submit_label"],
      validate_props: :validate_form_props,
      validate_values: :validate_form_values,
      auto_summary: :auto_summary_form
    }
  }

  @doc """
  The published `glific/*` block catalog (component name => schema descriptor).
  """
  @spec catalog() :: map()
  def catalog, do: @catalog

  @doc """
  Validate an outbound Custom UI envelope, as stored in
  `interactive_templates.interactive_content` (or one of its per-language `translations`).

  Checked for every namespace: required envelope fields, `component` format, serialized-size
  cap, and JSON-depth cap. For `glific/*` components, `props` is additionally checked against
  the block's published schema.
  """
  @spec validate_payload(envelope()) :: :ok | {:error, String.t()}
  def validate_payload(envelope) when is_map(envelope) do
    with :ok <- validate_required_string(envelope, "component"),
         :ok <- validate_required_string(envelope, "fallback"),
         :ok <- validate_required_string(envelope, "version"),
         :ok <- validate_props_present(envelope),
         :ok <- validate_component_format(envelope["component"]),
         :ok <- validate_size(envelope, @outbound_max_bytes, "Outbound"),
         :ok <- validate_depth(envelope) do
      validate_glific_props(envelope["component"], envelope["props"])
    end
  end

  def validate_payload(_envelope), do: {:error, "Custom UI payload must be a JSON object"}

  @doc """
  Validate an inbound `custom_ui_response` against the outbound envelope it answers.

  Enforces contract §7: required response fields, `summary` length cap, serialized-size cap,
  JSON-depth cap, and — for `glific/*` components — `values` checked against the block's
  published values shape. Also cross-checks the response's `component` echo against the
  outbound envelope's `component`, since a mismatch means the client answered the wrong
  message.

  Correlation (contact owns `message_id`, message is `:custom_ui` and unanswered) is the
  caller's responsibility — this function only validates the envelope contents.
  """
  @spec validate_response(response(), envelope()) :: :ok | {:error, String.t()}
  def validate_response(response, outbound_envelope)
      when is_map(response) and is_map(outbound_envelope) do
    with :ok <- validate_required_string(response, "component"),
         :ok <- validate_required_string(response, "summary"),
         :ok <- validate_summary_length(response["summary"]),
         :ok <- validate_values_present(response),
         :ok <- validate_component_match(response["component"], outbound_envelope["component"]),
         :ok <- validate_size(response, @inbound_max_bytes, "Response"),
         :ok <- validate_depth(response) do
      validate_glific_values(
        response["component"],
        outbound_envelope["props"],
        response["values"]
      )
    end
  end

  def validate_response(_response, _outbound_envelope),
    do: {:error, "Custom UI response must be a JSON object"}

  @doc """
  Server-side auto-summary for a `glific/*` response, mirroring the widget's client-side
  summary builder (contract §1, §6). `glific/*` responses always carry a client-supplied
  `summary`, so this is not on the acceptance path — it exists for server-side surfaces (e.g.
  the flow simulator) that need to compute the same summary without a browser.

  Returns `nil` for a namespace Glific does not own (org namespaces build their own summary).
  """
  @spec auto_summary(block_name(), map(), map()) :: String.t() | nil
  def auto_summary(component, props, values) do
    case Map.get(@catalog, component) do
      %{auto_summary: fun_name} -> apply(__MODULE__, fun_name, [props, values])
      _not_in_catalog -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Generic envelope checks (all namespaces)
  # ---------------------------------------------------------------------------

  @spec validate_required_string(map(), String.t()) :: :ok | {:error, String.t()}
  defp validate_required_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, "Custom UI payload is missing required field '#{key}'"}
    end
  end

  @spec validate_props_present(map()) :: :ok | {:error, String.t()}
  defp validate_props_present(%{"props" => props}) when is_map(props), do: :ok
  defp validate_props_present(_envelope), do: {:error, "Custom UI payload requires a 'props' map"}

  @spec validate_values_present(map()) :: :ok | {:error, String.t()}
  defp validate_values_present(%{"values" => values}) when is_map(values), do: :ok

  defp validate_values_present(_response),
    do: {:error, "Custom UI response requires a 'values' map"}

  @spec validate_component_format(any()) :: :ok | {:error, String.t()}
  defp validate_component_format(component) when is_binary(component) do
    if Regex.match?(@component_regex, component) do
      validate_namespace(component)
    else
      {:error, "Custom UI 'component' must match ^[a-z0-9_]+/[a-z0-9_]+$"}
    end
  end

  defp validate_component_format(_component), do: {:error, "Custom UI 'component' is required"}

  @spec validate_namespace(String.t()) :: :ok | {:error, String.t()}
  defp validate_namespace("glific/" <> _rest = component) do
    if Map.has_key?(@catalog, component),
      do: :ok,
      else: {:error, "'#{component}' is not a published glific/* block"}
  end

  defp validate_namespace(_component), do: :ok

  @spec validate_component_match(any(), any()) :: :ok | {:error, String.t()}
  defp validate_component_match(component, component), do: :ok

  defp validate_component_match(_response_component, _outbound_component),
    do: {:error, "Custom UI response 'component' does not match the outbound message"}

  @spec validate_summary_length(any()) :: :ok | {:error, String.t()}
  defp validate_summary_length(summary) when is_binary(summary) do
    if String.length(summary) <= @summary_max_length,
      do: :ok,
      else: {:error, "Custom UI 'summary' exceeds #{@summary_max_length} characters"}
  end

  defp validate_summary_length(_summary), do: {:error, "Custom UI 'summary' must be a string"}

  @spec validate_size(map(), non_neg_integer(), String.t()) :: :ok | {:error, String.t()}
  defp validate_size(payload, max_bytes, label) do
    size = payload |> Jason.encode!() |> byte_size()

    if size <= max_bytes,
      do: :ok,
      else: {:error, "#{label} Custom UI payload exceeds #{max_bytes} bytes"}
  end

  @spec validate_depth(term()) :: :ok | {:error, String.t()}
  defp validate_depth(payload) do
    if json_depth(payload) <= @max_json_depth,
      do: :ok,
      else: {:error, "Custom UI payload exceeds max JSON depth of #{@max_json_depth}"}
  end

  @spec json_depth(term()) :: non_neg_integer()
  defp json_depth(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.map(&json_depth/1)
    |> max_depth()
  end

  defp json_depth(list) when is_list(list) do
    list
    |> Enum.map(&json_depth/1)
    |> max_depth()
  end

  defp json_depth(_scalar), do: 0

  @spec max_depth(list(non_neg_integer())) :: non_neg_integer()
  defp max_depth([]), do: 1
  defp max_depth(depths), do: 1 + Enum.max(depths)

  # ---------------------------------------------------------------------------
  # `glific/*` props (template save)
  # ---------------------------------------------------------------------------

  @spec validate_glific_props(String.t(), map()) :: :ok | {:error, String.t()}
  defp validate_glific_props("glific/" <> _rest = component, props) do
    schema = Map.fetch!(@catalog, component)

    with :ok <- validate_required_keys(props, schema.required_props, "props"),
         :ok <-
           validate_known_keys(props, schema.required_props ++ schema.optional_props, "props") do
      apply(__MODULE__, schema.validate_props, [props])
    end
  end

  defp validate_glific_props(_component, _props), do: :ok

  @spec validate_required_keys(map(), [String.t()], String.t()) :: :ok | {:error, String.t()}
  defp validate_required_keys(map, required_keys, label) do
    missing = Enum.reject(required_keys, &Map.has_key?(map, &1))

    if missing == [],
      do: :ok,
      else: {:error, "Custom UI #{label} is missing required key(s): #{Enum.join(missing, ", ")}"}
  end

  @spec validate_known_keys(map(), [String.t()], String.t()) :: :ok | {:error, String.t()}
  defp validate_known_keys(map, known_keys, label) do
    unknown = Map.keys(map) -- known_keys

    if unknown == [],
      do: :ok,
      else: {:error, "Custom UI #{label} has unknown key(s): #{Enum.join(unknown, ", ")}"}
  end

  @doc false
  @spec validate_image_panel_props(map()) :: :ok | {:error, String.t()}
  def validate_image_panel_props(%{"id" => id, "options" => options} = props) do
    with :ok <- validate_non_blank_string(id, "options.id"),
         :ok <- validate_optional_string(props["body"], "body") do
      validate_options(options, ["id", "image", "label"], ["id", "image"])
    end
  end

  def validate_image_panel_props(_props), do: {:error, "glific/image_panel props are invalid"}

  @doc false
  @spec validate_carousel_props(map()) :: :ok | {:error, String.t()}
  def validate_carousel_props(%{"id" => id, "cards" => cards} = props) do
    with :ok <- validate_non_blank_string(id, "cards.id"),
         :ok <- validate_optional_string(props["body"], "body") do
      validate_options(cards, ["id", "image", "title", "description"], ["id", "image", "title"])
    end
  end

  def validate_carousel_props(_props), do: {:error, "glific/carousel props are invalid"}

  @doc false
  @spec validate_form_props(map()) :: :ok | {:error, String.t()}
  def validate_form_props(%{"fields" => fields} = props) do
    with :ok <- validate_optional_string(props["id"], "id"),
         :ok <- validate_optional_string(props["body"], "body"),
         :ok <- validate_optional_string(props["submit_label"], "submit_label") do
      validate_fields(fields)
    end
  end

  def validate_form_props(_props), do: {:error, "glific/form props are invalid"}

  @spec validate_options([map()], [String.t()], [String.t()]) :: :ok | {:error, String.t()}
  defp validate_options(options, allowed_keys, required_keys) when is_list(options) do
    count = length(options)

    cond do
      count < 1 or count > 10 ->
        {:error, "Custom UI options/cards must contain between 1 and 10 entries"}

      not Enum.all?(options, &is_map/1) ->
        {:error, "Custom UI options/cards entries must be JSON objects"}

      true ->
        options
        |> Enum.reduce_while(:ok, fn option, :ok ->
          with :ok <- validate_required_keys(option, required_keys, "option"),
               :ok <- validate_known_keys(option, allowed_keys, "option") do
            {:cont, :ok}
          else
            error -> {:halt, error}
          end
        end)
        |> then(fn
          :ok -> validate_unique_ids(options)
          error -> error
        end)
    end
  end

  defp validate_options(_options, _allowed_keys, _required_keys),
    do: {:error, "Custom UI options/cards must be a list"}

  @spec validate_unique_ids([map()]) :: :ok | {:error, String.t()}
  defp validate_unique_ids(options) do
    ids = Enum.map(options, &Map.get(&1, "id"))

    if length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, "Custom UI options/cards must have unique 'id' values"}
  end

  @spec validate_fields([map()]) :: :ok | {:error, String.t()}
  defp validate_fields(fields) when is_list(fields) do
    count = length(fields)

    cond do
      count < 1 or count > 10 ->
        {:error, "glific/form 'fields' must contain between 1 and 10 entries"}

      not Enum.all?(fields, &is_map/1) ->
        {:error, "glific/form 'fields' entries must be JSON objects"}

      true ->
        fields
        |> Enum.reduce_while(:ok, fn field, :ok ->
          with :ok <- validate_required_keys(field, ["id", "label"], "field"),
               :ok <-
                 validate_known_keys(
                   field,
                   ["id", "label", "placeholder", "required"],
                   "field"
                 ) do
            {:cont, :ok}
          else
            error -> {:halt, error}
          end
        end)
        |> then(fn
          :ok -> validate_unique_ids(fields)
          error -> error
        end)
    end
  end

  defp validate_fields(_fields), do: {:error, "glific/form 'fields' must be a list"}

  @spec validate_non_blank_string(any(), String.t()) :: :ok | {:error, String.t()}
  defp validate_non_blank_string(value, _label) when is_binary(value) and value != "", do: :ok

  defp validate_non_blank_string(_value, label),
    do: {:error, "Custom UI '#{label}' must be a non-blank string"}

  @spec validate_optional_string(any(), String.t()) :: :ok | {:error, String.t()}
  defp validate_optional_string(nil, _label), do: :ok
  defp validate_optional_string(value, _label) when is_binary(value), do: :ok

  defp validate_optional_string(_value, label),
    do: {:error, "Custom UI '#{label}' must be a string"}

  # ---------------------------------------------------------------------------
  # `glific/*` values (response receipt)
  # ---------------------------------------------------------------------------

  @spec validate_glific_values(String.t(), map(), map()) :: :ok | {:error, String.t()}
  defp validate_glific_values("glific/" <> _rest = component, props, values) do
    schema = Map.fetch!(@catalog, component)
    apply(__MODULE__, schema.validate_values, [props, values])
  end

  defp validate_glific_values(_component, _props, _values), do: :ok

  @doc false
  @spec validate_single_select_values(map(), map()) :: :ok | {:error, String.t()}
  def validate_single_select_values(props, values) do
    id_key = props["id"]
    option_key = if Map.has_key?(props, "options"), do: "options", else: "cards"
    valid_ids = props |> Map.get(option_key, []) |> Enum.map(&Map.get(&1, "id"))

    case values do
      %{^id_key => selected} when map_size(values) == 1 ->
        if selected in valid_ids,
          do: :ok,
          else: {:error, "Custom UI response value is not one of the offered option ids"}

      _ ->
        {:error, "Custom UI response 'values' must be exactly %{\"#{id_key}\" => <option id>}"}
    end
  end

  @doc false
  @spec validate_form_values(map(), map()) :: :ok | {:error, String.t()}
  def validate_form_values(props, values) do
    field_ids = props |> Map.get("fields", []) |> Enum.map(&Map.get(&1, "id")) |> MapSet.new()
    value_ids = values |> Map.keys() |> MapSet.new()

    cond do
      value_ids != field_ids ->
        {:error, "Custom UI form response 'values' must have exactly one entry per field id"}

      not Enum.all?(Map.values(values), &is_binary/1) ->
        {:error, "Custom UI form response 'values' must be strings"}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Server-side auto-summary (mirrors the widget's client-side builder)
  # ---------------------------------------------------------------------------

  @doc false
  @spec auto_summary_single_select(map(), map()) :: String.t() | nil
  def auto_summary_single_select(props, values) do
    id_key = props["id"]
    option_key = if Map.has_key?(props, "options"), do: "options", else: "cards"
    selected_id = Map.get(values, id_key)

    props
    |> Map.get(option_key, [])
    |> Enum.find(&(Map.get(&1, "id") == selected_id))
    |> case do
      %{"label" => label} -> label
      %{"title" => title} -> title
      _ -> nil
    end
  end

  # Contract §6: fields the contact left empty are skipped entirely (not just shown blank), and
  # a summary is never blank — `summary` becomes the persisted message `body`, so an all-empty
  # form must still substitute a non-empty stand-in.
  @doc false
  @spec auto_summary_form(map(), map()) :: String.t()
  def auto_summary_form(props, values) do
    summary =
      props
      |> Map.get("fields", [])
      |> Enum.reduce([], fn field, acc ->
        value = Map.get(values, Map.get(field, "id"), "")

        if value in ["", nil] do
          acc
        else
          label = Map.get(field, "label", Map.get(field, "id"))
          ["#{label}: #{value}" | acc]
        end
      end)
      |> Enum.reverse()
      |> Enum.join(", ")

    if summary == "", do: "Form submitted with no responses", else: summary
  end
end
