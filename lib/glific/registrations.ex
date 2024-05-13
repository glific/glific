defmodule Glific.Registrations do
  @moduledoc """
  The Registrations context
  """

  alias Glific.{
    Registrations.Registration,
    Repo
  }

  @doc """
  Creates a organization.

  ## Examples

      iex> Glific.Registrations.create_registration(%{organization_id: 1})
      {:ok, %Registration{}}

      iex> Glific.Registrations.create_registration(%{})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_registration(map()) :: {:ok, Registration.t()} | {:error, Ecto.Changeset.t()}
  def create_registration(attrs \\ %{}) do
    %Registration{}
    |> Registration.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetch a registration by given registration id
  """
  @spec get_registration(integer()) :: {:ok, Registration.t()} | {:error, term()}
  def get_registration(registration_id) do
    Repo.fetch_by(Registration, id: registration_id)
  end

  @doc """
  Updates the registrations table
  """
  @spec update_registation(Registration.t(), map()) ::
          {:ok, Registration.t()} | {:error, Ecto.Changeset.t()}
  def update_registation(registration, attrs) do
    registration
    |> Registration.changeset(attrs)
    |> Repo.update()
  end
end
