defmodule Glific.WhatsappFormResponsesTest do
  use GlificWeb.ConnCase
  import Mock
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.FlowContext,
    GCS.GcsWorker,
    Messages,
    Partners,
    Providers.Gupshup.PartnerAPI,
    Repo,
    Seeds.SeedsDev,
    Templates,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormResponse,
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
    SeedsDev.seed_flows(organization)
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

  test "write_to_google_sheet/2 stringifies map values like calendar_range and list values like options ",
       %{organization_id: organization_id} do
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
                  "calendar_range",
                  "options"
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

      whatsapp_form =
        Repo.get_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

      payload = %{
        "contact_number" => "919425010449",
        "organization_id" => organization_id,
        "raw_response" => %{
          "calendar_range" => %{
            "end-date" => "2025-12-11",
            "start-date" => "2025-12-02"
          },
          "options" => [
            "option1",
            "option2"
          ],
          "flow_token" => "unused"
        },
        "submitted_at" => "2026-03-17T12:47:36.000000Z",
        "whatsapp_form_id" => whatsapp_form.id,
        "whatsapp_form_name" => whatsapp_form.name
      }

      {:ok, values} =
        WhatsappFormsResponses.write_to_google_sheet(payload, whatsapp_form)

      calendar_value = Enum.at(values, 4)
      options_value = Enum.at(values, 5)
      assert is_binary(calendar_value)

      assert calendar_value ==
               Jason.encode!(%{"end-date" => "2025-12-11", "start-date" => "2025-12-02"})

      assert options_value == Enum.join(["option1", "option2"], ", ")
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

  @photo %{
    "id" => 27_286_093_617_715_235,
    "file_name" => "photo.jpg",
    "mime_type" => "image/jpeg",
    "sha256" => "GB5ASgGkjWWKqVRBtQ5flyIJRusvCdseiwZylfEd9gU="
  }

  describe "save_response_media/2" do
    test "downloads media to GCS and adds gcs_url, leaving other fields untouched",
         %{organization_id: organization_id} do
      with_mocks([
        {PartnerAPI, [:passthrough],
         [download_flow_media: fn _org, _media_id -> {:ok, <<255, 216, 255>>} end]},
        {GcsWorker, [:passthrough],
         [
           upload_media: fn _local, _remote, _org ->
             {:ok, %{url: "https://gcs.test/photo.jpg", type: :image}}
           end
         ]}
      ]) do
        raw_response = %{"photos" => [@photo], "students_attended" => "115"}

        enriched = WhatsappFormsResponses.save_response_media(raw_response, organization_id)

        assert [%{"gcs_url" => "https://gcs.test/photo.jpg"} = saved_photo] = enriched["photos"]
        # original metadata is preserved alongside the new gcs_url
        assert saved_photo["id"] == @photo["id"]
        assert saved_photo["file_name"] == @photo["file_name"]
        # non-media fields are untouched
        assert enriched["students_attended"] == "115"
      end
    end

    test "leaves the media unchanged (no gcs_url) when the download fails",
         %{organization_id: organization_id} do
      with_mocks([
        {PartnerAPI, [:passthrough],
         [download_flow_media: fn _org, _media_id -> {:error, "429 Too Many Requests"} end]},
        {GcsWorker, [:passthrough],
         [
           upload_media: fn _local, _remote, _org ->
             {:ok, %{url: "https://gcs.test", type: :image}}
           end
         ]}
      ]) do
        raw_response = %{"photos" => [@photo]}

        enriched = WhatsappFormsResponses.save_response_media(raw_response, organization_id)

        assert [saved_photo] = enriched["photos"]
        refute Map.has_key?(saved_photo, "gcs_url")
      end
    end

    test "leaves non-media list values and scalar values unchanged",
         %{organization_id: organization_id} do
      raw_response = %{"options" => ["option1", "option2"], "name" => "abc"}

      # no PartnerAPI/GcsWorker calls happen for non-media fields
      assert WhatsappFormsResponses.save_response_media(raw_response, organization_id) ==
               raw_response
    end

    test "returns the raw_response untouched when it is not a map",
         %{organization_id: organization_id} do
      assert WhatsappFormsResponses.save_response_media("not-a-map", organization_id) ==
               "not-a-map"
    end
  end

  defp form_response_for(contact_id, whatsapp_form, organization_id) do
    {:ok, response} =
      %WhatsappFormResponse{}
      |> WhatsappFormResponse.changeset(%{
        raw_response: %{},
        contact_id: contact_id,
        whatsapp_form_id: whatsapp_form.id,
        organization_id: organization_id,
        submitted_at: DateTime.utc_now()
      })
      |> Repo.insert()

    response
  end

  describe "inject_media_into_flow_results/1" do
    setup %{organization_id: organization_id} do
      whatsapp_form =
        Repo.get_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

      %{whatsapp_form: whatsapp_form, organization_id: organization_id}
    end

    test "injects the gcs_url into the contact's active flow result variable",
         %{whatsapp_form: whatsapp_form, organization_id: organization_id} do
      flow_context =
        Fixtures.flow_context_fixture(%{
          results: %{
            "orientation" => %{"students_attended" => "115", "photos" => "{\"id\":1}"}
          }
        })

      response = form_response_for(flow_context.contact_id, whatsapp_form, organization_id)

      payload = %{
        "whatsapp_form_response_id" => response.id,
        "raw_response" => %{
          "photos" => [
            %{"id" => 1, "mime_type" => "image/jpeg", "gcs_url" => "https://gcs.test/x.jpg"}
          ]
        }
      }

      assert :ok = WhatsappFormsResponses.inject_media_into_flow_results(payload)

      updated_context = Repo.get(FlowContext, flow_context.id)
      # the photos variable is upgraded to the gcs_url
      assert updated_context.results["orientation"]["photos"] == "https://gcs.test/x.jpg"
      # other result fields are untouched
      assert updated_context.results["orientation"]["students_attended"] == "115"
    end

    test "is a no-op (returns :ok) when the contact has no active flow context",
         %{whatsapp_form: whatsapp_form, organization_id: organization_id} do
      contact = Fixtures.contact_fixture()
      response = form_response_for(contact.id, whatsapp_form, organization_id)

      payload = %{
        "whatsapp_form_response_id" => response.id,
        "raw_response" => %{
          "photos" => [
            %{"id" => 1, "mime_type" => "image/jpeg", "gcs_url" => "https://gcs.test/x.jpg"}
          ]
        }
      }

      assert :ok = WhatsappFormsResponses.inject_media_into_flow_results(payload)
    end

    test "is a no-op when the response has no media field" do
      payload = %{
        "whatsapp_form_response_id" => 0,
        "raw_response" => %{"students_attended" => "115"}
      }

      assert :ok = WhatsappFormsResponses.inject_media_into_flow_results(payload)
    end

    test "does not touch result entries that have no media field",
         %{whatsapp_form: whatsapp_form, organization_id: organization_id} do
      flow_context =
        Fixtures.flow_context_fixture(%{
          results: %{"other" => %{"some_field" => "value"}}
        })

      response = form_response_for(flow_context.contact_id, whatsapp_form, organization_id)

      payload = %{
        "whatsapp_form_response_id" => response.id,
        "raw_response" => %{
          "photos" => [
            %{"id" => 1, "mime_type" => "image/jpeg", "gcs_url" => "https://gcs.test/x.jpg"}
          ]
        }
      }

      assert :ok = WhatsappFormsResponses.inject_media_into_flow_results(payload)

      updated_context = Repo.get(FlowContext, flow_context.id)
      assert updated_context.results == %{"other" => %{"some_field" => "value"}}
    end
  end

  describe "PartnerAPI.download_flow_media/2" do
    test "returns the raw media bytes on a 2xx response",
         %{organization_id: organization_id} do
      Fixtures.set_bsp_partner_tokens(organization_id)

      Tesla.Mock.mock(fn
        %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/media/123"} ->
          %Tesla.Env{status: 200, body: <<255, 216, 255>>}
      end)

      assert {:ok, <<255, 216, 255>>} = PartnerAPI.download_flow_media(organization_id, 123)
    end

    test "returns an error tuple on a non-2xx response",
         %{organization_id: organization_id} do
      Fixtures.set_bsp_partner_tokens(organization_id)

      Tesla.Mock.mock(fn
        %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/media/123"} ->
          %Tesla.Env{
            status: 429,
            body: ~s({"status":"error","message":"Too Many Requests"})
          }
      end)

      assert {:error, message} = PartnerAPI.download_flow_media(organization_id, 123)
      assert message =~ "flow media download failed"
    end
  end

  test "write_to_google_sheet/2 stringifies a list of media maps (photos) as JSON without crashing",
       %{organization_id: organization_id} do
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
                  "photos"
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
              "updates" => %{"updatedRows" => 1}
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
      Partners.create_credential(%{
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
      })

      whatsapp_form =
        Repo.get_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

      payload = %{
        "contact_number" => "919425010449",
        "organization_id" => organization_id,
        "raw_response" => %{
          "photos" => [
            %{
              "id" => 1,
              "file_name" => "a.jpg",
              "mime_type" => "image/jpeg",
              "gcs_url" => "https://gcs.test/a.jpg"
            }
          ],
          "flow_token" => "unused"
        },
        "submitted_at" => "2026-03-17T12:47:36.000000Z",
        "whatsapp_form_id" => whatsapp_form.id,
        "whatsapp_form_name" => whatsapp_form.name
      }

      {:ok, values} = WhatsappFormsResponses.write_to_google_sheet(payload, whatsapp_form)

      photos_value = Enum.at(values, 4)
      assert is_binary(photos_value)
      # the photo map is JSON-encoded into the cell, gcs_url included
      assert Jason.decode!(photos_value)["gcs_url"] == "https://gcs.test/a.jpg"
    end
  end
end
