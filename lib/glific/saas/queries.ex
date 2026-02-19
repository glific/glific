defmodule Glific.Saas.Queries do
  @moduledoc """
  Lets keep all the onboarding queries and validation here
  """
  use Gettext, backend: GlificWeb.Gettext
  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Contacts,
    Contacts.Contact,
    ERP,
    Flows.FlowContext,
    Flows.FlowResult,
    Messages.Message,
    Notion,
    Partners,
    Partners.Organization,
    Partners.Provider,
    Providers.Gupshup.PartnerAPI,
    Registrations,
    Registrations.Registration,
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
  Main function to setup the organization entity in Glific
  """
  @spec setup_v2(map(), map()) :: map()
  def setup_v2(result, params) do
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
    |> validate_phone(params["phone"])
    |> validate_text_field(params["name"], :name, {1, 250})
  end

  @doc """
  Validate all the details regarding NGO registration
  """
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

        "org_details" ->
          validate_org_details(result, value)

        _ ->
          result
      end
    end)
  end

  @doc """
  Validate reachout query params
  """
  @spec validate_reachout_details(map(), map()) :: map()
  def validate_reachout_details(result, params) do
    result
    |> validate_text_field(params["name"], :name, {1, 100})
    |> validate_text_field(params["message"], :message, {1, 300})
    |> validate_text_field(params["org_name"], :org_name, {1, 250}, true)
    |> validate_email(params["email"] || "")
  end

  @doc """
  Seed data for organization
  """
  @spec seed_data(map()) :: map()

  def seed_data(%{organization: organization} = results) when is_map(organization) do
    # Sometime we delete an org and create new org with the same previous shortcode.
    # But seeding won't work for the new org, since its already done(seeding is based on shortcode).
    # so we delete existing migrations in that case.
    delete_migration_if_exists(organization.shortcode)
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

  @doc """
  Validates if all the required fields are filled before submission
  """
  @spec eligible_for_submission?(map(), Registration.t()) :: map()
  def eligible_for_submission?(result, registration) do
    registration_map = Map.from_struct(registration)

    [:org_details, :finance_poc, :submitter, :signing_authority]
    |> Enum.reduce_while(result, fn key, result ->
      if is_nil(registration_map[key]) do
        result =
          dgettext("error", "Field cannot be empty.")
          |> error(result, key)

        {:halt, result}
      else
        {:cont, result}
      end
    end)
    |> validate_true(registration.terms_agreed, :terms_agreed)
    |> validate_true(registration.support_staff_account, :support_staff_account)
  end

  @spec validate_text_field(map(), String.t(), atom(), {number(), number()}, boolean()) :: map()
  defp validate_text_field(result, field, key, length, optional \\ false)

  defp validate_text_field(result, field, _key, {_min_len, _max_len}, true)
       when field in [nil, ""],
       do: result

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

  @spec organization(map(), map()) :: map()
  defp organization(%{is_valid: false} = result, _params), do: result

  defp organization(result, params) do
    org_name = String.trim(params["name"])
    is_trial = params["is_trial"] == true

    # Skip ERP check for trial accounts
    erp_result =
      if is_trial do
        {:ok, nil}
      else
        ERP.fetch_organization_detail(org_name)
      end

    case erp_result do
      {:ok, erp_data} ->
        customer_name = if is_map(erp_data), do: erp_data[:data][:customer_name], else: nil
        do_create_organization(result, params, org_name, customer_name, is_trial)

      {:error, error_message} ->
        error(inspect(error_message), result, :global)
    end
  end

  @spec do_create_organization(map(), map(), String.t(), String.t() | nil, boolean()) :: map()
  defp do_create_organization(result, params, org_name, erp_page_id, is_trial) do
    {:ok, provider} =
      Repo.fetch_by(Provider, %{shortcode: @default_provider, group: "bsp"},
        skip_organization_id: true
      )

    attrs = %{
      name: org_name,
      shortcode: String.downcase(params["shortcode"]),
      email: params["email"],
      bsp_id: provider.id,
      default_language_id: 1,
      active_language_ids: [1],
      timezone: "Asia/Kolkata",
      is_active: false,
      is_approved: false,
      parent_org: params["name"],
      is_trial_org: is_trial,
      setting: %{
        "send_warning_mail" => false,
        "run_flow_each_time" => false,
        "allow_bot_number_update" => true
      },
      signature_phrase: "Please change me, NOW!",
      team_emails: %{
        "finance" => params["email"],
        "analytics" => params["email"],
        "chatbot_design" => params["email"],
        "operations" => params["email"]
      }
    }

    case Partners.create_organization(attrs) do
      {:ok, organization} ->
        Repo.put_organization_id(organization.id)

        result
        |> Map.put(:organization, organization)
        |> Map.put_new(:erp_page_id, erp_page_id)

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

    {:ok, password} =
      Passgen.create!(length: 15, numbers: true, uppercase: true, lowercase: true, symbols: true)

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
        "bsp_limit" => 40
      },
      secrets: %{
        "api_key" => params["api_key"] || "NA",
        "app_name" => params["app_name"] || "NA",
        "app_id" => params["app_id"] || "NA"
      },
      is_active: true,
      organization_id: result.organization.id
    }

    case Partners.create_credential(attrs) do
      {:ok, %{secrets: %{"app_name" => "NA"}} = credential} ->
        # This will be case in onboarding v2

        Map.put(result, :credential, credential)

      {:ok, _credential} ->
        update_bsp_id(result)

      {:error, errors} ->
        error(inspect(errors), result, :global)
    end
  end

  @spec update_bsp_id(map()) :: map()
  defp update_bsp_id(result) do
    case Partners.set_bsp_app_id(result.organization, @default_provider) do
      {:ok, credential} ->
        Map.put(result, :credential, credential)

      {:error, error} ->
        error(error, result, :global)
    end
  end

  @doc """
  Updates the error map
  """
  @spec error(String.t(), map(), atom() | String.t()) :: map()
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
      validate_app(result, app_name)
    end
  end

  @spec validate_app(map(), String.t()) :: map()
  defp validate_app(result, app_name) do
    case PartnerAPI.fetch_gupshup_app_details(app_name) do
      resp when is_map(resp) -> result
      _ -> error("Invalid Gupshup App", result, :app_name)
    end
  end

  @doc """
  Validates organization shortocode
  """
  @spec validate_shortcode(map(), String.t()) :: map()
  def validate_shortcode(result, nil) do
    dgettext("error", "Shortcode cannot be empty.") |> error(result, :shortcode)
  end

  def validate_shortcode(result, shortcode) do
    with true <- Regex.match?(~r/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/, shortcode),
         nil <-
           Organization
           |> where([o], o.shortcode == ^shortcode and is_nil(o.deleted_at))
           |> Repo.one(skip_organization_id: true) do
      result
    else
      %Organization{} ->
        dgettext("error", "Shortcode has already been taken.")
        |> error(result, :shortcode)

      _ ->
        dgettext(
          "error",
          "Invalid shortcode. It should match the regex /^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/."
        )
        |> error(result, :shortcode)
    end
  end

  @doc """
  Validate onboarding params such as email and org name
  """
  @spec validate_onboard_params(map(), map()) :: result :: map()
  def validate_onboard_params(result, params) do
    result
    |> validate_text_field(params["name"], :name, {1, 250})
    |> validate_email(params["email"], :email)
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
      name: params["name"]
    }

    platform_details = %{
      api_key: params["api_key"],
      app_name: params["app_name"],
      phone: params["phone"],
      shortcode: params["shortcode"]
    }

    registration_map = %{
      org_details: org_details,
      organization_id: result.organization.id,
      platform_details: platform_details,
      ip_address: params["client_ip"],
      erp_page_id: result |> Map.get(:erp_page_id)
    }

    registration_map
    |> Registrations.create_registration()
    |> case do
      {:ok, %{id: id} = registration} ->
        :ok = create_registration_in_notion(result.organization.id, registration)
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

      value not in ["Monthly", "Quarterly", "Half-Yearly", "Annually"] ->
        dgettext("error", "Value should be one of Monthly , Quarterly, Half-Yearly, Annually.")
        |> error(result, :billing_frequency)

      true ->
        result
    end
  end

  @spec validate_finance_poc(map(), map()) :: map()

  defp validate_finance_poc(result, params) do
    result
    |> validate_text_field(params["name"], :finance_poc_name, {1, 100})
    |> validate_text_field(params["designation"], :finance_poc_designation, {1, 100})
    |> validate_phone(params["phone"], :finance_poc_phone)
    |> validate_email(params["email"], :finance_poc_email)
  end

  @spec validate_submitter_details(map(), map()) :: map()

  defp validate_submitter_details(result, params) do
    result
    |> validate_text_field(params["first_name"], :submitter_name, {1, 100})
    |> validate_email(params["email"], :submitter_name)
  end

  @spec validate_signer_details(map(), map()) :: map()

  defp validate_signer_details(result, params) do
    result
    |> validate_text_field(params["name"], :signer_name, {1, 100})
    |> validate_text_field(params["designation"], :signer_designation, {1, 100})
    |> validate_email(params["email"], :signer_email)
  end

  @spec validate_org_details(map(), map()) :: map()

  defp validate_org_details(result, params) do
    current_address = params["current_address"]
    registered_address = params["registered_address"]

    result
    |> validate_text_field(params["gstin"], :gstin, {15, 15}, true)
    |> validate_address_fields(registered_address, :registered_address)
    |> validate_address_fields(current_address, :current_address)
  end

  @spec validate_address_fields(map(), map(), atom()) :: map()
  defp validate_address_fields(result, address_map, field_prefix) do
    result
    |> validate_text_field(address_map["address_line1"], :"#{field_prefix}_line1", {1, 300})
    |> validate_text_field(address_map["city"], :"#{field_prefix}_city", {1, 100})
    |> validate_text_field(address_map["pincode"], :"#{field_prefix}_pincode", {1, 10})
  end

  @spec create_registration_in_notion(String.t(), Registration.t()) :: :ok
  defp create_registration_in_notion(org_id, registration) do
    {:ok, _} =
      Task.start(fn ->
        Repo.put_process_state(org_id)
        properties = Notion.init_table_properties(registration)

        with {:ok, page_id} <- Notion.create_database_entry(properties) do
          Registrations.update_registation(registration, %{notion_page_id: page_id})
        end
      end)

    :ok
  end

  @spec validate_true(map(), boolean(), atom()) :: map()
  defp validate_true(results, false, key) do
    dgettext("error", "Field cannot be false.")
    |> error(results, key)
  end

  defp validate_true(results, _, _key), do: results

  @spec delete_migration_if_exists(String.t()) :: any()
  defp delete_migration_if_exists(tenant) do
    query =
      from schema in "schema_seeds",
        where: schema.tenant == ^tenant

    Repo.delete_all(query, skip_organization_id: true)
  end
end
