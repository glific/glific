defmodule Glific.Processor.ConsumerWorker do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenServer
  use Publicist

  alias Glific.{
    Caches,
    Flows.Node,
    Messages.Message,
    Processor.ConsumerFlow,
    Processor.ConsumerTagger,
    Repo
  }

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(
      __MODULE__,
      []
    )
  end

  @doc false
  def init(_opts) do
    # cache information in an organization map in the state
    {:ok, %{organizations: %{}}}
  end

  defp needs_reload(organizations, org_id) do
    cond do
      !Map.has_key?(organizations, org_id) -> true
      organizations[org_id].cache_reload_key != Caches.get(org_id, :cache_reload_key) -> true
      true -> false
    end
  end

  @doc """
  Sets the immutable state for a specific organization. Making this public, so we can call it from
  the test suite
  """
  @spec load_state(non_neg_integer) :: map()
  def load_state(organization_id) do
    case Caches.fetch(organization_id, "consumer_worker_map", &load_consumer_worker_map/1) do
      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve consumer_worker_map, #{inspect(organization_id)}, #{error}"
        )

      {_, value} ->
        value
    end
  end

  @spec load_consumer_worker_map(tuple()) :: tuple()
  defp load_consumer_worker_map(cache_key) do
    # this is of the form {organization_id, "consumer_worker_map}"
    # we want the organization_id
    organization_id = cache_key |> elem(0)

    {:ok, cache_reload_key} = Caches.get(organization_id, :cache_reload_key)

    {
      :commit,
      %{
        cache_reload_key: cache_reload_key,
        organization_id: organization_id
      }
      |> Map.merge(ConsumerTagger.load_state(organization_id))
      |> Map.merge(ConsumerFlow.load_state(organization_id))
    }
  end

  defp reload(state, organization_id),
    do:
      if(needs_reload(state.organizations, organization_id),
        do:
          put_in(
            state,
            [:organizations, organization_id],
            load_state(organization_id)
          ),
        else: state
      )

  @doc false
  def handle_call({message, process_state, _}, _, state) do
    {_message, state} = handle_common(message, process_state, state)
    {:reply, nil, state, :hibernate}
  end

  @doc false
  def handle_cast({message, process_state, _}, state) do
    {_message, state} = handle_common(message, process_state, state)
    {:noreply, state, :hibernate}
  end

  defp handle_process_state({organization_id, user} = _process_state) do
    # resetting the node map which we use to track flow state
    Node.reset_node_map()

    # set the org and user context for downstream processing
    Repo.put_organization_id(organization_id)
    Repo.put_current_user(user)
  end

  @spec handle_common(any, any, any) :: any
  defp handle_common(message, process_state, state) do
    handle_process_state(process_state)

    state = reload(state, message.organization_id)
    message = process_message(message, state.organizations[message.organization_id])

    {message, state}
  end

  @spec process_message(atom() | Message.t(), map()) :: Message.t()
  defp process_message(message, state) do
    body = Glific.string_clean(message.body)

    # Since contact and language are the required fields in many places, lets preload them
    message = Repo.preload(message, [:location, :media, contact: [:language]])

    {message, state}
    |> ConsumerTagger.process_message(body)
    |> ConsumerFlow.process_message(body)
    # get the first element which is the message
    |> elem(0)
    |> Repo.preload(:tags)
  end
end
