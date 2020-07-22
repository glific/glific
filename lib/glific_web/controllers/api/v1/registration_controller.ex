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
  @spec send_registration_otp(Conn.t(), map()) :: Conn.t()
  def send_registration_otp(conn, %{"user" => %{"phone" => phone}}) do
    with {:error, _user} <- Glific.Repo.fetch_by(Glific.Users.User, %{phone: phone}),
         {:ok, contact} <- Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: phone}),
         true <- Glific.Contacts.can_send_message_to?(contact, true),
         {:ok, _otp} <- PasswordlessAuth.create_and_send_verification_code(phone) do
      conn
      |> json(%{
        data: %{phone: phone, message: "OTP sent successfully to #{phone}"}
      })
    else
      _ ->
        conn
        |> put_status(400)
        |> json(%{
          error: %{message: "Cannot send the registration otp to #{phone}"}
        })
    end
  end
end
