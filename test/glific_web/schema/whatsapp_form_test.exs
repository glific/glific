defmodule GlificWeb.Schema.WhatsappFormTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
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

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_whatsapp_forms(organization)
  end

  test "seed_whatsapp_forms creates forms that are visible during the test",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: %{"status" => "success"}}
    end)

    _result =
      auth_query_gql_by(:publish_whatsapp_form, user,
        variables: %{"id" => "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"}
      )

    {:ok, sign_up_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    assert sign_up_form.status == :published
  end

  test "seed_whatsapp_forms creates forms that are visible during the test qand akfwdfa",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: %{"status" => "sucesss"}}
    end)

    _result =
      auth_query_gql_by(:deactivate_wa_form, user,
        variables: %{"formId" => "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"}
      )

    {:ok, contact_form} =
      Repo.fetch_by(Glific.WhatsappForms.WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    assert contact_form != nil
    assert contact_form.status == :inactive
  end
end
