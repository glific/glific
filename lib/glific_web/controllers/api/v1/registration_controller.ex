defmodule GlificWeb.API.V1.RegistrationController do
  @moduledoc """
  The Pow User Registration Controller
  """

  use GlificWeb, :controller

  alias Ecto.Changeset
  alias GlificWeb.ErrorHelpers
  alias PasswordlessAuth
  alias Plug.Conn

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Repo,
    Tags,
    Users,
    Users.User
  }

  @doc false
  @spec create(Conn.t(), map()) :: Conn.t()
  def create(conn, %{"user" => user_params}) do
    %{"phone" => phone, "otp" => otp} = user_params

    with {:ok, _message} <- verify_otp(phone, otp),
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
    user_params_with_password_confirmation =
      user_params
      |> Map.merge(%{"password_confirmation" => user_params["password"]})

    conn
    |> Pow.Plug.create_user(user_params_with_password_confirmation)
    |> case do
      {:ok, user, conn} ->
        {:ok, _} = add_staff_tag_to_user_contact(user)

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

  @doc false
  @spec add_staff_tag_to_user_contact(User.t()) :: {:ok, String.t()}
  defp add_staff_tag_to_user_contact(user) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{phone: user.phone}),
         {:ok, tag} <- Repo.fetch_by(Tags.Tag, %{label: "Staff"}),
         {:ok, _} <- Tags.create_contact_tag(%{contact_id: contact.id, tag_id: tag.id}),
         do: {:ok, "Staff tag added to the user contatct"}
  end

  @doc false
  @spec send_otp(Conn.t(), map()) :: Conn.t()
  def send_otp(conn, %{"user" => %{"phone" => phone}} = user_params) do
    registration = user_params["user"]["registration"]

    with true <- can_send_otp_to_phone?(phone),
         true <- send_otp_allowed?(phone, registration),
         {:ok, _otp} <- PasswordlessAuth.create_and_send_verification_code(phone) do
      json(conn, %{data: %{phone: phone, message: "OTP sent successfully to #{phone}"}})
    else
      _ ->
        conn
        |> put_status(400)
        |> json(%{error: %{status: 400, message: "Cannot send the otp to #{phone}"}})
    end
  end

  @spec can_send_otp_to_phone?(String.t()) :: boolean
  defp can_send_otp_to_phone?(phone) do
    with {:ok, contact} <- Repo.fetch_by(Contact, %{phone: phone}),
         do: Contacts.can_send_message_to?(contact, true)
  end

  @spec send_otp_allowed?(String.t(), String.t()) :: boolean
  defp send_otp_allowed?(phone, registration) do
    {result, _} = Repo.fetch_by(User, %{phone: phone})
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
         {:ok, _response_data} <- reset_user_password(user_params) do
      {:ok, conn} =
        conn
        |> Pow.Plug.authenticate_user(user_params)

      json(conn, %{
        data: %{
          access_token: conn.private[:api_access_token],
          token_expiry_time: conn.private[:api_token_expiry_time],
          renewal_token: conn.private[:api_renewal_token]
        }
      })
    else
      {:error, _errors} ->
        conn
        |> put_status(500)
        |> json(%{error: %{status: 500, message: "Couldn't update user password"}})
    end
  end

  @spec reset_user_password(map()) :: {:ok, User.t()} | {:error, Changeset.t()}
  defp reset_user_password(%{"phone" => phone, "password" => password}) do
    update_params = %{
      "password" => password,
      "password_confirmation" => password
    }

    {:ok, user} = Repo.fetch_by(User, %{phone: phone})

    user
    |> Users.reset_user_password(update_params)
  end
end
