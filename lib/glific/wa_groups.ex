defmodule Glific.WAGroups do
  @moduledoc """
  The WAGroup context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Repo,
    WAGroup.WAManagedPhone
  }

  @spec list_wa_managed_phones() :: [WAManagedPhone.t()]
  @doc """
  Returns the list of wa_managed_phones.

  ## Examples

      iex> list_wa_managed_phones()
      [%WAManagedPhone{}, ...]

  """
  def list_wa_managed_phones do
    Repo.all(WAManagedPhone)
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

  # TODO Do we need a combined unique constraint?

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
    |> Repo.insert(
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:phone],
      returning: true
    )
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
end
