defmodule Glific.WhatsappFormResponsesTest do
  use GlificWeb.ConnCase
  import Mock
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Messages,
    Partners,
    Repo,
    Seeds.SeedsDev,
    Templates,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormWorker,
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

    {:ok, temp} =
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

    {:ok, _temp_message} =
      Messages.create_message(%{
        body: "Hello| [Open] ",
        flow: :outbound,
        type: :text,
        sender_id: 1,
        receiver_id: 2,
        contact_id: 1,
        organization_id: organization.id,
        bsp_message_id: "0e74fb92-eb8a-415a-bccd-42ee768665e0",
        template_id: temp.id
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
    context_id: "0e74fb92-eb8a-415a-bccd-42ee768665e0",
    template_id: "3982792f-a178-442d-be4b-3eadbb804726",
    raw_response:
      "{\"flow_token\":\"unused\",\"screen_1_Customer_service_2\":\"2_Average\",\"screen_0_Choose_one_0\":\"0_Yes\",\"screen_1_Delivery_and_setup_1\":\"0_Excellent\",\"screen_1_Purchase_experience_0\":\"1_Good\"}",
    submitted_at: "1765956142"
  }

  test "create_whatsapp_form_response/1 creates a whatsapp form response",
       %{organization_id: organization_id, global_schema: global_schema} do
    Tesla.Mock.mock(fn
      %{method: :get, url: url} when is_binary(url) ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "values" => [
                [
                  "timestamp",
                  "contact_phone_number",
                  "whatsapp_form_id",
                  "whatsapp_form_name",
                  "screen_0_Choose_one_0",
                  "screen_1_Purchase_experience_0",
                  "screen_1_Delivery_and_setup_1",
                  "screen_1_Customer_service_2"
                ]
              ]
            })
        }

      %{method: :post, url: _url} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
              "updates" => %{
                "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                "updatedRange" => "A1:A1",
                "updatedRows" => 1,
                "updatedColumns" => 1,
                "updatedCells" => 1
              }
            })
        }
    end)

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

      attrs = Map.put(@valid_attrs_for_create, :organization_id, organization_id)

      whatsapp_form =
        Repo.get_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

      {:ok, whatsapp_form_response} =
        WhatsappFormsResponses.create_whatsapp_form_response(attrs)

      assert_enqueued(worker: WhatsappFormWorker, prefix: global_schema)

      assert whatsapp_form_response.whatsapp_form_id == whatsapp_form.id
      assert whatsapp_form_response.contact_id == attrs.sender_id

      assert whatsapp_form_response.raw_response ==
               Jason.decode!(attrs.raw_response)

      assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :default)
    end
  end

  test "write_to_google_sheet/2 returns error when Google API is not active",
       %{organization_id: organization_id} do
    Tesla.Mock.mock(fn
      %{method: :get, url: url} when is_binary(url) ->
        %Tesla.Env{
          status: 403,
          body:
            Jason.encode!(%{
              "error" => %{
                "code" => 403,
                "message" => "The caller does not have permission",
                "status" => "PERMISSION_DENIED"
              }
            })
        }

      %{method: :post, url: _url} ->
        %Tesla.Env{
          status: 403,
          body:
            Jason.encode!(%{
              "error" => %{
                "code" => 403,
                "message" => "The caller does not have permission",
                "status" => "PERMISSION_DENIED"
              }
            })
        }
    end)

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

      whatsapp_form =
        Repo.get_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

      args = %Oban.Job{
        args: %{
          "organization_id" => organization_id,
          "payload" => %{
            "contact_number" => "919425010449",
            "organization_id" => organization_id,
            "raw_response" => %{
              "flow_token" => "unused",
              "screen_0_Choose_one_0" => "0_Yes"
            },
            "submitted_at" => "2025-12-20T09:46:24.000000Z",
            "whatsapp_form_id" => whatsapp_form.id,
            "whatsapp_form_name" => whatsapp_form.name
          },
          "whatsapp_form_id" => whatsapp_form.id
        }
      }

      result = WhatsappFormWorker.perform(args)
      assert {:error, _reason} = result
    end
  end
end
