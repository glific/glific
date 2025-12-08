defmodule GlificWeb.API.V1.TrialAccountController do
  @moduledoc """
  Controller for allocating trial accounts to users via an API endpoint.
  """
  use GlificWeb, :controller

  alias Glific.{
    Partners.Organization,
    Repo,
    Users,
    Users.User,
    Contacts,
    Contacts.Contact
  }

  alias GlificWeb.API.V1.RegistrationController

  import Ecto.Query

  @doc """
  Allocates a trial account to a user.
  """
  @spec trial(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def trial(conn, params) do
    token = get_req_header(conn, "x-api-key") |> List.first()
    expected_token = get_token()

    if token == expected_token do
      phone = params["phone"]

      with {:ok, _message} <-
             RegistrationController.verify_otp(phone, params["otp"]),
           {:ok, organization} <- get_available_trial_account(),
           {:ok, contact} <- create_trial_contact(organization, phone, params),
           {:ok, _user} <-
             create_trial_user(organization, contact, phone, params) do
        json(conn, %{
          success: true,
          data: %{
            login_url: "https://#{organization.shortcode}.glific.com"
          }
        })
      else
        {:error, error_list} when is_list(error_list) ->
          conn
          |> json(%{
            success: false,
            error: "Invalid OTP"
          })

        {:error, :no_available_accounts} ->
          json(conn, %{
            success: false,
            error: "No trial accounts available at the moment"
          })

        {:error, _} ->
          conn
          |> json(%{
            success: false,
            error: "Something went wrong"
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{success: false, error: "Invalid API token"})
    end
  end

  @spec get_available_trial_account() ::
          {:ok, Organization.t()} | {:error, :no_available_accounts | Ecto.Changeset.t()}
  defp get_available_trial_account do
    Repo.transaction(fn ->
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
        nil ->
          Repo.rollback(:no_available_accounts)

        org ->
          expiration_date =
            DateTime.utc_now()
            |> DateTime.truncate(:second)
            |> DateTime.add(14, :day)

          case Ecto.Changeset.change(org, %{
                 trial_expiration_date: expiration_date
               })
               |> Repo.update() do
            {:ok, updated_org} -> updated_org
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  @spec create_trial_contact(Organization.t(), String.t(), map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp create_trial_contact(organization, phone, params) do
    contact_params = %{
      phone: phone,
      name: params["name"],
      organization_id: organization.id,
      language_id: organization.default_language_id
    }

    Contacts.create_contact(contact_params)
  end

  @spec create_trial_user(Organization.t(), Contact.t(), String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defp create_trial_user(organization, contact, phone, params) do
    user_params = %{
      name: params["name"],
      phone: phone,
      password: params["password"],
      confirm_password: params["password"],
      roles: ["admin"],
      organization_id: organization.id,
      language_id: organization.default_language_id,
      last_login_at: DateTime.utc_now(),
      last_login_from: "127.0.0.1",
      contact_id: contact.id
    }

    Users.create_user(user_params)
  end

  @spec get_token() :: String.t()
  defp get_token, do: Application.fetch_env!(:glific, __MODULE__)[:trial_account_token]
end
