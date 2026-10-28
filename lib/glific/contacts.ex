defmodule Glific.Contacts do
  @moduledoc """
  The Contacts context.
  """
  import Ecto.Query
  use Gettext, backend: GlificWeb.Gettext

  use Tesla
  plug(Tesla.Middleware.FormUrlencoded)

  alias __MODULE__

  require Logger

  alias Ecto.Multi

  alias Glific.{
    Clients,
    Contacts.Contact,
    Contacts.ContactHistory,
    Contacts.ContactIdentities,
    Contacts.ContactIdentity,
    Contacts.Location,
    Contacts.TermSearch,
    Groups.ContactGroup,
    Groups.ContactWAGroup,
    Groups.UserGroup,
    Partners,
    Partners.Provider,
    Profiles,
    Repo,
    Tags.ContactTag,
    Users.User
  }

  @delete_timeout 400_000

  @type web_claims :: %{
          optional(:sub) => String.t(),
          optional(:exp) => integer(),
          optional(:name) => String.t(),
          optional(:phone) => String.t()
        }

  @doc """
  Add permission specific to groups, in this case we want to restrict the visibility of
  groups that the user can see
  """
  @spec add_permission(Ecto.Query.t(), User.t()) :: Ecto.Query.t()
  def add_permission(query, user) do
    organization_contact_id = Partners.organization_contact_id(user.organization_id)

    sub_query =
      ContactGroup
      |> select([cg], cg.contact_id)
      |> join(:inner, [cg], ug in UserGroup, as: :ug, on: ug.group_id == cg.group_id)
      |> where([cg, ug: ug], ug.user_id == ^user.id)

    query
    |> where(
      [c],
      c.id in [^user.contact_id, ^organization_contact_id] or c.id in subquery(sub_query)
    )
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
    |> Glific.add_limit()
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

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)
    user = Repo.get_current_user()

    Enum.reduce(filter, query, fn
      {:term, term}, query ->
        where(query, ^TermSearch.match(term, user))

      {:status, status}, query ->
        from(q in query, where: q.status == ^status)

      {:bsp_status, bsp_status}, query ->
        from(q in query, where: q.bsp_status == ^bsp_status)

      {:include_groups, []}, query ->
        query

      # We need distinct query expression with join,
      # in case if filter requires contacts added to multiple groups
      # Using sub query instead of join, so that distinct query expression can be avoided
      # We can come back and decide, which one is more expensive in this scenario.
      {:include_groups, group_ids}, query ->
        sub_query =
          ContactGroup
          |> where([cg], cg.group_id in ^group_ids)
          |> select([cg], cg.contact_id)

        query
        |> where([c], c.id in subquery(sub_query))

      {:include_wa_groups, []}, query ->
        query

      {:include_wa_groups, wa_group_ids}, query ->
        sub_query =
          ContactWAGroup
          |> where([wg], wg.wa_group_id in ^wa_group_ids)
          |> select([wa], wa.contact_id)

        query
        |> where([c], c.id in subquery(sub_query))

      {:exclude_groups, []}, query ->
        query

      {:exclude_groups, group_ids}, query ->
        sub_query =
          ContactGroup
          |> where([cg], cg.group_id in ^group_ids)
          |> select([cg], cg.contact_id)

        query
        |> where([c], c.id not in subquery(sub_query))

      {:exclude_wa_groups, []}, query ->
        query

      {:exclude_wa_groups, wa_group_ids}, query ->
        sub_query =
          ContactWAGroup
          |> where([wg], wg.wa_group_id in ^wa_group_ids)
          |> select([wa], wa.contact_id)

        query |> where([c], c.id not in subquery(sub_query))

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
    |> where([c], c.id == ^id)
    |> Repo.add_permission(&Contacts.add_permission/2)
    |> Repo.one!()
  end

  @doc """
  Return nil if contact is not present (rather than raising exception)
  """
  @spec get_contact(integer) :: Contact.t() | nil
  def get_contact(id) do
    Contact
    |> where([c], c.id == ^id)
    |> Repo.add_permission(&Contacts.add_permission/2)
    |> Repo.one()
  end

  @doc """
  Gets a single contact by phone number.

  Raises `Ecto.NoResultsError` if the Contact does not exist.

  ## Examples

      iex> get_contact_by_phone!("9876543210_1")
      %Contact{}

      iex> get_contact!("123")
      ** (Ecto.NoResultsError)

  """
  @spec get_contact_by_phone!(String.t()) :: Contact.t()
  def get_contact_by_phone!(phone) when phone in [nil, ""],
    do: raise(ArgumentError, "A phone number is required to look up a contact by phone")

  def get_contact_by_phone!(phone) do
    Contact
    |> where([c], c.phone == ^phone)
    |> Repo.add_permission(&Contacts.add_permission/2)
    |> Repo.one!()
  end

  @doc """
  Creates a contact and its identity in one transaction: its phone on `:whatsapp`, `identifier` on `:web`.

  ## Examples

      iex> create_contact(%{field: value})
      {:ok, %Contact{}}

      iex> create_contact(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_contact(map(), :whatsapp | :web, String.t() | nil) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_contact(attrs, channel \\ :whatsapp, identifier \\ nil)

  def create_contact(attrs, :whatsapp, _identifier),
    do:
      attrs |> new_contact_changeset(:whatsapp) |> insert_with_identity(:whatsapp, attrs[:phone])

  def create_contact(attrs, :web, identifier),
    do: attrs |> new_contact_changeset(:web) |> insert_with_identity(:web, identifier)

  @spec insert_with_identity(Ecto.Changeset.t(), :whatsapp | :web, String.t() | nil, keyword()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp insert_with_identity(changeset, channel, identifier, insert_opts \\ []) do
    Multi.new()
    |> Multi.insert(:contact, changeset, insert_opts)
    |> ContactIdentities.insert_identity(channel, identifier)
    |> Repo.transaction()
    |> case do
      {:ok, %{contact: contact}} -> {:ok, contact}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  # The flow is one-way: callers go through Contacts, which calls ContactIdentities; that never calls back.
  @doc """
  Adds a web username to a contact; one it already has is accepted, one another contact holds is refused.
  """
  @spec add_identity(Contact.t(), :whatsapp | :web, String.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def add_identity(%Contact{} = contact, :web, identifier),
    do: ContactIdentities.add_web_identity(contact, identifier)

  def add_identity(%Contact{} = contact, channel, _identifier) do
    contact
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(:channel, "#{channel} identities follow the contact's phone")
    |> Ecto.Changeset.apply_action(:insert)
  end

  @doc """
  Bulk-inserts contacts and their WhatsApp identities, returning the saved `id`, `phone` and `fields`.
  """
  @spec insert_contacts([map()], keyword()) :: [map()]
  def insert_contacts(entries, opts) do
    {organization_id, opts} = Keyword.pop!(opts, :organization_id)

    {_count, saved} =
      Repo.insert_all(
        Contact,
        entries,
        Keyword.merge(opts,
          conflict_target: [:phone, :organization_id],
          returning: [:id, :phone, :fields | ContactIdentity.consent_and_session_fields()]
        )
      )

    ContactIdentities.insert_whatsapp_identities(saved, organization_id)
    saved
  end

  @doc """
  The changeset for a new contact on a channel, with the organization's defaults filled in.
  """
  @spec new_contact_changeset(map(), :whatsapp | :web) :: Ecto.Changeset.t()
  def new_contact_changeset(attrs, channel),
    do: Contact.changeset(%Contact{}, with_new_contact_defaults(attrs), channel)

  @spec with_new_contact_defaults(map()) :: map()
  defp with_new_contact_defaults(%{organization_id: organization_id} = attrs) do
    attrs
    |> Map.put(
      :language_id,
      attrs[:language_id] || Partners.organization_language_id(organization_id)
    )
    |> Map.put(:last_communication_at, attrs[:last_communication_at] || DateTime.utc_now())
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
      if simulator_block?(contact, attrs) do
        # just treat it as if we blocked the simulator
        # but in reality, we don't block the simulator
        {:ok, contact}
      else
        contact
        |> Contact.changeset(attrs)
        |> persist_update()
      end
    else
      raise "Permission denied"
    end
  end

  @doc """
  Sets a contact's phone and moves its WhatsApp identity, for system callers with no current user.
  """
  @spec update_phone(Contact.t(), String.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def update_phone(%Contact{} = contact, phone) do
    contact
    |> Contact.changeset(%{phone: phone})
    |> persist_update()
  end

  @spec persist_update(Ecto.Changeset.t()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp persist_update(%{changes: changes} = changeset) do
    if ContactIdentities.whatsapp_changes?(changes) do
      Repo.transaction(fn ->
        case Repo.update(changeset) do
          {:ok, contact} ->
            update_whatsapp_identity(contact, changes)
            contact

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    else
      Repo.update(changeset)
    end
  end

  @spec update_whatsapp_identity(Contact.t(), map()) :: :ok
  defp update_whatsapp_identity(contact, changes) do
    if Map.has_key?(changes, :phone),
      do: ContactIdentities.move_whatsapp_identity_to_phone(contact)

    ContactIdentities.copy_state_to_whatsapp_identity(contact, changes)
  end

  # We do not want to block the simulator
  @spec simulator_block?(Contact.t(), map()) :: boolean
  defp simulator_block?(contact, attrs) do
    if simulator_contact?(contact.phone) &&
         attrs[:status] == :blocked,
       do: true,
       else: false
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
    cond do
      has_permission?(contact.id) == false ->
        raise("Permission denied")

      org_root_contact?(contact) == true ->
        {:error, "Sorry, this is your chatbot number and hence cannot be deleted."}

      simulator_contact?(contact.phone) == true ->
        {:error, "Sorry, this is simulator number and hence cannot be deleted."}

      true ->
        do_delete_contact(contact)
    end
  end

  @spec do_delete_contact(Contact.t()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp do_delete_contact(contact) do
    where = "WHERE organization_id = #{contact.organization_id} AND contact_id = #{contact.id}"

    # lets delete manually all the tables where most of the data is
    [
      "DELETE FROM messages #{where}",
      "DELETE FROM contact_histories #{where}",
      "DELETE FROM contacts_groups #{where}",
      "DELETE FROM flow_contexts #{where}"
    ]
    |> Enum.map(
      &Task.async(fn ->
        Repo.query!(&1, [], timeout: @delete_timeout, skip_organization_id: true)
      end)
    )
    |> Task.await_many(@delete_timeout + 1_000)

    Repo.delete(contact)
  end

  @doc """
  Checks if the contact passed in argument is organization root contact or not
  """
  @spec org_root_contact?(Contact.t()) :: boolean()
  def org_root_contact?(contact) do
    Partners.organization(contact.organization_id).contact_id == contact.id
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking contact changes.

  ## Examples

      iex> change_contact(contact)
      %Ecto.Changeset{data: %Contact{}}

  """
  @spec change_contact(Contact.t(), map()) :: Ecto.Changeset.t()
  def change_contact(%Contact{} = contact, attrs \\ %{}),
    do: Contact.changeset(contact, attrs)

  @doc """
  Gets or Creates a Contact based on the unique indexes in the table. If there is a match
  it returns the existing contact, else it creates a new one. The phone is the conflict target,
  so it is required: a nil phone would never conflict and would insert a contact without one.
  """
  @spec upsert(map()) :: {:ok, Contact.t()}
  def upsert(%{organization_id: organization_id} = attrs) do
    # we keep this separate to avoid overwriting the language if already set by a contact
    # this will not appear in the set field of the on_conflict: clause below
    other_attrs = %{
      organization_id: organization_id,
      language_id: attrs[:language_id] || Partners.organization_language_id(organization_id)
    }

    insert_opts = [
      returning: true,
      on_conflict: [set: Enum.map(attrs, fn {key, value} -> {key, value} end)],
      conflict_target: [:phone, :organization_id]
    ]

    case %Contact{}
         |> Contact.changeset(Map.merge(other_attrs, attrs))
         |> insert_with_identity(:whatsapp, attrs[:phone], insert_opts) do
      {:ok, contact} ->
        {:ok, contact}

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  # A username joins the contact owning the phone claim when that contact is on WhatsApp: it holds
  # the phone as its WhatsApp identity or has messaged. A phone only another web login stored is
  # neither, so it is not linked to, nor stored again.
  @spec resolve_phone_claim(String.t() | nil) ::
          {:link, Contact.t()} | {:create, String.t() | nil}
  defp resolve_phone_claim(nil), do: {:create, nil}

  defp resolve_phone_claim(phone) do
    with false <- simulator_contact?(phone),
         {:ok, contact, has_identity?} <- fetch_whatsapp_contact(phone) do
      if linkable_contact?(contact, has_identity?), do: {:link, contact}, else: {:create, nil}
    else
      true -> {:create, nil}
      {:error, :not_found} -> {:create, phone}
    end
  end

  @spec linkable_contact?(Contact.t(), boolean()) :: boolean()
  defp linkable_contact?(contact, has_identity?),
    do:
      (has_identity? or contact.last_message_at != nil) and
        contact.id != Partners.organization_contact_id(contact.organization_id)

  @spec link_or_create_web_contact(
          {:link, Contact.t()} | {:create, String.t() | nil},
          web_claims(),
          String.t()
        ) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp link_or_create_web_contact({:link, contact}, _claims, identifier),
    do: add_identity(contact, :web, identifier)

  defp link_or_create_web_contact({:create, phone}, claims, identifier),
    do: claims |> web_contact_attrs(identifier, phone) |> create_contact(:web, identifier)

  @spec web_contact_attrs(web_claims(), String.t(), String.t() | nil) :: map()
  defp web_contact_attrs(claims, identifier, phone) do
    %{
      organization_id: Repo.get_organization_id(),
      name: claims[:name] || identifier,
      phone: phone,
      status: :valid,
      bsp_status: :none,
      contact_type: nil
    }
  end

  # Two first connects can race on the same new username or the same phone. The loser of a username
  # race returns the winner's contact; the loser of a phone race looks again, now finding the phone.
  @spec retry_web_login_race(
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()},
          web_claims(),
          String.t()
        ) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp retry_web_login_race({:error, changeset} = error, claims, identifier) do
    cond do
      ContactIdentities.identifier_taken?(changeset) ->
        with {:error, :not_found} <- ContactIdentities.fetch_contact(:web, identifier), do: error

      phone_taken?(changeset) ->
        maybe_create_contact(claims, :web, identifier)

      true ->
        error
    end
  end

  defp retry_web_login_race(result, _claims, _identifier), do: result

  @spec phone_taken?(Ecto.Changeset.t()) :: boolean()
  defp phone_taken?(changeset),
    do:
      Enum.any?(changeset.errors, fn {field, {_message, opts}} ->
        field == :phone and opts[:constraint] == :unique
      end)

  @spec handle_phone_error(map(), Ecto.Changeset.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp handle_phone_error(sender, changeset) do
    map = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

    with ["has already been taken"] <- Map.get(map, :phone),
         {:ok, contact} <- fetch_by_identity(:whatsapp, sender.phone) do
      {:ok, contact}
    else
      _ -> {:error, changeset}
    end
  end

  @spec missing_phone_error(map()) :: {:error, Ecto.Changeset.t()}
  defp missing_phone_error(attrs) do
    %Contact{}
    |> Ecto.Changeset.change(Map.take(attrs, [:organization_id]))
    |> Ecto.Changeset.add_error(:phone, "can't be blank")
    |> Ecto.Changeset.apply_action(:insert)
  end

  @doc """
  Returns the contact for a WhatsApp sender or an NGO token's username, creating it if it does not exist.
  """
  @spec maybe_create_contact(map() | web_claims(), :whatsapp | :web, String.t() | nil) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def maybe_create_contact(attrs, channel \\ :whatsapp, identifier \\ nil)

  def maybe_create_contact(claims, :web, identifier) do
    identifier = String.downcase(identifier)

    with {:error, :not_found} <- ContactIdentities.fetch_contact(:web, identifier) do
      claims[:phone]
      |> resolve_phone_claim()
      |> link_or_create_web_contact(claims, identifier)
      |> retry_web_login_race(claims, identifier)
    end
  end

  def maybe_create_contact(sender, :whatsapp, _identifier) do
    case fetch_whatsapp_sender(Map.get(sender, :phone)) do
      {:error, :no_identifier} ->
        missing_phone_error(sender)

      {:error, :not_found} ->
        case create_contact(sender) do
          {:ok, contact} -> {:ok, contact}
          # there is a small chance that due to the opt-in and first message
          # arriving at the same time, we fire this twice, which results in an error
          # Issue #850
          {:error, changeset} -> handle_phone_error(sender, changeset)
        end

      {:ok, contact} ->
        # If either the sender name have changed or if we need to update contact_type, we need to update the contact
        case get_contact_update_attrs(contact, sender) do
          nil ->
            {:ok, contact}

          attrs ->
            update_contact(contact, attrs)
        end
    end
  end

  @doc """
  This function will be use just by ngo user where they can only update the contacts.
  """
  @spec maybe_update_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, any}
  def maybe_update_contact(sender) do
    case fetch_by_identity(:whatsapp, Map.get(sender, :phone)) do
      {:error, :no_identifier} ->
        {:error, "Phone number is missing"}

      {:error, :not_found} ->
        {:error, "Contact #{sender.phone} was not found and hence not added"}

      {:ok, contact} ->
        update_contact(contact, sender)
    end
  end

  @doc """
  Check if this contact id is a new contact.
  We set the last message number in the contact.
  So if this is a first message then we can assume that this is a new contact.
  """
  @spec new_contact?(integer()) :: boolean()
  def new_contact?(contact_id) do
    contact = get_contact!(contact_id)
    contact.last_message_number <= 1
  end

  @doc """
  Records a contact's opt-in on a channel, finding or creating the contact by identity, or given the contact.
  """
  @spec contact_opted_in(:whatsapp | :web, String.t() | Contact.t() | nil, map(), Keyword.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t() | :no_identifier}
  def contact_opted_in(channel, identifier, attrs, opts \\ [])
      when channel in [:whatsapp, :web] do
    opts = optin_opts(channel, opts)

    with {:ok, contact} <- find_or_create_contact(channel, identifier, attrs),
         {:ok, contact, recorded?} <- write_optin(channel, contact, identifier, attrs, opts) do
      if recorded?, do: capture_optin_history(channel, contact, opts)
      {:ok, contact}
    end
  end

  @spec optin_opts(:whatsapp | :web, Keyword.t()) :: Keyword.t()
  defp optin_opts(channel, opts) do
    utc_time = Keyword.get_lazy(opts, :utc_time, &DateTime.utc_now/0)

    opts
    |> Keyword.put_new(:method, if(channel == :whatsapp, do: "BSP", else: "API"))
    |> Keyword.put(:utc_time, DateTime.truncate(utc_time, :second))
  end

  @spec find_or_create_contact(:whatsapp | :web, String.t() | Contact.t() | nil, map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t() | :no_identifier}
  defp find_or_create_contact(_channel, %Contact{} = contact, _attrs), do: {:ok, contact}

  defp find_or_create_contact(:web, username, _attrs) when username in [nil, ""],
    do: {:error, :no_identifier}

  defp find_or_create_contact(:web, username, attrs),
    do: attrs |> Map.take([:name]) |> maybe_create_contact(:web, username)

  defp find_or_create_contact(:whatsapp, phone, attrs),
    do: attrs |> Map.put(:phone, phone) |> maybe_create_contact(:whatsapp)

  # A blocked contact records nothing. WhatsApp keeps master's rule: a BSP re-send for an opted-in
  # contact only refreshes its session status; any other opt-in records again, which is how an NGO
  # repairs a contact. Web keeps the first opt-in, checked inside its UPDATE.
  @spec write_optin(:whatsapp | :web, Contact.t(), String.t() | Contact.t(), map(), Keyword.t()) ::
          {:ok, Contact.t(), boolean()} | {:error, Ecto.Changeset.t()}
  defp write_optin(_channel, %Contact{status: :blocked} = contact, _identifier, _attrs, _opts),
    do: {:ok, contact, false}

  defp write_optin(:whatsapp, contact, phone, attrs, opts) do
    if contact.optin_status and opts[:method] == "BSP" do
      with {:ok, contact} <- set_session_status(contact, :hsm), do: {:ok, contact, false}
    else
      record_whatsapp_optin(contact, phone, attrs, opts)
    end
  end

  defp write_optin(:web, contact, username, _attrs, opts) do
    username = if is_struct(username, Contact), do: nil, else: username

    recorded =
      ContactIdentities.record_optin(contact.id, :web, username, opts[:utc_time], opts[:method])

    {:ok, contact, recorded == :recorded}
  end

  @spec record_whatsapp_optin(Contact.t(), String.t(), map(), Keyword.t()) ::
          {:ok, Contact.t(), true} | {:error, Ecto.Changeset.t()}
  defp record_whatsapp_optin(contact, phone, attrs, opts) do
    optin_attrs =
      Map.merge(attrs, %{
        phone: phone,
        optin_time: opts[:utc_time],
        optin_status: true,
        optin_method: opts[:method],
        optin_message_id: opts[:message_id],
        optout_time: nil,
        status: :valid,
        bsp_status: hsm_bsp_status(contact),
        updated_at: DateTime.utc_now()
      })

    with {:ok, contact} <- update_contact(contact, optin_attrs), do: {:ok, contact, true}
  end

  @spec capture_optin_history(:whatsapp | :web, Contact.t(), Keyword.t()) ::
          {:ok, ContactHistory.t()} | {:error, Ecto.Changeset.t()}
  defp capture_optin_history(channel, contact, opts) do
    meta = %{channel: Atom.to_string(channel), method: opts[:method], utc_time: opts[:utc_time]}

    capture_history(contact, :contact_opted_in, %{
      channel: channel,
      event_label: optin_history_label(channel, opts[:method]),
      event_meta:
        if(opts[:message_id], do: Map.put(meta, :optin_message_id, opts[:message_id]), else: meta)
    })
  end

  # The WhatsApp label stays as it was recorded before web opt-in existed, so old and new events read alike.
  @spec optin_history_label(:whatsapp | :web, String.t()) :: String.t()
  defp optin_history_label(:whatsapp, method), do: "contact opted in, via #{method}"
  defp optin_history_label(:web, method), do: "contact opted in on web, via #{method}"

  @spec opted_out_attrs(String.t(), non_neg_integer, DateTime.t(), String.t()) :: map()
  defp opted_out_attrs(phone, organization_id, utc_time, method),
    do: %{
      phone: phone,
      optout_time: utc_time,
      optout_method: method,
      optin_time: nil,
      optin_status: false,
      optin_method: nil,
      optin_message_id: nil,
      status: :invalid,
      bsp_status: :none,
      organization_id: organization_id,
      updated_at: DateTime.utc_now()
    }

  @doc """
  Update DB fields when contact opted out
  """
  @spec contact_opted_out(:whatsapp, String.t() | nil, non_neg_integer, DateTime.t(), String.t()) ::
          :ok | :error
  def contact_opted_out(:whatsapp, phone, organization_id, utc_time, method \\ "Glific Flows") do
    if simulator_contact?(phone) do
      :ok
    else
      case fetch_by_identity(:whatsapp, phone) do
        {:error, :no_identifier} ->
          Logger.error("Cannot opt out a contact without a phone number")
          :error

        {:error, :not_found} ->
          Logger.error("Contact does not exist with phone: #{phone}")
          :error

        {:ok, contact} ->
          capture_history(contact.id, :contact_opted_out, %{
            event_label: "contact opted out, via #{method}",
            event_meta: %{
              method: method,
              utc_time: utc_time
            }
          })

          update_contact(
            contact,
            opted_out_attrs(phone, organization_id, utc_time, method)
          )

          :ok
      end
    end
  end

  @doc """
  Opt out a contact if the provider returns an error code about Number not
  existing or not on whatsapp
  """
  @spec number_does_not_exist(non_neg_integer(), String.t()) :: any()
  def number_does_not_exist(contact_id, method \\ "Number does not exist") do
    contact = get_contact!(contact_id)

    with {:ok, phone} <- whatsapp_phone(contact) do
      update_contact(
        contact,
        opted_out_attrs(phone, contact.organization_id, DateTime.utc_now(), method)
      )
    end
  end

  @doc """
  Check if we can send a message to the contact
  """
  @spec can_send_message_to?(Contact.t()) :: {:ok | :error, String.t() | nil}
  def can_send_message_to?(contact), do: can_send_message_to?(contact, false)

  @doc false
  @spec can_send_message_to?(Contact.t(), boolean()) :: {:ok | :error, String.t() | nil}
  def can_send_message_to?(contact, true = _is_hsm) do
    cond do
      whatsapp_phone(contact) == {:error, :no_phone} ->
        {:error, dgettext("errors", "Contact has no WhatsApp number.")}

      contact.status != :valid ->
        {:error, dgettext("errors", "Contact status is not valid.")}

      contact.bsp_status not in [:session_and_hsm, :hsm, :session] ->
        {:error, dgettext("errors", "Cannot send hsm message to contact, invalid BSP status.")}

      contact.optin_time == nil ->
        {:error, dgettext("errors", "Cannot send hsm message to contact, not opted in.")}

      true ->
        # ensure that the organization is not in suspended state
        organization = Partners.organization(contact.organization_id)

        if organization.is_suspended,
          do:
            {:error,
             dgettext(
               "errors",
               "Cannot send hsm message to contact, organization is in suspended state"
             )},
          else: {:ok, nil}
    end
  end

  @doc """
  Check if we can send a session message to the contact
  """
  def can_send_message_to?(contact, false = _is_hsm) do
    cond do
      whatsapp_phone(contact) == {:error, :no_phone} ->
        {:error, dgettext("errors", "Contact has no WhatsApp number.")}

      contact.status != :valid ->
        {:error, dgettext("errors", "Contact status is not valid.")}

      contact.bsp_status not in [:session_and_hsm, :session] ->
        {:error,
         dgettext(
           "errors",
           "Sorry! 24 hrs window closed. Your message cannot be sent at this time."
         )}

      true ->
        {:ok, nil}
    end
  end

  @doc """
  Check if we can send a session message to the contact with some extra parameters
  Specifically designed for when we are trying to optin an opted out contact
  """
  @spec can_send_message_to?(Contact.t(), boolean(), map()) :: {:ok | :error, String.t() | nil}
  # The web channel has no BSP, so it has no 24 hour session window and no `bsp_status`: a
  # contact that has only ever existed in a browser sits at `:none`, which both clauses above
  # refuse. On the web the checks are the contact's own: not blocked, and opted in on the web channel.
  def can_send_message_to?(contact, _is_hsm, %{channel: channel} = _attrs)
      when channel in [:web, "web"] do
    cond do
      contact.status == :blocked ->
        {:error, dgettext("errors", "Contact is blocked.")}

      not ContactIdentities.opted_in?(contact, :web) ->
        {:error, dgettext("errors", "Contact has not opted in on the web channel.")}

      true ->
        {:ok, nil}
    end
  end

  def can_send_message_to?(contact, is_hsm, %{is_optin_flow: true} = _attrs) do
    cond do
      whatsapp_phone(contact) == {:error, :no_phone} ->
        {:error, dgettext("errors", "Contact has no WhatsApp number.")}

      is_hsm ->
        optin_flow_hsm_check(contact)

      true ->
        optin_flow_session_check(contact)
    end
  end

  # The web channel OTP is transactional — the person asked for it by typing their own number into
  # a login form — so it is exempt from the marketing opt-in that #5713 stopped a web login from
  # creating. Without this exemption a first-time visitor could never be sent a code at all:
  # `optin_time` is nil and `bsp_status` is `:none` on a contact that has only ever existed on the
  # web, which fails both clauses above.
  def can_send_message_to?(contact, _is_hsm, %{is_web_channel_otp: true} = _attrs) do
    cond do
      whatsapp_phone(contact) == {:error, :no_phone} ->
        {:error, dgettext("errors", "Contact has no WhatsApp number.")}

      contact.status == :blocked ->
        {:error, dgettext("errors", "Contact is blocked.")}

      true ->
        {:ok, nil}
    end
  end

  def can_send_message_to?(contact, is_hsm, _), do: can_send_message_to?(contact, is_hsm)

  @spec optin_flow_hsm_check(Contact.t()) :: {:ok | :error, String.t() | nil}
  defp optin_flow_hsm_check(contact) do
    if contact.bsp_status in [:session_and_hsm, :hsm, :session],
      do: {:ok, nil},
      else:
        {:error, dgettext("errors", "Cannot send hsm message to contact, invalid BSP status.")}
  end

  @spec optin_flow_session_check(Contact.t()) :: {:ok | :error, String.t() | nil}
  defp optin_flow_session_check(contact) do
    if contact.bsp_status in [:session_and_hsm, :session] &&
         Glific.in_past_time(contact.last_message_at, :hours, 24),
       do: {:ok, nil},
       else:
         {:error,
          "Cannot send session message to contact, invalid BSP status or not messaged in 24 hour window."}
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
    t = Glific.go_back_time(24 * 60 - 1, DateTime.utc_now(), :minute)

    Contact
    |> where([c], c.organization_id == ^organization_id)
    |> where([c], c.last_message_at <= ^t)
    |> where([c], c.bsp_status in [:session, :session_and_hsm])
    |> select([c], c.id)
    |> Repo.all()
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

  def set_session_status(%Contact{} = contact, :hsm = _status),
    do: update_contact(contact, %{bsp_status: hsm_bsp_status(contact)})

  def set_session_status(contact_ids, :none = _status) when is_list(contact_ids) do
    now = DateTime.utc_now()

    Contact
    |> where([c], is_nil(c.optin_time))
    |> where([c], c.id in ^contact_ids)
    |> Repo.update_all([set: [bsp_status: :none, updated_at: now]], skip_organization_id: true)

    Contact
    |> where([c], not is_nil(c.optin_time))
    |> where([c], c.id in ^contact_ids)
    |> Repo.update_all([set: [bsp_status: :hsm, updated_at: now]], skip_organization_id: true)

    ContactIdentities.set_bsp_status(contact_ids, false, :none, now)
    ContactIdentities.set_bsp_status(contact_ids, true, :hsm, now)

    :ok
  end

  def set_session_status(contact, :session = _status) do
    if is_nil(contact.optin_time),
      do: update_contact(contact, %{bsp_status: :session}),
      else: update_contact(contact, %{bsp_status: :session_and_hsm})
  end

  def set_session_status(_, _), do: :ok

  # An opted-in contact can get templates; a message in the last 24 hours also opens the session.
  @spec hsm_bsp_status(Contact.t()) :: :hsm | :session_and_hsm
  defp hsm_bsp_status(%Contact{last_message_at: last_message_at}) do
    if !is_nil(last_message_at) && Timex.compare(last_message_at, Glific.go_back_time(24)) > 0,
      do: :session_and_hsm,
      else: :hsm
  end

  @doc """
  check if contact is blocked or not
  """
  @spec contact_blocked?(Contact.t()) :: boolean()
  def contact_blocked?(contact) do
    cond do
      contact.status == :blocked -> true
      simulator_contact?(contact.phone) -> false
      whatsapp_phone(contact) == {:error, :no_phone} -> false
      Clients.blocked?(contact.phone, contact.organization_id) -> true
      true -> false
    end
  end

  @doc """
  Upload a contact phone as opted in
  """
  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def optin_contact(%{organization_id: _organization_id, phone: phone})
      when phone in [nil, ""],
      do: {:error, dgettext("errors", "Contact has no WhatsApp number.")}

  def optin_contact(%{organization_id: organization_id} = attrs) do
    bsp_module = Provider.bsp_module(organization_id, :contact)
    bsp_module.optin_contact(attrs)
  end

  @doc """
  Convert contact field to map for variable substitution
  """
  @spec get_contact_field_map(integer) :: map()
  def get_contact_field_map(contact_id) do
    contact =
      contact_id
      |> Contacts.get_contact!()
      |> Repo.preload([:language, :groups, :active_profile])
      |> Map.from_struct()

    # we are splitting this up since we need to use contact within the various function
    # calls and a lot cleaner this way
    contact
    |> get_contact_fields(contact)
    |> get_contact_profile_name(contact)
    |> get_contact_fields_language(contact)
    |> get_contact_field_groups()
    |> get_contact_field_list_profiles(contact)
    |> get_contact_field_name(contact)
  end

  @spec get_contact_fields(map(), Contact.t()) :: map()
  defp get_contact_fields(field_map, contact) do
    with false <- is_nil(contact.active_profile_id),
         profile <- contact.active_profile do
      Map.put(field_map, :fields, profile.fields)
    else
      _ -> field_map
    end
  end

  @spec get_contact_fields_language(map(), Contact.t()) :: map()
  defp get_contact_fields_language(field_map, contact) do
    with false <- is_nil(contact.active_profile_id),
         profile <- contact.active_profile |> Repo.preload([:language]) do
      put_in(
        field_map,
        [:fields, :language],
        %{label: profile.language.label}
      )
    else
      _ ->
        put_in(
          field_map,
          [:fields, :language],
          %{label: contact.language.label}
        )
    end
  end

  @spec get_contact_profile_name(map(), Contact.t()) :: map()
  defp get_contact_profile_name(field_map, contact) do
    if contact.active_profile_id != nil do
      Map.put(field_map, :active_profile_name, contact.active_profile.name)
    else
      field_map
    end
  end

  @spec get_contact_field_groups(map()) :: map()
  defp get_contact_field_groups(field_map) do
    Map.put(
      field_map,
      :in_groups,
      Enum.reduce(
        field_map.groups,
        [],
        fn g, list -> [g.id | list] end
      )
    )
  end

  @spec get_contact_field_list_profiles(map(), Contact.t()) :: map()
  defp get_contact_field_list_profiles(field_map, contact) do
    if is_nil(contact.active_profile_id) do
      field_map
    else
      indexed_profiles = Profiles.get_indexed_profile(contact)

      profile_map =
        Enum.reduce(indexed_profiles, %{}, fn {profile, index}, acc ->
          Map.put(acc, "profile_#{index}", %{id: profile.id, name: profile.name, index: index})
        end)
        |> Map.put(:count, length(indexed_profiles))

      Map.put(
        field_map,
        :list_profiles,
        indexed_profiles
        |> Enum.reduce("", fn {profile, index}, acc ->
          acc <> " #{index}. #{profile.name} \n"
        end)
      )
      |> Map.put(:profiles, profile_map)
      |> Map.put(:has_multiple_profile, %{
        "type" => "string",
        "label" => "has_multiple_profile",
        "inserted_at" => DateTime.utc_now(),
        "value" => true
      })
    end
  end

  ## We change the name of the contact whenever we receive a message from the contact.
  ## so the contact name will always be the name contact added in the WhatsApp app.
  ## This is just so that organizations can use the custom name or the name they collected from
  ## the various surveys in glific flows.
  @spec get_contact_field_name(map(), Contact.t()) :: map()
  defp get_contact_field_name(field_map, contact) do
    with false <- is_nil(contact.active_profile_id),
         profile <- contact.active_profile do
      put_in(
        field_map,
        [:fields, "name"],
        profile.fields["name"] || default_name(contact)
      )
    else
      _ ->
        put_in(
          field_map,
          [:fields, "name"],
          contact.fields["name"] || default_name(contact)
        )
    end
  end

  @spec default_name(Contact.t()) :: map()
  defp default_name(contact) do
    %{
      "type" => "string",
      "label" => "Name",
      "inserted_at" => DateTime.utc_now(),
      "value" => contact.name
    }
  end

  @simulator_phone_prefix "9876543210"

  @doc false
  @spec simulator_phone_prefix :: String.t()
  def simulator_phone_prefix, do: @simulator_phone_prefix

  @doc """
  Lets centralize the code to detect simulator messages and interaction
  """
  @spec simulator_contact?(String.t() | nil) :: boolean
  def simulator_contact?(nil), do: false
  def simulator_contact?(phone), do: String.starts_with?(phone, @simulator_phone_prefix)

  @doc """
  The ids of an organization's contacts with a web identity, for use in `subquery/1`.
  """
  @spec web_identity_contact_ids_query(non_neg_integer()) :: Ecto.Query.t()
  def web_identity_contact_ids_query(organization_id),
    do: ContactIdentities.web_contact_ids_query(organization_id)

  @doc """
  Looks a contact up by its identity on a channel (web identities are case-insensitive).
  """
  @spec fetch_by_identity(:whatsapp | :web, String.t() | nil) ::
          {:ok, Contact.t()} | {:error, :no_identifier | :not_found}
  def fetch_by_identity(_channel, identifier) when identifier in [nil, ""],
    do: {:error, :no_identifier}

  def fetch_by_identity(:web, identifier) when is_binary(identifier),
    do: ContactIdentities.fetch_contact(:web, identifier)

  def fetch_by_identity(:whatsapp, phone) when is_binary(phone), do: fetch_by_phone(phone)

  @spec fetch_by_phone(String.t()) :: {:ok, Contact.t()} | {:error, :not_found}
  defp fetch_by_phone(phone) do
    case Repo.get_by(Contact, %{phone: phone}) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  @spec fetch_whatsapp_contact(String.t()) :: {:ok, Contact.t(), boolean()} | {:error, :not_found}
  defp fetch_whatsapp_contact(phone) do
    query =
      from(c in Contact,
        left_join: i in ContactIdentity,
        on: i.contact_id == c.id and i.channel == :whatsapp and i.identifier == c.phone,
        where: c.phone == ^phone,
        select: {c, not is_nil(i.id)}
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      {contact, has_identity?} -> {:ok, contact, has_identity?}
    end
  end

  # A web login can store a phone without a WhatsApp identity, since WhatsApp has not confirmed it. The
  # first inbound WhatsApp message from that number confirms it, so the identity is created here.
  @spec fetch_whatsapp_sender(String.t() | nil) ::
          {:ok, Contact.t()} | {:error, :not_found | :no_identifier}
  defp fetch_whatsapp_sender(phone) when phone in [nil, ""], do: {:error, :no_identifier}

  defp fetch_whatsapp_sender(phone) do
    case fetch_whatsapp_contact(phone) do
      {:ok, contact, true} ->
        {:ok, contact}

      {:ok, contact, false} ->
        ContactIdentities.move_whatsapp_identity_to_phone(contact)
        {:ok, contact}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  A stable key for naming files after a contact: its phone, or `contact-<id>` when it has none.
  """
  @spec file_key(Contact.t()) :: String.t()
  def file_key(%Contact{phone: phone}) when is_binary(phone) and phone != "", do: phone
  def file_key(%Contact{id: id}), do: "contact-#{id}"

  @doc """
  The only way to get the number a contact is reached on over WhatsApp.
  """
  @spec whatsapp_phone(Contact.t()) :: {:ok, String.t()} | {:error, :no_phone}
  def whatsapp_phone(%Contact{phone: phone}) when is_binary(phone) and phone != "",
    do: {:ok, phone}

  def whatsapp_phone(%Contact{phone: phone}) when phone in [nil, ""], do: {:error, :no_phone}

  @doc """
  create new contact history record.
  """
  @spec capture_history(Contact.t() | non_neg_integer(), atom(), map()) ::
          {:ok, ContactHistory.t()} | {:error, Ecto.Changeset.t()}
  def capture_history(contact_id, event_type, attrs) when is_integer(contact_id),
    do:
      contact_id
      |> get_contact!()
      |> capture_history(event_type, attrs)

  def capture_history(%Contact{} = contact, event_type, attrs) do
    ## I will add the telemetry events here.
    attrs =
      Map.merge(
        %{
          event_type: event_type |> Atom.to_string(),
          contact_id: contact.id,
          event_datetime: DateTime.utc_now(),
          organization_id: contact.organization_id,
          event_meta: %{}
        },
        attrs
      )

    %ContactHistory{}
    |> ContactHistory.changeset(attrs)
    |> Repo.insert()
  end

  def capture_history(_, _event_type, _attrs),
    do: {:error, dgettext("errors", "Invalid event type")}

  @doc """
  Get contact history
  """
  @spec list_contact_history(map()) :: [ContactHistory.t()]
  def list_contact_history(args) do
    args
    |> Repo.list_filter_query(
      ContactHistory,
      &Repo.opts_with_id/2,
      &filter_history_with/2
    )
    |> Repo.all()
  end

  @doc """
  count contact history
  """
  @spec count_contact_history(map) :: integer
  def count_contact_history(args),
    do: Repo.count_filter(args, ContactHistory, &filter_history_with/2)

  @spec filter_history_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_history_with(query, filter) do
    query = Repo.filter_with(query, filter)
    # these filters are specific to webhook logs only.
    # We might want to move them in the repo in the future.
    Enum.reduce(filter, query, fn
      {:contact_id, contact_id}, query ->
        from(q in query, where: q.contact_id == ^contact_id)

      {:profile_id, profile_id}, query ->
        from(q in query, where: q.profile_id == ^profile_id)

      {:event_type, event_type}, query ->
        from(q in query, where: ilike(q.event_type, ^"%#{event_type}%"))

      {:event_label, event_label}, query ->
        from(q in query, where: ilike(q.event_label, ^"%#{event_label}%"))

      {:channel, channel}, query ->
        from(q in query, where: q.channel == ^channel)

      _, query ->
        query
    end)
  end

  @spec get_contact_update_attrs(Contact.t(), map()) :: map() | nil
  defp get_contact_update_attrs(
         %Contact{contact_type: "WABA"} = _contact,
         %{contact_type: "WA"} = sender
       ) do
    case Map.get(sender, :name) do
      nil -> %{contact_type: "WABA+WA"}
      sender_name -> %{name: sender_name, contact_type: "WABA+WA"}
    end
  end

  defp get_contact_update_attrs(
         %Contact{contact_type: "WA"} = _contact,
         %{contact_type: "WABA"} = sender
       ) do
    case Map.get(sender, :name) do
      nil -> %{contact_type: "WABA+WA"}
      sender_name -> %{name: sender_name, contact_type: "WABA+WA"}
    end
  end

  defp get_contact_update_attrs(%Contact{name: name} = _contact, %{name: sender_name} = _sender)
       when name != sender_name do
    %{name: sender_name}
  end

  defp get_contact_update_attrs(%Contact{}, _), do: nil

  @doc """
  preload language
  """
  @spec preload_contact_language(non_neg_integer()) :: any()
  def preload_contact_language(contact_id) do
    case Repo.fetch(Contact, contact_id) do
      {:ok, contact} -> contact |> Repo.preload(:language)
      {:error, error} -> error
    end
  end

  @doc """
  Ensures phone numbers are normalized to international E.164 format and validated using ExPhoneNumber to prevent invalid entries.
  """
  @spec parse_phone_number(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_phone_number(phone) do
    phone =
      phone
      |> sanitize_phone_number()
      |> String.trim()

    phone_with_plus =
      if String.starts_with?(phone, "+"), do: phone, else: "+#{phone}"

    with {:ok, phone_number} <- ExPhoneNumber.parse(phone_with_plus, ""),
         true <- ExPhoneNumber.is_valid_number?(phone_number) do
      {:ok, "#{phone_number.country_code}#{phone_number.national_number}"}
    else
      {:error, reason} ->
        {:error, "Phone number is not valid because #{reason}."}

      false ->
        {:error,
         "Phone number is not valid. Please enter the phone number with country code, without the + symbol."}
    end
  end

  @spec sanitize_phone_number(String.t()) :: String.t()
  defp sanitize_phone_number(phone) do
    String.replace(phone, ~r/[^\d+]/, "")
  end
end
