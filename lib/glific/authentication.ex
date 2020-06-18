defmodule Glific.Authentication do
  @moduledoc """
  The Authentication context.
  """
  import Ecto.Query, warn: false
  alias PasswordlessAuth

  @doc """
  Creates and sends the OTP to phone number
  """
  @spec create_and_send_otp_to_phone(map()) :: {:ok, String.t()}
  def create_and_send_otp_to_phone(args) do
    %{phone: phone} = args

    {:ok, otp} = PasswordlessAuth.create_and_send_verification_code(phone)

    {:ok, "OTP #{otp} sent successfully to #{phone}"}
  end

  @doc """
  Verifies otp and updates database with new contact
  Removes otp from agent
  """
  @spec verify_otp(map()) :: {:ok, String.t()}
  def verify_otp(%{phone: phone, otp: otp}) do
    case PasswordlessAuth.verify_code(phone, otp) do
      :ok ->
        # To do: Update contact table

        # Remove otp code
        PasswordlessAuth.remove_code(phone)

        {:ok, "OTP verified successfully for #{phone}"}

      {:error, error} ->
        {:ok, Atom.to_string(error)}
    end
  end
end
