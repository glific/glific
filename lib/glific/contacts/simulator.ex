defmodule Glific.Contacts.Simulator do
  @moduledoc """
  Manage simulator state and allocation to ensure we can have multiple simulators
  run at the same time
  """

  use Publicist

  use GenServer

  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Repo}

  # lets first define the genserver Server callbacks

  @impl true
  @doc false
  def init(_opts) do
    # our state is a map of organization ids to simulator contexts
    {:ok, reset_state()}
  end

  @impl true
  @doc false
  def handle_call({:get, organization_id, user_id}, _from, state) do
    {contact, state} = get_simulator(organization_id, user_id, state)

    {:reply, contact, state}
  end

  @impl true
  @doc false
  def handle_call({:release, organization_id, user_id}, _from, state) do
    state = release_simulator(organization_id, user_id, state)

    {:reply, :ok, state}
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
  def get(organization_id, user_id) do
    GenServer.call(__MODULE__, {:get, organization_id, user_id})
  end

  @doc false
  def release(organization_id, user_id) do
    GenServer.call(__MODULE__, {:release, organization_id, user_id})
  end

  @doc false
  def state(organization_id) do
    GenServer.call(__MODULE__, {:state, organization_id})
  end

  @doc false
  def reset() do
    GenServer.call(__MODULE__, :reset)
  end

  # We now implement the rest of the API

  @doc """
  Check if there is an available simulator for this user_id
  - If available, return the free Simulator Contact
    (there are multiple simulator contacts per organization)
  - If none available, trurn nil
  """
  @spec get_simulator(non_neg_integer, non_neg_integer, map()) :: {Contact.t(), map()}
  def get_simulator(organization_id, user_id, state) do
    {org_state, contact} =
      get_state(state, organization_id)
      |> free_simulators()
      |> get_simulator(user_id)

    {contact, Map.put(state, organization_id, org_state)}
  end

  @spec get_simulator(map(), non_neg_integer) :: {map, Contact.t()} | nil
  defp get_simulator(%{free: free, busy: busy} = state, user_id) do
    cond do
      # if userid already has a simulator, send that contact
      # and update time
      Map.has_key?(busy, user_id) ->
        contact = elem(busy[user_id], 0)

        {
          %{
            free: free,
            busy: Map.put(busy, user_id, {contact, DateTime.utc_now()})
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
            busy: Map.put(busy, user_id, {contact, DateTime.utc_now()})
          },
          contact
        }
    end
  end

  @doc """
  Release the simulator associated with this user id. It is possible
  that there is no simulator associated with this user
  """
  @spec release_simulator(non_neg_integer, non_neg_integer, map()) :: map()
  def release_simulator(organization_id, user_id, state) do
    org_state =
      get_state(state, organization_id)
      |> free_simulators(user_id)

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

  @simulator_phone_prefix "9876543210"
  # we'll assign the simulator for 10 minute intervals
  @cache_time 10

  @spec init_state(non_neg_integer) :: map()
  defp init_state(organization_id) do
    phone = @simulator_phone_prefix <> "%"

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

  @spec free_simulators(map(), non_neg_integer | nil) :: map()
  defp free_simulators(%{free: free, busy: busy} = _state, uid \\ nil) do
    expiry_time = DateTime.utc_now() |> DateTime.add(-1 * @cache_time * 60, :second)

    {f, b} =
      Enum.reduce(
        busy,
        {free, busy},
        fn {user_id, {contact, time}}, {f, b} ->
          if uid == user_id || DateTime.compare(time, expiry_time) == :lt do
            {
              [contact | f],
              Map.delete(b, user_id)
            }
          else
            {f, b}
          end
        end
      )

    %{free: f, busy: b}
  end
end
