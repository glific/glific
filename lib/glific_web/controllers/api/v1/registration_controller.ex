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
    conn
    |> Pow.Plug.create_user(user_params)
    |> case do
      {:ok, _user, conn} ->
        json(conn, %{
          data: %{
            access_token: conn.private[:api_access_token],
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
    with {:ok, otp} <- PasswordlessAuth.create_and_send_verification_code(phone),
         do:
           json(conn, %{
             data: %{
               phone: phone,
               otp: otp,
               message: "OTP #{otp} sent successfully to #{phone}"
             }
           })
  end
end
