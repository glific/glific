defmodule Glific.Contacts.Simulator do
  @moduledoc """
  Manage simulator state and allocation to ensure we can have multiple simulators
  run at the same time
  """

  use Publicist

  import Ecto.Query, warn: false

  alias Glific.{Caches, Contacts.Contact, Repo}

  @doc """
  Check if there is an available simulator for this user_id
  - If available, return the free Simulator Contact
    (there are multiple simulator contacts per organization)
  - If none available, trurn nil
  """
  @spec get_simulator(non_neg_integer) :: Contact.t() | nil
  def get_simulator(user_id) do
    {simulator, contact} =
      get_cache()
      |> free_simulators()
      |> get_simulator(user_id)

    set_cache(simulator)
    contact
  end

  @spec get_simulator(map(), non_neg_integer) :: {map, Contact.t()} | nil
  defp get_simulator(%{free: free, busy: busy} = simulators, user_id) do
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
        {simulators, nil}

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
  @spec release_simulator(non_neg_integer) :: nil
  def release_simulator(user_id) do
    get_cache()
    |> free_simulators(user_id)
    |> set_cache()
  end

  # initializes the simulator cache for this organization
  # if not already present
  @spec get_cache :: map()
  defp get_cache() do
    organization_id = Repo.get_organization_id()

    {status, simulators} =
      Caches.fetch(
        organization_id,
        :simulators,
        &load_cache/1
      )

    if status not in [:ok, :commit],
      do: raise(ArgumentError, message: "Failed to retrieve simulators for #{organization_id}")

    simulators
  end

  @spec set_cache(map()) :: nil
  defp set_cache(simulators) do
    {:ok, _} = Caches.set(Repo.get_organization_id(), :simulators, simulators)
    nil
  end

  @simulator_phone_prefix "9876543210"
  # we'll assign the simulator for 10 minute intervals
  @cache_time 10

  @spec load_cache(tuple()) :: tuple()
  defp load_cache(cache_key) do
    {organization_id, :simulators} = cache_key

    {:commit, init_state(organization_id)}
  end

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

  @spec init_cache(non_neg_integer) :: nil
  defp init_cache(organization_id) do
    Caches.set(organization_id, :simulators, init_state(organization_id))
  end

  @spec free_simulators(map(), non_neg_integer | nil) :: map()
  defp free_simulators(simulators, uid \\ nil) do
    %{free: free, busy: busy} = simulators

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
