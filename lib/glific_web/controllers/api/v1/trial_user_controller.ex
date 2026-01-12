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
    with {:ok, parsed_phone} <- Contacts.parse_phone_number(phone),
         {:ok, trial_user} <-
           create_or_handle_existing_trial_user(
             username,
             email,
             parsed_phone,
             organization_name
           ),
         {:ok, _result} <- send_otp_to_trial_user(trial_user, username) do
      json(conn, %{
        data: %{message: "OTP sent successfully to #{trial_user.email}"}
      })
    else
      {:error, :already_registered} ->
        json(conn, %{
          success: false,
          error: "Email or phone already registered"
        })

      {:error, error_message} when is_binary(error_message) ->
        conn
        |> put_status(400)
        |> json(%{success: false, error: error_message})

      {:error, :email_send_failed, reason} ->
        Logger.error("Failed to send OTP email. Reason: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{success: false, error: "Failed to send OTP email"})

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("Failed to create trial account. Errors: #{inspect(changeset.errors)}")

        conn
        |> put_status(400)
        |> json(%{success: false, error: "Failed to create trial account"})
    end
  end

  @spec create_or_handle_existing_trial_user(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, TrialUsers.t()} | {:error, term()}
  defp create_or_handle_existing_trial_user(username, email, phone, organization_name) do
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

  @spec handle_existing_user(String.t(), String.t()) ::
          {:ok, TrialUsers.t()} | {:error, :already_registered}
  defp handle_existing_user(email, phone) do
    existing_user =
      TrialUsers
      |> where([t], t.email == ^email or t.phone == ^phone)
      |> Repo.one(skip_organization_id: true)

    if existing_user.otp_entered do
      {:error, :already_registered}
    else
      {:ok, existing_user}
    end
  end

  @spec send_otp_to_trial_user(TrialUsers.t(), String.t()) ::
          {:ok, term()} | {:error, :email_send_failed, term()}
  defp send_otp_to_trial_user(trial_user, username) do
    code = PasswordlessAuth.generate_code(trial_user.phone)
    org = Saas.organization_id() |> Partners.get_organization!()

    case TrialAccountMail.otp_verification_mail(org, trial_user.email, code, username)
         |> Mailer.send(%{
           category: "trial_otp_verification",
           organization_id: org.id
         }) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, :email_send_failed, reason}
    end
  end
end
