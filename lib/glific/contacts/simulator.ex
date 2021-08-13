defmodule Glific.Contacts.Simulator do
  @moduledoc """
  Manage simulator state and allocation to ensure we can have multiple simulators
  run at the same time
  """

  use Publicist

  use GenServer

  import Ecto.Query, warn: false

  alias Glific.{Communications, Contacts, Contacts.Contact, Flows.Flow, Repo, Users.User}

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
    {contact, state} = get_simulator(user, state)

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
    {flow, state} = get_flow(params.user, params.flow_id, state)
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

  # We now implement the rest of the API

  @doc """
  Check if there is an available simulator for this user
  - If available, return the free Simulator Contact
    (there are multiple simulator contacts per organization)
  - If none available, trurn nil
  """
  @spec get_simulator(User.t(), map()) :: {Contact.t(), map()}
  def get_simulator(user, state) do
    organization_id = user.organization_id

    {org_state, contact} =
      get_state(state, organization_id)
      |> free_resource(:simulators)
      |> get_org_simulator(user)

    {contact, Map.put(state, organization_id, org_state)}
  end

  @spec get_org_simulator(map(), User.t()) :: {map, Contact.t()} | nil
  defp get_org_simulator(
         %{
           free_simulators: free,
           busy_simulators: busy,
           free_flows: free_flows,
           busy_flows: busy_flows
         } = state,
         user
       ) do
    key = {user.id, user.fingerprint}

    cond do
      # if userid already has a simulator, send that contact
      # and update time
      Map.has_key?(busy, key) ->
        contact = elem(busy[key], 0)

        {
          %{
            free_simulators: free,
            busy_simulators: Map.put(busy, key, {contact, DateTime.utc_now()}),
            free_flows: free_flows,
            busy_flows: busy_flows
          },
          contact
        }

      Enum.empty?(free) ->
        {state, nil}

      true ->
        [contact | free] = free

        {
          %{
            free_simulators: free,
            busy_simulators: Map.put(busy, key, {contact, DateTime.utc_now()}),
            free_flows: free_flows,
            busy_flows: busy_flows
          },
          contact
        }
    end
  end

  # initializes the simulator cache for this organization
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
      Contact
      |> where([c], like(c.phone, ^phone))
      |> where([c], c.organization_id == ^organization_id)
      |> Repo.all(skip_organization_id: true, skip_permission: true)

    # fetch all the flows for this organization
    flows =
      Flow
      |> where([f], f.organization_id == ^organization_id)
      |> Repo.all(skip_organization_id: true, skip_permission: true)

    %{free_simulators: contacts, busy_simulators: %{}, free_flows: flows, busy_flows: %{}}
  end

  @spec reset_state :: map()
  defp reset_state do
    %{}
  end

  @spec publish_data(non_neg_integer, non_neg_integer) :: any()
  defp publish_data(organization_id, user_id) do
    Communications.publish_data(
      %{"simulator_release" => %{user_id: user_id}},
      :simulator_release,
      organization_id
    )
  end

  @spec get_flow(User.t(), non_neg_integer, map) :: {Flow.t(), map}
  defp get_flow(user, flow_id, state) do
    organization_id = user.organization_id

    {org_state, contact} =
      get_state(state, organization_id)
      |> free_resource(:flows)
      |> get_org_flows(user, flow_id)

    {contact, Map.put(state, organization_id, org_state)}
  end

  @spec update_state(atom(), map(), map(), map()) :: map()
  defp update_state(:simulators, free, busy, state),
    do: Map.merge(state, %{free_simulators: free, busy_simulators: busy})

  defp update_state(:flows, free, busy, state),
    do: Map.merge(state, %{free_flows: free, busy_flows: busy})

  @spec get_org_flows(map(), User.t(), non_neg_integer()) :: {map, Flow.t()} | nil
  defp get_org_flows(
         %{
           free_simulators: free_simulators,
           busy_simulators: busy_simulators,
           free_flows: free,
           busy_flows: busy
         } = state,
         user,
         flow_id
       ) do
    key = {user.id, user.fingerprint}
    organization_id = user.organization_id

    [flow] =
      Flow
      |> where([f], f.organization_id == ^organization_id)
      |> where([f], f.id == ^flow_id)
      |> Repo.all(skip_organization_id: true, skip_permission: true)

    [available_flow] = [flow] |> check_available(free)

    cond do
      Map.has_key?(busy, key) ->
        {assigned_flow, _time} = Map.get(busy, key)

        requested_flow =
          if assigned_flow == flow,
            do: assigned_flow,
            else: available_flow

        # Updating free flows list when a new flow is assigned to user
        available_flows = if assigned_flow == flow, do: free, else: free ++ [assigned_flow]

        {
          %{
            free_simulators: free_simulators,
            busy_simulators: busy_simulators,
            free_flows: Enum.uniq(available_flows) -- [requested_flow],
            busy_flows: Map.put(busy, key, {requested_flow, DateTime.utc_now()})
          },
          requested_flow
        }

      is_nil(available_flow) || Enum.empty?(free) ->
        {state, nil}

      true ->
        {
          %{
            free_simulators: free_simulators,
            busy_simulators: busy_simulators,
            free_flows: free -- [available_flow],
            busy_flows: Map.put(busy, key, {flow, DateTime.utc_now()})
          },
          available_flow
        }
    end
  end

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

  @spec check_available(list, any) :: nil | list
  defp check_available(flow, free),
    do: if(Enum.member?(free, List.first(flow)), do: flow, else: [nil])

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
    {free, busy} = do_free_resource(free_flows, busy_flows, user)
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
    {free, busy} = do_free_resource(free_simulators, busy_simulators, user)
    update_state(:simulators, free, busy, state)
  end

  @spec do_free_resource(map(), map(), User.t() | nil) :: {map(), map()}
  defp do_free_resource(free, busy, user) do
    expiry_time = DateTime.utc_now() |> DateTime.add(-1 * @cache_time * 60, :second)

    Enum.reduce(
      busy,
      {free, busy},
      fn {{id, fingerprint}, {contact, time}}, {free, busy} ->
        if (user && user.id == id && user.fingerprint == fingerprint) ||
             DateTime.compare(time, expiry_time) == :lt do
          publish_data(contact.organization_id, id)

          {
            [contact | free],
            Map.delete(busy, {id, fingerprint})
          }
        else
          {free, busy}
        end
      end
    )
  end
end
