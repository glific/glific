defmodule Glific.ProfilesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.Profiles` context.
  """

  @doc """
  Generate a profile.
  """
  def profile_fixture(attrs \\ %{}) do
    {:ok, profile} =
      attrs
      |> Enum.into(%{
        name: "some name",
        type: "some type"
      })
      |> Glific.Profiles.create_profile()

    profile
  end
end
