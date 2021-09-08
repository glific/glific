defmodule Glific.State.Simulator do
  @moduledoc """
  Manage simulator state and allocation to ensure we can have multiple simulators
  run at the same time
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Repo,
    State,
    Users.User
  }

  @doc """
  Check if there is an available simulator for this user
  - If available, return the free Simulator Contact
    (there are multiple simulator contacts per organization)
  - If none available, return nil
  """
  @spec get_simulator(User.t(), map()) :: {Contact.t(), map()}
  def get_simulator(user, state) do
    organization_id = user.organization_id

    {org_state, contact} =
      State.get_state(state, organization_id)
      |> State.free_entity(:simulators, user)
      |> get_org_simulator(user)

    {contact, Map.put(state, organization_id, org_state)}
  end

  @spec get_org_simulator(map(), User.t()) :: {map, Contact.t()} | nil
  defp get_org_simulator(
         %{
           simulator: %{free: free, busy: busy}
         } = state,
         user
       ) do
    key = {user.id, user.fingerprint}

    cond do
      # if userid already has a simulator, assign same simulator
      # and update time
      Map.has_key?(busy, key) ->
        contact = elem(busy[key], 0)

        {
          State.update_state(
            state,
            :simulator,
            free,
            Map.put(busy, key, {contact, DateTime.utc_now()})
          ),
          contact
        }

      # if no simulator is present
      Enum.empty?(free) ->
        {state, nil}

      # if simulator is present
      true ->
        [contact | free] = free

        {
          State.update_state(
            state,
            :simulator,
            free,
            Map.put(busy, key, {contact, DateTime.utc_now()})
          ),
          contact
        }
    end
  end

  @doc false
  @spec init_state(non_neg_integer) :: map()
  def init_state(organization_id) do
    phone = Contacts.simulator_phone_prefix() <> "%"

    # fetch all the simulator contacts for this organization
    contacts =
      Glific.Contacts.Contact
      |> where([c], like(c.phone, ^phone))
      |> where([c], c.organization_id == ^organization_id)
      |> Repo.all(skip_organization_id: true, skip_permission: true)

    %{simulator: %{free: contacts, busy: %{}}}
  end
end
