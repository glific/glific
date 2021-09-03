defmodule Glific.State.Simulator do
  @moduledoc """
  Manage simulator state and allocation to ensure we can have multiple simulators
  run at the same time
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    State,
    Users.User
  }

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
      State.get_state(state, organization_id)
      |> State.free_resource(:simulators)
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
end
