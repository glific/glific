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
end
