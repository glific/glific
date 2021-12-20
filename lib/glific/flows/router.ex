defmodule Glific.Flows.Router do
  @moduledoc """
  The Router object which encapsulates the router in a given node.
  """
  alias __MODULE__

  use Ecto.Schema
  import GlificWeb.Gettext
  require Logger

  alias Glific.{
    Contacts,
    Flows,
    Messages,
    Messages.Message
  }

  alias Glific.Flows.{
    Case,
    Category,
    FlowContext,
    Localization,
    Node,
    Wait
  }

  @required_fields [:type, :operand, :default_category_uuid, :cases, :categories]

  @type t() :: %__MODULE__{
          type: String.t() | nil,
          result_name: String.t() | nil,
          default_category_uuid: Ecto.UUID.t() | nil,
          default_category: Category.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          other_exit_uuid: Ecto.UUID.t() | nil,
          no_response_exit_uuid: Ecto.UUID.t() | nil,
          wait: Wait.t() | nil,
          node: Node.t() | nil,
          cases: [Case.t()] | nil,
          categories: [Category.t()] | nil
        }

  schema "routers" do
    field :type, :string
    field :operand, :string
    field :result_name, :string
    field :wait_type, :string

    field :default_category_uuid, Ecto.UUID
    embeds_one :default_category, Category

    embeds_one :wait, Wait

    field :node_uuid, Ecto.UUID
    embeds_one :node, Node

    embeds_many :cases, Case
    embeds_many :categories, Category

    # in case we need to figure out the node for other/no response
    # lets cache the exit uuids
    field :other_exit_uuid, Ecto.UUID
    field :no_response_exit_uuid, Ecto.UUID
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Node.t()) :: {Router.t(), map()}
  def process(json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields)

    router = %Router{
      node: node,
      node_uuid: node.uuid,
      type: json["type"],
      operand: json["operand"],
      result_name: json["result_name"]
    }

    {categories, uuid_map} =
      Flows.build_flow_objects(
        json["categories"],
        uuid_map,
        &Category.process/3
      )

    # Check that the default_category_uuid exists, if not raise an error
    if !Map.has_key?(uuid_map, json["default_category_uuid"]),
      do: raise(ArgumentError, message: "Default Category ID does not exist for Router")

    {cases, uuid_map} =
      Flows.build_flow_objects(
        json["cases"],
        uuid_map,
        &Case.process/3
      )

    {wait, uuid_map} =
      if Map.has_key?(json, "wait"),
        do: Wait.process(json["wait"], uuid_map, router),
        else: {nil, uuid_map}

    {
      router
      |> Map.put(:categories, categories)
      |> Map.put(:default_category_uuid, json["default_category_uuid"])
      |> Map.put(:cases, cases)
      |> Map.put(:wait, wait)
      |> Map.put(:other_exit_uuid, get_category_exit_uuid(categories, "Other"))
      |> Map.put(:no_response_exit_uuid, get_category_exit_uuid(categories, "No Response")),
      uuid_map
    }
  end

  @spec get_category_exit_uuid([Category.t()], String.t()) :: Ecto.UUID.t() | nil
  defp get_category_exit_uuid(categories, name) do
    category = Enum.find(categories, fn c -> c.name == name end)

    if is_nil(category),
      do: nil,
      else: category.exit_uuid
  end

  @spec validate_eex(Keyword.t(), String.t()) :: Keyword.t()
  defp validate_eex(errors, content) do
    cond do
      Glific.suspicious_code(content) ->
        [{EEx, "Suspicious Code"}] ++ errors

      !is_nil(EEx.compile_string(content)) ->
        errors
    end
  rescue
    # if there is a syntax error or anything else
    # an exception is thrown and hence we rescue it here
    _ ->
      [{EEx, "Invalid Code"}] ++ errors
  end

  @doc """
  Validate a action and all its children
  """
  @spec validate(Router.t(), Keyword.t(), map()) :: Keyword.t()
  def validate(router, errors, flow) do
    errors = validate_eex(errors, router.operand)

    errors =
      router.categories
      |> Enum.reduce(
        errors,
        &Category.validate(&1, &2, flow)
      )

    errors =
      router.cases
      |> Enum.reduce(
        errors,
        &Case.validate(&1, &2, flow)
      )

    if router.wait,
      do: Wait.validate(router.wait, errors, flow),
      else: errors
  end

  @doc """
  Execute a router, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Router.t(), FlowContext.t(), [Message.t()]) ::
          {:ok, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  def execute(nil, context, messages),
    do: {:ok, context, messages}

  def execute(%{wait: wait} = _router, context, []) when wait != nil,
    do: Wait.execute(wait, context, [])

  def execute(%{type: type} = router, context, messages) when type == "switch" do
    Node.bump_count(router.node, context)

    {msg, rest} =
      if messages == [] do
        ## split by group is also calling the same function.
        ## currently we are differentiating based on operand
        split_by_expression(router, context)
      else
        [msg | rest] = messages
        {msg, rest}
      end

    context = FlowContext.update_recent(context, msg.body, :recent_inbound)

    {category_uuid, is_checkbox} = find_category(router, context, msg)

    execute_category(router, context, {msg, rest}, {category_uuid, is_checkbox})
  end

  def execute(_router, _context, _messages),
    do: raise(UndefinedFunctionError, message: "Unimplemented router type and/or wait type")

  @spec execute_category(
          Router.t(),
          FlowContext.t(),
          {Message.t(), [Message.t()]},
          {Ecto.UUID.t() | nil, boolean}
        ) ::
          {:ok, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  defp execute_category(_router, context, {msg, _rest}, {nil, _is_checkbox}) do
    # lets reset the context tree
    FlowContext.reset_all_contexts(context, "Could not find category for: #{msg.body}")

    # This error is logged and sent upstream to the reporting engine
    {:error, dgettext("errors", "Could not find category for: %{body}", body: msg.body)}
  end

  defp execute_category(router, context, {msg, rest}, {category_uuid, is_checkbox}) do
    # find the category object and send it over
    {:ok, {:category, category}} = Map.fetch(context.uuid_map, category_uuid)

    translated_category_name = Localization.get_translated_category_name(context, category)

    category = Map.put(category, :name, translated_category_name)

    ## We need to change the category name for other translations.

    context =
      if is_nil(router.result_name),
        # if there is a result name, store it in the context table along with the category name first
        do: context,
        else: update_context_results(context, router.result_name, msg, {category, is_checkbox})

    Category.execute(category, context, rest)
  end

  ## We are using this operand for split contats by groups
  @spec split_by_expression(Router.t(), FlowContext.t()) :: {Message.t(), []}
  defp split_by_expression(%{operand: "@contact.groups"} = _router, context) do
    contact = Contacts.get_contact_field_map(context.contact_id)

    msg =
      context.organization_id
      |> Messages.create_temp_message("#{inspect(contact.in_groups)}",
        extra: %{contact_groups: contact.in_groups}
      )

    {msg, []}
  end

  defp split_by_expression(router, context) do
    content =
      FlowContext.parse_context_string(context, router.operand)
      # Once we have the content, we send it over to EEx to execute
      |> Glific.execute_eex()

    msg = Messages.create_temp_message(context.organization_id, content)
    {msg, []}
  end

  # return the right category but also return if it is a "checkbox" related category
  @spec find_category(Router.t(), FlowContext.t(), Message.t()) :: {Ecto.UUID.t() | nil, boolean}
  defp find_category(router, _context, %{body: body, extra: %{intent: intent}} = _msg)
       when body in ["No Response", "Exit Loop", "Success", "Failure"] and is_nil(intent) do
    # Find the category with above name
    category = Enum.find(router.categories, fn c -> c.name == body end)

    if is_nil(category),
      do: {nil, false},
      else: {category.uuid, false}
  end

  defp find_category(router, context, msg) do
    # go thru the cases and find the first one that succeeds
    c =
      Enum.find(
        router.cases,
        nil,
        fn c -> Case.execute(c, context, msg) end
      )

    if is_nil(c),
      do: {router.default_category_uuid, false},
      else: {c.category_uuid, c.type == "has_multiple"}
  end

  @spec update_context_results(FlowContext.t(), String.t(), Message.t(), {Category.t(), boolean}) ::
          FlowContext.t()
  defp update_context_results(context, key, _msg, _) when key in ["", nil] do
    Logger.info("invalid results key for context: #{inspect(context)}")
    context
  end

  defp update_context_results(context, key, msg, {category, is_checkbox}) do
    results =
      cond do
        Flows.is_media_type?(msg.type) ->
          json =
            msg.media
            |> Map.take([:id, :source_url, :url, :caption])
            |> Map.put(:category, "media")
            |> Map.put(:input, msg.media.url)
            |> Map.put(:inserted_at, DateTime.utc_now())

          %{key => json}

        msg.type in [:location] ->
          json =
            msg.location
            |> Map.take([:id, :longitude, :latitude])
            |> Map.put(:category, "location")
            |> Map.put(:inserted_at, DateTime.utc_now())

          %{key => json}

        is_checkbox ->
          %{
            key => %{
              "input" => msg.body,
              "selected" => msg.body |> Glific.make_set() |> MapSet.to_list(),
              "category" => category.name,
              "inserted_at" => DateTime.utc_now()
            }
          }

        # this also handles msg.type in [:text]
        true ->
          %{
            key =>
              Map.merge(
                %{
                  "input" => msg.body,
                  "category" => category.name,
                  "inserted_at" => DateTime.utc_now()
                },
                msg.extra
              )
          }
      end

    FlowContext.update_results(context, results)
  end
end
