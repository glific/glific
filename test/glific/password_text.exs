defmodule Glific.PasswordTest do
  @moduledoc """
  Tests for Glific.Password
  """
  use ExUnit.Case

  test "Creates a valid password and hashes it" do
      hashed_password = Glific.Password.generate_password()
      assert is_binary(hashed_password)
    end
  end
