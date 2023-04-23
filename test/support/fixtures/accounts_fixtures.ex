defmodule Glific.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.Accounts` context.
  """
  alias Glific.Fixtures

  @doc false
  @spec unique_user_email() :: String.t()
  def unique_user_email, do: "#{System.unique_integer()}2323243"

  @doc false
  @spec valid_user_password() :: String.t()
  def valid_user_password, do: "hello world!"

  @doc false
  @spec valid_user_attributes(map()) :: map()
  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      phone: unique_user_email(),
      password: valid_user_password(),
      password_confirmation: valid_user_password()
    })
  end

  @doc false
  @spec user_fixture(map()) :: any()
  def user_fixture(attrs \\ %{}) do
    user =
      attrs
      |> valid_user_attributes()
      |> Fixtures.user_fixture()

    user
  end

  @doc false
  @spec extract_user_token(any()) :: any()
  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
