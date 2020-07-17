defmodule GlificWeb.API.V1.RegistrationController do
  @moduledoc """
  The Pow User Registration Controller
  """

  use GlificWeb, :controller

  alias Ecto.Changeset
  alias GlificWeb.ErrorHelpers
  alias PasswordlessAuth
  alias Plug.Conn

  @doc false
  @spec create(Conn.t(), map()) :: Conn.t()
  def create(conn, %{"user" => user_params}) do
    %{"phone" => phone, "otp" => otp} = user_params

    case PasswordlessAuth.verify_code(phone, otp) do
      :ok ->
        # Remove otp code
        PasswordlessAuth.remove_code(phone)
        create_user(conn, user_params)

      {:error, error} ->
        # Error response options: :attempt_blocked | :code_expired | :does_not_exist | :incorrect_code
        conn
        |> put_status(500)
        |> json(%{
          error: %{status: 500, message: "Couldn't create user", errors: [Atom.to_string(error)]}
        })
    end
  end

  @spec create_user(Conn.t(), map()) :: Conn.t()
  defp create_user(conn, user_params) do
    user_params_with_password_confirmation =
      user_params
      |> Map.merge(%{"password_confirmation" => user_params["password"]})

    conn
    |> Pow.Plug.create_user(user_params_with_password_confirmation)
    |> case do
      {:ok, _user, conn} ->
        json(conn, %{
          data: %{
            access_token: conn.private[:api_access_token],
            token_expiry_time: conn.private[:api_token_expiry_time],
            renewal_token: conn.private[:api_renewal_token]
          }
        })

      {:error, changeset, conn} ->
        errors = Changeset.traverse_errors(changeset, &ErrorHelpers.translate_error/1)

        conn
        |> put_status(500)
        |> json(%{error: %{status: 500, message: "Couldn't create user", errors: errors}})
    end
  end

  @doc false
  @spec send_otp(Conn.t(), map()) :: Conn.t()
  def send_otp(conn, %{"user" => %{"phone" => phone}}) do
    with {:ok, contact} <- Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: phone}),
         true <- Glific.Contacts.can_send_hsm_message_to?(contact),
         {:ok, _otp} <- PasswordlessAuth.create_and_send_verification_code(phone) do
      json(conn, %{
        data: %{
          phone: phone,
          message: "OTP sent successfully to #{phone}"
        }
      })
    else
      {:error, _} ->
        conn
        |> put_status(400)
        |> json(%{error: %{status: 400, message: "Phone number is incorrect"}})

      false ->
        conn
        |> json(%{
          error: %{status: 200, message: "Contact is not opted in yet"}
        })
    end
  end

  @doc false
  @spec validate_phone(Conn.t(), map()) :: Conn.t()
  def validate_phone(conn, %{"user" => %{"phone" => phone}}) do
    # we can put more validations for phone number here
    with {:error, _user} <- Glific.Repo.fetch_by(Glific.Users.User, %{phone: phone}),
         {:ok, contact} <- Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: phone}),
         true <- Glific.Contacts.can_send_hsm_message_to?(contact) do
      json(conn, %{
        data: %{
          is_valid: true,
          message: "Phone number is successfully validated"
        }
      })
    else
      {:error, "Resource not found"} ->
        json(conn, %{
          data: %{
            is_valid: false,
            message: "Phone number is incorrect"
          }
        })

      false ->
        json(conn, %{
          data: %{
            is_valid: false,
            message: "Contact is not opted in yet"
          }
        })

      {:ok, _} ->
        json(conn, %{
          data: %{
            is_valid: false,
            message: "Phone number already exists"
          }
        })
    end
  end
end
