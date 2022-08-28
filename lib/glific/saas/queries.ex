defmodule Glific.Saas.Queries do
  @moduledoc """
  Lets keep all the onboarding queries and validation here
  """
  import GlificWeb.Gettext
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.FlowContext,
    Flows.FlowResult,
    Messages.Message,
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient,
    Providers.GupshupContacts,
    Repo,
    Seeds.Seeder,
    Seeds.SeedsMigration,
    Users
  }

  alias Pow.Ecto.Schema.Changeset

  @doc """
  Main function to setup the organization entity in Glific
  """
  @spec setup(map(), map()) :: map()
  def setup(result, params) do
    result
    # first create the organization
    |> organization(params)
    # then create the contact and associate contact with organization
    |> contact(params)
    # create the credentials
    |> credentials(params)
  end

  @doc """
  Validate all the input elements
  """
  @spec validate(map(), map()) :: map()
  def validate(result, params) do
    result
    |> validate_bsp_keys(params)
    |> validate_shortcode(params["shortcode"])
    |> validate_email(params["email"])
    |> validate_phone(params["phone"])
  end

  @doc """
  Seed data for organization
  """
  @spec seed_data(map()) :: map()

  def seed_data(%{organization: organization} = results) when is_map(organization) do
    Seeder.seed(tenant: organization.shortcode, tenant_id: organization.id)
    results
  end

  def seed_data(results), do: results

  @doc """
  Seed data for organization
  """
  @spec sync_templates(map()) :: map()
  def sync_templates(%{organization: organization} = results) when is_map(organization) do
    SeedsMigration.migrate_data(:submit_common_otp_template, organization)
    SeedsMigration.migrate_data(:sync_hsm_templates, organization)
    results
  end

  def sync_templates(results), do: results

  @spec organization(map(), map()) :: map()
  defp organization(%{is_valid: false} = result, _params), do: result

  defp organization(result, params) do
    attrs = %{
      name: params["name"],
      shortcode: params["shortcode"],
      email: params["email"],
      bsp_id: 1,
      default_language_id: 1,
      active_language_ids: [1],
      timezone: "Asia/Kolkata",
      is_active: false,
      is_approved: false,
      status: :inactive
    }

    case Partners.create_organization(attrs) do
      {:ok, organization} ->
        Repo.put_organization_id(organization.id)
        Map.put(result, :organization, organization)

      {:error, errors} ->
        error(inspect(errors), result, :global)
    end
  end

  @spec contact(map(), map()) :: map()
  defp contact(%{is_valid: false} = result, _params), do: result

  defp contact(result, params) do
    attrs = %{
      name: "NGO Main Account",
      phone: params["phone"],
      language_id: result.organization.default_language_id,
      organization_id: result.organization.id
    }

    password = Ecto.UUID.generate()

    case Contacts.create_contact(attrs) do
      {:ok, contact} ->
        Users.create_user(
          Map.merge(attrs, %{
            password: password,
            confirm_password: password,
            roles: ["admin"],
            contact_id: contact.id,
            last_login_at: DateTime.utc_now(),
            last_login_from: "127.0.0.1",
            organization_id: result.organization.id
          })
        )

        {:ok, organization} =
          Partners.update_organization(
            result.organization,
            %{contact_id: contact.id}
          )

        result
        |> Map.put(:organization, organization)
        |> Map.put(:contact, contact)

      {:error, errors} ->
        error(inspect(errors), result, :global)
    end
  end

  @spec credentials(map(), map()) :: map()
  defp credentials(%{is_valid: false} = result, _params), do: result

  defp credentials(result, params) do
    attrs = %{
      shortcode: "gupshup",
      keys: %{
        "url" => "https://gupshup.io/",
        "worker" => "Glific.Providers.Gupshup.Worker",
        "handler" => "Glific.Providers.Gupshup.Message",
        "bsp_limit" => 40,
        "api_end_point" => "https://api.gupshup.io/sm/api/v1"
      },
      secrets: %{
        "api_key" => params["api_key"],
        "app_name" => params["app_name"],
        "app_id" => params["app_id"] || "NA"
      },
      is_active: true,
      organization_id: result.organization.id
    }

    case Partners.create_credential(attrs) do
      {:ok, credential} ->
        Map.put(result, :credential, credential)

      {:error, errors} ->
        error(inspect(errors), result, :global)
    end
  end

  @spec error(String.t(), map(), atom()) :: map()
  defp error(message, result, key) do
    result
    |> Map.put(:is_valid, false)
    |> Map.update!(:messages, fn msgs -> Map.put(msgs, key, message) end)
  end

  # [message | msgs]
  # return if a string is nil or empty
  @spec empty(String.t() | nil) :: boolean
  defp empty(str), do: is_nil(str) || str == ""

  # Validate the APIKey and AppName entered by the organization. We will use the gupshup
  # opt-in url which requires both and ensure that it returns success to validate these two
  # parameters
  @spec validate_bsp_keys(map(), map()) :: map()
  defp validate_bsp_keys(result, params) do
    api_key = params["api_key"]
    app_name = params["app_name"]

    if empty(api_key) || empty(app_name) do
      dgettext("error", "API Key or App Name is empty.")
      |> error(result, :api_key_name)
    else
      validate_bsp_keys(result, api_key, app_name)
    end
  end

  @spec validate_bsp_keys(map(), String.t(), String.t()) :: map()
  defp validate_bsp_keys(result, api_key, app_name) do
    response =
      ApiClient.users_get(api_key, app_name)
      |> GupshupContacts.validate_opted_in_contacts()

    case response do
      {:ok, _users} -> result
      {:error, message} -> error(message, result, :app_name)
    end
  end

  # Ensure this shortcode is currently not being used
  @spec validate_shortcode(map(), String.t()) :: map()
  defp validate_shortcode(result, nil) do
    dgettext("error", "Shortcode cannot be empty.") |> error(result, :shortcode)
  end

  defp validate_shortcode(result, shortcode) do
    Repo.fetch_by(Organization, %{shortcode: shortcode}, skip_organization_id: true)
    |> case do
      {:ok, _} ->
        dgettext("error", "Shortcode has already been taken.")
        |> error(result, :shortcode)

      {:error, _} ->
        result
    end
  end

  @spec validate_email(map(), String.t()) :: map()
  defp validate_email(result, email) do
    case Changeset.validate_email(email) do
      :ok ->
        result

      _ ->
        dgettext("error", "Email is not valid.")
        |> error(result, :email)
    end
  end

  @spec validate_phone(map(), String.t()) :: map()
  defp validate_phone(result, phone) do
    case ExPhoneNumber.parse(phone, "IN") do
      {:ok, _phone} ->
        result

      _ ->
        dgettext("error", "Phone is not valid.")
        |> error(result, :phone)
    end
  end

  @doc """
  Reset selected data of an organization which could potentially be considered test
  data
  """
  @spec reset(non_neg_integer) :: {:ok | :error, String.t()}
  def reset(reset_organization_id) do
    reset_organization_id
    |> reset_table(Message)
    |> reset_table(FlowResult)
    |> reset_table(FlowContext)
    |> reset_contact_fields()

    {:ok, "Reset Data for Organization"}
  end

  @spec reset_table(non_neg_integer, atom()) :: non_neg_integer
  defp reset_table(reset_organization_id, object) do
    object
    |> where([o], o.organization_id == ^reset_organization_id)
    |> Repo.delete_all(skip_organization_id: true)

    reset_organization_id
  end

  @spec reset_contact_fields(non_neg_integer) :: non_neg_integer
  defp reset_contact_fields(reset_organization_id) do
    Contact
    |> where([c], c.organization_id == ^reset_organization_id)
    |> Repo.update_all(set: [fields: %{}, settings: %{}])

    reset_organization_id
  end
end
