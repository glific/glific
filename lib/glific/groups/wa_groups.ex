defmodule Glific.Groups.WAGroups do
  @moduledoc """
  Whatsapp groups context.
  """
  import Ecto.Query, warn: false

  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Contacts,
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Groups.WAGroupsCollection,
    Providers.Maytapi.ApiClient,
    Repo,
    WAGroup.WAManagedPhone,
    WAManagedPhones
  }

  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:include_groups, []}, query ->
        query

      {:include_groups, group_ids}, query ->
        sub_query =
          WAGroupsCollection
          |> where([wc], wc.group_id in ^group_ids)
          |> select([wa], wa.wa_group_id)

        query
        |> where([wg], wg.id in subquery(sub_query))

      {:exclude_groups, []}, query ->
        query

      {:exclude_groups, group_ids}, query ->
        sub_query =
          WAGroupsCollection
          |> where([wc], wc.group_id in ^group_ids)
          |> select([wc], wc.wa_group_id)

        query
        |> where([c], c.id not in subquery(sub_query))

      {:term, term}, query ->
        query |> where([wa_grp], ilike(wa_grp.label, ^"%#{term}%"))

      _, query ->
        query
    end)
  end

  @doc """
  get all the wa groups associated with the group
  """
  @spec wa_groups(map()) :: [WAGroup.t()]
  def wa_groups(args) do
    args
    |> Repo.list_filter_query(WAGroup, &Repo.opts_with_label/2, &filter_with/2)
    |> Repo.all()
  end

  @spec phone_number(String.t()) :: non_neg_integer()
  defp phone_number(phone_number), do: String.split(phone_number, "@") |> List.first()

  @doc """
  Fetches group using maytapi API and sync it in Glific
  """
  @spec fetch_wa_groups(non_neg_integer()) :: :ok
  def fetch_wa_groups(org_id) do
    wa_managed_phones =
      WAManagedPhones.list_wa_managed_phones(%{organization_id: org_id})

    Enum.each(wa_managed_phones, fn wa_managed_phone ->
      do_fetch_wa_groups(org_id, wa_managed_phone)
    end)
  end

  @spec do_fetch_wa_groups(non_neg_integer(), map()) :: list() | {:error, any()}
  defp do_fetch_wa_groups(org_id, wa_managed_phone) do
    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           ApiClient.list_wa_groups(org_id, wa_managed_phone.phone_id),
         {:ok, decoded} <- Jason.decode(body) do
      group_details =
        decoded
        |> get_group_details(wa_managed_phone)

      create_whatsapp_groups(group_details, org_id)
      sync_wa_groups_with_contacts(group_details, org_id)
      sync_wa_group_phones(group_details, wa_managed_phone)
    else
      {:ok, %Tesla.Env{body: body}} ->
        {:error, body}

      {:error, message} ->
        {:error, inspect(message)}
    end
  end

  @spec get_group_details(map(), WAManagedPhone.t()) :: [map()]
  defp get_group_details(%{"data" => groups}, wa_managed_phone) when is_list(groups) do
    Enum.reduce(groups, [], fn group, acc ->
      if group["name"] != nil and group["name"] != "" do
        [
          %{
            name: group["name"],
            bsp_id: group["id"],
            wa_managed_phone_id: wa_managed_phone.id,
            participants: group["participants"] || [],
            admins: group["admins"]
          }
          | acc
        ]
      else
        acc
      end
    end)
  end

  @doc """
  Syncs the contacts in each WA group by diffing Maytapi's participant list
  against the current `contacts_wa_groups` rows: new participants are added,
  departed participants are hard-deleted, and unchanged participants are left
  untouched (no `updated_at` bump, so no downstream resync churn).
  """
  @spec sync_wa_groups_with_contacts(list(), non_neg_integer()) :: :ok
  def sync_wa_groups_with_contacts(group_details, org_id) do
    Enum.each(group_details, fn group ->
      {:ok, wa_group} =
        Repo.fetch_by(WAGroup, %{
          bsp_id: group.bsp_id,
          wa_managed_phone_id: group.wa_managed_phone_id,
          organization_id: org_id
        })

      diff_contacts(group, wa_group.id, org_id)
    end)
  end

  @spec diff_contacts(map(), non_neg_integer(), non_neg_integer()) :: :ok
  defp diff_contacts(group, wa_group_id, org_id) do
    desired = resolve_desired_members(group, org_id)
    desired_ids = MapSet.new(Map.keys(desired))

    existing_ids =
      ContactWAGroups.list_contact_wa_group(%{wa_group_id: wa_group_id})
      |> Enum.map(& &1.contact_id)
      |> MapSet.new()

    to_add = MapSet.difference(desired_ids, existing_ids)
    to_remove = MapSet.difference(existing_ids, desired_ids)

    Enum.each(to_add, fn contact_id ->
      ContactWAGroups.create_contact_wa_group(%{
        contact_id: contact_id,
        wa_group_id: wa_group_id,
        organization_id: org_id,
        is_admin: Map.get(desired, contact_id, false)
      })
    end)

    if MapSet.size(to_remove) > 0 do
      ContactWAGroups.delete_wa_group_contacts_by_ids(wa_group_id, MapSet.to_list(to_remove))
    end

    :ok
  end

  # Resolves Maytapi's participant phone list into a map of
  # %{contact_id => is_admin?}, creating contacts as needed.
  @spec resolve_desired_members(map(), non_neg_integer()) :: %{non_neg_integer() => boolean()}
  defp resolve_desired_members(group, org_id) do
    admin_phone_numbers = Enum.map(group.admins || [], &phone_number(&1))

    Enum.reduce(group.participants, %{}, fn participant_phone, acc ->
      phone = phone_number(participant_phone)

      case Contacts.maybe_create_contact(%{
             phone: phone,
             organization_id: org_id,
             contact_type: "WA"
           }) do
        {:ok, contact} ->
          Map.put(acc, contact.id, admin?(phone, admin_phone_numbers))

        {:error, _reason} ->
          acc
      end
    end)
  end

  @doc """
  Upserts `wa_groups_phones` memberships from a single phone's Maytapi
  `getGroups` response. Groups the phone is currently in are marked
  `is_active: true`; memberships for groups no longer returned are marked
  `is_active: false`. `is_primary` is never touched here.
  """
  @spec sync_wa_group_phones(list(), WAManagedPhone.t()) :: :ok
  def sync_wa_group_phones(group_details, wa_managed_phone) do
    org_id = wa_managed_phone.organization_id

    present_group_ids =
      Enum.map(group_details, fn group ->
        {:ok, wa_group} =
          Repo.fetch_by(WAGroup, %{
            bsp_id: group.bsp_id,
            wa_managed_phone_id: group.wa_managed_phone_id,
            organization_id: org_id
          })

        activate_membership(wa_group.id, wa_managed_phone)
        wa_group.id
      end)

    deactivate_missing_memberships(wa_managed_phone, present_group_ids)
    :ok
  end

  @spec activate_membership(non_neg_integer(), WAManagedPhone.t()) :: {:ok, WAGroupPhone.t()}
  defp activate_membership(wa_group_id, wa_managed_phone) do
    %WAGroupPhone{}
    |> WAGroupPhone.changeset(%{
      wa_group_id: wa_group_id,
      wa_managed_phone_id: wa_managed_phone.id,
      organization_id: wa_managed_phone.organization_id,
      is_active: true
    })
    |> Repo.insert(
      on_conflict: [set: [is_active: true, updated_at: DateTime.utc_now()]],
      conflict_target: [:wa_group_id, :wa_managed_phone_id]
    )
  end

  @spec deactivate_missing_memberships(WAManagedPhone.t(), [non_neg_integer()]) :: :ok
  defp deactivate_missing_memberships(wa_managed_phone, present_group_ids) do
    WAGroupPhone
    |> where([wgp], wgp.wa_managed_phone_id == ^wa_managed_phone.id)
    |> where([wgp], wgp.wa_group_id not in ^present_group_ids)
    |> where([wgp], wgp.is_active == true)
    |> Repo.update_all(set: [is_active: false, updated_at: DateTime.utc_now()])

    :ok
  end

  @spec admin?(non_neg_integer(), [non_neg_integer()]) :: boolean()
  defp admin?(phone, admin_phone_numbers) do
    phone in admin_phone_numbers
  end

  @spec create_whatsapp_groups(list(), non_neg_integer) :: list()
  defp create_whatsapp_groups(groups, org_id) do
    Enum.map(
      groups,
      fn group ->
        maybe_create_group(%{
          label: group.name,
          organization_id: org_id,
          bsp_id: group.bsp_id,
          wa_managed_phone_id: group.wa_managed_phone_id,
          last_communication_at: DateTime.utc_now()
        })
      end
    )
  end

  @doc """
  Creates a wa_group.

  ## Examples

      iex> create_wa_group(%{field: value})
      {:ok, %WAGroup{}}

      iex> create_wa_group(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_wa_group(map()) :: {:ok, WAGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_wa_group(attrs \\ %{}) do
    %WAGroup{}
    |> WAGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the list of wa_groups.

  ## Examples

      iex> list_wa_groups()
      [%WAManagedPhone{}, ...]

  """
  @spec list_wa_groups(map()) :: [WAGroup.t()]
  def list_wa_groups(args) do
    args
    |> Repo.list_filter_query(WAGroup, &Repo.opts_with_name/2, &Repo.filter_with/2)
    |> Repo.all()
  end

  @doc """
  Gets a single wa_group.

  Raises `Ecto.NoResultsError` if the wa group does not exist.

  ## Examples

      iex> get_wa_group!(123)
      %WAGroup{}

      iex> get_wa_group!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_wa_group!(non_neg_integer()) :: WAGroup.t()
  def get_wa_group!(id), do: Repo.get!(WAGroup, id)

  @doc """
  Gets a wa_groups from list of IDs.

  ## Examples

      iex> get_wa_groups!([123])
      [%WAGroup{}]

      iex> get_wa_groups!([456])
      []

  """
  @spec get_wa_groups!([non_neg_integer()]) :: list(WAGroup.t())
  def get_wa_groups!(ids) do
    WAGroup
    |> where([wag], wag.id in ^ids)
    |> Repo.all()
  end

  @doc """
  Fetches a group with given bsp_id and organization_id (Creates a group if doesnt exist)
  """
  @spec maybe_create_group(map()) ::
          {:ok, Glific.Groups.WAGroup.t()} | {:error, Ecto.Changeset.t()}
  def maybe_create_group(params) do
    case Repo.get_by(WAGroup, %{
           bsp_id: params.bsp_id,
           organization_id: params.organization_id,
           wa_managed_phone_id: params.wa_managed_phone_id
         }) do
      nil ->
        create_wa_group(params)

      wa_group ->
        if params.label && wa_group.label != params.label do
          update_wa_group(wa_group, %{label: params.label})
        else
          {:ok, wa_group}
        end
    end
  end

  @doc """
  get all the wa groups associated with the group
  """
  @spec wa_groups_count(map()) :: integer()
  def wa_groups_count(args) do
    args
    |> Repo.list_filter_query(WAGroup, nil, &filter_with/2)
    |> Repo.aggregate(:count)
  end

  @doc """
  Sets the maytapi webhook for the org
  """
  @spec set_webhook_endpoint(map()) :: :ok | {:error, String.t()}
  def set_webhook_endpoint(org_details) do
    payload = %{
      "webhook" => Glific.api_callback_base(org_details.shortcode) <> "/maytapi"
    }

    case ApiClient.set_webhook(org_details.id, payload) do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Tesla.Env{body: body}} ->
        Logger.error(
          "Failed to set maytapi webhook for #{org_details.shortcode} due to #{inspect(body)}"
        )

        {:error, "Failed to set maytapi webhook. Try Again"}

      {:error, error} ->
        Logger.error(
          "Failed to set maytapi webhook for #{org_details.shortcode} due to #{inspect(error)}"
        )

        {:error, "Failed to set maytapi webhook. Try Again"}
    end
  end

  @doc """
  Updates a wa_group.

  ## Examples

    iex> update_wa_group(%{fields: value})
    {:ok, %WAGroup{}}

    iex> update_wa_group(%{fields: bad_value})
    {:error, %Ecto.Changeset{}}
  """
  @spec update_wa_group(WAGroup.t(), map()) :: {:ok, WAGroup.t()} | {:error, Ecto.Changeset.t()}
  def update_wa_group(wa_group, attrs \\ %{}) do
    wa_group
    |> WAGroup.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a WAGroup.t() as map
  """
  @spec get_wa_group_map(integer()) :: map()
  def get_wa_group_map(wa_group_id) do
    get_wa_group!(wa_group_id)
    |> Map.from_struct()
  end
end
