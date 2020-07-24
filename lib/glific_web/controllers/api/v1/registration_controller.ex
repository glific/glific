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
      {:ok, user, conn} ->
        {:ok, _} = add_staff_tag_to_user_contact(user)

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
  @spec add_staff_tag_to_user_contact(Glific.Users.User.t()) :: {:ok, String.t()}
  defp add_staff_tag_to_user_contact(user) do
    with {:ok, contact} <-
           Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: user.phone}),
         {:ok, tag} <- Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: "Staff"}),
         {:ok, _} <- Glific.Tags.create_contact_tag(%{contact_id: contact.id, tag_id: tag.id}),
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
        put_status(conn, 400)
        |> json(%{error: %{message: "Cannot send the otp to #{phone}"}})
    end
  end

  @spec can_send_otp_to_phone?(String.t()) :: boolean
  defp can_send_otp_to_phone?(phone) do
    with {:ok, contact} <- Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: phone}),
         do: Glific.Contacts.can_send_message_to?(contact, true)
  end

  @spec send_otp_allowed?(String.t(), String.t()) :: boolean
  defp send_otp_allowed?(phone, registration) do
    {result, _} = Glific.Repo.fetch_by(Glific.Users.User, %{phone: phone})
    (result == :ok && registration == "false") || (result == :error && registration != "false")
  end

  @doc """
    Controller function for reset password
    It also verifies OTP to authorize the request
  """
  @spec reset_password(Conn.t(), map()) :: Conn.t()
  def reset_password(conn, %{"user" => user_params}) do
    %{"phone" => phone, "otp" => otp} = user_params

    case PasswordlessAuth.verify_code(phone, otp) do
      :ok ->
        # Remove otp code
        PasswordlessAuth.remove_code(phone)
        reset_user_password(conn, user_params)

      {:error, error} ->
        # Error response options: :attempt_blocked | :code_expired | :does_not_exist | :incorrect_code
        conn
        |> put_status(500)
        |> json(%{
          error: %{
            status: 500,
            message: "Couldn't update user password",
            errors: [Atom.to_string(error)]
          }
        })
    end
  end

  @spec reset_user_password(Conn.t(), map()) :: Conn.t()
  defp reset_user_password(conn, %{"phone" => phone, "password" => password}) do
    update_params = %{
      "password" => password,
      "password_confirmation" => password
    }

    {:ok, user} = Glific.Repo.fetch_by(Glific.Users.User, %{phone: phone})

    user
    |> Glific.Users.reset_user_password(update_params)
    |> case do
      {:ok, _user} ->
        json(conn, %{
          data: %{phone: phone, message: "Password is updated for #{phone}"}
        })

      {:error, _error} ->
        conn
        |> put_status(500)
        |> json(%{error: %{status: 500, message: "Couldn't update user password"}})
    end
  end
end
