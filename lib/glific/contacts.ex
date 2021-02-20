defmodule Glific.Contacts do
  @moduledoc """
  The Contacts context.
  """
  import Ecto.Query, warn: false

  use Tesla
  plug Tesla.Middleware.FormUrlencoded

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Contacts.Location,
    Groups.ContactGroup,
    Groups.UserGroup,
    Partners,
    Providers.GupshupContacts,
    Repo,
    Tags.ContactTag,
    Users.User
  }

  @doc """
  Add permissioning specific to groups, in this case we want to restrict the visibility of
  groups that the user can see
  """
  @spec add_permission(Ecto.Query.t(), User.t()) :: Ecto.Query.t()
  def add_permission(query, user) do
    sub_query =
      ContactGroup
      |> select([cg], cg.contact_id)
      |> join(:inner, [cg], ug in UserGroup, as: :ug, on: ug.group_id == cg.group_id)
      |> where([cg, ug: ug], ug.user_id == ^user.id)

    query
    |> where([c], c.id == ^user.contact_id or c.id in subquery(sub_query))
  end

  @doc """
  Returns the list of contacts.

  ## Examples

      iex> list_contacts()
      [%Contact{}, ...]

  Get the list of contacts filtered by various search options
  Include contacts only if within list of groups
  Include contacts only if have list of tags
  """
  @spec list_contacts(map()) :: [Contact.t()]
  def list_contacts(args) do
    args
    |> Repo.list_filter_query(Contact, &Repo.opts_with_name/2, &filter_with/2)
    |> Repo.add_permission(&Contacts.add_permission/2)
    |> Repo.all()
  end

  @doc """
  Return the list of contacts who are also users
  """
  @spec list_user_contacts(map()) :: [Contact.t()]
  def list_user_contacts(args \\ %{}) do
    args
    |> Repo.list_filter_query(Contact, &Repo.opts_with_name/2, &filter_with/2)
    |> join(:inner, [c], u in User, as: :u, on: u.contact_id == c.id)
    |> where([u: u], :none not in u.roles)
    |> Repo.all()
  end

  @doc """
  Return the count of contacts, using the same filter as list_contacts
  """
  @spec count_contacts(map()) :: integer
  def count_contacts(args) do
    args
    |> Repo.list_filter_query(Contact, nil, &filter_with/2)
    |> Repo.add_permission(&Contacts.add_permission/2)
    |> Repo.aggregate(:count)
  end

  # codebeat:disable[ABC, LOC]
  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:status, status}, query ->
        from q in query, where: q.status == ^status

      {:bsp_status, bsp_status}, query ->
        from q in query, where: q.bsp_status == ^bsp_status

      {:include_groups, []}, query ->
        query

      # We need distinct query expression with join,
      # in case if filter requires contacts added to multiple groups
      # Using subquery instead of join, so that distict query expression can be avoided
      # We can come back and decide, which one is more expensive in this scenario.
      {:include_groups, group_ids}, query ->
        sub_query =
          ContactGroup
          |> where([cg], cg.group_id in ^group_ids)
          |> select([cg], cg.contact_id)

        query
        |> where([c], c.id in subquery(sub_query))

      {:include_tags, []}, query ->
        query

      {:include_tags, tag_ids}, query ->
        sub_query =
          ContactTag
          |> where([ct], ct.tag_id in ^tag_ids)
          |> select([ct], ct.contact_id)

        query
        |> where([c], c.id in subquery(sub_query))

      _, query ->
        query
    end)
    |> filter_contacts_with_blocked_status(filter)
  end

  # codebeat:enable[ABC, LOC]

  # Remove contacts with blocked status unless filtered by status
  @spec filter_contacts_with_blocked_status(Ecto.Queryable.t(), %{optional(atom()) => any}) ::
          Ecto.Queryable.t()
  defp filter_contacts_with_blocked_status(query, %{status: _}), do: query

  defp filter_contacts_with_blocked_status(query, _),
    do: from(q in query, where: q.status != "blocked")

  @spec has_permission?(non_neg_integer) :: boolean()
  defp has_permission?(id) do
    if Repo.skip_permission?() == true do
      true
    else
      contact =
        Contact
        |> Ecto.Queryable.to_query()
        |> Repo.add_permission(&Contacts.add_permission/2)
        |> where([c], c.id == ^id)
        |> select([c], c.id)
        |> Repo.one()

      if contact == nil,
        do: false,
        else: true
    end
  end

  @doc """
  Gets a single contact.

  Raises `Ecto.NoResultsError` if the Contact does not exist.

  ## Examples

      iex> get_contact!(123)
      %Contact{}

      iex> get_contact!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_contact!(integer) :: Contact.t()
  def get_contact!(id) do
    Contact
    |> Ecto.Queryable.to_query()
    |> Repo.add_permission(&Contacts.add_permission/2)
    |> Repo.get!(id)
  end

  @doc """
  Creates a contact.

  ## Examples

      iex> create_contact(%{field: value})
      {:ok, %Contact{}}

      iex> create_contact(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_contact(%{organization_id: organization_id} = attrs) do
    attrs =
      attrs
      |> Map.put(
        :language_id,
        attrs[:language_id] || Partners.organization_language_id(organization_id)
      )
      |> Map.put(
        :last_communication_at,
        attrs[:last_communication_at] || DateTime.utc_now()
      )

    %Contact{}
    |> Contact.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a contact.

  ## Examples

      iex> update_contact(contact, %{field: new_value})
      {:ok, %Contact{}}

      iex> update_contact(contact, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_contact(Contact.t(), map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def update_contact(%Contact{} = contact, attrs) do
    if has_permission?(contact.id) do
      contact
      |> Contact.changeset(attrs)
      |> Repo.update()
    else
      raise "Permission denied"
    end
  end

  @doc """
  Deletes a contact.

  ## Examples

      iex> delete_contact(contact)
      {:ok, %Contact{}}

      iex> delete_contact(contact)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_contact(Contact.t()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def delete_contact(%Contact{} = contact) do
    if has_permission?(contact.id),
      do: Repo.delete(contact),
      else: raise("Permission denied")
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking contact changes.

  ## Examples

      iex> change_contact(contact)
      %Ecto.Changeset{data: %Contact{}}

  """
  @spec change_contact(Contact.t(), map()) :: Ecto.Changeset.t()
  def change_contact(%Contact{} = contact, attrs \\ %{}) do
    Contact.changeset(contact, attrs)
  end

  @doc """
  Gets or Creates a Contact based on the unique indexes in the table. If there is a match
  it returns the existing contact, else it creates a new one
  """
  @spec upsert(map()) :: {:ok, Contact.t()}
  def upsert(%{organization_id: organization_id} = attrs) do
    # we keep this separate to avoid overwriting the language if already set by a contact
    # this will not appear in the set field of the on_conflict: clause below
    other_attrs = %{
      organization_id: organization_id,
      language_id: attrs[:language_id] || Partners.organization_language_id(organization_id)
    }

    contact =
      Repo.insert!(
        change_contact(%Contact{}, Map.merge(other_attrs, attrs)),
        returning: true,
        on_conflict: [set: Enum.map(attrs, fn {key, value} -> {key, value} end)],
        conflict_target: [:phone, :organization_id]
      )

    {:ok, contact}
  end

  @spec handle_phone_error(map(), Ecto.Changeset.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp handle_phone_error(sender, changeset) do
    map = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

    if Map.get(map, :phone) == ["has already been taken"] do
      Repo.fetch_by(Contact, %{phone: sender.phone})
    else
      {:error, changeset}
    end
  end

  @doc """
  This function is called by the messaging framework for all incoming messages, hence
  might be a good candidate to maintain a contact level cache at some point

  We use a fetch followed by create, to avoid the explosion in the id namespace
  """
  @spec maybe_create_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def maybe_create_contact(sender) do
    case Repo.get_by(Contact, %{phone: sender.phone}) do
      nil ->
        case create_contact(sender) do
          {:ok, contact} -> {:ok, contact}
          # there is a small chance that due to the opt-in and first message
          # arriving at the same time, we fire this twice, which results in an error
          # Issue #850
          {:error, changeset} -> handle_phone_error(sender, changeset)
        end

      contact ->
        if contact.name != sender.name do
          # the contact name has changed, so we need to update it
          update_contact(contact, %{name: sender.name})
        else
          {:ok, contact}
        end
    end
  end

  @doc """
  Check if this contact id is a new contact.
  In general, we should always retrive as little as possible from the DB
  """
  @spec is_new_contact(integer()) :: boolean()
  def is_new_contact(contact_id) do
    case Glific.Messages.Message
         |> where([m], m.contact_id == ^contact_id)
         |> where([m], m.flow == "outbound")
         |> select([m], m.id)
         |> limit(1)
         |> Repo.all() do
      [] -> true
      _ -> false
    end
  end

  @doc """
  Update DB fields when contact opted in and ignore if it's blocked
  """
  @spec contact_opted_in(String.t(), non_neg_integer, DateTime.t(), Keyword.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def contact_opted_in(phone, organization_id, utc_time, opts \\ []) do
    attrs = %{
      phone: phone,
      optin_time: utc_time,
      optin_status: true,
      optin_method: Keyword.get(opts, :method, "URL"),
      optin_message_id: Keyword.get(opts, :message_id),
      last_message_at: nil,
      optout_time: nil,
      status: :valid,
      bsp_status: :hsm,
      organization_id: organization_id,
      updated_at: DateTime.utc_now()
    }

    case Repo.get_by(Contact, %{phone: phone}) do
      nil ->
        create_contact(attrs)

      contact ->
        if contact.status == :blocked,
          do: {:ok, contact},
          else: update_contact(contact, attrs)
    end
  end

  @doc """
  Update DB fields when contact opted out
  """
  @spec contact_opted_out(String.t(), non_neg_integer, DateTime.t()) :: {:ok}
  def contact_opted_out(phone, organization_id, utc_time) do
    attrs = %{
      phone: phone,
      optout_time: utc_time,
      optin_time: nil,
      optin_status: false,
      optin_method: nil,
      optin_message_id: nil,
      status: :invalid,
      bsp_status: :none,
      organization_id: organization_id,
      updated_at: DateTime.utc_now()
    }

    case Repo.get_by(Contact, %{phone: phone}) do
      nil ->
        raise "Contact does not exist with phone: #{phone}"

      contact ->
        update_contact(contact, attrs)
    end

    {:ok}
  end

  @doc """
  Check if we can send a message to the contact
  """
  @spec can_send_message_to?(Contact.t()) :: boolean()
  def can_send_message_to?(contact), do: can_send_message_to?(contact, false)

  @doc false
  @spec can_send_message_to?(Contact.t(), boolean()) :: boolean()
  def can_send_message_to?(contact, true = _is_hsm) do
    if contact.status == :valid &&
         contact.bsp_status in [:session_and_hsm, :hsm] &&
         contact.optin_time != nil,
       do: true,
       else: false
  end

  @doc """
  Check if we can send a session message to the contact
  """
  def can_send_message_to?(contact, false = _is_hsm) do
    if contact.status == :valid &&
         contact.bsp_status in [:session_and_hsm, :session] &&
         Glific.in_past_time(contact.last_message_at, :hours, 24),
       do: true,
       else: false
  end

  @doc """
  Get contact's current location
  """
  @spec contact_location(Contact.t()) :: {:ok, Location.t()}
  def contact_location(contact) do
    location =
      Location
      |> where([l], l.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    {:ok, location}
  end

  @doc """
  Creates a location.

  ## Examples
      iex> Glific.Contacts.create_location(%{name: value})
      {:ok, %Glific.Contacts.Location{}}

      iex> Glific.Contacts.create_location(%{bad_field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_location(map()) :: {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  def create_location(attrs \\ %{}) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Invoked from cron jobs to mass update the status of contacts belonging to
  a specific organization

  In this case, if we can, we might want to do it across the entire DB since the
  update is across all organizations. The main issue might be the row level security
  of postgres and how it ties in. For now, lets stick to per organization
  """
  @spec update_contact_status(non_neg_integer, map()) :: :ok
  def update_contact_status(organization_id, _args) do
    t = Glific.go_back_time(24)

    Contact
    |> where([c], c.last_message_at <= ^t)
    |> where([c], c.organization_id == ^organization_id)
    |> select([c], c.id)
    |> Repo.all(skip_organization_id: true)
    |> set_session_status(:none)
  end

  @doc """
  Set session status for opted in and opted out contacts
  """
  @spec set_session_status(Contact.t() | [non_neg_integer], atom()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | :ok
  def set_session_status(contact, :none = _status) when is_struct(contact) do
    if is_nil(contact.optin_time),
      do: update_contact(contact, %{bsp_status: :none}),
      else: update_contact(contact, %{bsp_status: :hsm})
  end

  def set_session_status([], _) do
    :ok
  end

  def set_session_status(contact_ids, :none = _status) when is_list(contact_ids) do
    Contact
    |> where([c], is_nil(c.optin_time))
    |> where([c], c.id in ^contact_ids)
    |> Repo.update_all([set: [bsp_status: :none]], skip_organization_id: true)

    Contact
    |> where([c], not is_nil(c.optin_time))
    |> where([c], c.id in ^contact_ids)
    |> Repo.update_all([set: [bsp_status: :hsm]], skip_organization_id: true)

    :ok
  end

  def set_session_status(contact, :session = _status) do
    if is_nil(contact.optin_time),
      do: update_contact(contact, %{bsp_status: :session}),
      else: update_contact(contact, %{bsp_status: :session_and_hsm})
  end

  @doc """
  check if contact is blocked or not
  """
  @spec is_contact_blocked?(String.t(), non_neg_integer) :: boolean()
  def is_contact_blocked?(phone, _organization_id) do
    case Repo.fetch_by(Contact, %{phone: phone}) do
      {:ok, contact} -> contact.status == :blocked
      _ -> false
    end
  end

  @doc """
  Upload a contact phone as opted in
  """
  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    organization = Partners.organization(organization_id)

    case organization.bsp.shortcode do
      "gupshup" -> GupshupContacts.optin_contact(attrs)
      _ -> {:error, "Invalid provider"}
    end
  end

  @doc """
  Convert contact field to map for variable substitution
  """
  @spec get_contact_field_map(integer) :: map()
  def get_contact_field_map(contact_id) do
    contact =
      contact_id
      |> Contacts.get_contact!()
      |> Repo.preload([:language, :groups])
      |> Map.from_struct()

    # we are splliting this up since we need to use contact within the various function
    # calls and a lot cleaner this way
    contact
    |> put_in(
      [:fields, :language],
      %{label: contact.language.label}
    )
    |> Map.put(
      :in_groups,
      Enum.reduce(
        contact.groups,
        [],
        fn g, list -> [g.label | list] end
      )
    )
  end

  @simulator_phone_prefix "9876543210"

  @doc false
  @spec simulator_phone_prefix :: String.t()
  def simulator_phone_prefix, do: @simulator_phone_prefix

  @doc false
  @spec saas_phone :: String.t()
  def saas_phone, do: Application.fetch_env!(:glific, :saas_phone)

  @doc """
  Lets centralize the code to detect simulator messages and interaction
  """
  @spec is_simulator_contact?(String.t()) :: boolean
  def is_simulator_contact?(phone), do: String.starts_with?(phone, @simulator_phone_prefix)
end
