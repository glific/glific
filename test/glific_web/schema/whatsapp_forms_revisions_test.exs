defmodule GlificWeb.Schema.WhatsappFormsRevisionsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Repo,
    Seeds.SeedsDev,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormRevision,
    WhatsappFormsRevisions
  }

  @form_json %{
    "version" => "7.2",
    "screens" => [
      %{
        "title" => "Feedback 1 of 2",
        "layout" => %{
          "type" => "SingleColumnLayout",
          "children" => []
        },
        "id" => "RECOMMEND",
        "data" => %{}
      },
      %{
        "title" => "Feedback 2 of 2",
        "terminal" => true,
        "success" => true,
        "layout" => %{
          "type" => "SingleColumnLayout",
          "children" => [
            %{
              "type" => "Form",
              "name" => "form",
              "children" => [
                %{
                  "type" => "Footer",
                  "on-click-action" => %{
                    "payload" => %{
                      "screen_1_Purchase_experience_0" => "${form.Purchase_experience}",
                      "screen_1_Delivery_and_setup_1" => "${form.Delivery_and_setup}",
                      "screen_1_Customer_service_2" => "${form.Customer_service}",
                      "screen_0_Leave_a_comment_1" => "${data.screen_0_Leave_a_comment_1}",
                      "screen_0_Choose_one_0" => "${data.screen_0_Choose_one_0}"
                    },
                    "name" => "complete"
                  },
                  "label" => "Done"
                }
              ]
            }
          ]
        },
        "id" => "RATE",
        "data" => %{
          "screen_0_Leave_a_comment_1" => %{
            "type" => "string",
            "__example__" => "Example"
          },
          "screen_0_Choose_one_0" => %{
            "type" => "string",
            "__example__" => "Example"
          }
        }
      }
    ]
  }

  load_gql(
    :save_revision,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms_revisions/save_whatsapp_form_revision.gql"
  )

  load_gql(
    :list_whatsapp_form_revisions,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms_revisions/list_whatsapp_form_revisions.gql"
  )

  load_gql(
    :whatsapp_form_revision,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms_revisions/whatsapp_form_revision.gql"
  )

  load_gql(
    :revert_to_revision,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms_revisions/revert_to_revision.gql"
  )

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_whatsapp_forms(organization)
  end

  test "save_revision should save the WhatsApp form revision", %{user: user} do
    {:ok, whatsapp_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    {:ok, result} =
      auth_query_gql_by(:save_revision, user,
        variables: %{
          "input" => %{
            "definition" => @form_json |> Jason.encode!(),
            "whatsappFormId" => whatsapp_form.id
          }
        }
      )

    assert result.data["saveWhatsappFormRevision"]["whatsappFormRevision"]["whatsappFormId"] ==
             whatsapp_form.id |> to_string()

    {:ok, revision} =
      Repo.fetch_by(WhatsappFormRevision, %{
        id: whatsapp_form.revision_id
      })

    {:ok, updated_revision} =
      Repo.fetch_by(WhatsappFormRevision, %{
        id: result.data["saveWhatsappFormRevision"]["whatsappFormRevision"]["id"]
      })

    assert updated_revision.revision_number == revision.revision_number + 1
  end

  test "list_whatsapp_form_revisions should list the WhatsApp form revisions", %{user: user} do
    {:ok, whatsapp_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    {:ok, result_before_saving} =
      auth_query_gql_by(:list_whatsapp_form_revisions, user,
        variables: %{
          "whatsappFormId" => whatsapp_form.id,
          "limit" => 5
        }
      )

    WhatsappFormsRevisions.save_revision(
      %{
        definition: @form_json,
        whatsapp_form_id: whatsapp_form.id
      },
      user
    )

    {:ok, result_after_saving} =
      auth_query_gql_by(:list_whatsapp_form_revisions, user,
        variables: %{
          "whatsappFormId" => whatsapp_form.id,
          "limit" => 5
        }
      )

    assert length(result_before_saving.data["listWhatsappFormRevisions"]) + 1 ==
             length(result_after_saving.data["listWhatsappFormRevisions"])
  end

  test "whatsapp_form_revision should get a specific WhatsApp form revision by ID", %{user: user} do
    {:ok, whatsapp_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    {:ok, revision} =
      Repo.fetch_by(WhatsappFormRevision, %{
        id: whatsapp_form.revision_id
      })

    {:ok, result} =
      auth_query_gql_by(:whatsapp_form_revision, user,
        variables: %{
          "whatsappFormRevisionId" => revision.id
        }
      )

    assert result.data["whatsappFormRevision"]["whatsappFormRevision"]["id"] ==
             revision.id |> to_string()
  end

  test " revert_to_whatsapp_form_revision should revert to a specific WhatsApp form revision", %{
    user: user
  } do
    {:ok, whatsapp_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    {:ok, revision} =
      Repo.fetch_by(WhatsappFormRevision, %{
        id: whatsapp_form.revision_id
      })

    {:ok, _new_revision} =
      WhatsappFormsRevisions.save_revision(
        %{
          definition: @form_json,
          whatsapp_form_id: whatsapp_form.id
        },
        user
      )

    result =
      auth_query_gql_by(:revert_to_revision, user,
        variables: %{
          "whatsappFormId" => whatsapp_form.id,
          "revisionId" => revision.id
        }
      )

    {:ok, whatsapp_form} =
      Repo.fetch_by(WhatsappForm, %{
        meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
      })

    whatsapp_form = Repo.preload(whatsapp_form, [:revision])

    assert {:ok, _} = result
    assert whatsapp_form.revision_id == revision.id
  end
end
