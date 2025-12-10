defmodule GlificWeb.API.V1.TrialUsersController do
  @moduledoc """
  Controller for allocating trial users to users via an API endpoint.
  """
  use GlificWeb, :controller

  require Logger

  alias PasswordlessAuth
  alias Plug.Conn

  alias Glific.{
    Communications.Mailer,
    Mails.TrialAccountMail,
    Partners,
    Partners.Saas,
    Repo,
    TrialUsers
  }

  import Ecto.Query

  @doc """
  Create trial user and send OTP via email
  """
  @spec create_trial_user(Conn.t(), map()) :: Conn.t()
  def create_trial_user(
        conn,
        %{
          "username" => username,
          "email" => email,
          "phone" => phone,
          "organization_name" => organization_name
        }
      ) do
    existing_user =
      TrialUsers
      |> where([t], t.email == ^email or t.phone == ^phone)
      |> Repo.one(skip_organization_id: true)

    case existing_user do
      nil ->
        create_and_send_otp(conn, username, email, phone, organization_name)

      user ->
        handle_existing_user(conn, user, email, phone)
    end
  end

  @spec handle_existing_user(Conn.t(), TrialUsers.t(), String.t(), String.t()) :: Conn.t()
  defp handle_existing_user(conn, existing_user, _email, _phone) do
    if existing_user.otp_entered do
      conn
      |> json(%{
        success: false,
        error: "User with this email or phone already exists"
      })
    else
      resend_otp_to_existing_user(conn, existing_user)
    end
  end

  @spec resend_otp_to_existing_user(Conn.t(), TrialUsers.t()) :: Conn.t()
  defp resend_otp_to_existing_user(conn, trial_user) do
    username = trial_user.username
    code = PasswordlessAuth.generate_code(trial_user.phone)
    send_otp_email(conn, trial_user, code, username)
  end

  @spec create_and_send_otp(Conn.t(), String.t(), String.t(), String.t(), String.t()) ::
          Conn.t()
  defp create_and_send_otp(conn, username, email, phone, organization_name) do
    code = PasswordlessAuth.generate_code(phone)

    trial_user_attrs = %{
      username: username,
      email: email,
      phone: phone,
      organization_name: organization_name
    }

    case TrialUsers.create_trial_user(trial_user_attrs) do
      {:ok, trial_user} ->
        send_otp_email(conn, trial_user, code, username)

      {:error, changeset} ->
        Logger.error(
          "Failed to create trial account for #{email}. Errors: #{inspect(changeset.errors)}"
        )

        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to create trial account"
        })
    end
  end

  @spec send_otp_email(Conn.t(), TrialUsers.t(), String.t(), String.t()) :: Conn.t()
  defp send_otp_email(conn, trial_user, code, username) do
    org = Saas.organization_id() |> Partners.get_organization!()
    email = trial_user.email

    TrialAccountMail.otp_verification_mail(org, email, code, username)
    |> Mailer.send(%{
      category: "trial_otp_verification",
      organization_id: org.id
    })
    |> case do
      {:ok, _result} ->
        json(conn, %{
          data: %{
            message: "OTP sent successfully to #{trial_user.email}"
          }
        })

      {:error, reason} ->
        Logger.error(
          "Failed to send OTP email to #{trial_user.email}. Reason: #{inspect(reason)}"
        )

        conn
        |> put_status(500)
        |> json(%{
          success: false,
          error: "Failed to send OTP email"
        })
    end
  end
end
