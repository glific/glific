defmodule Glific.SMSAdapter.Gupshup.Message do
  @moduledoc """
  Adapter to send OTP
  """

  alias Glific.{
    Communications,
    Contacts.Contact,
    Repo,
    Templates.SessionTemplate
  }

  @doc """
  Create OTP and send verification message with OTP code
  """
  @spec create(map()) :: {:ok, String.t()}
  def create(request) do
    # fetch contact by phone number
    case Repo.fetch_by(Contact, %{phone: request.to}) do
      {:ok, contact} ->
        create_and_send_verification_message(contact, request.code)
    end
  end

  defp create_and_send_verification_message(contact, otp) do
    # fetch session template by shortcode "verification"
    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{
        shortcode: "verification"
      })

    # create and send verification message with OTP code
    message_params = %{
      body: session_template.body <> otp,
      type: session_template.type,
      sender_id: Communications.Message.organization_contact_id(),
      receiver_id: contact.id
    }

    Glific.Messages.create_and_send_message(message_params)

    {:ok, otp}
  end
end
