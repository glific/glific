defmodule Glific.OTPTest do
  use Glific.DataCase

  alias Glific.OTP

  # PasswordlessAuth's store is global and outlives a single test, so every test gets its own
  # phone to stay independent of ordering.
  setup do
    %{phone: "9198#{System.unique_integer([:positive])}"}
  end

  describe "verify_code/3" do
    test "accepts a code generated for the same scope", %{phone: phone} do
      code = OTP.generate_code(:auth, phone)

      assert :ok == OTP.verify_code(:auth, phone, code)
    end

    test "rejects a code generated for another scope", %{phone: phone} do
      trial_code = OTP.generate_code(:trial, phone)

      assert {:error, :does_not_exist} == OTP.verify_code(:auth, phone, trial_code)
    end

    test "a code for one scope leaves another scope's code untouched", %{phone: phone} do
      auth_code = OTP.generate_code(:auth, phone)
      _trial_code = OTP.generate_code(:trial, phone)

      assert :ok == OTP.verify_code(:auth, phone, auth_code)
    end

    test "consumes the code so it cannot be replayed", %{phone: phone} do
      code = OTP.generate_code(:auth, phone)

      assert :ok == OTP.verify_code(:auth, phone, code)
      assert {:error, :does_not_exist} == OTP.verify_code(:auth, phone, code)
    end

    test "rejects an incorrect code", %{phone: phone} do
      OTP.generate_code(:auth, phone)

      assert {:error, :incorrect_code} == OTP.verify_code(:auth, phone, "000000")
    end

    test "rejects a code for a phone that was never issued one", %{phone: phone} do
      assert {:error, :does_not_exist} == OTP.verify_code(:auth, phone, "123456")
    end
  end
end
