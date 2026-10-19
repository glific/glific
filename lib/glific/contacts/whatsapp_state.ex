defmodule Glific.Contacts.WhatsAppState do
  @moduledoc """
  Internal to `Glific.Contacts`, which is the only module that calls it. A contact's WhatsApp consent and
  session state (opt-in, opt-out, BSP status, the last inbound message) lives on its `(whatsapp, phone)`
  `Glific.Contacts.ContactIdentity` row.

  Until `Glific.Contacts.IdentityBackfill` has created every row, a contact may have none. This module is
  the only place that knows how to cope:

    * a read uses the identity row when there is one, otherwise the contact's own pre-identity columns
      (`Contact.legacy_*`), which nothing writes any more;
    * a write first creates the row seeded from those columns, then applies the change, so nothing is lost;
    * `value/2` and `with_identity/1` give SQL readers the same rule, row by row: a field is never taken from the
      contact once the identity row exists, even when the identity's value is null.

  When the backfill is complete, this fallback is deleted by reading the identity alone.
  """

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Enums.ContactProviderStatus,
    Repo
  }

  @fields [
    :optin_time,
    :optin_status,
    :optin_method,
    :optout_time,
    :optout_method,
    :bsp_status,
    :last_message_at
  ]

  @field_types %{
    optin_time: :utc_datetime,
    optin_status: :boolean,
    optin_method: :string,
    optout_time: :utc_datetime,
    optout_method: :string,
    bsp_status: ContactProviderStatus,
    last_message_at: :utc_datetime
  }

  @time_fields [:optin_time, :optout_time, :last_message_at]

  @typedoc "A contact's WhatsApp consent and session state."
  @type t :: %{
          optin_time: DateTime.t() | nil,
          optin_status: boolean(),
          optin_method: String.t() | nil,
          optout_time: DateTime.t() | nil,
          optout_method: String.t() | nil,
          bsp_status: ContactProviderStatus.t(),
          last_message_at: DateTime.t() | nil
        }

  defmacrop legacy_select(contact) do
    quote do
      %{
        optin_time: field(unquote(contact), :legacy_optin_time),
        optin_status: field(unquote(contact), :legacy_optin_status),
        optin_method: field(unquote(contact), :legacy_optin_method),
        optout_time: field(unquote(contact), :legacy_optout_time),
        optout_method: field(unquote(contact), :legacy_optout_method),
        bsp_status: field(unquote(contact), :legacy_bsp_status),
        last_message_at: field(unquote(contact), :legacy_last_message_at)
      }
    end
  end

  @doc """
  The state of a contact with no WhatsApp number or no history on it.
  """
  @spec default() :: t()
  def default,
    do: %{
      optin_time: nil,
      optin_status: false,
      optin_method: nil,
      optout_time: nil,
      optout_method: nil,
      bsp_status: :none,
      last_message_at: nil
    }

  @doc """
  Splits `attrs` into the state fields and everything else.
  """
  @spec split(map()) :: {map(), map()}
  def split(attrs), do: Map.split(attrs, @fields)

  @doc """
  Drops from a contact's map the fields that only store the WhatsApp state, so it can be replaced by `fetch/1`.
  """
  @spec without_storage_fields(map()) :: map()
  def without_storage_fields(contact_map),
    do: Map.drop(contact_map, [:whatsapp_identity | Enum.map(@fields, &:"legacy_#{&1}")])

  @doc """
  The state of one contact.
  """
  @spec fetch(non_neg_integer()) :: t()
  def fetch(contact_id), do: [contact_id] |> fetch_many() |> Map.get(contact_id, default())

  @doc """
  The state of each contact, keyed by contact id; a contact that does not exist is absent.
  """
  @spec fetch_many([non_neg_integer()]) :: %{non_neg_integer() => t()}
  def fetch_many([]), do: %{}

  def fetch_many(contact_ids) do
    from(c in Contact,
      left_join: i in ContactIdentity,
      on: i.contact_id == c.id and i.channel == :whatsapp and i.identifier == c.phone,
      where: c.id in ^contact_ids,
      select: %{id: c.id, identity: i, legacy: legacy_select(c)}
    )
    |> Repo.all(skip_organization_id: true)
    |> Map.new(&{&1.id, to_state(&1.identity, &1.legacy)})
  end

  @doc """
  The state of a contact loaded with its `:whatsapp_identity` preloaded, without a query.
  """
  @spec from_preload(Contact.t()) :: t()
  def from_preload(%Contact{whatsapp_identity: %ContactIdentity{} = identity}),
    do: to_state(identity, nil)

  def from_preload(%Contact{whatsapp_identity: nil} = contact) do
    to_state(nil, %{
      optin_time: contact.legacy_optin_time,
      optin_status: contact.legacy_optin_status,
      optin_method: contact.legacy_optin_method,
      optout_time: contact.legacy_optout_time,
      optout_method: contact.legacy_optout_method,
      bsp_status: contact.legacy_bsp_status,
      last_message_at: contact.legacy_last_message_at
    })
  end

  @doc """
  Applies `changes` to the contact's state, creating its WhatsApp identity from the contact's current values
  first when it has none, and marks the contact updated unless `touch: false`. The `contacts` row is always locked
  before the identity row. A contact with no phone has no WhatsApp state, so it returns `{:error, :no_phone}`.
  """
  @spec update(Contact.t(), map(), Keyword.t()) :: :ok | {:error, :no_phone}
  def update(contact, changes, opts \\ [])
  def update(_contact, changes, _opts) when map_size(changes) == 0, do: :ok

  def update(%Contact{phone: phone}, _changes, _opts) when phone in [nil, ""],
    do: {:error, :no_phone}

  def update(%Contact{id: contact_id}, changes, opts) do
    now = DateTime.utc_now()
    changes = normalize(changes)

    if Keyword.get(opts, :touch, true), do: touch_contacts([contact_id], now)

    if update_identities([contact_id], changes, now) == 0 do
      seed([contact_id])
      update_identities([contact_id], changes, now)
    end

    :ok
  end

  @doc """
  Applies each contact's `changes`, in as few statements as there are distinct changes, and marks the contacts
  updated unless `touch: false`. The contacts' identities must exist already: see `seed/1`.
  """
  @spec update_many([{non_neg_integer(), map()}], Keyword.t()) :: :ok
  def update_many(changes_by_contact, opts \\ []) do
    now = DateTime.utc_now()

    changes_by_contact
    |> Enum.reject(fn {_contact_id, changes} -> changes == %{} end)
    |> Enum.group_by(fn {_contact_id, changes} -> normalize(changes) end, &elem(&1, 0))
    |> Enum.each(fn {changes, contact_ids} ->
      if Keyword.get(opts, :touch, true), do: touch_contacts(contact_ids, now)
      update_identities(contact_ids, changes, now)
    end)
  end

  @doc """
  Creates the WhatsApp identity of each contact that has a phone and none yet, from its current values.
  """
  @spec seed([non_neg_integer()]) :: :ok
  def seed([]), do: :ok

  def seed(contact_ids) do
    now = DateTime.utc_now()

    rows =
      from(c in Contact,
        where: c.id in ^contact_ids and not is_nil(c.phone) and c.phone != "",
        select: %{
          contact_id: c.id,
          organization_id: c.organization_id,
          identifier: c.phone,
          legacy: legacy_select(c)
        }
      )
      |> Repo.all(skip_organization_id: true)
      |> Enum.map(fn %{legacy: legacy} = row ->
        row
        |> Map.delete(:legacy)
        |> Map.merge(to_state(nil, legacy))
        |> Map.merge(%{channel: :whatsapp, inserted_at: now, updated_at: now})
      end)

    Repo.insert_all(ContactIdentity, rows,
      on_conflict: :nothing,
      conflict_target: [:organization_id, :channel, :identifier],
      skip_organization_id: true
    )

    :ok
  end

  @doc """
  Adds the join of each contact's WhatsApp identity, named `:whatsapp_state`, to a query whose first binding
  is the contact, for use with `value/2`.
  """
  @spec with_identity(Ecto.Queryable.t()) :: Ecto.Query.t()
  def with_identity(query) do
    join(query, :left, [c], i in ContactIdentity,
      as: :whatsapp_state,
      on: i.contact_id == c.id and i.channel == :whatsapp and i.identifier == c.phone
    )
  end

  @doc """
  Like `with_identity/1`, for a query where the contact has the named binding `contact_binding`.
  """
  @spec with_identity(Ecto.Queryable.t(), atom()) :: Ecto.Query.t()
  def with_identity(query, contact_binding) do
    join(query, :left, [], i in ContactIdentity,
      as: :whatsapp_state,
      on:
        i.contact_id == field(as(^contact_binding), :id) and i.channel == :whatsapp and
          i.identifier == field(as(^contact_binding), :phone)
    )
  end

  @doc """
  The quoted SQL expression for one state field of the contact bound to `contact`, taken from the
  `:whatsapp_state` join when that row exists and from the contact otherwise.
  """
  @spec value(Macro.t(), atom()) :: Macro.t()
  def value(contact, field) when field in @fields do
    legacy = String.to_atom("legacy_#{field}")
    type = Map.fetch!(@field_types, field)

    quote do
      type(
        fragment(
          "CASE WHEN ? IS NULL THEN ? ELSE ? END",
          field(as(:whatsapp_state), :id),
          field(unquote(contact), unquote(legacy)),
          field(as(:whatsapp_state), unquote(field))
        ),
        unquote(type)
      )
    end
  end

  @spec to_state(ContactIdentity.t() | nil, map()) :: t()
  defp to_state(nil, legacy) do
    legacy
    |> Map.update!(:optin_status, &(&1 == true))
    |> Map.update!(:bsp_status, &(&1 || :none))
  end

  defp to_state(%ContactIdentity{} = identity, _legacy), do: Map.take(identity, @fields)

  @spec normalize(map()) :: map()
  defp normalize(changes) do
    Map.new(changes, fn
      {field, %DateTime{} = time} when field in @time_fields ->
        {field, DateTime.truncate(time, :second)}

      pair ->
        pair
    end)
  end

  @spec update_identities([non_neg_integer()], map(), DateTime.t()) :: non_neg_integer()
  defp update_identities(contact_ids, changes, now) do
    {updated, _rows} =
      from(i in ContactIdentity, where: i.contact_id in ^contact_ids and i.channel == :whatsapp)
      |> Repo.update_all([set: Map.to_list(changes) ++ [updated_at: now]],
        skip_organization_id: true
      )

    updated
  end

  @spec touch_contacts([non_neg_integer()], DateTime.t()) :: :ok
  defp touch_contacts(contact_ids, now) do
    from(c in Contact, where: c.id in ^contact_ids)
    |> Repo.update_all([set: [updated_at: now]], skip_organization_id: true)

    :ok
  end
end
