defmodule Glific.Saas.Onboard do
  @moduledoc """
  For now, we will build this on top of organization table, and have a group of helper functions
  here to manage global operations across all organizations.
  At some later point, we might decide to have a separate onboarding table and managment structure
  """

  require Logger
  import GlificWeb.Gettext

  alias Glific.{
    Communications.Mailer,
    Contacts.Contact,
    Mails.NewPartnerOnboardedMail,
    Notion,
    Partners,
    Partners.Billing,
    Partners.Organization,
    Partners.Saas,
    Registrations,
    Registrations.Registration,
    Repo,
    Saas.Queries
  }

  # 1 year
  @forced_suspension_hrs 8760
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
  Updates the registration details and send submission mail to user
  """
  @spec update_registration(map(), Organization.t()) :: map()
  def update_registration(%{"registration_id" => reg_id} = params, org) do
    result = %{is_valid: true, messages: %{}}

    with {:ok, registration} <- Registrations.get_registration(reg_id),
         %{is_valid: true} = result <- Queries.validate_registration_details(result, params) do
      {:ok, registration} = update_registration_details(params, registration)

      {:ok, org} = update_org_details(org, params, registration)

      process_on_submission(result, org, registration)
      |> Map.put(:registration, Registration.to_minimal_map(registration))
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

    update_organization_billing(organization)
  end

  @spec organization_status(atom(), map()) :: map()
  defp organization_status(:active, changes) do
    changes
    |> add_map(:is_active, true)
    |> add_map(:is_approved, true)
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
  Delete an organization from the DB, ensure that the confirmed flag is set
  since this is a super destructive operation
  """
  @spec delete(non_neg_integer, boolean) ::
          {:ok, Organization.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def delete(delete_organization_id, true) do
    organization = Partners.get_organization!(delete_organization_id)

    # ensure that the organization is not active, our last check before we
    # blow it away
    if organization.is_active do
      {:error, "Organization is still active"}
    else
      Partners.delete_organization(organization)
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

  @spec process_on_submission(map(), Organization.t(), Registration.t()) :: map()
  defp process_on_submission(result, org, %{has_submitted: true} = registration) do
    with %{is_valid: true} = result <- Queries.eligible_for_submission?(result, registration) do
      Task.start(fn ->
        notify_on_submission(org, registration)
        notify_saas_team(org)

        Notion.update_table_properties(registration)
        |> then(&Notion.update_database_entry(registration.notion_page_id, &1))
      end)

      result
    end
  end

  defp process_on_submission(result, _org, _registration), do: result

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
          "Error sending NGO reachout query email #{inspect(error)} for org: #{org.id}"
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
end
