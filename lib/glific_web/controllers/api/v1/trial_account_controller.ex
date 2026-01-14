defmodule GlificWeb.API.V1.TrialAccountController do
  @moduledoc """
  Controller for allocating trial accounts to users via an API endpoint.
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.{
    Communications.Mailer,
    Contacts,
    Contacts.Contact,
    Mails.TrialAccountMail,
    Partners,
    Partners.Organization,
    Repo,
    TrialUsers,
    Users,
    Users.User
  }

  alias Ecto.Multi
  alias Glific.Metrics
  alias GlificWeb.API.V1.RegistrationController

  import Ecto.Query

  @doc """
  Allocates a trial account to a user.
  """
  @spec trial(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def trial(conn, params) do
    phone = params["phone"]

    with {:ok, _message} <-
           RegistrationController.verify_otp(phone, params["otp"]),
         {:ok, result} <- allocate_trial_account(phone, params) do
      organization = result.update_organization

      send_trial_account_emails(:success, organization, result.update_trial_user)
      Metrics.increment("Trial Account allocated")

      json(conn, %{
        success: true,
        data: %{
          login_url: "https://#{organization.shortcode}.glific.com/login"
        }
      })
    else
      {:error, error_list} when is_list(error_list) ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Invalid OTP"
        })

      {:error, :organization, :no_available_accounts, _changes} ->
        org = Partners.get_organization!(1)

        attrs = %TrialUsers{
          username: params["username"],
          email: params["email"],
          phone: params["phone"],
          organization_name: params["organization_name"]
        }

        send_trial_account_emails(
          :allocation_failed,
          org,
          attrs
        )

        conn
        |> json(%{
          success: false,
          error:
            "Thank you for your interest in exploring Glific.

          Apologies, at the moment, all our trial accounts are currently in use. Our Sales team will reach out to you shortly to discuss alternative options."
        })

      {:error, failed_step, reason, _changes} ->
        Logger.error(
          "Trial account allocation failed at #{failed_step}, reason: #{inspect(reason)}"
        )

        conn
        |> put_status(500)
        |> json(%{
          success: false,
          error: "Something went wrong"
        })
    end
  end

  @spec allocate_trial_account(String.t(), map()) ::
          {:ok, map()} | {:error, atom(), any(), map()}
  defp allocate_trial_account(phone, params) do
    Multi.new()
    |> Multi.run(:organization, fn _repo, _changes ->
      get_and_lock_trial_org()
    end)
    |> Multi.run(:update_organization, fn _repo, %{organization: org} ->
      update_trial_expiration(org)
    end)
    |> Multi.run(:contact, fn _repo, %{update_organization: org} ->
      create_contact(org, phone, params)
    end)
    |> Multi.run(:user, fn _repo, %{update_organization: org, contact: contact} ->
      create_user(org, contact, phone, params)
    end)
    |> Multi.run(:update_trial_user, fn _repo, _changes ->
      mark_otp_entered(phone)
    end)
    |> Repo.transaction()
  end

  @spec get_and_lock_trial_org() ::
          {:ok, Organization.t()} | {:error, :no_available_accounts}
  defp get_and_lock_trial_org do
    available_org =
      from(o in Organization,
        where: o.is_trial_org == true,
        where: is_nil(o.trial_expiration_date),
        order_by: [asc: o.id],
        limit: 1,
        lock: "FOR UPDATE"
      )
      |> Repo.one(skip_organization_id: true)

    case available_org do
      nil -> {:error, :no_available_accounts}
      org -> {:ok, org}
    end
  end

  @spec update_trial_expiration(Organization.t()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  defp update_trial_expiration(org) do
    expiration_date =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(14, :day)

    org
    |> Ecto.Changeset.change(%{trial_expiration_date: expiration_date})
    |> Repo.update()
  end

  @spec create_contact(Organization.t(), String.t(), map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp create_contact(organization, phone, params) do
    contact_params = %{
      phone: phone,
      name: params["username"],
      organization_id: organization.id,
      language_id: organization.default_language_id
    }

    Contacts.create_contact(contact_params)
  end

  @spec create_user(Organization.t(), Contact.t(), String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defp create_user(organization, contact, phone, params) do
    user_params = %{
      name: params["username"],
      phone: phone,
      password: params["password"],
      confirm_password: params["password"],
      roles: ["admin"],
      organization_id: organization.id,
      language_id: organization.default_language_id,
      last_login_at: nil,
      last_login_from: "127.0.0.1",
      contact_id: contact.id
    }

    Users.create_user(user_params)
  end

  @spec mark_otp_entered(String.t()) :: {:ok, TrialUsers.t()} | {:error, :not_found}
  defp mark_otp_entered(phone) do
    trial_user =
      from(t in TrialUsers,
        where: t.phone == ^phone
      )
      |> Repo.one(skip_organization_id: true)

    case trial_user do
      nil ->
        {:error, :not_found}

      user ->
        TrialUsers.update_trial_user(user, %{otp_entered: true})
    end
  end

  @spec send_trial_account_emails(
          :success | :allocation_failed,
          Organization.t(),
          TrialUsers.t()
        ) :: :ok
  defp send_trial_account_emails(:success, organization, trial_user) do
    TrialAccountMail.welcome_to_trial_account(organization, trial_user)
    |> Mailer.send(%{
      category: "trial_user_welcome",
      organization_id: organization.id
    })

    TrialAccountMail.trial_account_allocated(organization, trial_user)
    |> Mailer.send(%{
      category: "new_trial_account_allocated",
      organization_id: organization.id
    })

    :ok
  end

  defp send_trial_account_emails(:allocation_failed, organization, trial_user) do
    TrialAccountMail.trial_account_allocation_failed(organization, trial_user)
    |> Mailer.send(%{
      category: "trial_account_allocation_failed",
      organization_id: 1
    })

    :ok
  end
end
