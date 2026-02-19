defmodule Glific.Saas.Onboard do
  @moduledoc """
  For now, we will build this on top of organization table, and have a group of helper functions
  here to manage global operations across all organizations.
  At some later point, we might decide to have a separate onboarding table and managment structure
  """

  require Logger
  use Gettext, backend: GlificWeb.Gettext
  import Ecto.Query, warn: false

  alias Glific.{
    Communications.Mailer,
    Contacts.Contact,
    Erase,
    ERP,
    Mails.NewPartnerOnboardedMail,
    Notion,
    Partners,
    Partners.Billing,
    Partners.Credential,
    Partners.Organization,
    Partners.Saas,
    Registrations,
    Registrations.Registration,
    Repo,
    Saas.Queries,
    Seeds.SeedsMigration,
    ThirdParty.Kaapi,
    Users.User
  }

  alias Pow.Ecto.Schema.Password
  # 1 year
  @forced_suspension_hrs 8760

  @dummy_phone_number "91783481114"

  @type setup_params :: %{
          (name :: String.t()) => String.t(),
          (email :: String.t()) => String.t(),
          optional(shortcode :: String.t()) => String.t()
        }
  @doc """
  Setup all the tables and necessary values to onboard an organization
  """
  @spec setup(map()) :: map()
  def setup(params) do
    %{is_valid: true, messages: %{}}
    |> Queries.validate(params)
    |> Queries.setup(params)
    |> Queries.seed_data()
    |> format_results()
  end

  @doc """
  V2 of setup/1, where email and name are the only mandatory values we need to provide

  example argument %{"email" => "foo@bar.com", "name" => "test"}
  for trial org %{"email" => "foo@bar.com", "name" => "trial_org", "is_trial" => true}

  Optionally we can provide "shortcode" too, incase system generated shortcode
  has any validation issue.
  """
  @spec setup_v2(setup_params()) :: map()
  def setup_v2(params) do
    params =
      Map.merge(params, %{
        "phone" => @dummy_phone_number,
        "api_key" => nil,
        "app_name" => nil,
        "app_id" => nil,
        "is_trial" => Map.get(params, "is_trial", false)
      })

    result = %{is_valid: true, messages: %{}}

    with %{is_valid: true} <- Queries.validate_onboard_params(result, params),
         shortcode <- generate_shortcode(params["name"], params["shortcode"]),
         %{is_valid: true} <- Queries.validate_shortcode(result, shortcode),
         %{is_valid: true} = result <-
           Queries.setup_v2(result, params |> Map.put("shortcode", shortcode)) do
      Repo.put_process_state(result.organization.id)
      Queries.seed_data(result)
      SeedsMigration.migrate_data(:template_flows, result.organization)
      org = status(result.organization.id, :active)
      notify_saas_team(result.organization)
      setup_kaapi_for_organization(result.organization)

      if params["is_trial"] do
        setup_gcs(result.organization)
      end

      Map.put(result, :organization, org)
    end
  end

  @spec generate_shortcode(String.t(), String.t() | nil) :: String.t()
  defp generate_shortcode(org_name, nil) do
    name_parts = String.split(org_name, " ")

    if length(name_parts) > 1 do
      Enum.map_join(name_parts, fn parts -> String.first(parts) end)
    else
      org_name
    end
    |> String.slice(0..7)
    |> String.downcase()
  end

  defp generate_shortcode(_org_name, shortcode), do: shortcode

  @doc """
  Updates the registration details and send submission mail to user
  """
  @spec update_registration(map(), Organization.t()) :: map()
  def update_registration(%{"registration_id" => reg_id} = params, org) do
    result = %{is_valid: true, messages: %{}}

    with {:ok, registration} <- Registrations.get_registration(reg_id),
         %{is_valid: true} = result <- Queries.validate_registration_details(result, params) do
      {:ok, registration} = update_registration_details(params, registration)
      {:ok, org} = update_org_details(org, params, registration)

      process_result = process_on_submission(result, org, registration)

      if Map.get(process_result, :is_valid, true) do
        Map.put(process_result, :registration, Registration.to_minimal_map(registration))
      else
        process_result
      end
    else
      {:error, _} ->
        dgettext("error", "Registration doesn't exist for given registration ID.")
        |> Queries.error(result, :registration_id)

      result ->
        result
    end
  end

  def update_registration(_params, _org) do
    result = %{is_valid: false, messages: %{}}

    dgettext("error", "Registration ID is empty.")
    |> Queries.error(result, :registration_id)
  end

  @doc """
  Send the queries to support mail
  """
  @spec reachout(map()) :: map()
  def reachout(params) do
    %{is_valid: true, messages: %{}}
    |> Queries.validate_reachout_details(params)
    |> notify_user_queries(params)
  end

  @doc """
  Returns the ip of client

  conn - Plug.Conn object
  """
  @spec get_client_ip(Plug.Conn.t()) :: String.t()
  def get_client_ip(conn) do
    Plug.Conn.get_req_header(conn, "x-forwarded-for")
    |> List.first()
    |> case do
      nil -> conn.remote_ip |> :inet_parse.ntoa() |> to_string()
      forwaded_ips -> String.split(forwaded_ips, ",") |> Enum.map(&String.trim/1) |> List.first()
    end
  end

  @spec add_map(map(), atom(), any()) :: map()
  defp add_map(map, _key, nil), do: map
  defp add_map(map, key, value), do: Map.put(map, key, value)

  @doc """
  Update the active and/or approved status of an organization
  """
  @spec status(non_neg_integer, atom()) :: Organization.t() | nil
  def status(update_organization_id, status) do
    changes =
      status
      |> organization_status(add_map(%{}, :status, status))

    {:ok, organization} =
      update_organization_id
      |> Partners.get_organization!()
      |> Partners.update_organization(changes)

    # When the status of an organization is changed from suspension the cached data,
    # still contains the old is_suspended flag (set to true)This prevents HSM messages
    # from being sent in the function Glific.Contacts.can_send_message_to?/2. To ensure the
    # updated suspension details is reflected, the cache must be cleared after updating the organization's status.
    Partners.remove_organization_cache(organization.id, organization.shortcode)
    update_organization_billing(organization)
  end

  @spec organization_status(atom(), map()) :: map()
  defp organization_status(:active, changes) do
    changes
    |> add_map(:is_active, true)
    |> add_map(:is_approved, true)
    |> add_map(:is_suspended, false)
    |> Map.put(:suspended_until, nil)
  end

  defp organization_status(:approved, changes) do
    changes
    |> add_map(:is_active, false)
    |> add_map(:is_approved, true)
  end

  defp organization_status(:forced_suspension, changes) do
    changes
    |> add_map(:is_suspended, true)
    |> add_map(:suspended_until, Timex.shift(DateTime.utc_now(), hours: @forced_suspension_hrs))
  end

  defp organization_status(_, changes) do
    changes
    |> add_map(:is_active, false)
    |> add_map(:is_approved, false)
  end

  @spec update_organization_billing(Organization.t()) :: Organization.t()
  defp update_organization_billing(%{is_active: false} = organization) do
    # putting organization id in process as this operation is used by glific_admin for other organizations
    Repo.put_process_state(organization.id)

    with billing <- Billing.get_billing(%{organization_id: organization.id}),
         false <- is_nil(billing),
         true <- billing.is_active do
      Billing.update_subscription(billing, organization)
    else
      _ -> organization
    end
  end

  defp update_organization_billing(organization), do: organization

  @doc """
  Soft delete an organization: deletes all related data and sets deleted_at timestamp.
  Ensure that the confirmed flag is set since this is a destructive operation.
  """
  @spec delete(non_neg_integer, boolean) ::
          {:ok, Organization.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def delete(delete_organization_id, true) do
    organization = Partners.get_organization!(delete_organization_id)

    # ensure that the organization is not active, our last check before we
    # delete its data
    if organization.is_active do
      {:error, "Organization is still active"}
    else
      with :ok <- Erase.delete_all_organization_data(delete_organization_id) do
        Partners.delete_organization(organization)
      end
    end
  end

  def delete(_delete_organization_id, false), do: {:error, "Cannot delete organization"}

  @doc """
  Reset a few tables and fields for an organization, so they can get rid of all the test data and experiments.
  As dangerous as delete, so also needs confirmation
  """
  @spec reset(non_neg_integer, boolean) :: {:ok | :error, String.t()}
  def reset(reset_organization_id, true) do
    Queries.reset(reset_organization_id)
  end

  def reset(_, false), do: {:error, "Cannot reset organization data"}

  @spec format_results(map()) :: map()
  defp format_results(%{is_valid: true} = results) do
    results
    |> Map.put(:organization, Organization.to_minimal_map(results.organization))
    |> Map.put(:contact, Contact.to_minimal_map(results.contact))
    |> Map.put(:credential, "Gupshup secrets has been added.")
  end

  defp format_results(results), do: results

  @spec notify_saas_team(Organization.t()) :: map()
  defp notify_saas_team(org) do
    if !org.is_trial_org do
      NewPartnerOnboardedMail.new_mail(org)
      |> Mailer.send(%{
        category: "new_partner_onboarded",
        organization_id: org.id
      })
      |> case do
        {:ok, _} ->
          org

        error ->
          Glific.log_error(
            "Error sending new partner onboarded email #{inspect(error)} for org: #{inspect(org.id)}"
          )
      end
    end
  end

  @spec process_on_submission(map(), Organization.t(), Registration.t()) :: map()
  defp process_on_submission(result, org, %{has_submitted: true} = registration) do
    with %{is_valid: true} = result <- Queries.eligible_for_submission?(result, registration),
         {:ok, erp_response} <- ERP.update_organization(registration) do
      notify_on_submission(org, registration)
      notify_saas_team(org)

      Task.start(fn ->
        Notion.update_table_properties(registration)
        |> then(&Notion.update_database_entry(registration.notion_page_id, &1))
      end)

      Map.put(result, :erp_response, erp_response)
    else
      {:error, erp_error} ->
        Map.put(result, :is_valid, false)
        |> Map.put(:error, erp_error)

      _ ->
        Map.put(result, :is_valid, false)
        |> Map.put(:error, "Unexpected response from ERP update")
    end
  end

  defp process_on_submission(result, _org, _registration), do: result

  @doc """
  Updates password_hash field of passed org_id with hashed password generated via Glific.Password
  """
  @spec update_ngo_password(non_neg_integer()) :: {:error, String.t()} | {:ok, String.t()}
  def update_ngo_password(org_id) do
    now = DateTime.utc_now()
    {:ok, password} = Passgen.create!(length: 15, numbers: true, uppercase: true, lowercase: true)
    password_hash = Password.pbkdf2_hash(password)
    Glific.Repo.put_process_state(org_id)

    User
    |> where([user], user.organization_id == ^org_id)
    |> where([user], user.name == "NGO Main Account")
    |> update([user], set: [password_hash: ^password_hash, updated_at: ^now])
    |> Repo.update_all([])
    |> case do
      # expecting one data cell change
      {1, _} ->
        {:ok, "User was successfully updated"}

      err ->
        {:error, "Error updating password due to #{inspect(err)}"}
    end
  end

  @spec notify_on_submission(Organization.t(), Registration.t()) :: any()
  defp notify_on_submission(org, registration) do
    Map.put(%{}, "submitter", registration.submitter)
    |> Map.put("signing_authority", registration.signing_authority)
    |> NewPartnerOnboardedMail.confirmation_mail()
    |> Mailer.send(%{
      category: "Onboarding_confirmation",
      organization_id: org.id
    })
    |> case do
      {:ok, _} ->
        :ok

      error ->
        Glific.log_error(
          "Error sending submission confirmation email #{inspect(error)} for org: #{org.id}"
        )
    end
  end

  @spec notify_user_queries(map(), map()) :: map()
  defp notify_user_queries(%{is_valid: false} = results, _params), do: results

  defp notify_user_queries(results, params) do
    org = Saas.organization_id() |> Partners.get_organization!()

    NewPartnerOnboardedMail.user_query_mail(params, org)
    |> Mailer.send(%{
      category: "onboard_ngo_query",
      organization_id: org.id
    })
    |> case do
      {:ok, _} ->
        results

      error ->
        Glific.log_error(
          "Error sending NGO reachout query email #{inspect(error)} for org: #{inspect(org.id)}"
        )
    end

    results
  end

  @spec update_registration_details(map(), Registration.t()) ::
          {:ok, Registration.t()} | {:error, Ecto.Changeset.t()}
  defp update_registration_details(params, registration) do
    # updates the `Dispute in T&C` column in Notion whenever user disagrees with T&C
    confirm_terms_acceptance(params["terms_agreed"], registration)
    params = update_is_disputed(params, registration)

    case params do
      %{"org_details" => org_details} ->
        Map.put(
          params,
          "org_details",
          Map.merge(registration.org_details, org_details)
        )

      _ ->
        params
    end
    |> then(&Registrations.update_registation(registration, &1))
  end

  @spec update_org_details(Organization.t(), map(), Registration.t()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  defp update_org_details(
         org,
         %{"signing_authority" => signing_authority} = _params,
         registration
       )
       when is_map(signing_authority) do
    team_emails =
      Enum.reduce(org.team_emails, %{}, fn {key, _val}, team_emails ->
        case key do
          "finance" ->
            Map.put(team_emails, key, registration.finance_poc["email"])

          key ->
            Map.put(team_emails, key, signing_authority["email"])
        end
      end)

    changes = %{
      email: signing_authority["email"],
      team_emails: team_emails
    }

    Partners.update_organization(org, changes)
  end

  defp update_org_details(org, _params, _registration), do: {:ok, org}

  @spec confirm_terms_acceptance(boolean() | nil, Registration.t()) :: any()
  defp confirm_terms_acceptance(false, registration) do
    Task.start(fn ->
      Notion.update_tc_dispute_property()
      |> then(&Notion.update_database_entry(registration.notion_page_id, &1))
    end)
  end

  defp confirm_terms_acceptance(_terms_agreed, _registration), do: :ok

  @spec update_is_disputed(map(), Registration.t()) :: map()
  defp update_is_disputed(params, registration) do
    case {params["terms_agreed"], registration.is_disputed} do
      {false, _} -> Map.put(params, "is_disputed", true)
      _ -> params
    end
  end

  defp setup_kaapi_for_organization(organization) do
    open_ai_key = Glific.get_open_ai_key()

    %{
      organization_id: organization.id,
      organization_name: organization.parent_org || organization.name,
      project_name: organization.shortcode,
      openai_api_key: open_ai_key
    }
    |> Kaapi.onboard()
  end

  @spec setup_gcs(Organization.t()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  defp setup_gcs(trial_org) do
    org_id = Saas.organization_id()

    task =
      Task.async(fn ->
        Repo.put_process_state(org_id)

        Partners.get_credential(%{
          organization_id: org_id,
          shortcode: "google_cloud_storage"
        })
      end)

    {:ok, cred} = Task.await(task)

    Partners.create_credential(%{
      organization_id: trial_org.id,
      shortcode: "google_cloud_storage",
      keys: %{},
      secrets: cred.secrets,
      is_active: true
    })
  end
end
