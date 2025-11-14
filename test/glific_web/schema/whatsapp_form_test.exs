defmodule GlificWeb.Schema.WhatsappFormTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Repo,
    Seeds.SeedsDev,
    WhatsappForms.WhatsappForm
  }

  load_gql(
    :publish_whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/publish_whatsapp_form.gql"
  )

  load_gql(
    :deactivate_whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/deactivate_whatsapp_form.gql"
  )

  load_gql(
    :count_whatsapp_forms,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/count.gql"
  )

  load_gql(
    :list_whatsapp_forms,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/list.gql"
  )

  load_gql(
    :whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/get.gql"
  )

  load_gql(
    :delete_whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/delete.gql"
  )

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_whatsapp_forms(organization)
  end

  test "published a whatsapp form and updates its status to published",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: %{"status" => "success"}}
    end)

    {:ok, sign_up_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    _result =
      auth_query_gql_by(:publish_whatsapp_form, user, variables: %{"id" => sign_up_form.id})

    {:ok, updated_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    assert updated_form.status == :published
  end

  test "deactivates a whatsapp form and updates its status to inactive",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: %{"status" => "success"}}
    end)

    {:ok, sign_up_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    _result =
      auth_query_gql_by(:deactivate_whatsapp_form, user, variables: %{"id" => sign_up_form.id})

    {:ok, updated_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    assert updated_form.status == :inactive
  end

  test "fails to deactivate WhatsApp form if the form does not exist",
       %{manager: user} do
    {:ok, %{data: %{"deactivateWhatsappForm" => %{"errors" => [error | _]}}}} =
      auth_query_gql_by(:deactivate_whatsapp_form, user, variables: %{"id" => "318182039810832"})

    assert error["message"] ==
             "Resource not found"
  end

  test "fails to publish WhatsApp form if the form does not exist",
       %{manager: user} do
    {:ok, %{data: %{"publishWhatsappForm" => %{"errors" => [error | _]}}}} =
      auth_query_gql_by(:publish_whatsapp_form, user, variables: %{"id" => "318182039810832"})

    assert error["message"] ==
             "Resource not found"
  end

  test "count returns the number of whatsapp forms", %{manager: user} do
    {:ok, query_data1} =
      auth_query_gql_by(:count_whatsapp_forms, user,
        variables: %{"filter" => %{"name" => "sign_up_form"}}
      )

    assert query_data1.data["countWhatsappForms"] == 1

    {:ok, query_data3} =
      auth_query_gql_by(:count_whatsapp_forms, user,
        variables: %{"filter" => %{"meta_flow_id" => "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"}}
      )

    assert query_data3.data["countWhatsappForms"] == 1

    {:ok, query_data4} =
      auth_query_gql_by(:count_whatsapp_forms, user,
        variables: %{"filter" => %{"status" => "DRAFT"}}
      )

    assert query_data4.data["countWhatsappForms"] == 2
  end

  test "list WhatsApp forms with different filters applied", %{manager: user} do
    {:ok, query} =
      auth_query_gql_by(:list_whatsapp_forms, user,
        variables: %{"filter" => %{"name" => "sign_up_form"}}
      )

    [form] = query.data["listWhatsappForms"]
    assert form["name"] == "sign_up_form"
    assert form["metaFlowId"] == "flow-9e3bf3f2-0c9f-4a8b-bf23-33b7e5d2fbb2"
    assert form["status"] == "PUBLISHED"
  end

  test "retrieves a WhatsApp form by ID", %{manager: user} do
    {:ok, answer} = Repo.fetch_by(WhatsappForm, %{name: "newsletter_subscription_form"})

    {:ok, query} =
      auth_query_gql_by(:whatsapp_form, user, variables: %{"whatsappFormId" => answer.id})

    assert query.data["whatsappForm"]["whatsappForm"]["metaFlowId"] ==
             "flow-2a73be22-0a11-4a6d-bb77-8c21df5cdb92"

    assert query.data["whatsappForm"]["whatsappForm"]["status"] == "DRAFT"
    assert query.data["whatsappForm"]["whatsappForm"]["id"] == "#{answer.id}"

    assert query.data["whatsappForm"]["whatsappForm"]["description"] ==
             "Draft form to collect email subscriptions for newsletters"
  end

  test "returns an error when a WhatsApp form with the given ID is not found", %{manager: user} do
    {:ok, %{data: %{"whatsappForm" => %{"errors" => [error | _]}}}} =
      auth_query_gql_by(:whatsapp_form, user, variables: %{"whatsappFormId" => "712398717432"})

    assert error["message"] == "Resource not found"
  end

  test "deletes a WhatsApp form by ID", %{manager: user} do
    {:ok, form} = Repo.fetch_by(WhatsappForm, %{name: "newsletter_subscription_form"})

    {:ok, query} =
      auth_query_gql_by(:delete_whatsapp_form, user, variables: %{"id" => form.id})

    assert query.data["deleteWhatsappForm"]["whatsappForm"]["id"] == "#{form.id}"

    {:error, _} = Repo.fetch_by(WhatsappForm, %{id: form.id})
  end

  test "delete a whatsApp form that does not exist returns an error", %{manager: user} do
    {:ok, %{data: %{"deleteWhatsappForm" => %{"errors" => [error | _]}}}} =
      auth_query_gql_by(:delete_whatsapp_form, user, variables: %{"id" => "9999999"})

    assert error["message"] == "Resource not found"
  end
end
