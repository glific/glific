defmodule Glific.Flows.FlowContext do
  @moduledoc """
  When we are running a flow, we are running it in the context of a
  contact and/or a conversation (or other Glific data types). Let encapsulate
  this in a module and isolate the flow from the other aspects of Glific
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  import GlificWeb.Gettext
  require Logger

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows,
    Flows.Flow,
    Flows.FlowBroadcast,
    Flows.FlowResult,
    Flows.MessageVarParser,
    Flows.Node,
    Messages,
    Messages.Message,
    Notifications,
    Partners.Organization,
    Repo
  }

  @required_fields [:contact_id, :flow_id, :flow_uuid, :status, :organization_id]
  @optional_fields [
    :node_uuid,
    :parent_id,
    :results,
    :wakeup_at,
    :is_background_flow,
    :is_await_result,
    :completed_at,
    :delay,
    :uuids_seen,
    :uuid_map,
    :recent_inbound,
    :recent_outbound,
    :flow_broadcast_id
  ]

  # we store one more than the number of messages specified here
  @max_message_len 11

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid_map: map() | nil,
          results: map() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          last_message: Message.t() | nil,
          flow_id: non_neg_integer | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          status: String.t() | nil,
          parent_id: non_neg_integer | nil,
          parent: FlowContext.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_broadcast_id: non_neg_integer | nil,
          flow_broadcast: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | nil,
          delay: integer,
          uuids_seen: map(),
          recent_inbound: [map()] | [],
          recent_outbound: [map()] | [],
          wakeup_at: :utc_datetime | nil,
          is_background_flow: boolean,
          is_await_result: boolean,
          completed_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_contexts" do
    field(:uuid_map, :map, virtual: true)
    field(:node, :map, virtual: true)

    field(:results, :map, default: %{})

    field(:node_uuid, Ecto.UUID)
    field(:flow_uuid, Ecto.UUID)

    field(:status, :string, default: "published")

    field(:wakeup_at, :utc_datetime, default: nil)
    field(:completed_at, :utc_datetime, default: nil)

    field(:is_background_flow, :boolean, default: false)
    field(:is_await_result, :boolean, default: false)

    field(:delay, :integer, default: 0, virtual: true)

    # keep a map of all uuids we encounter (start with flows)
    # this allows to to detect infinite loops and abort
    field(:uuids_seen, :map, default: %{}, virtual: true)

    field(:recent_inbound, {:array, :map}, default: [])
    field(:recent_outbound, {:array, :map}, default: [])

    field(:last_message, :map, virtual: true)

    belongs_to(:contact, Contact)
    belongs_to(:flow, Flow)
    belongs_to(:organization, Organization)
    belongs_to(:parent, FlowContext, foreign_key: :parent_id)

    # the originating group message which kicked off this flow if any
    belongs_to(:flow_broadcast, FlowBroadcast)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowContext.t(), map()) :: Ecto.Changeset.t()
  def changeset(context, attrs) do
    context
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Create a FlowContext
  """
  @spec create_flow_context(map()) :: {:ok, FlowContext.t()} | {:error, Ecto.Changeset.t()}
  def create_flow_context(attrs \\ %{}) do
    %FlowContext{}
    |> FlowContext.changeset(attrs)
    |> Repo.insert()
  end

  @doc false
  @spec update_flow_context(FlowContext.t(), map()) ::
          {:ok, FlowContext.t()} | {:error, Ecto.Changeset.t()}
  def update_flow_context(context, attrs) do
    context
    |> FlowContext.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Generate a notifcation having all the flow context data.
  """
  @spec notification(FlowContext.t(), String.t()) :: nil
  def notification(context, message) do
    context = Repo.preload(context, [:flow])
    Logger.info(message)

    {:ok, _} =
      Notifications.create_notification(%{
        category: "Flow",
        message: message,
        severity: "Warning",
        organization_id: context.organization_id,
        entity: %{
          contact_id: context.contact_id,
          flow_id: context.flow_id,
          flow_uuid: context.flow.uuid,
          parent_id: context.parent_id,
          name: context.flow.name
        }
      })

    nil
  end

  @doc """
  Resets all the context for the user when we hit an error. This can potentially
  prevent an infinite loop from happening if flows are connected in a cycle
  """
  @spec reset_all_contexts(FlowContext.t(), String.t()) :: FlowContext.t() | nil
  def reset_all_contexts(context, message) do
    # lets skip logging and notifications for things that occur quite often
    if !ignore_error?(message) do
      Logger.info(message)
      notification(context, message)
    end

    # lets reset the entire flow tree complete if this context is a child
    if context.parent_id,
      do: mark_flows_complete(context.contact_id, false)

    # lets reset the current context and return the resetted context
    reset_one_context(context)
  end

  @doc """
  Reset this context, but dont follow parent context tail. This is used
  for tail call optimization
  """
  @spec reset_one_context(FlowContext.t()) :: FlowContext.t()
  def reset_one_context(context) do
    {:ok, context} =
      FlowContext.update_flow_context(
        context,
        %{
          completed_at: DateTime.utc_now(),
          node: nil,
          node_uuid: nil
        }
      )

    :telemetry.execute(
      [:glific, :flow, :stop],
      %{},
      %{
        id: context.flow_id,
        context_id: context.id,
        contact_id: context.contact_id,
        organization_id: context.organization_id
      }
    )

    context = Repo.preload(context, [:flow, :contact])

    {:ok, _} =
      Contacts.capture_history(context.contact, :contact_flow_ended, %{
        event_label: "Flow Ended",
        event_meta: %{
          context_id: context.id,
          flow: %{
            id: context.flow.id,
            name: context.flow.name,
            uuid: context.flow.uuid
          }
        }
      })

    context
  end

  @doc """
  Resets the context and sends control back to the parent context
  if one exists
  """
  @min_delay 2

  @spec reset_context(FlowContext.t()) :: FlowContext.t() | nil
  def reset_context(context) do
    Logger.info("Ending Flow: id: '#{context.flow_id}', contact_id: '#{context.contact_id}'")

    # we first update this entry with the completed at time
    context = reset_one_context(context)

    # check if context has a parent_id, if so, we need to
    # load that context and keep going
    if context.parent_id do
      # we load the parent context, and resume it with a message of "Completed"
      parent = active_context(context.contact_id, context.parent_id)

      # ensure the parent is still active. If the parent completed (or was terminated)
      # we dont get back a valid parent
      if parent do
        Logger.info(
          "Resuming Parent Flow: id: '#{parent.flow_id}', contact_id: '#{context.contact_id}'"
        )

        ## add delay so that it does not execute the message before sub flows
        ## adding this line saprately so that we can easily identify this in different cases.
        parent = Map.put(parent, :delay, max(context.delay + @min_delay, @min_delay))

        parent
        |> load_context(Flow.get_flow(context.organization_id, parent.flow_uuid, context.status))
        |> merge_child_results(context)
        |> step_forward(Messages.create_temp_message(context.organization_id, "completed"))
      end
    end

    # return the orginal context, which is now completed
    context
  end

  @spec merge_child_results(FlowContext.t(), FlowContext.t()) :: FlowContext.t()
  defp merge_child_results(parent, child) do
    # merge the child results into parent
    # but lets remove the parent result field to keep the map simple
    child_results = Map.delete(child.results, "parent")

    if child_results == %{} do
      parent
    else
      child_results = %{
        # for now commenting this out since folks have complex flows
        # "child #{child.flow_id}" => child_results,
        "child" => child_results
      }

      update_results(parent, child_results)
    end
  end

  @doc """
  Update the recent_* state as we consume or send a message
  """
  @spec update_recent(FlowContext.t(), String.t(), atom()) :: FlowContext.t()
  def update_recent(context, body, type) do
    now = DateTime.utc_now()

    # since we are storing in DB and want to avoid hassle of atom <-> string conversion
    # we'll always use strings as keys
    messages =
      [%{"message" => body, "date" => now} | Map.get(context, type)]
      |> Enum.slice(0..@max_message_len)

    # since we have recd a message, we also ensure that we are not going to be woken
    # up by a timer if present.
    {:ok, context} =
      update_flow_context(context, %{type => messages, wakeup_at: nil, is_background_flow: false})

    context
  end

  @doc """
  Update the contact results with each element of the json map
  """
  @spec update_results(FlowContext.t(), map() | nil) :: FlowContext.t()
  def update_results(context, result) do
    results =
      if context.results == %{} || is_nil(context.results),
        do: result,
        else: Map.merge(context.results, result)

    {:ok, context} = update_flow_context(context, %{results: results})

    args = %{
      results: results,
      contact_id: context.contact_id,
      flow_id: context.flow_id,
      flow_version: context.flow.version,
      flow_context_id: context.id,
      flow_uuid: context.flow_uuid,
      organization_id: context.organization_id
    }

    # we try the upsert twice in case the first one conflicts with another
    # simultaneous insert. Happens rarely but a couple of times.
    case FlowResult.upsert_flow_result(args) do
      {:ok, flow_result} -> flow_result
      {:error, _} -> FlowResult.upsert_flow_result(args)
    end

    context
  end

  @doc """
  Count the number of times we have sent the same message in the recent past
  """
  @spec match_outbound(FlowContext.t(), String.t(), integer) :: integer
  def match_outbound(context, body, go_back \\ 6) do
    since = Glific.go_back_time(go_back)

    Enum.filter(
      context.recent_outbound,
      fn item ->
        # sometime we get this from memory, and its not retrived from DB
        # in which case its already in a valid date format
        date =
          if is_binary(item["date"]),
            do:
              (
                {:ok, date, _} = DateTime.from_iso8601(item["date"])
                date
              ),
            else: item["date"]

        item["message"] == body and DateTime.compare(date, since) in [:gt, :eq]
      end
    )
    |> length()
  end

  @doc """
  Set the new node for the context
  """
  @spec set_node(FlowContext.t(), Node.t()) :: FlowContext.t()
  def set_node(context, node) do
    {:ok, context} = update_flow_context(context, %{node_uuid: node.uuid})
    %{context | node: node}
  end

  @doc """
  Execute one (or more) steps in a flow based on the message stream
  """
  @spec execute(FlowContext.t(), [Message.t()]) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  def execute(%FlowContext{node: node} = _context, _messages) when is_nil(node),
    do: {:error, dgettext("errors", "We have finished the flow")}

  def execute(context, messages) do
    case Node.execute(context.node, context, messages) do
      {:ok, context, []} ->
        {:ok, context, []}

      {:wait, context, messages} ->
        {:wait, context, messages}

      # Routers basically break the processing, and return back to the top level
      # and hence we hit this case. Since they can be multiple routers stacked (e.g. when
      # the flow has multiple webhooks in it), we recurse till we no longer change state
      {:ok, context, new_messages} ->
        # if we've consumed some messages, lets continue calling the function,
        # till we consume all messages that we potentially can
        if messages != new_messages do
          execute(context, new_messages)
        else
          # lets discard the message stream and go forward
          {:ok, context, []}
        end

      others ->
        others
    end
  end

  # this marks complete all the context which are newer than date
  # this is used when a background flow  wakes up, and it has no
  # idea what happened it was sleeping
  @spec add_date_clause(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp add_date_clause(query, nil), do: query

  defp add_date_clause(query, after_insert),
    do: query |> where([fc], fc.inserted_at > ^after_insert)

  @doc """
  Set all the flows for a specific context to be completed
  """
  @spec mark_flows_complete(non_neg_integer, boolean(), DateTime.t() | nil) :: nil
  def mark_flows_complete(_contact_id, _is_background_flow, after_insert_date \\ nil)
  def mark_flows_complete(_contact_id, true, _after_insert_date), do: nil

  def mark_flows_complete(contact_id, false, after_insert_date) do
    now = DateTime.utc_now()

    FlowContext
    |> where([fc], fc.contact_id == ^contact_id)
    |> where([fc], is_nil(fc.completed_at))
    |> add_date_clause(after_insert_date)
    # lets not touch the contexts which are waiting to be woken up at a specific time
    |> where([fc], fc.is_background_flow == false)
    |> Repo.update_all(set: [completed_at: now, node_uuid: nil, updated_at: now])

    {:ok, _} =
      Contacts.capture_history(contact_id, :contact_flow_ended_all, %{
        event_label: "All contact flows are ended"
      })

    :telemetry.execute(
      [:glific, :flow, :stop_all],
      %{},
      %{
        contact_id: contact_id,
        organization_id: Repo.get_organization_id()
      }
    )
  end

  @doc """
  Seed the context and set the wakeup time as needed
  """
  @spec seed_context(Flow.t(), Contact.t(), String.t(), Keyword.t()) ::
          {:ok, FlowContext.t()} | {:error, Ecto.Changeset.t()}
  def seed_context(flow, contact, status, opts \\ []) do
    parent_id = Keyword.get(opts, :parent_id)
    flow_broadcast_id = Keyword.get(opts, :flow_broadcast_id)
    delay = Keyword.get(opts, :delay, 0)
    uuids_seen = Keyword.get(opts, :uuids_seen, %{})
    wakeup_at = Keyword.get(opts, :wakeup_at)
    results = Keyword.get(opts, :results, %{})

    Logger.info(
      "Seeding flow: id: '#{flow.id}', parent_id: '#{parent_id}', contact_id: '#{contact.id}'"
    )

    node = flow.start_node

    create_flow_context(%{
      contact_id: contact.id,
      parent_id: parent_id,
      flow_broadcast_id: flow_broadcast_id,
      node_uuid: node.uuid,
      flow_uuid: flow.uuid,
      status: status,
      node: node,
      results: results,
      flow_id: flow.id,
      flow: flow,
      organization_id: flow.organization_id,
      uuid_map: flow.uuid_map,
      delay: delay,
      uuids_seen: uuids_seen,
      wakeup_at: wakeup_at
    })
  end

  @doc """
  Start a new context, if there is an existing context, blow it away
  """
  @spec init_context(Flow.t(), Contact.t(), String.t(), Keyword.t() | []) ::
          {:ok | :wait, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def init_context(flow, contact, status, opts \\ []) do
    parent_id = Keyword.get(opts, :parent_id)
    # set all previous context to be completed if we are not starting a sub flow
    if is_nil(parent_id) do
      mark_flows_complete(contact.id, flow.is_background)
    end

    {:ok, context} = seed_context(flow, contact, status, opts)

    :telemetry.execute(
      [:glific, :flow, :start],
      %{duration: 1},
      %{
        id: flow.id,
        context_id: context.id,
        contact_id: contact.id,
        organization_id: context.organization_id
      }
    )

    {:ok, _} =
      Contacts.capture_history(contact, :contact_flow_started, %{
        event_label: "Flow Started",
        event_meta: %{
          context_id: context.id,
          flow: %{
            id: flow.id,
            uuid: flow.uuid,
            name: flow.name
          }
        }
      })

    context
    |> load_context(flow)
    # lets do the first steps and start executing it till we need a message
    |> execute([])
  end

  @doc """
  Check if there is an active context (i.e. with a non null, node_uuid for this contact)
  """
  @spec active_context(non_neg_integer, non_neg_integer | nil) :: FlowContext.t() | nil
  def active_context(contact_id, parent_id \\ nil) do
    # need to fix this instead of assuming the highest id is the most
    # active context (or is that a wrong assumption). Maybe a context number? like
    # we do for other tables
    # We should not wakeup those contexts which are waiting on time
    query =
      from(fc in FlowContext,
        where:
          fc.contact_id == ^contact_id and
            not is_nil(fc.node_uuid) and
            is_nil(fc.completed_at) and
            fc.is_background_flow == false,
        order_by: [desc: fc.id],
        limit: 1
      )

    query =
      if parent_id,
        do: query |> where([fc], fc.id == ^parent_id),
        else: query

    # There are lot of test cases failing becuase of this change. Will come back to it end of this PR.
    fc =
      query
      |> Repo.one()
      |> Repo.preload([:contact, :flow])

    # if this context is waiting on time, we skip it
    if fc && fc.is_background_flow,
      do: nil,
      else: fc
  end

  @doc """
  Load the context object, given a flow object and a contact. At some point,
  we'll get the genserver to cache this
  """
  @spec load_context(FlowContext.t(), Flow.t()) :: FlowContext.t()
  def load_context(context, flow) do
    case Map.fetch(flow.uuid_map, context.node_uuid) do
      {:ok, {:node, node}} ->
        context
        |> Repo.preload(:contact)
        |> Map.put(:flow, flow)
        |> Map.put(:uuid_map, flow.uuid_map)
        |> Map.put(:node, node)

      :error ->
        # Seems like the flow changed underneath us
        # so this node no longer exists. Lets reset the context
        # and terminate the flow, which sets the context.node to nil
        # and hence does not execute
        Logger.error(
          "Seems like the flow: #{flow.id} changed underneath us for: #{context.organization_id}"
        )

        reset_all_contexts(context, "A new flow was published, resetting flows for this contact.")
    end
  end

  @spec ignore_error?(String.t()) :: boolean
  defp ignore_error?(error) do
    # These errors are ok, and need not be reported to appsignal
    # to a large extent, its more a completion exit rather than an
    # error exit
    String.contains?(error, "Exit Loop") ||
      String.contains?(error, "finished the flow")
  end

  @doc """
  Log the error and also send it over to our friends at appsignal
  """
  @spec log_error(String.t()) :: {:error, String.t()}
  def log_error(error) do
    Logger.error(error)

    # disable sending exit loop and finished flow errors, since
    # these are beneficiary errors
    if !ignore_error?(error) do
      {_, stacktrace} = Process.info(self(), :current_stacktrace)
      Appsignal.send_error(:error, error, stacktrace)
    end

    {:error, error}
  end

  @doc """
  Given an input string, consume the input and advance the state of the context
  """
  @spec step_forward(FlowContext.t(), Message.t()) :: {:ok, map()} | {:error, String.t()}
  def step_forward(context, message) do
    case execute(context, [message]) do
      {:ok, context, []} ->
        {:ok, context}

      {:wait, context, _messages} ->
        {:ok, context}

      {:error, error} ->
        log_error(error)
    end
  end

  @spec wakeup_flows(non_neg_integer) :: any
  @doc """
  Find all the contexts which need to be woken up and processed
  """
  def wakeup_flows(_organization_id) do
    FlowContext
    |> where([fc], fc.wakeup_at < ^DateTime.utc_now())
    |> where([fc], is_nil(fc.completed_at))
    |> preload(:flow)
    |> Repo.all()
    |> Enum.each(&wakeup_one(&1))
  end

  @doc """
  Process one context at a time that is ready to be woken
  """
  @spec wakeup_one(FlowContext.t(), Message.t() | nil) ::
          {:ok, FlowContext.t() | nil, [String.t()]} | {:error, String.t()} | nil
  def wakeup_one(context, message \\ nil) do
    # update the context woken up time as soon as possible to avoid someone else
    # grabbing this context
    {:ok, context} =
      update_flow_context(
        context,
        %{
          wakeup_at: nil,
          is_background_flow: false,
          is_await_result: false
        }
      )

    # also mark all newer contexts as completed
    mark_flows_complete(context.contact_id, context.flow.is_background, context.inserted_at)

    {:ok, flow} =
      Flows.get_cached_flow(
        context.organization_id,
        {:flow_uuid, context.flow_uuid, context.status}
      )

    message =
      if is_nil(message),
        do: Messages.create_temp_message(context.organization_id, "No Response"),
        else: message

    context
    |> FlowContext.load_context(flow)
    |> FlowContext.step_forward(message)
    |> case do
      {:ok, context} -> {:ok, context, []}
      {:error, message} -> {:error, message}
    end
  end

  @spec await_context(non_neg_integer, non_neg_integer) :: FlowContext.t() | nil
  defp await_context(contact_id, flow_id) do
    FlowContext
    |> where([fc], fc.contact_id == ^contact_id)
    |> where([fc], fc.flow_id == ^flow_id)
    |> where([fc], fc.is_await_result == true)
    |> where([fc], is_nil(fc.completed_at))
    |> preload(:flow)
    |> Repo.one()
  end

  @doc """
  Resume the flow for a given contact and a given flow id if still active
  """
  @spec resume_contact_flow(
          Contact.t(),
          non_neg_integer | FlowContext.t() | nil,
          map(),
          Message.t() | nil
        ) ::
          {:ok, FlowContext.t() | nil, [String.t()]} | {:error, String.t()} | nil
  def resume_contact_flow(contact, flow_id, result, message \\ nil)

  def resume_contact_flow(contact, flow_id, result, message) when is_integer(flow_id) do
    context = await_context(contact.id, flow_id)
    resume_contact_flow(contact, context, result, message)
  end

  def resume_contact_flow(contact, nil, _result, _message) do
    {:error, "#{contact.id} does not have any active flows awaiting results."}
  end

  def resume_contact_flow(_contact, context, result, message) do
    # first update the flow context with the result
    context = update_results(context, result)

    # and then proceed as if we are waking the flow up
    wakeup_one(context, message)
  end

  @doc """
  Delete all the contexts which are completed before two days
  """
  @spec delete_completed_flow_contexts(non_neg_integer) :: :ok
  def delete_completed_flow_contexts(back \\ 2) do
    back_date = DateTime.utc_now() |> DateTime.add(-1 * back * 24 * 60 * 60, :second)

    """
    DELETE FROM flow_contexts
    WHERE id = any (array(
       SELECT id
       FROM flow_contexts AS f0
       WHERE f0.completed_at < '#{back_date}' AND F0.completed_at IS NOT NULL LIMIT 500));
    """
    |> Repo.query!([], timeout: 60_000, skip_organization_id: true)

    Logger.info("Deleting flow contexts completed #{back} days back")

    :ok
  end

  @doc """
  Delete all the contexts which are older than 7 days
  """
  @spec delete_old_flow_contexts(non_neg_integer) :: :ok
  def delete_old_flow_contexts(back \\ 7) do
    deletion_date = DateTime.utc_now() |> DateTime.add(-1 * back * 24 * 60 * 60, :second)

    """
    DELETE FROM flow_contexts
    WHERE id = any (array(SELECT id FROM flow_contexts AS f0 WHERE f0.inserted_at < '#{deletion_date}' LIMIT 500));
    """
    |> Repo.query!([], timeout: 60_000, skip_organization_id: true)

    Logger.info("Deleting flow contexts older than #{back} days")

    :ok
  end

  @doc """
    A single place to parse the variable in a string related to flows.
  """
  @spec parse_context_string(FlowContext.t(), String.t()) :: String.t()
  def parse_context_string(context, str) do
    vars = %{
      "results" => context.results,
      "contact" => Contacts.get_contact_field_map(context.contact_id),
      "flow" => %{name: context.flow.name, id: context.flow.id}
    }

    MessageVarParser.parse(str, vars)
  end
end
