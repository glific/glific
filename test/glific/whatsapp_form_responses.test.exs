defmodule Glific.WhatsappFormResponsesTest do
  use GlificWeb.ConnCase
  import Mock

  alias Glific.{
    Partners,
    Repo,
    Seeds.SeedsDev,
    Templates,
    WhatsappForms.WhatsappForm,
    WhatsappFormsResponses
  }

  setup do
    Tesla.Mock.mock(fn
      %{method: :get, url: url} when is_binary(url) ->
        %Tesla.Env{
          status: 200,
          body:
            "timestamp,contact_phone_number,whatsapp_form_id,whatsapp_form_name,field1,field2\n"
        }

      %{method: :get, url: nil} ->
        {:error, :invalid_url}

      %{method: :post, url: _url} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
              "updates" => %{
                "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                "updatedRange" => "Sheet1!A1:F1",
                "updatedRows" => 1,
                "updatedColumns" => 6,
                "updatedCells" => 6
              }
            })
        }
    end)

    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_whatsapp_forms(organization)

    {:ok, _temp} =
      Templates.create_session_template(%{
        label: "Whatsapp Form Template",
        type: :text,
        body: "Hello World",
        language_id: 1,
        organization_id: organization.id,
        uuid: "3982792f-a178-442d-be4b-3eadbb804726",
        buttons: [
          %{
            "text" => "RATE",
            "type" => "FLOW",
            "flow_id" => "flow-8f91de44-b123-482e-bb52-77f1c3a78df0",
            "flow_action" => "NAVIGATE",
            "navigate_screen" => "RATE"
          }
        ]
      })

    %{organization_id: organization.id}
  end

  @valid_attrs_for_create %{
    status: :received,
    type: :whatsapp_form_response,
    body: "",
    organization_id: 1,
    flow: :inbound,
    bsp_status: :delivered,
    sender: %{name: "abc", phone: "9876543210_1", contact_type: "WABA"},
    bsp_message_id: "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0EzRTUwQjRGQzg4NTgxOTBCODMA",
    sender_id: 2,
    receiver_id: 1,
    context_id: "031U5mGKSgDZdXxdrtBEa2",
    template_id: "3982792f-a178-442d-be4b-3eadbb804726",
    raw_response:
      "{\"flow_token\":\"unused\",\"screen_1_Customer_service_2\":\"2_Average\",\"screen_0_Choose_one_0\":\"0_Yes\",\"screen_1_Delivery_and_setup_1\":\"0_Excellent\",\"screen_1_Purchase_experience_0\":\"1_Good\"}",
    submitted_at: "1765956142"
  }

  @valid_attrs_for_headers %{
    id: 1,
    organization_id: 1,
    submitted_at: ~U[2025-12-16 08:24:15.000000Z],
    raw_response: %{
      "flow_token" => "unused",
      "screen_0_Choose_one_0" => "0_Yes",
      "screen_1_Customer_service_2" => "1_Good",
      "screen_1_Delivery_and_setup_1" => "3_Poor",
      "screen_1_Purchase_experience_0" => "2_Average"
    },
    contact_id: 2,
    whatsapp_form_id: 2,
    whatsapp_form_name: "contact_us_form",
    contact_number: "9876543210_1",
    inserted_at: ~U[2025-12-16 12:31:58.211190Z],
    updated_at: ~U[2025-12-16 12:31:58.211190Z]
  }

  test "create_whatsapp_form_response/1 creates a whatsapp form response",
       %{organization_id: organization_id} do
    attrs = Map.put(@valid_attrs_for_create, :organization_id, organization_id)

    whatsapp_form =
      Repo.get_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

    {:ok, whatsapp_form_response} =
      WhatsappFormsResponses.create_whatsapp_form_response(attrs)

    assert whatsapp_form_response.whatsapp_form_id == whatsapp_form.id
    assert whatsapp_form_response.contact_id == attrs.sender_id

    assert whatsapp_form_response.raw_response ==
             Jason.decode!(attrs.raw_response)
  end

  test "prepare_row_from_headers/1 creates a correct headers",
       %{organization_id: organization_id} do
    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
      end
    ) do
      sheet_attrs = %{
        shortcode: "google_sheets",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "DEFAULT PROJECT ID",
              private_key_id: "DEFAULT API KEY",
              client_email: "DEFAULT CLIENT EMAIL",
              private_key: "DEFAULT PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: organization_id
      }

      Partners.create_credential(sheet_attrs)

      expected_headers = [
        "timestamp",
        "contact_phone_number",
        "whatsapp_form_id",
        "whatsapp_form_name",
        "screen_1_Purchase_experience_0",
        "screen_1_Delivery_and_setup_1",
        "screen_1_Customer_service_2",
        "screen_0_Choose_one_0"
      ]

      with_mock(
        Glific.Sheets.GoogleSheets,
        [],
        get_headers: fn _org_id, _spreadsheet_id -> {:ok, expected_headers} end
      ) do
        {:ok, ordered_row} =
          WhatsappFormsResponses.prepare_row_from_headers(
            @valid_attrs_for_headers,
            "1234678904004"
          )

        assert length(ordered_row) == length(expected_headers)

        assert Enum.at(ordered_row, 1) == to_string(@valid_attrs_for_headers.contact_number)
        assert Enum.at(ordered_row, 2) == to_string(@valid_attrs_for_headers.whatsapp_form_id)
      end
    end
  end
end
