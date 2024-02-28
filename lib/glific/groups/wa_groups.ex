defmodule Glific.Groups.WAGroups do
  @moduledoc """
  Whatsapp groups context.
  """

  alias Glific.{
    Groups.WAGroup,
    Providers.Maytapi.ApiClient,
    Repo,
    WAManagedPhones
  }

  @doc """
  Fetches group using maytapi API and sync it in Glific
  """
  @spec fetch_wa_groups(non_neg_integer()) :: :ok
  def fetch_wa_groups(org_id) do
    wa_managed_phones = WAManagedPhones.list_wa_managed_phones(%{organization_id: org_id})

    Enum.each(wa_managed_phones, fn wa_managed_phone ->
      do_fetch_wa_groups(org_id, wa_managed_phone)
    end)
  end

  @spec do_fetch_wa_groups(non_neg_integer(), map()) :: list() | {:error, any()}
  defp do_fetch_wa_groups(org_id, wa_managed_phone) do
    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           ApiClient.list_wa_groups(org_id, wa_managed_phone.phone_id),
         {:ok, decoded} <- Jason.decode(body) do
      decoded
      |> get_group_details(wa_managed_phone)
      |> create_whatsapp_groups(org_id)
    else
      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, body}

      {:error, message} ->
        {:error, inspect(message)}
    end
  end

  defp get_group_details(%{"data" => groups}, wa_managed_phone) when is_list(groups) do
    Enum.map(groups, fn group ->
      %{name: group["name"], bsp_id: group["id"], wa_managed_phone_id: wa_managed_phone.id}
    end)
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

  Raises `Ecto.NoResultsError` if the Wa managed phone does not exist.

  ## Examples

      iex> get_wa_group!(123)
      %WAGroup{}

      iex> get_wa_group!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_wa_group!(non_neg_integer()) :: WAGroup.t()
  def get_wa_group!(id), do: Repo.get!(WAGroup, id)

  @doc """
  Fetches a group with given bsp_id and organization_id (Creates a group if doesnt exist)
  """
  @spec maybe_create_group(map()) :: {:ok, WAGroup.t()} | {:error, Ecto.Changeset.t()}
  def maybe_create_group(params) do
    case Repo.get_by(WAGroup, %{
           bsp_id: params.bsp_id,
           organization_id: params.organization_id,
           wa_managed_phone_id: params.wa_managed_phone_id
         }) do
      nil ->
        create_wa_group(params)

      wa_group ->
        {:ok, wa_group}
    end
  end
end
