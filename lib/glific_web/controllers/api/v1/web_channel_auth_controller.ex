defmodule GlificWeb.API.V1.WebChannelAuthController do
  @moduledoc """
  Public (unauthenticated) OTP-based auth for the web channel.

  An end user on an NGO's web page enters a phone number and an OTP; on success we
  resolve/create the shared `Glific.Contacts.Contact` for that phone + org and hand back a
  contact-scoped token (`GlificWeb.WebChannel.Token`) the browser uses to open the web
  socket (`GlificWeb.WebChannelSocket`). This is intentionally distinct from the staff-facing
  Pow `RegistrationController` flow — no `Glific.Users.User` is created or touched here.

  PROTOTYPE: OTP delivery is not yet implemented. `request_otp/2` does not send an SMS, and
  `verify_otp/2` accepts a single hardcoded OTP ("9999") when explicitly enabled via the
  `:web_channel_otp_bypass` application env (see config comments). This must be replaced by
  real SMS OTP delivery/verification before this ships to any production organization.
  """

  use GlificWeb, :controller

  alias Glific.Contacts
  alias GlificWeb.WebChannel.DisplayName
  alias GlificWeb.WebChannel.Token
  alias Plug.Conn

  @doc """
  Accept a phone number and (prototype) pretend to send an OTP.

  Rate limiting is handled upstream by `GlificWeb.RateLimitPlug` in the `:api` pipeline.
  """
  @spec request_otp(Conn.t(), map()) :: Conn.t()
  def request_otp(conn, %{"phone" => phone}) when is_binary(phone) and phone != "" do
    json(conn, %{data: %{phone: phone, message: "OTP sent"}})
  end

  def request_otp(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{error: %{message: "Phone number is required"}})
  end

  @doc """
  Verify the (prototype) OTP and, on success, resolve/create the contact for the given
  phone + org and return a contact-scoped web channel token.
  """
  @spec verify_otp(Conn.t(), map()) :: Conn.t()
  def verify_otp(conn, %{"phone" => phone, "otp" => otp}) do
    organization_id = conn.assigns[:organization_id]

    with :ok <- verify_prototype_otp(otp),
         {:ok, contact} <-
           Contacts.maybe_create_contact(%{phone: phone, organization_id: organization_id}) do
      token = Token.sign_contact_token(contact)

      json(conn, %{
        data: %{
          token: token,
          contact_id: contact.id,
          name: DisplayName.resolve(contact),
          phone: contact.phone
        }
      })
    else
      {:error, _reason} ->
        conn
        |> put_status(401)
        |> json(%{error: %{message: "Invalid OTP"}})
    end
  end

  # Prototype-only OTP check. Feature-gated by `:web_channel_otp_bypass` so this bypass can
  # never silently be live in an environment that hasn't explicitly opted in (see
  # config/dev.exs and config/test.exs; deliberately absent/false in config/prod.exs and
  # config/runtime.exs).
  @spec verify_prototype_otp(String.t()) :: :ok | {:error, String.t()}
  defp verify_prototype_otp(otp) do
    if Application.get_env(:glific, :web_channel_otp_bypass, false) and otp == "9999" do
      :ok
    else
      {:error, "Invalid OTP"}
    end
  end
end
