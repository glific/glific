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
    Partners,
    Partners.Billing,
    Partners.Organization,
    Registrations,
    Registrations.Registration,
    Repo,
    Saas.Queries
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
  Updates the registration details and send submission mail to user
  """
  @spec update_registration(map()) :: map()
  def update_registration(%{"registration_id" => reg_id} = params) when is_integer(reg_id) do
    result = %{is_valid: true, messages: %{}}

    with {:ok, registration} <- Registrations.get_registration(reg_id),
         %{is_valid: true} <- Queries.validate_registration_details(result, params) do
      {:ok, registration} = Registrations.update_registation(registration, params)

      if is_map(params["signing_authority"]) do
        {:ok, _org} =
          update_org_email(registration.organization_id, params["signing_authority"]["email"])
      end

      notify_on_submission(params["has_submitted"] || false)

      result
      |> Map.put(:registration, Registration.to_minimal_map(registration))
      |> Map.put(:support_mail, "glific.user@gmail.com")
    else
      {:error, _} ->
        dgettext("error", "Registration doesn't exist for given registration ID.")
        |> Queries.error(result, :registration_id)

      err ->
        err
    end
  end

  def update_registration(_params) do
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
    |> notify_user_queries()
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

  @spec notify_saas_team(map()) :: map()
  defp notify_saas_team(%{is_valid: true} = results) do
    NewPartnerOnboardedMail.new_mail(results.organization)
    |> Mailer.send(%{
      category: "new_partner_onboarded",
      organization_id: results.organization.id
    })
    |> case do
      {:ok, _} ->
        results

      error ->
        Glific.log_error(
          "Error sending new partner onboarded email #{inspect(error)} for org: #{inspect(results)}"
        )
    end

    results
  end

  defp notify_saas_team(results), do: results

  @spec update_org_email(non_neg_integer(), String.t()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  defp update_org_email(org_id, email) do
    changes = %{
      email: email
    }

    Partners.get_organization!(org_id)
    |> Partners.update_organization(changes)
  end

  # TODO: spec needed
  # TODO: send mail later

  defp notify_on_submission(false), do: :ok

  defp notify_on_submission(true) do
    :ok
  end

  defp notify_user_queries(results) do
    # TODO: Implement this.
    results
  end
end
