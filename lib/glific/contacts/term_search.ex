defmodule Glific.Contacts.TermSearch do
  @moduledoc """
  The condition a free-text term must satisfy to match a contact: its name or phone contains the
  term, or, for a user allowed to see them, one of its web usernames starts with it.

  Contact lists, the inbox search and the multi search all build their term filter here, so the
  escaping of the term and the username rule live in one place.
  """

  import Ecto.Query

  alias Glific.{Contacts.ContactIdentities, Users.User}

  @doc """
  A condition on the first binding, a contact, for ANDing into a contact query. The username
  alternative is included only for a `user` that is not a `:staff` user, who may not see
  identifiers; with no user (a background job, say) it is left out.
  """
  @spec match(String.t(), User.t() | nil) :: Ecto.Query.dynamic_expr()
  def match(term, user) do
    pattern = "%#{escape_like(term)}%"
    name_or_phone = dynamic([c], ilike(c.name, ^pattern) or ilike(c.phone, ^pattern))

    if include_usernames?(user),
      do: dynamic([c], ^name_or_phone or ^username_match(term, user.organization_id)),
      else: name_or_phone
  end

  @spec include_usernames?(User.t() | nil) :: boolean()
  defp include_usernames?(%{roles: roles}) when is_list(roles),
    do: not Enum.any?(roles, &(to_string(&1) == "staff"))

  defp include_usernames?(_user), do: false

  @spec username_match(String.t(), non_neg_integer()) :: Ecto.Query.dynamic_expr()
  defp username_match(term, organization_id) do
    pattern = "#{term |> String.downcase() |> escape_like()}%"
    matching = ContactIdentities.web_contact_ids_query(organization_id, pattern)

    dynamic([c], c.id in subquery(matching))
  end

  @spec escape_like(String.t()) :: String.t()
  defp escape_like(term), do: String.replace(term, ["\\", "%", "_"], &"\\#{&1}")
end
