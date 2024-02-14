defmodule Glific.WAManagedPhones do
  @moduledoc """
  The WAGroup context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Providers.Maytapi.ApiClient,
    Repo,
    WAGroup.WAManagedPhone
  }

  @doc """
  Returns the list of wa_managed_phones.

  ## Examples

      iex> list_wa_managed_phones()
      [%WAManagedPhone{}, ...]

  """
  @spec list_wa_managed_phones(map()) :: [WAManagedPhone.t()]
  def list_wa_managed_phones(args) do
    args
    |> Repo.list_filter_query(WAManagedPhone, &Repo.opts_with_name/2, &Repo.filter_with/2)
    |> Repo.all()
  end

  @doc """
  Gets a single wa_managed_phone.

  Raises `Ecto.NoResultsError` if the Wa managed phone does not exist.

  ## Examples

      iex> get_wa_managed_phone!(123)
      %WAManagedPhone{}

      iex> get_wa_managed_phone!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_wa_managed_phone!(non_neg_integer()) :: WAManagedPhone.t()
  def get_wa_managed_phone!(id), do: Repo.get!(WAManagedPhone, id)

  @doc """
  Creates a wa_managed_phone.

  ## Examples

      iex> create_wa_managed_phone(%{field: value})
      {:ok, %WAManagedPhone{}}

      iex> create_wa_managed_phone(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_wa_managed_phone(map()) :: {:ok, WAManagedPhone.t()} | {:error, Ecto.Changeset.t()}
  def create_wa_managed_phone(attrs \\ %{}) do
    %WAManagedPhone{}
    |> WAManagedPhone.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a wa_managed_phone.

  ## Examples

      iex> update_wa_managed_phone(wa_managed_phone, %{field: new_value})
      {:ok, %WAManagedPhone{}}

      iex> update_wa_managed_phone(wa_managed_phone, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_wa_managed_phone(WAManagedPhone.t(), map()) ::
          {:ok, WAManagedPhone.t()} | {:error, Ecto.Changeset.t()}
  def update_wa_managed_phone(%WAManagedPhone{} = wa_managed_phone, attrs) do
    wa_managed_phone
    |> WAManagedPhone.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a wa_managed_phone.

  ## Examples

      iex> delete_wa_managed_phone(wa_managed_phone)
      {:ok, %WAManagedPhone{}}

      iex> delete_wa_managed_phone(wa_managed_phone)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_wa_managed_phone(WAManagedPhone.t()) ::
          {:ok, WAManagedPhone.t()} | {:error, Ecto.Changeset.t()}
  def delete_wa_managed_phone(%WAManagedPhone{} = wa_managed_phone) do
    Repo.delete(wa_managed_phone)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking wa_managed_phone changes.

  ## Examples

      iex> change_wa_managed_phone(wa_managed_phone)
      %Ecto.Changeset{data: %WAManagedPhone{}}

  """
  @spec change_wa_managed_phone(WAManagedPhone.t(), map()) :: Ecto.Changeset.t()
  def change_wa_managed_phone(%WAManagedPhone{} = wa_managed_phone, attrs \\ %{}) do
    WAManagedPhone.changeset(wa_managed_phone, attrs)
  end

  # TODO Can't we use bulk insert?

  @doc """
  fetches WhatsApp enabled phone added in Maytapi account
  """
  @spec fetch_wa_managed_phones(non_neg_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_wa_managed_phones(org_id) do
    with {:ok, secrets} <- ApiClient.fetch_credentials(org_id),
         {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           ApiClient.list_wa_managed_phones(org_id),
         {:ok, wa_managed_phones} <- Jason.decode(body) do
      Enum.each(wa_managed_phones, fn wa_managed_phone ->
        phone = wa_managed_phone["number"]

        params =
          %{
            label: wa_managed_phone["name"],
            phone: phone,
            phone_id: wa_managed_phone["id"],
            api_token: secrets["token"],
            product_id: secrets["product_id"],
            organization_id: org_id
          }

        with {:ok, contact} <- Contacts.maybe_create_contact(%{phone: phone}) |> IO.inspect(),
             nil <- Repo.get_by(WAManagedPhone, %{phone: phone}) do
          Map.put(params, :contact_id, contact.id)
          |> create_wa_managed_phone()
        else
          _ -> :ok
        end

        {:ok, "success"}
      end)
    else
      _ -> {:error, "error"}
    end
  end
end
