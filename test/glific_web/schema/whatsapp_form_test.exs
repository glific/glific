defmodule GlificWeb.Schema.WhatsappFormTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Mock
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Partners,
    Repo,
    Seeds.SeedsDev,
    Sheets.Sheet,
    WhatsappForms,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormWorker
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
    :activate_whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/activate.gql"
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

  load_gql(
    :sync_whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/sync.gql"
  )

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_whatsapp_forms(organization)
  end

  @defintion_value %{
    "screens" => [
      %{
        "data" => %{},
        "id" => "screen_bcvvpc",
        "layout" => %{
          "children" => [
            %{
              "children" => [
                %{"text" => "Text", "type" => "TextHeading"},
                %{
                  "label" => "Continue",
                  "on-click-action" => %{
                    "name" => "complete",
                    "payload" => %{}
                  },
                  "type" => "Footer"
                }
              ],
              "name" => "flow_path",
              "type" => "Form"
            }
          ],
          "type" => "SingleColumnLayout"
        },
        "terminal" => true,
        "title" => "Screen 1"
      }
    ],
    "version" => "7.3"
  }

  test "publishes a whatsapp form and updates its status to published",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :put, url: url} when is_binary(url) ->
        %Tesla.Env{
          status: 200,
          body: %{status: "success", success: true}
        }

      %{method: :post} ->
        %Tesla.Env{status: 200, body: %{"status" => "success"}}
    end)

    {:ok, sign_up_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    _result =
      auth_query_gql_by(:publish_whatsapp_form, user, variables: %{"id" => sign_up_form.id})

    {:ok, updated_form} =
      Repo.fetch_by(WhatsappForm, %{
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
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    _result =
      auth_query_gql_by(:deactivate_whatsapp_form, user, variables: %{"id" => sign_up_form.id})

    {:ok, updated_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    assert updated_form.status == :inactive
  end

  test "activates a whatsapp form and updates its status to published",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: %{"status" => "success"}}
    end)

    {:ok, sign_up_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-7a12cd90-c6e4-4e56-9a23-001f89b2a8b1"
      })

    assert sign_up_form.status == :inactive

    _result =
      auth_query_gql_by(:activate_whatsapp_form, user, variables: %{"id" => sign_up_form.id})

    {:ok, updated_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-7a12cd90-c6e4-4e56-9a23-001f89b2a8b1"
      })

    assert updated_form.status == :published
  end

  test "fails to activate WhatsApp form if the form does not exist",
       %{manager: user} do
    {:ok, %{data: %{"activateWhatsappForm" => %{"errors" => [error | _]}}}} =
      auth_query_gql_by(:activate_whatsapp_form, user, variables: %{"id" => "318182039810832"})

    assert error["message"] ==
             "Resource not found"
  end

  test "fails to deactivate WhatsApp form if the form does not exist",
       %{manager: user} do
    {:ok, %{data: %{"deactivateWhatsappForm" => %{"errors" => [error | _]}}}} =
      auth_query_gql_by(:deactivate_whatsapp_form, user, variables: %{"id" => "318182039810832"})

    assert error["message"] == "Resource not found"
  end

  test "fails to publish WhatsApp form if the form does not exist",
       %{manager: user} do
    {:ok, %{data: %{"publishWhatsappForm" => %{"errors" => [error | _]}}}} =
      auth_query_gql_by(:publish_whatsapp_form, user, variables: %{"id" => "318182039810832"})

    assert error["message"] == "Resource not found"
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

  test "retrieves a WhatsApp form with sheet details when sheet is associated", %{
    manager: user,
    organization_id: organization_id
  } do
    Tesla.Mock.mock(fn %{method: :get} -> %Tesla.Env{status: 200, body: ""} end)

    {:ok, sheet} =
      Glific.Sheets.create_sheet(%{
        label: "WhatsApp Form Responses",
        url: "https://docs.google.com/spreadsheets/d/test-sheet-id/edit",
        type: "READ",
        organization_id: organization_id
      })

    {:ok, form} = Repo.fetch_by(WhatsappForm, %{name: "newsletter_subscription_form"})

    {:ok, updated_form} =
      form
      |> Ecto.Changeset.change(%{sheet_id: sheet.id})
      |> Repo.update()

    {:ok, query} =
      auth_query_gql_by(:whatsapp_form, user, variables: %{"whatsappFormId" => updated_form.id})

    sheet_data = query.data["whatsappForm"]["whatsappForm"]["sheet"]
    assert sheet_data != nil
    assert sheet_data["id"] == "#{sheet.id}"
    assert sheet_data["label"] == "WhatsApp Form Responses"
    assert sheet_data["url"] == "https://docs.google.com/spreadsheets/d/test-sheet-id/edit"
    assert sheet_data["isActive"] == true
  end

  test "retrieves a WhatsApp form with null sheet when no sheet is associated", %{
    manager: user
  } do
    {:ok, form} = Repo.fetch_by(WhatsappForm, %{name: "sign_up_form"})

    {:ok, query} =
      auth_query_gql_by(:whatsapp_form, user, variables: %{"whatsappFormId" => form.id})

    assert query.data["whatsappForm"]["whatsappForm"]["sheet"] == nil
  end

  test "lists WhatsApp forms with sheet details when sheets are associated", %{
    manager: user,
    organization_id: organization_id
  } do
    Tesla.Mock.mock(fn %{method: :get} -> %Tesla.Env{status: 200, body: ""} end)

    {:ok, sheet1} =
      Glific.Sheets.create_sheet(%{
        label: "Sign Up Responses",
        url: "https://docs.google.com/spreadsheets/d/test-sheet-1/edit",
        type: "READ",
        organization_id: organization_id
      })

    {:ok, sheet2} =
      Glific.Sheets.create_sheet(%{
        label: "Contact Responses",
        url: "https://docs.google.com/spreadsheets/d/test-sheet-2/edit",
        type: "READ",
        organization_id: organization_id
      })

    {:ok, form1} = Repo.fetch_by(WhatsappForm, %{name: "sign_up_form"})
    {:ok, form2} = Repo.fetch_by(WhatsappForm, %{name: "contact_us_form"})

    form1 |> Ecto.Changeset.change(%{sheet_id: sheet1.id}) |> Repo.update()
    form2 |> Ecto.Changeset.change(%{sheet_id: sheet2.id}) |> Repo.update()

    {:ok, query} = auth_query_gql_by(:list_whatsapp_forms, user, variables: %{})

    forms = query.data["listWhatsappForms"]

    form_with_sheet1 = Enum.find(forms, fn f -> f["name"] == "sign_up_form" end)
    form_with_sheet2 = Enum.find(forms, fn f -> f["name"] == "contact_us_form" end)
    form_without_sheet = Enum.find(forms, fn f -> f["name"] == "feedback_form" end)

    assert form_with_sheet1["sheet"]["id"] == "#{sheet1.id}"
    assert form_with_sheet1["sheet"]["label"] == "Sign Up Responses"

    assert form_with_sheet2["sheet"]["id"] == "#{sheet2.id}"
    assert form_with_sheet2["sheet"]["label"] == "Contact Responses"

    assert form_without_sheet["sheet"] == nil
  end

  test "syncs WhatsApp forms for an organization that does not exist in the database from Business Manager",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :get, url: url} = _env ->
        cond do
          String.contains?(url, "/flows") and not String.contains?(url, "/assets") ->
            %Tesla.Env{
              status: 200,
              body: [
                %{
                  id: "1234567890",
                  status: "draft",
                  name: "Customer Feedback Form",
                  categories: ["survey"]
                }
              ]
            }

          String.contains?(url, "/assets") ->
            %Tesla.Env{
              status: 200,
              body: [
                %{
                  download_url: "https://example.com/fake_download.json"
                }
              ]
            }

          String.starts_with?(url, "https://") ->
            %Tesla.Env{
              status: 200,
              body: ~s({"title": "Customer Feedback Form"})
            }

          true ->
            %Tesla.Env{status: 404, body: "not mocked"}
        end
    end)

    auth_query_gql_by(:sync_whatsapp_form, user)

    assert_enqueued(
      worker: WhatsappFormWorker,
      prefix: "global"
    )

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :default, with_scheduled: true)

    {:ok, form} = Repo.fetch_by(WhatsappForm, %{meta_flow_id: "1234567890"})
    assert form.name == "Customer Feedback Form"
    assert form.status == :draft
  end

  test "syncs whatsapp forms will only updates non published ones in db",
       %{manager: user} do
    Tesla.Mock.mock(fn
      %{method: :get, url: url} = _env ->
        cond do
          String.contains?(url, "/flows") and not String.contains?(url, "/assets") ->
            %Tesla.Env{
              status: 200,
              body: [
                %{
                  id: "flow-9e3bf3f2-0c9f-4a8b-bf23-33b7e5d2fbb2",
                  status: "published",
                  name: "Customer Feedback Form",
                  categories: ["survey"]
                },
                %{
                  id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0",
                  status: "published",
                  name: "Customer",
                  categories: ["survey"]
                }
              ]
            }

          String.contains?(url, "/assets") ->
            %Tesla.Env{
              status: 200,
              body: [
                %{
                  download_url: "https://example.com/fake_download.json"
                }
              ]
            }

          String.starts_with?(url, "https://") ->
            %Tesla.Env{
              status: 200,
              body: ~s({"title": "Customer Feedback Form"})
            }

          true ->
            %Tesla.Env{status: 404, body: "not mocked"}
        end
    end)

    {:ok, existing_form1} =
      Repo.fetch_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

    form_with_revision = Repo.preload(existing_form1, :revision)

    assert form_with_revision.revision.definition == @defintion_value

    {:ok, existing_form2} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-9e3bf3f2-0c9f-4a8b-bf23-33b7e5d2fbb2"
      })

    assert existing_form1.status == :draft

    assert existing_form2.status == :published
    assert existing_form2.name == "sign_up_form"

    auth_query_gql_by(:sync_whatsapp_form, user)

    assert_enqueued(
      worker: WhatsappFormWorker,
      prefix: "global"
    )

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :default, with_scheduled: true)

    {:ok, updated_form1} =
      Repo.fetch_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

    form_with_synced_revision = Repo.preload(updated_form1, :revision)

    {:ok, updated_form2} =
      Repo.fetch_by(WhatsappForm, %{meta_flow_id: "flow-9e3bf3f2-0c9f-4a8b-bf23-33b7e5d2fbb2"})

    assert form_with_synced_revision.revision.definition == %{"title" => "Customer Feedback Form"}
    assert updated_form1.status == :published
    assert updated_form1.name == "Customer"
    assert updated_form2.name == "sign_up_form"
  end

  test "if an existing sheet is associated with a WhatsApp form, updating the form updates the sheet details",
       %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :put} ->
        %Tesla.Env{
          status: 200,
          body: %{status: "success", success: true}
        }

      %{method: :post, url: url} when is_binary(url) ->
        cond do
          String.contains?(url, "googleapis.com") && String.contains?(url, ":append") ->
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
        end
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
        organization_id: user.organization_id
      }

      Partners.create_credential(sheet_attrs)

      {:ok, whatsapp_form_1} =
        Repo.fetch_by(WhatsappForm, %{meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"})

      {:ok, sheet} = Repo.fetch_by(Sheet, %{label: "User Data Sheet"})

      whatsapp_form_1 = Repo.preload(whatsapp_form_1, [:sheet])

      valid_attrs = %{
        name: whatsapp_form_1.name,
        description: whatsapp_form_1.description,
        categories: ["other"],
        organization_id: whatsapp_form_1.organization_id,
        google_sheet_url: sheet.url
      }

      result = WhatsappForms.update_whatsapp_form(whatsapp_form_1, valid_attrs)

      assert {:error, %Ecto.Changeset{}} = result
    end
  end
end
