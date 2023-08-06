defmodule GlificWeb.API.V1.RegistrationController do
  @moduledoc """
  The Pow User Registration Controller
  """
  @dialyzer {:no_return, reset_password: 2}
  @dialyzer {:no_return, reset_user_password: 2}

  use GlificWeb, :controller

  alias Ecto.Changeset
  alias PasswordlessAuth
  alias Plug.Conn

  alias GlificWeb.{
    APIAuthPlug,
    ErrorHelpers
  }

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Partners,
    Repo,
    Users,
    Users.User
  }

  @doc false
  @spec create(Conn.t(), map()) :: Conn.t()
  def create(conn, %{"user" => user_params}) do
    with {:ok, _message} <- verify_otp(user_params["phone"], user_params["otp"]),
         {:ok, response_data} <- create_user(conn, user_params) do
      json(conn, response_data)
    else
      {:error, errors} ->
        conn
        |> put_status(500)
        |> json(%{error: %{status: 500, message: "Couldn't create user", errors: errors}})
    end
  end

  @spec verify_otp(String.t(), String.t()) :: {:ok, String.t()} | {:error, []}
  defp verify_otp(phone, otp) do
    case PasswordlessAuth.verify_code(phone, otp) do
      :ok ->
        # Remove otp code
        PasswordlessAuth.remove_code(phone)
        {:ok, "verified"}

      {:error, error} ->
        # Error response options: :attempt_blocked | :code_expired | :does_not_exist | :incorrect_code
        {:error, [Atom.to_string(error)]}
    end
  end

  @spec create_user(Conn.t(), map()) :: {:ok, map()} | {:error, []}
  defp create_user(conn, user_params) do
    organization_id = conn.assigns[:organization_id]

    {:ok, contact} =
      Repo.fetch_by(Contact, %{phone: user_params["phone"], organization_id: organization_id})

    updated_user_params =
      user_params
      |> Map.merge(%{
        "password_confirmation" => user_params["password"],
        "contact_id" => contact.id,
        "organization_id" => organization_id,
        "language_id" => contact.language_id
      })

    conn
    |> Pow.Plug.create_user(updated_user_params)
    |> case do
      {:ok, user, conn} ->
        Users.promote_first_user(user)

        response_data = %{
          data: %{
            access_token: conn.private[:api_access_token],
            token_expiry_time: conn.private[:api_token_expiry_time],
            renewal_token: conn.private[:api_renewal_token]
          }
        }

        {:ok, response_data}

      {:error, changeset, _conn} ->
        errors = Changeset.traverse_errors(changeset, &ErrorHelpers.translate_error/1)

        {:error, errors}
    end
  end

  # we need to give user permissions here so we can retrieve and send messages
  # in some cases
  defp build_context(organization_id) do
    organization = Partners.organization(organization_id)
    Repo.put_current_user(organization.root_user)
  end

  @doc """
  verifying google captcha only when token is passed
  """
  @spec send_otp(Conn.t(), map()) :: Conn.t()
  def send_otp(
        conn,
        %{"user" => %{"token" => token, "registration" => "true", "phone" => phone}} =
          _user_params
      ) do
    case Glific.verify_google_captcha(token) do
      {:ok, "success"} ->
        send_otp(conn, %{"user" => %{"phone" => phone, "registration" => "true"}})

      {:error, error} ->
        send_otp_error(conn, error)
    end
  end

  def send_otp(
        conn,
        %{"user" => %{"phone" => phone, "registration" => registration}} = _user_params
      ) do
    organization_id = conn.assigns[:organization_id]
    build_context(organization_id)

    with {:ok, _contact} <- optin_contact(organization_id, phone),
         {:ok, contact} <- can_send_otp_to_phone?(organization_id, phone),
         true <- send_otp_allowed?(organization_id, phone, registration),
         {:ok, _otp} <- create_and_send_verification_code(contact) do
      json(conn, %{data: %{phone: phone, message: "OTP sent successfully to #{phone}"}})
    else
      _ ->
        send_otp_error(conn, "Cannot send the otp to #{phone}")
    end
  end

  @doc false
  @spec send_otp_error(Conn.t(), String.t()) :: Conn.t()
  defp send_otp_error(conn, msg) do
    conn
    |> put_status(400)
    |> json(%{error: %{status: 400, message: msg}})
  end

  @doc """
  Function for generating verification code and sending otp verification message
  """
  @spec create_and_send_verification_code(Contact.t()) :: {:ok, String.t()}
  def create_and_send_verification_code(contact) do
    code = PasswordlessAuth.generate_code(contact.phone)
    Glific.Messages.create_and_send_otp_verification_message(contact, code)
    {:ok, code}
  end

  # see if we can send an hsm or session message to this contact
  @spec can_send_message_to?(Contact.t()) :: boolean
  defp can_send_message_to?(contact) do
    hsm = Contacts.can_send_message_to?(contact, true)
    session = Contacts.can_send_message_to?(contact, false)
    elem(hsm, 0) == :ok || elem(session, 0) == :ok
  end

  @spec can_send_otp_to_phone?(integer, String.t()) :: {:ok, Contact.t()} | {:error, any} | false
  defp can_send_otp_to_phone?(organization_id, phone) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{phone: phone, organization_id: organization_id}),
         true <- can_send_message_to?(contact),
         do: {:ok, contact}
  end

  @spec send_otp_allowed?(integer, String.t(), String.t()) :: boolean
  defp send_otp_allowed?(organization_id, phone, registration) do
    {result, _} = Repo.fetch_by(User, %{phone: phone, organization_id: organization_id})
    (result == :ok && registration == "false") || (result == :error && registration != "false")
  end

  @doc """
  Controller function for reset password
  It also verifies OTP to authorize the request
  """
  @spec reset_password(Conn.t(), map()) :: Conn.t()
  def reset_password(conn, %{"user" => user_params}) do
    %{"phone" => phone, "otp" => otp} = user_params

    with {:ok, _data} <- verify_otp(phone, otp),
         {:ok, response_data} <- reset_user_password(conn, user_params) do
      json(conn, response_data)
    else
      {:error, _errors} ->
        conn
        |> put_status(500)
        |> json(%{error: %{status: 500, message: "Couldn't update user password"}})
    end
  end

  @spec reset_user_password(Conn.t(), map()) :: {:ok, map()} | {:error, []}
  defp reset_user_password(conn, %{"phone" => phone, "password" => password} = user_params) do
    update_params = %{"password" => password, "password_confirmation" => password}

    {:ok, user} =
      Repo.fetch_by(User, %{phone: phone, organization_id: conn.assigns[:organization_id]})

    user
    |> Users.reset_user_password(update_params)
    |> case do
      {:ok, user} ->
        APIAuthPlug.delete_user_sessions(user, conn)

        # Create new user session
        {:ok, conn} =
          Pow.Plug.authenticate_user(
            conn,
            Map.put(user_params, "organization_id", conn.assigns[:organization_id])
          )

        {:ok,
         %{
           data: %{
             access_token: conn.private[:api_access_token],
             token_expiry_time: conn.private[:api_token_expiry_time],
             renewal_token: conn.private[:api_renewal_token]
           }
         }}

      {:error, _error} ->
        {:error, []}
    end
  end

  @spec optin_contact(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, []}
  defp optin_contact(organization_id, phone) do
    %{
      phone: phone,
      organization_id: organization_id,
      method: "registration"
    }
    |> Contacts.optin_contact()
  end
end
