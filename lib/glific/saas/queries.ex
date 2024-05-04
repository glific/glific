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
    Partners.Provider,
    Providers.Gupshup.ApiClient,
    Providers.GupshupContacts,
    Registrations,
    Repo,
    Seeds.Seeder,
    Seeds.SeedsMigration,
    Users
  }

  alias Pow.Ecto.Schema.Changeset

  @default_provider "gupshup"

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
    # create registration details
    |> registration(params)
  end

  @doc """
  Validate all the input elements
  """
  @spec validate(map(), map()) :: map()
  def validate(result, params) do
    result
    |> validate_bsp_keys(params)
    |> validate_shortcode(params["shortcode"])
    |> validate_phone(params["phone"])
    |> validate_text_field(params["gstin"], :gstin, {15, 15}, true)
    |> validate_text_field(
      params["registered_address"],
      :registered_address,
      {1, 300}
    )
    |> validate_text_field(params["current_address"], :current_address, {0, 300})
    |> validate_registration_document(params["registration_doc_link"])
  end

  @spec validate_registration_details(map(), map()) :: map()
  def validate_registration_details(result, params) do
    Enum.reduce(params, result, fn {key, value}, result ->
      case key do
        "billing_frequency" ->
          validate_billing_frequency(result, value)

        "finance_poc" ->
          validate_finance_poc(result, value)

        "submitter" ->
          validate_submitter_details(result, value)

        "signing_authority" ->
          validate_signer_details(result, value)

        _ ->
          result
      end
    end)
  end

  @spec validate_reachout_details(map(), map()) :: map()
  def validate_reachout_details(result, params) do
    result
    |> validate_text_field(params["name"], :name, {1, 25})
    |> validate_text_field(params["message"], :message, {1, 300})
    |> validate_email(params["email"] || "")
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

  @spec validate_text_field(map(), String.t(), atom(), {number(), number()}, boolean()) :: map()
  defp validate_text_field(result, field, key, length, optional \\ false)
  defp validate_text_field(result, nil, _key, {_min_len, _max_len}, true), do: result

  defp validate_text_field(result, field, key, {min_len, max_len}, _optional) do
    cond do
      empty(field) ->
        dgettext("error", "Field cannot be empty.", key: key)
        |> error(result, key)

      String.length(field) < min_len ->
        dgettext("error", "Field cannot be less than %{length} letters.",
          key: key,
          length: min_len
        )
        |> error(result, key)

      String.length(field) > max_len ->
        dgettext("error", "Field cannot be more than %{length} letters.",
          key: key,
          length: max_len
        )
        |> error(result, key)

      true ->
        result
    end
  end

  @spec validate_registration_document(map(), String.t()) :: map()
  defp validate_registration_document(result, document_link) do
    cond do
      empty(document_link) ->
        dgettext("error", "Url cannot be empty.", key: :registration_doc_link)
        |> error(result, :registration_doc_link)

      String.starts_with?(document_link, "https://storage.googleapis.com") == false ->
        dgettext("error", "Url should start with https://storage.googleapis.com.",
          key: :registration_doc_link
        )
        |> error(result, :registration_doc_link)

      true ->
        result
    end
  end

  @spec organization(map(), map()) :: map()
  defp organization(%{is_valid: false} = result, _params), do: result

  defp organization(result, params) do
    {:ok, provider} =
      Repo.fetch_by(Provider, %{shortcode: @default_provider, group: "bsp"},
        skip_organization_id: true
      )

    attrs = %{
      name: params["name"],
      shortcode: params["shortcode"],
      email: params["email"],
      bsp_id: provider.id,
      default_language_id: 1,
      active_language_ids: [1],
      timezone: "Asia/Kolkata",
      is_active: false,
      is_approved: false,
      status: :inactive,
      parent_org: params["name"],
      setting: %{"send_warning_mail" => false, "run_flow_each_time" => false},
      team_emails: %{
        "finance" => params["email"],
        "analytics" => params["email"],
        "chatbot_design" => params["email"]
      }
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

    password = (Ecto.UUID.generate() |> binary_part(16, 16)) <> "-ABC!"

    case Contacts.create_contact(attrs) do
      {:ok, contact} ->
        {:ok, _user} =
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
      shortcode: @default_provider,
      keys: %{
        "url" => "https://gupshup.io/",
        "worker" => "Glific.Providers.Gupshup.Worker",
        "handler" => "Glific.Providers.Gupshup.Message",
        "bsp_limit" => 40,
        "api_end_point" => "https://api.gupshup.io/wa/api/v1"
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
        Partners.set_bsp_app_id(result.organization, @default_provider)
        Map.put(result, :credential, credential)

      {:error, errors} ->
        error(inspect(errors), result, :global)
    end
  end

  @doc """
  Updates the error map
  """
  @spec error(String.t(), map(), atom()) :: map()
  def error(message, result, key) do
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

  @spec validate_email(map(), String.t(), atom()) :: map()
  defp validate_email(result, email, key \\ :email) do
    case Changeset.validate_email(email) do
      :ok ->
        result

      _ ->
        dgettext("error", "Email is not valid.")
        |> error(result, key)
    end
  end

  @spec validate_phone(map(), String.t(), atom()) :: map()
  defp validate_phone(result, phone, key \\ :phone) do
    case ExPhoneNumber.parse(phone, "IN") do
      {:ok, _phone} ->
        result

      _ ->
        dgettext("error", "Phone is not valid.")
        |> error(result, key)
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

  @spec registration(map(), map()) :: map()
  defp registration(%{is_valid: false} = result, _params), do: result

  defp registration(result, params) do
    org_details = %{
      name: params["name"],
      gstin: params["gstin"],
      registration_document: params["registration_doc_link"],
      registered_address: params["registered_address"],
      current_address: params["current_address"]
    }

    platform_details = %{
      api_key: params["api-key"],
      app_name: params["ngo"],
      phone: params["phone"],
      shortcode: params["shortcode"]
    }

    %{
      org_details: org_details,
      organization_id: result.organization.id,
      platform_details: platform_details
    }
    |> Registrations.create_registration()
    |> case do
      {:ok, %{id: id}} ->
        Map.put(result, :registration_id, id)

      {:error, errors} ->
        error(inspect(errors), result, :registration)
    end
  end

  @spec validate_billing_frequency(map(), String.t()) :: map()
  defp validate_billing_frequency(result, value) when is_binary(value) do
    cond do
      empty(value) ->
        dgettext("error", "Billing frequency cannot be empty.")
        |> error(result, :billing_frequency)

      value not in ["yearly", "monthly", "quarterly"] ->
        dgettext("error", "Value should be one of yearly, monthly, or quarterly.")
        |> error(result, :billing_frequency)

      true ->
        result
    end
  end

  @spec validate_finance_poc(map(), map()) :: map()
  defp validate_finance_poc(result, params) do
    result
    |> validate_text_field(params["name"], :finance_poc_name, {1, 25})
    |> validate_text_field(params["designation"], :finance_poc_designation, {1, 25})
    |> validate_phone(params["phone"], :finance_poc_phone)
    |> validate_email(params["email"], :finance_poc_email)
  end

  @spec validate_submitter_details(map(), map()) :: map()
  defp validate_submitter_details(result, params) do
    result
    |> validate_text_field(params["name"], :submitter_name, {1, 25})
    |> validate_email(params["email"], :submitter_name)
  end

  @spec validate_signer_details(map(), map()) :: map()
  defp validate_signer_details(result, params) do
    result
    |> validate_text_field(params["name"], :signer_name, {1, 25})
    |> validate_text_field(params["designation"], :signer_designation, {1, 25})
    |> validate_email(params["email"], :signer_email)
  end
end
