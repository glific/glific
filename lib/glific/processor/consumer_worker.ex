defmodule Glific.Processor.ConsumerWorker do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenServer

  alias Glific.{
    Caches,
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

  defp load_state(organization_id) do
    {:ok, cache_reload_key} = Caches.get(organization_id, :cache_reload_key)

    %{
      cache_reload_key: cache_reload_key,
      organization_id: organization_id
    }
    |> Map.merge(ConsumerTagger.load_state(organization_id))
    |> Map.merge(ConsumerFlow.load_state(organization_id))
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
  def handle_call({message, _}, _, state) do
    {message, state} = handle_common(message, state)
    {:reply, message, state}
  end

  @doc false
  def handle_cast({message, _}, state) do
    {_message, state} = handle_common(message, state)
    {:noreply, state}
  end

  defp handle_common(message, state) do
    state = reload(state, message.organization_id)
    message = process_message(message, state.organizations[message.organization_id])
    {message, state}
  end

  @spec process_message(atom() | Message.t(), map()) :: Message.t()
  defp process_message(message, state) do
    body = Glific.string_clean(message.body)

    # Since conatct and language are the required fiels in many places, lets preload them
    message = Repo.preload(message, contact: [:language])

    {message, state}
    |> ConsumerTagger.process_message(body)
    |> ConsumerFlow.process_message(body)
    # get the first element which is the message
    |> elem(0)
    |> Repo.preload(:tags)
  end
end
