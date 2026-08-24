defmodule Glific.Saas.Queries do
  @moduledoc """
  Lets keep all the onboarding queries and validation here
  """
  use Gettext, backend: GlificWeb.Gettext
  import Ecto.Query
  require Logger

  alias Glific.{
    Contacts,
    Contacts.Contact,
    ERP,
    Flows.FlowContext,
    Flows.FlowResult,
    Messages.Message,
    Partners,
    Partners.Organization,
    Partners.Provider,
    Providers.Gupshup.PartnerAPI,
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
        error(Glific.SafeLog.safe_inspect(error_message), result, :global)
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
        error(Glific.SafeLog.safe_inspect(errors), result, :global)
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
        error(Glific.SafeLog.safe_inspect(errors), result, :global)
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
      {:ok, credential} ->
        # This will be case in onboarding v2

        Map.put(result, :credential, credential)

      {:error, errors} ->
        error(Glific.SafeLog.safe_inspect(errors), result, :global)
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
    case PartnerAPI.fetch_gupshup_app_details(app_name: app_name) do
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
         {:error, _} <-
           Repo.fetch_by(Organization, %{shortcode: shortcode},
             skip_organization_id: true,
             include_deleted: true
           ) do
      result
    else
      {:ok, _} ->
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

  @spec delete_migration_if_exists(String.t()) :: any()
  defp delete_migration_if_exists(tenant) do
    query =
      from schema in "schema_seeds",
        where: schema.tenant == ^tenant

    Repo.delete_all(query, skip_organization_id: true)
  end
end
