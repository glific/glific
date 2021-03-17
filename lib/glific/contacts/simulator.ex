defmodule Glific.Contacts.Simulator do
  @moduledoc """
  Manage simulator state and allocation to ensure we can have multiple simulators
  run at the same time
  """

  use Publicist

  use GenServer

  import Ecto.Query, warn: false

  alias Glific.{Communications, Contacts, Contacts.Contact, Repo, Users.User}

  # lets first define the genserver Server callbacks

  @impl true
  @doc false
  def init(_opts) do
    # our state is a map of organization ids to simulator contexts
    {:ok, reset_state()}
  end

  @impl true
  @doc false
  def handle_call({:get, user}, _from, state) do
    {contact, state} = get_simulator(user, state)

    {:reply, contact, state}
  end

  @impl true
  @doc false
  def handle_call({:release, user}, _from, state) do
    state = release_simulator(user, state)

    {:reply, nil, state}
  end

  @impl true
  @doc false
  def handle_call({:state, organization_id}, _from, state) do
    {:reply, get_state(state, organization_id), state}
  end

  @impl true
  @doc false
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, reset_state()}
  end

  # Note that we are specifically not implementing the handle_cast callback
  # since it does not make sense for the purposes of this interface

  # lets define the client interface
  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def get(user) do
    GenServer.call(__MODULE__, {:get, user})
  end

  @doc false
  def release(user) do
    GenServer.call(__MODULE__, {:release, user})
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
      |> free_simulators()
      |> get_org_simulator(user)

    {contact, Map.put(state, organization_id, org_state)}
  end

  @spec get_org_simulator(map(), User.t()) :: {map, Contact.t()} | nil
  defp get_org_simulator(%{free: free, busy: busy} = state, user) do
    key = {user.id, user.fingerprint}

    cond do
      # if userid already has a simulator, send that contact
      # and update time
      Map.has_key?(busy, key) ->
        contact = elem(busy[key], 0)

        {
          %{
            free: free,
            busy: Map.put(busy, key, {contact, DateTime.utc_now()})
          },
          contact
        }

      Enum.empty?(free) ->
        {state, nil}

      true ->
        [contact | free] = free

        {
          %{
            free: free,
            busy: Map.put(busy, key, {contact, DateTime.utc_now()})
          },
          contact
        }
    end
  end

  @doc """
  Release the simulator associated with this user id. It is possible
  that there is no simulator associated with this user
  """
  @spec release_simulator(User.t(), map()) :: map()
  def release_simulator(user, state) do
    organization_id = user.organization_id

    org_state =
      get_state(state, organization_id)
      |> free_simulators(user)

    Map.put(state, organization_id, org_state)
  end

  # initializes the simulator cache for this organization
  # if not already present
  @spec get_state(map(), non_neg_integer) :: map()
  defp get_state(state, organization_id) do
    if Map.has_key?(state, organization_id),
      do: state[organization_id],
      else: init_state(organization_id)
  end

  # we'll assign the simulator for 10 minute intervals
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

    %{free: contacts, busy: %{}}
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

  @spec free_simulators(map(), User.t() | nil) :: map()
  defp free_simulators(%{free: free, busy: busy} = _state, user \\ nil) do
    expiry_time = DateTime.utc_now() |> DateTime.add(-1 * @cache_time * 60, :second)

    {f, b} =
      Enum.reduce(
        busy,
        {free, busy},
        fn {{id, fingerprint}, {contact, time}}, {f, b} ->
          if (user && user.id == id && user.fingerprint == fingerprint) ||
               DateTime.compare(time, expiry_time) == :lt do
            publish_data(contact.organization_id, id)

            {
              [contact | f],
              Map.delete(b, {id, fingerprint})
            }
          else
            {f, b}
          end
        end
      )

    %{free: f, busy: b}
  end
end
