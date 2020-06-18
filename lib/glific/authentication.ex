defmodule Glific.Authentication do
  @moduledoc """
  The Authentication context.
  """
  import Ecto.Query, warn: false

  @doc """
  Creates and sends the OTP to phone number
  """
  @spec create_and_send_otp_to_phone(map()) :: String.t()
  def create_and_send_otp_to_phone(args \\ %{}) do
    %{phone: phone} = args

    PasswordlessAuth.create_and_send_verification_code(
      phone
    )

    {:ok, "OTP sent successfully to #{phone}"}
  end
end
