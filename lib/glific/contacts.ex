defmodule Glific.Contacts do
  @moduledoc """
  The Contacts context.
  """
  import Ecto.Query, warn: false
  import GlificWeb.Gettext

  use Tesla
  plug(Tesla.Middleware.FormUrlencoded)

  alias __MODULE__

  require Logger

  alias Glific.{
    Clients,
    Contacts.Contact,
    Contacts.ContactHistory,
    Contacts.Location,
    Groups.ContactGroup,
    Groups.UserGroup,
    Partners,
    Partners.Provider,
    Profiles,
    Repo,
    Tags.ContactTag,
    Users.User
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
        from(q in query, where: q.status == ^status)

      {:bsp_status, bsp_status}, query ->
        from(q in query, where: q.bsp_status == ^bsp_status)

      {:include_groups, []}, query ->
        query

      # We need distinct query expression with join,
      # in case if filter requires contacts added to multiple groups
      # Using subquery instead of join, so that distinct query expression can be avoided
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
    |> where([c], c.id == ^id)
    |> Repo.add_permission(&Contacts.add_permission/2)
    |> Repo.one!()
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
  def get_contact_by_phone!(phone) do
    Contact
    |> where([c], c.phone == ^phone)
    |> Repo.add_permission(&Contacts.add_permission/2)
    |> Repo.one!()
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
      if is_simulator_block?(contact, attrs) do
        # just treat it as if we blocked the simulator
        # but in reality, we don't block the simulator
        {:ok, contact}
      else
        contact
        |> Contact.changeset(attrs)
        |> Repo.update()
      end
    else
      raise "Permission denied"
    end
  end

  # We do not want to block the simulator
  @spec is_simulator_block?(Contact.t(), map()) :: boolean
  defp is_simulator_block?(contact, attrs) do
    if is_simulator_contact?(contact.phone) &&
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

      is_org_root_contact?(contact) == true ->
        {:error, "Sorry, this is your chatbot number and hence cannot be deleted."}

      true ->
        Repo.delete(contact)
    end
  end

  @doc """
  Checks if the contact passed in argument is organization root contact or not
  """
  @spec is_org_root_contact?(Contact.t()) :: boolean()
  def is_org_root_contact?(contact) do
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

  We use a fetch followed by create, to avoid the explosion in the id namespace. We also
  avoid updating the contact to skip the DB call, and only do so if the name has changed
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
  In general, we should always retrieve as little as possible from the DB
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
  @spec contact_opted_in(map(), non_neg_integer, DateTime.t(), Keyword.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def contact_opted_in(%{phone: phone} = contact_attrs, organization_id, utc_time, opts \\ []) do
    attrs = %{
      phone: phone,
      optin_time: utc_time,
      optin_status: true,
      optin_method: Keyword.get(opts, :method, "BSP"),
      optin_message_id: Keyword.get(opts, :message_id),
      optout_time: nil,
      status: :valid,
      organization_id: organization_id,
      updated_at: DateTime.utc_now()
    }

    attrs = Map.merge(contact_attrs, attrs)

    Repo.get_by(Contact, %{phone: phone})
    |> case do
      nil ->
        create_contact(attrs)

      contact ->
        # we ignore the optin from the BSP if we are already opted in
        if ignore_optin?(contact, opts),
          do: {:ok, contact},
          else: update_contact(contact, attrs)
    end
    |> case do
      {:ok, contact} ->
        {:ok, contact} = set_session_status(contact, :hsm)

        capture_history(contact.id, :contact_opted_in, %{
          event_label: "contact opted in, via #{attrs.optin_method}",
          event_meta: %{
            method: attrs[:optin_method],
            utc_time: utc_time,
            optin_message_id: attrs[:optin_message_id]
          }
        })

        {:ok, contact}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec ignore_optin?(Contact.t(), Keyword.t()) :: boolean()
  defp ignore_optin?(contact, opts) do
    cond do
      # if we are already opted in and we get the optin request from
      # BSP, we ignore it
      contact.optin_status and opts[:method] == "BSP" -> true
      contact.status == :blocked -> true
      true -> false
    end
  end

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
  @spec contact_opted_out(String.t(), non_neg_integer, DateTime.t(), String.t()) :: :ok | :error
  def contact_opted_out(phone, organization_id, utc_time, method \\ "Glific Flows") do
    if is_simulator_contact?(phone) do
      :ok
    else
      case Repo.get_by(Contact, %{phone: phone}) do
        nil ->
          Logger.error("Contact does not exist with phone: #{phone}")
          :error

        contact ->
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

    update_contact(
      contact,
      opted_out_attrs(
        contact.phone,
        contact.organization_id,
        DateTime.utc_now(),
        method
      )
    )
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
      contact.status != :valid ->
        {:error, dgettext("errors", "Contact status is not valid.")}

      contact.bsp_status not in [:session_and_hsm, :hsm] ->
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
  def can_send_message_to?(contact, is_hsm, %{is_optin_flow: true} = _attrs) do
    if is_hsm do
      if contact.bsp_status in [:session_and_hsm, :hsm],
        do: {:ok, nil},
        else:
          {:error, dgettext("errors", "Cannot send hsm message to contact, invalid BSP status.")}
    else
      if contact.bsp_status in [:session_and_hsm, :session] &&
           Glific.in_past_time(contact.last_message_at, :hours, 24),
         do: {:ok, nil},
         else:
           {:error,
            "Cannot send session message to contact, invalid BSP status or not messaged in 24 hour window."}
    end
  end

  def can_send_message_to?(contact, is_hsm, _), do: can_send_message_to?(contact, is_hsm)

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

  def set_session_status(%Contact{} = contact, :hsm = _status) do
    last_message_at = contact.last_message_at
    t = Glific.go_back_time(24)

    if !is_nil(last_message_at) && Timex.compare(last_message_at, t) > 0,
      do: update_contact(contact, %{bsp_status: :session_and_hsm}),
      else: update_contact(contact, %{bsp_status: :hsm})
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

  def set_session_status(_, _), do: :ok

  @doc """
  check if contact is blocked or not
  """
  @spec is_contact_blocked?(Contact.t()) :: boolean()
  def is_contact_blocked?(contact) do
    cond do
      contact.status == :blocked -> true
      is_simulator_contact?(contact.phone) -> false
      Clients.blocked?(contact.phone, contact.organization_id) -> true
      true -> false
    end
  end

  @doc """
  Upload a contact phone as opted in
  """
  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
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

  @spec get_contact_field_groups(map()) :: map()
  defp get_contact_field_groups(field_map) do
    Map.put(
      field_map,
      :in_groups,
      Enum.reduce(
        field_map.groups,
        [],
        fn g, list -> [g.label | list] end
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
  @spec is_simulator_contact?(String.t()) :: boolean
  def is_simulator_contact?(phone), do: String.starts_with?(phone, @simulator_phone_prefix)

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

      _, query ->
        query
    end)
  end
end
