defmodule Glific.State do
  @moduledoc """
  Manage simulator and flows, managing state and allocation to ensure we can have multiple simulators
  and flow run at the same time
  """

  use Publicist

  use GenServer

  require Logger
  import Ecto.Query, warn: false

  alias Glific.{
    Communications,
    State.Flow,
    State.Simulator,
    Users.User
  }

  # lets first define the genserver Server callbacks

  @impl true
  @doc false
  @spec init(any) :: {:ok, %{}}
  def init(_opts) do
    # our state is a map of organization ids to simulator contexts
    {:ok, reset_state()}
  end

  @impl true
  @doc false
  def handle_call({:get_simulator, user}, _from, state) do
    {contact, state} = Simulator.get_simulator(user, state)

    {:reply, contact, state, :hibernate}
  end

  @impl true
  @doc false
  def handle_call({:release_simulator, user}, _from, state) do
    state = release_entity(user, state, :simulators)

    {:reply, nil, state, :hibernate}
  end

  @impl true
  @doc false
  def handle_call({:state, organization_id}, _from, state) do
    {:reply, get_state(state, organization_id), state, :hibernate}
  end

  @impl true
  @doc false
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, reset_state(), :hibernate}
  end

  @impl true
  @doc false
  def handle_call({:get_flow, params}, _from, state) do
    {flow, state} = Flow.get_flow(params.user, params.flow_id, state)
    {:reply, flow, state, :hibernate}
  end

  @impl true
  @doc false
  def handle_call({:release_flow, user}, _from, state) do
    state = release_entity(user, state, :flows)

    {:reply, nil, state, :hibernate}
  end

  # Note that we are specifically not implementing the handle_cast callback
  # since it does not make sense for the purposes of this interface

  # lets define the client interface
  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def get_simulator(user) do
    GenServer.call(__MODULE__, {:get_simulator, user})
  end

  @doc false
  def release_simulator(user) do
    GenServer.call(__MODULE__, {:release_simulator, user})
  end

  @doc false
  def get_flow(user, flow_id) do
    GenServer.call(__MODULE__, {:get_flow, %{user: user, flow_id: flow_id}})
  end

  @doc false
  def release_flow(user) do
    GenServer.call(__MODULE__, {:release_flow, user})
  end

  @doc false
  def state(organization_id) do
    GenServer.call(__MODULE__, {:state, organization_id})
  end

  @doc false
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  initializes the state for this organization
  if not already present
  """
  @spec get_state(map(), non_neg_integer) :: map()
  def get_state(state, organization_id) do
    if Map.has_key?(state, organization_id),
      do: state[organization_id],
      else: init_state(organization_id)
  end

  @spec init_state(non_neg_integer) :: map()
  defp init_state(organization_id) do
    %{}
    |> Map.merge(Simulator.init_state(organization_id))
    |> Map.merge(Flow.init_state(organization_id))
  end

  @spec reset_state :: map()
  defp reset_state do
    %{}
  end

  @doc """
  Release the entity associated with this user id. It is possible
  that there is no entity associated with this user
  """
  @spec release_entity(User.t(), map(), atom()) :: map()
  def release_entity(user, state, type) do
    organization_id = user.organization_id

    org_state =
      get_state(state, organization_id)
      |> free_entity(type, user)

    Map.put(state, organization_id, org_state)
  end

  @doc """
  Free the entity after holding an entity period is over
  """
  @spec free_entity(map(), atom(), User.t()) :: map()
  def free_entity(
        %{
          flow: %{free: free_flows, busy: busy_flows}
        } = state,
        :flows,
        user
      ) do
    {free, busy} = do_free_entity(free_flows, busy_flows, user, :flows)
    update_state(state, :flow, free, busy)
  end

  def free_entity(
        %{
          simulator: %{free: free_simulators, busy: busy_simulators}
        } = state,
        :simulators,
        user
      ) do
    {free, busy} = do_free_entity(free_simulators, busy_simulators, user, :simulators)
    update_state(state, :simulator, free, busy)
  end

  @doc false
  @spec update_state(map(), atom(), list() | map(), map()) :: map()
  def update_state(state, key, free, busy),
    do: Map.put(state, key, %{free: free, busy: busy})

  # we'll assign the simulator and flows for 10 minute intervals
  @cache_time 10
  @spec do_free_entity(map(), map(), User.t() | nil, atom()) :: {map(), map()}
  defp do_free_entity(free, busy, user, entity_type) do
    expiry_time = DateTime.utc_now() |> DateTime.add(-1 * @cache_time * 60, :second)

    Enum.reduce(
      busy,
      {free, busy},
      fn {{id, fingerprint}, {entity, time}}, {free, busy} ->
        # when user already has entity flow assigned with same fingerprint
        if (user && user.id == id && user.fingerprint == fingerprint) ||
             DateTime.compare(time, expiry_time) == :lt do
          Logger.info(
            "Releasing entity: #{inspect(entity)} for user: #{user.name} of org_id: #{
              user.organization_id
            }."
          )

          publish_data(entity.organization_id, id, entity_type)

          {
            [entity | free],
            Map.delete(busy, {id, fingerprint})
          }
        else
          {free, busy}
        end
      end
    )
  end

  # sending subscription when simulator is released
  @spec publish_data(non_neg_integer, non_neg_integer, atom()) :: any() | nil
  defp publish_data(organization_id, user_id, :simulators) do
    Communications.publish_data(
      %{"simulator_release" => %{user_id: user_id}},
      :simulator_release,
      organization_id
    )
  end

  defp publish_data(_organization_id, _user_id, :flows), do: nil
end
