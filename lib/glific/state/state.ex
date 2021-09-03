defmodule Glific.State do
  @moduledoc """
  Manage simulator and flows, managing state and allocation to ensure we can have multiple simulators
  and flow run at the same time
  """

  use Publicist

  use GenServer

  import Ecto.Query, warn: false

  alias Glific.{
    Communications,
    Contacts,
    Repo,
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
    state = release_resource(user, state, :simulators)

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
    state = release_resource(user, state, :flows)

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

  # initializes the state for this organization
  # if not already present
  @spec get_state(map(), non_neg_integer) :: map()
  defp get_state(state, organization_id) do
    if Map.has_key?(state, organization_id),
      do: state[organization_id],
      else: init_state(organization_id)
  end

  # we'll assign the simulator and flows for 10 minute intervals
  @cache_time 10

  @spec init_state(non_neg_integer) :: map()
  defp init_state(organization_id) do
    phone = Contacts.simulator_phone_prefix() <> "%"

    # fetch all the simulator contacts for this organization
    contacts =
      Glific.Contacts.Contact
      |> where([c], like(c.phone, ^phone))
      |> where([c], c.organization_id == ^organization_id)
      |> Repo.all(skip_organization_id: true, skip_permission: true)

    # fetch all the flows for this organization
    flows =
      Glific.Flows.Flow
      |> where([f], f.organization_id == ^organization_id)
      |> Repo.all(skip_organization_id: true, skip_permission: true)

    %{free_simulators: contacts, busy_simulators: %{}, free_flows: flows, busy_flows: %{}}
  end

  @spec reset_state :: map()
  defp reset_state do
    %{}
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

  @spec update_state(atom(), map(), map(), map()) :: map()
  defp update_state(:simulators, free, busy, state),
    do: Map.merge(state, %{free_simulators: free, busy_simulators: busy})

  defp update_state(:flows, free, busy, state),
    do: Map.merge(state, %{free_flows: free, busy_flows: busy})

  @doc """
  Release the resource associated with this user id. It is possible
  that there is no resource associated with this user
  """
  @spec release_resource(User.t(), map(), atom()) :: map()
  def release_resource(user, state, type) do
    organization_id = user.organization_id

    org_state =
      get_state(state, organization_id)
      |> free_resource(type, user)

    Map.put(state, organization_id, org_state)
  end

  @spec free_resource(map(), atom(), User.t() | nil) :: map()
  defp free_resource(_state, _stage, user \\ nil)

  defp free_resource(
         %{
           free_flows: free_flows,
           busy_flows: busy_flows
         } = state,
         :flows,
         user
       ) do
    {free, busy} = do_free_resource(free_flows, busy_flows, user, :flows)
    update_state(:flows, free, busy, state)
  end

  defp free_resource(
         %{
           free_simulators: free_simulators,
           busy_simulators: busy_simulators
         } = state,
         :simulators,
         user
       ) do
    {free, busy} = do_free_resource(free_simulators, busy_simulators, user, :simulators)
    update_state(:simulators, free, busy, state)
  end

  @spec do_free_resource(map(), map(), User.t() | nil, atom()) :: {map(), map()}
  defp do_free_resource(free, busy, user, entity_type) do
    expiry_time = DateTime.utc_now() |> DateTime.add(-1 * @cache_time * 60, :second)

    Enum.reduce(
      busy,
      {free, busy},
      fn {{id, fingerprint}, {entity, time}}, {free, busy} ->
        if (user && user.id == id && user.fingerprint == fingerprint) ||
             DateTime.compare(time, expiry_time) == :lt do
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
end
