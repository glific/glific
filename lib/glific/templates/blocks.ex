defmodule Glific.Templates.Blocks do
  @moduledoc """
  Envelope + block-schema validation, unwrap, and derived-body support for Blocks interactive
  messages (see `plans/web-channel/blocks-contract.md` §2, §5, §6, §7, §9 for the frozen wire
  shape this module implements).

  Authored content is stored **typed**: every leaf a human wrote is a `%{"kind" => ..., "value"
  => ...}` node, so the translation walker and the validator can find it without knowing the
  component's schema. `unwrap/1` collapses the typed tree to the plain wire shape the widget
  renders (contract §2.2).

  Two tiers, split by namespace on `component`:

    * `glific/*` — the **published catalog** below. Glific renders these natively, so both
      `props` (at template save) and `values` (on response receipt) are schema-checked against
      the block's published shape.
    * any other namespace (e.g. `tap/*`) — **opaque**. Only the envelope + typed-node shape is
      validated; `props`/`values` are org-owned and never interpreted here.

  Block schemas are kept data-driven (`@catalog`) so adding a `glific/*` block is a data
  change, not a new code path.
  """

  @component_regex ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?\/[a-z0-9]([a-z0-9-]*[a-z0-9])?$/

  @stored_max_bytes 128 * 1024
  @outbound_max_bytes 64 * 1024
  @inbound_max_bytes 16 * 1024
  @summary_max_length 500
  @max_json_depth 10

  @valid_kinds ~w(text alt image url number boolean list)
  @typed_node_keys ~w(kind value translate)

  # Contract §5.1 — flattening flow results means an author-chosen id can overwrite one of
  # these reserved keys (`input` silently replacing what a bare `@results.picker` resolves to
  # is the one that actually bites). Rejected at save, anywhere an "id" appears in `props`.
  @reserved_ids ~w(input category inserted_at summary component value)

  @type envelope :: map()
  @type response :: map()
  @type block_name :: String.t()

  # ---------------------------------------------------------------------------
  # Published `glific/*` catalog
  # ---------------------------------------------------------------------------

  @catalog %{
    "glific/image-panel" => %{
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
  Collapse a typed node tree to its plain wire value (contract §2.2).

  Every typed node — a map whose keys are a subset of `kind`/`value`/`translate` and that
  carries both `kind` and `value` — collapses to exactly its `value`, recursively. This makes
  the unwrapped output byte-identical to what the widget renders, so the widget needs no change
  for typing.
  """
  @spec unwrap(term()) :: term()
  def unwrap(%{"kind" => _kind, "value" => value} = node) do
    if Map.keys(node) -- @typed_node_keys == [] do
      unwrap(value)
    else
      Map.new(node, fn {k, v} -> {k, unwrap(v)} end)
    end
  end

  def unwrap(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, unwrap(v)} end)
  def unwrap(list) when is_list(list), do: Enum.map(list, &unwrap/1)
  def unwrap(value), do: value

  @doc """
  The derived message body (contract §9), replacing the removed `fallback` field.

  Walks `content["props"]` in (a deterministic, sorted-key) document order and concatenates the
  `value` of every `kind: "text"` node, joined with `" — "`, clamped to 500 characters.
  `kind: "alt"` nodes are skipped (contract §2.1, §9) — alt text is accessibility metadata, not
  body copy. Empty/whitespace-only text values are dropped before joining, so a half-filled
  template never produces a leading, trailing, or doubled `" — "`. A block with no (non-blank)
  text nodes (e.g. a Custom Block) derives an empty string; that is accepted, not an error —
  substituting a readable placeholder is the render site's job, not this function's, so the
  derivation stays byte-identical across every repo that implements it.
  """
  @spec derive_body(map()) :: String.t()
  def derive_body(%{"props" => props}) when is_map(props) do
    props
    |> collect_text_values()
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.join(" — ")
    |> clamp(@summary_max_length)
  end

  def derive_body(_content), do: ""

  @spec collect_text_values(term()) :: [String.t()]
  defp collect_text_values(%{"kind" => "text", "value" => value}) when is_binary(value),
    do: [value]

  defp collect_text_values(%{"kind" => "list", "value" => value}) when is_list(value),
    do: collect_text_values(value)

  defp collect_text_values(%{"kind" => _other_kind}), do: []

  defp collect_text_values(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.flat_map(fn {_key, value} -> collect_text_values(value) end)
  end

  defp collect_text_values(list) when is_list(list),
    do: Enum.flat_map(list, &collect_text_values/1)

  defp collect_text_values(_scalar), do: []

  @doc """
  Collect every `text`/`alt` typed node under `content["props"]`, paired with its path (contract
  §10) — a list of `Access`-compatible keys from `content` down to the node's `"value"`, ready
  to hand to `put_translated_nodes/2` for a **by-path**, never-positional reinsert. Both kinds
  are translated; `derive_body/1` is the only place that discriminates between them.
  """
  @spec collect_translatable_nodes(map()) :: [{[term()], String.t()}]
  def collect_translatable_nodes(%{"props" => props}) when is_map(props),
    do: collect_translatable_nodes(props, ["props"])

  def collect_translatable_nodes(_content), do: []

  @spec collect_translatable_nodes(term(), [term()]) :: [{[term()], String.t()}]
  defp collect_translatable_nodes(%{"kind" => kind, "value" => value}, path)
       when kind in ["text", "alt"] and is_binary(value),
       do: [{path ++ ["value"], value}]

  defp collect_translatable_nodes(%{"kind" => "list", "value" => value}, path)
       when is_list(value),
       do: collect_translatable_nodes(value, path ++ ["value"])

  defp collect_translatable_nodes(%{"kind" => _other_kind}, _path), do: []

  defp collect_translatable_nodes(map, path) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.flat_map(fn {key, value} -> collect_translatable_nodes(value, path ++ [key]) end)
  end

  defp collect_translatable_nodes(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      collect_translatable_nodes(item, path ++ [Access.at(index)])
    end)
  end

  defp collect_translatable_nodes(_scalar, _path), do: []

  @doc """
  Reinsert translated text at the paths `collect_translatable_nodes/1` returned — by path, never
  positionally (contract §10), so a reordered or added text node can never land in the wrong
  slot.
  """
  @spec put_translated_nodes(map(), [{[term()], String.t()}]) :: map()
  def put_translated_nodes(content, paths_and_texts) do
    Enum.reduce(paths_and_texts, content, fn {path, text}, acc -> put_in(acc, path, text) end)
  end

  @doc """
  Validate a stored typed Blocks envelope, as kept in
  `interactive_templates.interactive_content` (or one of its per-language `translations`).

  Checked for every namespace: required envelope fields, `component` format, the typed-node
  shape of every node in `props` (contract §2.1), the reserved-id rule (§5.1), the stored-typed
  size cap, and — measured on the *unwrapped* payload — the outbound size cap and the JSON-depth
  cap (§7). For `glific/*` components, `props` is additionally checked against the block's
  published schema.
  """
  @spec validate_payload(envelope()) :: :ok | {:error, String.t()}
  def validate_payload(envelope) when is_map(envelope) do
    with :ok <- validate_type_value(envelope["type"]),
         :ok <- validate_required_integer(envelope, "version"),
         :ok <- validate_props_present(envelope),
         :ok <- validate_component_format(envelope["component"]),
         :ok <- validate_size(envelope, @stored_max_bytes, "Stored typed"),
         :ok <- validate_typed_tree(envelope["props"]),
         :ok <- validate_reserved_ids(envelope["props"]),
         unwrapped = unwrap(envelope),
         :ok <- validate_size(unwrapped, @outbound_max_bytes, "Outbound"),
         :ok <- validate_depth(unwrapped) do
      validate_glific_props(envelope["component"], envelope["props"])
    end
  end

  def validate_payload(_envelope), do: {:error, "Blocks payload must be a JSON object"}

  @doc """
  Belt-and-braces check that a `:blocks` message is about to send an already-unwrapped
  envelope shaped like contract §3 — the wire form `messages.interactive_content` and the
  widget actually see.

  This is deliberately lighter than `validate_payload/1`: by the time content reaches
  `Messages.check_for_hsm_message/2`, it has already passed `validate_payload/1` (typed-node
  shape, glific/\* props schema, the §5.1 reserved-id rule) at template save, and has already
  been `unwrap/1`'d by the trusted producer path (`ContactAction.do_send_interactive_message/4`
  or `Messages.check_for_interactive/2`) — there is no `kind`/`value` structure left to
  re-validate. What's still worth checking here is that the producer path did what it was
  supposed to: required fields present, `component` well-formed, and the outbound size/depth
  caps (§7), since those are cheap invariants a caller with no legitimate route to
  `interactive_content` (it is not a settable `message_input` field) should never be able to
  violate, but that a bug in the producer path could.
  """
  @spec validate_outbound_envelope(envelope()) :: :ok | {:error, String.t()}
  def validate_outbound_envelope(envelope) when is_map(envelope) do
    with :ok <- validate_type_value(envelope["type"]),
         :ok <- validate_required_integer(envelope, "version"),
         :ok <- validate_props_present(envelope),
         :ok <- validate_component_format(envelope["component"]),
         :ok <- validate_size(envelope, @outbound_max_bytes, "Outbound") do
      validate_depth(envelope)
    end
  end

  def validate_outbound_envelope(_envelope), do: {:error, "Blocks payload must be a JSON object"}

  @doc """
  Validate an inbound `blocks_response` against the outbound envelope it answers.

  Enforces contract §7: required response fields, `summary` length cap, serialized-size cap,
  JSON-depth cap, and — for `glific/*` components — `values` checked against the block's
  published values shape. Also cross-checks the response's `component` echo against the
  outbound envelope's `component`, since a mismatch means the client answered the wrong
  message.

  Correlation (contact owns `message_id`, message is `:blocks` and unanswered) is the caller's
  responsibility — this function only validates the envelope contents.
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
    do: {:error, "Blocks response must be a JSON object"}

  @doc """
  Server-side auto-summary for a `glific/*` response, mirroring the widget's client-side
  summary builder (contract §6). `glific/*` responses always carry a client-supplied `summary`,
  so this is not on the acceptance path — it exists for server-side surfaces (e.g. the flow
  simulator) that need to compute the same summary without a browser.

  `props` is the (unwrapped, translated) props the contact was shown — the same shape
  `outbound.interactive_content["props"]` always has (contract §2). Returns `nil` for a
  namespace Glific does not own (org namespaces build their own summary).
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

  @spec validate_type_value(any()) :: :ok | {:error, String.t()}
  defp validate_type_value("blocks"), do: :ok
  defp validate_type_value(_type), do: {:error, "Blocks payload 'type' must be \"blocks\""}

  @spec validate_required_string(map(), String.t()) :: :ok | {:error, String.t()}
  defp validate_required_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, "Blocks payload is missing required field '#{key}'"}
    end
  end

  @spec validate_required_integer(map(), String.t()) :: :ok | {:error, String.t()}
  defp validate_required_integer(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) -> :ok
      _ -> {:error, "Blocks payload requires an integer 'version'"}
    end
  end

  @spec validate_props_present(map()) :: :ok | {:error, String.t()}
  defp validate_props_present(%{"props" => props}) when is_map(props), do: :ok
  defp validate_props_present(_envelope), do: {:error, "Blocks payload requires a 'props' map"}

  @spec validate_values_present(map()) :: :ok | {:error, String.t()}
  defp validate_values_present(%{"values" => values}) when is_map(values), do: :ok

  defp validate_values_present(_response),
    do: {:error, "Blocks response requires a 'values' map"}

  @spec validate_component_format(any()) :: :ok | {:error, String.t()}
  defp validate_component_format(component) when is_binary(component) do
    if Regex.match?(@component_regex, component) do
      validate_namespace(component)
    else
      {:error,
       "Blocks 'component' must match ^[a-z0-9]([a-z0-9-]*[a-z0-9])?/[a-z0-9]([a-z0-9-]*[a-z0-9])?$"}
    end
  end

  defp validate_component_format(_component), do: {:error, "Blocks 'component' is required"}

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
    do: {:error, "Blocks response 'component' does not match the outbound message"}

  @spec validate_summary_length(any()) :: :ok | {:error, String.t()}
  defp validate_summary_length(summary) when is_binary(summary) do
    if String.length(summary) <= @summary_max_length,
      do: :ok,
      else: {:error, "Blocks 'summary' exceeds #{@summary_max_length} characters"}
  end

  defp validate_summary_length(_summary), do: {:error, "Blocks 'summary' must be a string"}

  @spec validate_size(map(), non_neg_integer(), String.t()) :: :ok | {:error, String.t()}
  defp validate_size(payload, max_bytes, label) do
    size = payload |> Jason.encode!() |> byte_size()

    if size <= max_bytes,
      do: :ok,
      else: {:error, "#{label} Blocks payload exceeds #{max_bytes} bytes"}
  end

  @spec validate_depth(term()) :: :ok | {:error, String.t()}
  defp validate_depth(payload) do
    if json_depth(payload) <= @max_json_depth,
      do: :ok,
      else: {:error, "Blocks payload exceeds max JSON depth of #{@max_json_depth}"}
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
  # Typed-node tree validation (contract §2.1, all namespaces)
  # ---------------------------------------------------------------------------

  # A map carrying a `"kind"` key is an *attempted* typed node — validate its shape strictly
  # (rather than silently letting a near-miss through as an opaque plain value), then recurse
  # into `value` so a `kind: "list"` node's items are checked too.
  @spec validate_typed_tree(term()) :: :ok | {:error, String.t()}
  defp validate_typed_tree(%{"kind" => _kind} = node), do: validate_typed_node(node)

  defp validate_typed_tree(map) when is_map(map),
    do: map |> Map.values() |> validate_typed_list()

  defp validate_typed_tree(list) when is_list(list), do: validate_typed_list(list)
  defp validate_typed_tree(_scalar), do: :ok

  @spec validate_typed_list([term()]) :: :ok | {:error, String.t()}
  defp validate_typed_list(items) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case validate_typed_tree(item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @spec validate_typed_node(map()) :: :ok | {:error, String.t()}
  defp validate_typed_node(%{"kind" => kind} = node) do
    extra_keys = Map.keys(node) -- @typed_node_keys

    with :ok <- validate_no_extra_keys(extra_keys),
         :ok <- validate_kind_name(kind),
         :ok <- validate_translate_flag(node["translate"]),
         :ok <- validate_value_present(node) do
      validate_kind_value(kind, node["value"])
    end
  end

  @spec validate_no_extra_keys([String.t()]) :: :ok | {:error, String.t()}
  defp validate_no_extra_keys([]), do: :ok

  defp validate_no_extra_keys(extra_keys),
    do: {:error, "Blocks typed node has unknown key(s): #{Enum.join(extra_keys, ", ")}"}

  @spec validate_kind_name(any()) :: :ok | {:error, String.t()}
  defp validate_kind_name(kind) when kind in @valid_kinds, do: :ok

  defp validate_kind_name(_kind),
    do: {:error, "Blocks typed node 'kind' must be one of: #{Enum.join(@valid_kinds, ", ")}"}

  @spec validate_translate_flag(any()) :: :ok | {:error, String.t()}
  defp validate_translate_flag(nil), do: :ok
  defp validate_translate_flag(value) when is_boolean(value), do: :ok

  defp validate_translate_flag(_value),
    do: {:error, "Blocks typed node 'translate' must be a boolean"}

  @spec validate_value_present(map()) :: :ok | {:error, String.t()}
  defp validate_value_present(%{"value" => _value}), do: :ok
  defp validate_value_present(_node), do: {:error, "Blocks typed node is missing 'value'"}

  @spec validate_kind_value(String.t(), term()) :: :ok | {:error, String.t()}
  defp validate_kind_value(kind, value) when kind in ["text", "alt"] and is_binary(value), do: :ok

  defp validate_kind_value(kind, _value) when kind in ["text", "alt"],
    do: {:error, "Blocks '#{kind}' node value must be a string"}

  defp validate_kind_value(kind, value) when kind in ["image", "url"] and is_binary(value) do
    if Regex.match?(~r{^https?://}, value),
      do: :ok,
      else: {:error, "Blocks '#{kind}' node value must be an absolute http(s) URL"}
  end

  defp validate_kind_value(kind, _value) when kind in ["image", "url"],
    do: {:error, "Blocks '#{kind}' node value must be an absolute http(s) URL"}

  defp validate_kind_value("number", value) when is_number(value), do: :ok

  defp validate_kind_value("number", _value),
    do: {:error, "Blocks 'number' node value must be a number"}

  defp validate_kind_value("boolean", value) when is_boolean(value), do: :ok

  defp validate_kind_value("boolean", _value),
    do: {:error, "Blocks 'boolean' node value must be a boolean"}

  defp validate_kind_value("list", value) when is_list(value), do: validate_typed_tree(value)

  defp validate_kind_value("list", _value),
    do: {:error, "Blocks 'list' node value must be an array"}

  # ---------------------------------------------------------------------------
  # Reserved-id validation (contract §5.1, all namespaces)
  # ---------------------------------------------------------------------------

  @spec validate_reserved_ids(term()) :: :ok | {:error, String.t()}
  defp validate_reserved_ids(props) do
    reserved = props |> collect_ids() |> Enum.uniq() |> Enum.filter(&(&1 in @reserved_ids))

    if reserved == [],
      do: :ok,
      else:
        {:error,
         "Blocks id(s) reserved for flow results and cannot be used: #{Enum.join(reserved, ", ")}"}
  end

  @spec collect_ids(term()) :: [String.t()]
  defp collect_ids(%{"id" => id} = map) when is_binary(id),
    do: [id | collect_ids(Map.delete(map, "id"))]

  defp collect_ids(map) when is_map(map), do: map |> Map.values() |> Enum.flat_map(&collect_ids/1)
  defp collect_ids(list) when is_list(list), do: Enum.flat_map(list, &collect_ids/1)
  defp collect_ids(_value), do: []

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
      else: {:error, "Blocks #{label} is missing required key(s): #{Enum.join(missing, ", ")}"}
  end

  @spec validate_known_keys(map(), [String.t()], String.t()) :: :ok | {:error, String.t()}
  defp validate_known_keys(map, known_keys, label) do
    unknown = Map.keys(map) -- known_keys

    if unknown == [],
      do: :ok,
      else: {:error, "Blocks #{label} has unknown key(s): #{Enum.join(unknown, ", ")}"}
  end

  @doc false
  @spec validate_image_panel_props(map()) :: :ok | {:error, String.t()}
  def validate_image_panel_props(%{"id" => id, "options" => options} = props) do
    with :ok <- validate_non_blank_string(id, "options.id"),
         :ok <- validate_node_kind(props["body"], "text", "body") do
      validate_item_list(options, %{required: ["id", "image", "label"], optional: ["image_alt"]})
      |> combine(fn ->
        validate_items_node_kinds(options, %{
          "image" => "image",
          "label" => "text",
          "image_alt" => "alt"
        })
      end)
    end
  end

  def validate_image_panel_props(_props), do: {:error, "glific/image-panel props are invalid"}

  @doc false
  @spec validate_carousel_props(map()) :: :ok | {:error, String.t()}
  def validate_carousel_props(%{"id" => id, "cards" => cards} = props) do
    with :ok <- validate_non_blank_string(id, "cards.id"),
         :ok <- validate_node_kind(props["body"], "text", "body") do
      validate_item_list(cards, %{
        required: ["id", "image", "title"],
        optional: ["image_alt", "description"]
      })
      |> combine(fn ->
        validate_items_node_kinds(cards, %{
          "image" => "image",
          "title" => "text",
          "image_alt" => "alt",
          "description" => "text"
        })
      end)
    end
  end

  def validate_carousel_props(_props), do: {:error, "glific/carousel props are invalid"}

  @doc false
  @spec validate_form_props(map()) :: :ok | {:error, String.t()}
  def validate_form_props(%{"fields" => fields} = props) do
    with :ok <- validate_optional_string(props["id"], "id"),
         :ok <- validate_node_kind(props["body"], "text", "body"),
         :ok <- validate_node_kind(props["submit_label"], "text", "submit_label") do
      validate_item_list(fields, %{
        required: ["id", "label"],
        optional: ["placeholder", "required"]
      })
      |> combine(fn ->
        validate_items_node_kinds(fields, %{
          "label" => "text",
          "placeholder" => "text",
          "required" => "boolean"
        })
      end)
    end
  end

  def validate_form_props(_props), do: {:error, "glific/form props are invalid"}

  @spec combine(:ok | {:error, String.t()}, (-> :ok | {:error, String.t()})) ::
          :ok | {:error, String.t()}
  defp combine(:ok, next_fun), do: next_fun.()
  defp combine(error, _next_fun), do: error

  @spec validate_node_kind(any(), String.t(), String.t()) :: :ok | {:error, String.t()}
  defp validate_node_kind(nil, _expected_kind, _label), do: :ok

  defp validate_node_kind(%{"kind" => kind}, expected_kind, _label) when kind == expected_kind,
    do: :ok

  defp validate_node_kind(_node, expected_kind, label),
    do: {:error, "Blocks '#{label}' must be a '#{expected_kind}' node"}

  @spec validate_item_list(any(), %{required: [String.t()], optional: [String.t()]}) ::
          :ok | {:error, String.t()}
  defp validate_item_list(%{"kind" => "list", "value" => items}, %{
         required: required_keys,
         optional: optional_keys
       })
       when is_list(items) do
    count = length(items)

    cond do
      count < 1 or count > 10 ->
        {:error, "Blocks options/cards/fields must contain between 1 and 10 entries"}

      not Enum.all?(items, &is_map/1) ->
        {:error, "Blocks options/cards/fields entries must be JSON objects"}

      true ->
        items
        |> Enum.reduce_while(:ok, fn item, :ok ->
          with :ok <- validate_required_keys(item, required_keys, "item"),
               :ok <- validate_known_keys(item, required_keys ++ optional_keys, "item") do
            {:cont, :ok}
          else
            error -> {:halt, error}
          end
        end)
        |> then(fn
          :ok -> validate_unique_item_ids(items)
          error -> error
        end)
    end
  end

  defp validate_item_list(_items_node, _schema),
    do: {:error, "Blocks options/cards/fields must be a typed 'list' node"}

  @spec validate_items_node_kinds(map(), %{String.t() => String.t()}) ::
          :ok | {:error, String.t()}
  defp validate_items_node_kinds(%{"value" => items}, expected_kinds) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      expected_kinds
      |> Enum.reduce_while(:ok, fn {key, expected_kind}, :ok ->
        case validate_node_kind(item[key], expected_kind, key) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
      |> case do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_items_node_kinds(_items_node, _expected_kinds), do: :ok

  @spec validate_unique_item_ids([map()]) :: :ok | {:error, String.t()}
  defp validate_unique_item_ids(items) do
    ids = Enum.map(items, &Map.get(&1, "id"))

    if length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, "Blocks options/cards/fields must have unique 'id' values"}
  end

  @spec validate_non_blank_string(any(), String.t()) :: :ok | {:error, String.t()}
  defp validate_non_blank_string(value, _label) when is_binary(value) and value != "", do: :ok

  defp validate_non_blank_string(_value, label),
    do: {:error, "Blocks '#{label}' must be a non-blank string"}

  @spec validate_optional_string(any(), String.t()) :: :ok | {:error, String.t()}
  defp validate_optional_string(nil, _label), do: :ok
  defp validate_optional_string(value, _label) when is_binary(value), do: :ok

  defp validate_optional_string(_value, label),
    do: {:error, "Blocks '#{label}' must be a string"}

  # ---------------------------------------------------------------------------
  # `glific/*` values (response receipt)
  # ---------------------------------------------------------------------------

  @spec validate_glific_values(String.t(), map(), map()) :: :ok | {:error, String.t()}
  defp validate_glific_values("glific/" <> _rest = component, props, values) do
    schema = Map.fetch!(@catalog, component)
    apply(__MODULE__, schema.validate_values, [props, values])
  end

  defp validate_glific_values(_component, _props, _values), do: :ok

  # `props` here is the **unwrapped** form (contract §2 — `outbound.interactive_content` is
  # always unwrapped by the time `Communications.WebMessage.receive_blocks_response/2` reads it
  # from `messages.interactive_content`), so `options`/`cards`/`fields` are plain lists of plain
  # maps — no `kind`/`value` wrapper to unwrap here.

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
          else: {:error, "Blocks response value is not one of the offered option ids"}

      _ ->
        {:error, "Blocks response 'values' must be exactly %{\"#{id_key}\" => <option id>}"}
    end
  end

  @doc false
  @spec validate_form_values(map(), map()) :: :ok | {:error, String.t()}
  def validate_form_values(props, values) do
    field_ids = props |> Map.get("fields", []) |> Enum.map(&Map.get(&1, "id")) |> MapSet.new()
    value_ids = values |> Map.keys() |> MapSet.new()

    cond do
      value_ids != field_ids ->
        {:error, "Blocks form response 'values' must have exactly one entry per field id"}

      not Enum.all?(Map.values(values), &is_binary/1) ->
        {:error, "Blocks form response 'values' must be strings"}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Server-side auto-summary (mirrors the widget's client-side builder)
  # ---------------------------------------------------------------------------

  # `props` here is also unwrapped (see note above) — mirroring the widget's own client-side
  # summary builder, which never sees typed nodes either.
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

  @spec clamp(String.t(), non_neg_integer()) :: String.t()
  defp clamp(text, max_length) when is_binary(text) do
    if String.length(text) > max_length,
      do: String.slice(text, 0, max_length),
      else: text
  end
end
