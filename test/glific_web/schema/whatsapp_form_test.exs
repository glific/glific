defmodule GlificWeb.Schema.WhatsappFormTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Providers.Gupshup.WhatsappForms.ApiClient,
    Repo,
    Seeds.SeedsDev
  }

  load_gql(
    :publish_whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/publish_wa_form.gql"
  )

  load_gql(
    :deactivate_wa_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/deactivate_wa_form.gql"
  )

  @flow_id "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
  @org_id 1
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
        %Tesla.Env{status: 200, body: %{"status" => "sucess"}}
    end)

    {:ok, sign_up_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    _result =
      auth_query_gql_by(:deactivate_wa_form, user, variables: %{"formId" => sign_up_form.id})

    {:ok, updated_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    assert updated_form.status == :inactive
  end

  test "fails to deactivate WhatsApp form if the form does not exist",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: %{"status" => "sucess"}}
    end)

    {:ok, _sign_up_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    {:ok, %{errors: [error | _]}} =
      auth_query_gql_by(:deactivate_wa_form, user, variables: %{"formId" => "231222222"})

    assert error.message == "WhatsApp form not found"
  end

  test "fails to published WhatsApp form if the form does not exist",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: %{"status" => "success"}}
    end)

    {:ok, _sign_up_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    {:ok, %{errors: [error | _]}} =
      auth_query_gql_by(:publish_whatsapp_form, user, variables: %{"id" => "318182039810832"})

    assert error.message == "Failed to publish WhatsApp Form: WhatsApp Form not found"
  end

  test "fails to publish WhatsApp form due to invalid request" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{"error" => "Invalid flow ID"}
        }
    end)

    assert {:error, body} = ApiClient.publish_wa_form(@flow_id, @org_id)
    assert body["error"] == "Invalid flow ID"
  end
end
