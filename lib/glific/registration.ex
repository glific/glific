defmodule Glific.Registrations do
  @moduledoc """
  The Registrations context
  """

  alias Glific.{
    Repo,
    Registrations.Registration,
  }

  @doc """
  Creates a organization.

  ## Examples

      iex> Glific.Registrations.create_registration(%{name: value})
      {:ok, %Glific.Organization{}}

      iex> Glific.Registrations.create_registration(%{bad_field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_registration(map()) :: {:ok, Registration.t()} | {:error, Ecto.Changeset.t()}
  def create_registration(attrs \\ %{}) do
    %Registration{}
    |> Registration.changeset(attrs)
    |> Repo.insert(skip_organization_id: true)
  end
end
