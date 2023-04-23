defmodule Glific.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.Accounts` context.
  """
  alias Glific.Fixtures

  def unique_user_email, do: "#{System.unique_integer()}2323243"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      phone: unique_user_email(),
      password: valid_user_password(),
      password_confirmation: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    user =
      attrs
      |> valid_user_attributes()
      |> Fixtures.user_fixture()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
