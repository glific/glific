defmodule Glific.Saas.Onboard do
  @moduledoc """
  For now, we will build this on top of organization table, and have a group of helper functions
  here to manage global operations across all organizations.
  At some later point, we might decide to have a separate onboarding table and managment structure
  """
  alias Glific.{
    Communications.Mailer,
    Contacts.Contact,
    Mails.NewPartnerOnboardedMail,
    Partners,
    Partners.Billing,
    Partners.Organization,
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
    |> format_results()
    |> notify_saas_team()
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
    {:ok, _} =
      NewPartnerOnboardedMail.new_mail(results.organization)
      |> Mailer.send(%{
        category: "new_partner_onboarded",
        organization_id: results.organization.id
      })

    results
  end

  defp notify_saas_team(results), do: results
end
