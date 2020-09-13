defmodule Glific.Processor.ConsumerWorker do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenServer

  alias Glific.{
    Caches,
    Flows.FlowContext,
    Messages.Message,
    Processor.ConsumerFlow,
    Processor.ConsumerTagger,
    Repo
  }

  @wakeup_timeout_ms 1 * 60 * 1000

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    wakeup_timeout = Keyword.get(opts, :wakeup_timeout, @wakeup_timeout_ms)

    GenServer.start_link(
      __MODULE__,
      wakeup_timeout: wakeup_timeout
    )
  end

  @doc false
  def init(opts) do
    state = %{
      wakeup_timeout: opts[:wakeup_timeout],
      organizations: %{},
      flows: %{}
    }

    # process the wakeup queue every timeout units
    Process.send_after(self(), :wakeup_timeout, state[:wakeup_timeout])

    {:ok, state}
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
  def handle_call(message, _from, state) do
    {message, state} = handle_common(message, state)
    {:reply, message, state}
  end

  @doc false
  def handle_cast(message, state) do
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
    message = message |> Repo.preload(:contact)

    {message, state}
    |> ConsumerTagger.process_message(body)
    |> ConsumerFlow.process_message(body)
    # get the first element which is the message
    |> elem(0)
    |> Repo.preload(:tags)
  end

  @doc """
  This callback handles the nudges in the system. It processes the jobs and then
  sets a timer to invoke itself when done
  """
  def handle_info(:wakeup_timeout, state) do
    # check DB and process all flows that need to be woken update_in
    FlowContext.wakeup()
    |> Enum.each(fn fc -> ConsumerFlow.wakeup(fc, state) end)

    Process.send_after(self(), :wakeup_timeout, state[:wakeup_timeout])
    {:noreply, state}
  end
end
