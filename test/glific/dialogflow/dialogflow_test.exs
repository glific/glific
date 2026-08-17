defmodule Glific.DialogflowTest do
  @moduledoc false
  use Glific.DataCase, async: false

  alias Glific.{
    Dialogflow,
    Partners,
    Partners.Credential,
    Partners.Provider,
    Repo
  }

  test "get_intent_list/1 returns cleanly instead of raising when service_account is nil",
       %{organization_id: organization_id} = _attrs do
    {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "dialogflow"})

    {:ok, _credential} =
      %Credential{}
      |> Credential.changeset(%{
        secrets: %{"service_account" => nil},
        is_active: true,
        provider_id: provider.id,
        organization_id: organization_id
      })
      |> Repo.insert()

    organization = Partners.organization(organization_id)
    Partners.remove_organization_cache(organization_id, organization.shortcode)
    Glific.Caches.remove(organization_id, [{:provider_token, "dialogflow"}])

    assert {:ok, "no token found"} == Dialogflow.get_intent_list(organization_id)
  end

  test "get_intent_list/1 returns cleanly instead of raising when service_account is valid JSON but not an object",
       %{organization_id: organization_id} = _attrs do
    {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "dialogflow"})

    {:ok, _credential} =
      %Credential{}
      |> Credential.changeset(%{
        secrets: %{"service_account" => "[]"},
        is_active: true,
        provider_id: provider.id,
        organization_id: organization_id
      })
      |> Repo.insert()

    organization = Partners.organization(organization_id)
    Partners.remove_organization_cache(organization_id, organization.shortcode)
    Glific.Caches.remove(organization_id, [{:provider_token, "dialogflow"}])

    assert {:ok, "no token found"} == Dialogflow.get_intent_list(organization_id)
  end
end
