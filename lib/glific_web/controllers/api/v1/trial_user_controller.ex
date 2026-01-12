defmodule GlificWeb.API.V1.TrialUsersController do
  @moduledoc """
  Controller for allocating trial users to users via an API endpoint.
  """
  use GlificWeb, :controller
  require Logger
  alias PasswordlessAuth
  alias Plug.Conn
  alias Glific.Metrics

  alias Glific.{
    Communications.Mailer,
    Contacts,
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
    case Contacts.parse_phone_number(phone) do
      {:ok, phone} ->
        handle_trial_user_creation(
          conn,
          username,
          email,
          phone,
          organization_name
        )

      {:error, error_message} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: error_message
        })
    end
  end

  @spec handle_trial_user_creation(Conn.t(), String.t(), String.t(), String.t(), String.t()) ::
          Conn.t()
  defp handle_trial_user_creation(
         conn,
         username,
         email,
         phone,
         organization_name
       ) do
    trial_user_attrs = %{
      username: username,
      email: email,
      phone: phone,
      organization_name: organization_name
    }

    case TrialUsers.create_trial_user(trial_user_attrs) do
      {:ok, trial_user} ->
        Metrics.increment("Trial user created")
        send_otp_email(conn, trial_user, username)

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if has_unique_constraint_error?(errors) do
          handle_existing_user(conn, email, phone, username)
        else
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
  end

  @spec has_unique_constraint_error?(keyword()) :: boolean()
  defp has_unique_constraint_error?(errors) do
    Enum.any?(errors, fn
      {_field, {_, [constraint: :unique, constraint_name: _]}} -> true
      _ -> false
    end)
  end

  @spec handle_existing_user(Conn.t(), String.t(), String.t(), String.t()) :: Conn.t()
  defp handle_existing_user(conn, email, phone, username) do
    existing_user =
      TrialUsers
      |> where([t], t.email == ^email or t.phone == ^phone)
      |> Repo.one(skip_organization_id: true)

    if existing_user.otp_entered do
      conn
      |> json(%{
        success: false,
        error: "Email or phone already registered"
      })
    else
      Logger.info("Resending OTP to existing unverified user: #{email}")
      send_otp_email(conn, existing_user, username)
    end
  end

  @spec send_otp_email(Conn.t(), TrialUsers.t(), String.t()) :: Conn.t()
  defp send_otp_email(conn, trial_user, username) do
    code = PasswordlessAuth.generate_code(trial_user.phone)
    org = Saas.organization_id() |> Partners.get_organization!()
    email = trial_user.email

    TrialAccountMail.otp_verification_mail(org, email, code, username)
    |> Mailer.send(%{
      category: "trial_otp_verification",
      organization_id: org.id
    })
    |> case do
      {:ok, _result} ->
        Metrics.increment("Trial OTP sent")

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
