defmodule Glific.Clients.Weunlearn do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows.Action,
    Groups.ContactGroup,
    Groups.UserGroup,
    Repo,
    Users.User
  }

  @doc """
  Choose the first group the contact belongs to, and send the message
  to the first staff member in that group
  """
  # codebeat:disable[ABC]
  @spec broadcast(Action.t(), Contact.t(), non_neg_integer) :: non_neg_integer
  def broadcast(_action, contact, staff_id) do
    group_staff_id =
      Contact
      |> where([c], c.id == ^contact.id)
      |> join(:inner, [c], cg in ContactGroup, on: c.id == cg.contact_id)
      |> join(:inner, [_c, cg], ug in UserGroup, on: cg.group_id == ug.group_id)
      |> join(:inner, [_c, _cg, ug], u in User, on: ug.user_id == u.id)
      |> select([_c, _cg, _ug, u], u.contact_id)
      |> order_by([_c, _cg, _ug, u], u.contact_id)
      |> first()
      |> Repo.one()

    if is_nil(group_staff_id),
      do: staff_id,
      else: group_staff_id
  end

  # codebeat:enable[ABC]
end
