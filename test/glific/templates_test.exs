defmodule Glific.TemplatesTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Mails.MailLog,
    Providers.Gupshup,
    Providers.GupshupEnterprise.Template,
    Seeds.SeedsDev,
    Settings,
    Templates,
    Templates.SessionTemplate
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.hsm_templates(organization)
    :ok
  end

  describe "session_template" do
    @valid_attrs %{
      label: "some label",
      body: "some body",
      type: :text,
      is_active: true,
      is_reserved: true
    }
    @valid_attrs_1 %{
      label: "Another label",
      body: "some body 1",
      shortcode: "sl1",
      type: :text,
      is_active: true,
      is_reserved: true
    }
    @valid_attrs_to_test_order_1 %{
      label: "aaaa label",
      body: "some body 2",
      type: :text,
      is_active: true,
      is_reserved: true
    }
    @valid_attrs_to_test_order_2 %{
      label: "zzzz label",
      body: "some body 2",
      type: :text,
      is_active: true,
      is_reserved: true
    }

    @update_attrs %{
      label: "some updated label",
      body: "some updated body"
    }

    @invalid_attrs %{
      label: nil,
      body: nil,
      language_id: nil
    }

    @valid_language_attrs %{
      label: "English",
      label_locale: "English",
      locale: "en",
      is_active: true
    }
    @valid_language_attrs_1 %{
      label: "Hindi",
      label_locale: "हिन्दी",
      locale: "hi_US",
      is_active: true
    }

    def language_fixture(attrs \\ %{}) do
      {:ok, language} =
        attrs
        |> Enum.into(@valid_language_attrs)
        |> Settings.language_upsert()

      language
    end

    def session_template_fixture(attrs) do
      language = language_fixture()

      {:ok, session_template} =
        attrs
        |> Map.put(:language_id, language.id)
        |> Enum.into(@valid_attrs)
        |> Templates.create_session_template()

      session_template
    end

    test "list_session_templates/1 returns all session_templates", attrs do
      templates_count = Templates.count_session_templates(%{filter: attrs})

      _session_template = session_template_fixture(attrs)
      assert length(Templates.list_session_templates(%{filter: attrs})) == templates_count + 1
    end

    test "count_session_templates/0 returns count of all session templates", attrs do
      templates_count = Templates.count_session_templates(%{filter: attrs})

      session_template_fixture(attrs)
      assert Templates.count_session_templates(%{filter: attrs}) == templates_count + 1

      session_template_fixture(Map.merge(attrs, @valid_attrs_1))
      assert Templates.count_session_templates(%{filter: attrs}) == templates_count + 2

      assert Templates.count_session_templates(%{
               filter: Map.merge(attrs, %{label: "Another label"})
             }) == 1
    end

    test "list_session_templates/1 with multiple session_templates filteres", attrs do
      _session_template = session_template_fixture(attrs)
      session_template1 = session_template_fixture(Map.merge(attrs, @valid_attrs_1))

      session_template_list =
        Templates.list_session_templates(%{
          filter: Map.merge(attrs, %{label: session_template1.label})
        })

      assert session_template_list == [session_template1]

      session_template_list =
        Templates.list_session_templates(%{
          filter: Map.merge(attrs, %{body: session_template1.body})
        })

      assert session_template_list == [session_template1]

      session_template_list =
        Templates.list_session_templates(%{
          filter: Map.merge(attrs, %{shortcode: session_template1.shortcode})
        })

      assert session_template_list == [session_template1]

      session_template_list =
        Templates.list_session_templates(%{
          filter: Map.merge(attrs, %{is_active: session_template1.is_active})
        })

      assert session_template1 in session_template_list
    end

    test "list_session_templates/1 with tag_ids filter on session_templates", attrs do
      tag1 = Fixtures.tag_fixture(Map.merge(attrs, %{label: "test_tag"}))
      template = session_template_fixture(Map.merge(attrs, %{label: "label4", tag_id: tag1.id}))

      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{tag_ids: [tag1.id]})})

      assert session_template_list == [template]
    end

    test "list_session_templates/1 with term filter on session_templates", attrs do
      # Match term with labe/body/shortcode of template
      session_template_fixture(Map.merge(attrs, %{label: "filterterm"}))
      session_template_fixture(Map.merge(attrs, %{label: "label2", body: "filterterm"}))
      session_template_fixture(Map.merge(attrs, %{label: "label3", shortcode: "filterterm"}))

      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{term: "filterterm"})})

      assert length(session_template_list) == 3

      # Match term with label of associated tag
      template = session_template_fixture(Map.merge(attrs, %{label: "label4"}))
      tag_1 = Fixtures.tag_fixture(Map.merge(attrs, %{label: "filterterm"}))

      _template_tag =
        Fixtures.template_tag_fixture(
          Map.merge(attrs, %{template_id: template.id, tag_id: tag_1.id})
        )

      template = session_template_fixture(Map.merge(attrs, %{label: "label5"}))
      tag_2 = Fixtures.tag_fixture(Map.merge(attrs, %{shortcode: "filterterm"}))

      _template_tag =
        Fixtures.template_tag_fixture(
          Map.merge(attrs, %{template_id: template.id, tag_id: tag_2.id})
        )

      # Match term with label of associated tag and not shortcode
      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{term: "filterterm"})})

      assert length(session_template_list) == 4

      # In case of a template tagged with multiple tags with similar label or shortcode
      # result should not give repeated templates
      _template_tag =
        Fixtures.template_tag_fixture(
          Map.merge(attrs, %{template_id: template.id, tag_id: tag_1.id})
        )

      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{term: "filterterm"})})

      assert length(session_template_list) == 5
    end

    test "list_session_templates/1 with multiple items", attrs do
      templates_count = Templates.count_session_templates(%{filter: attrs})

      session_template_fixture(attrs)
      session_template_fixture(Map.merge(attrs, @valid_attrs_1))

      session_templates = Templates.list_session_templates(%{filter: attrs})
      assert length(session_templates) == templates_count + 2
    end

    test "list_session_templates/1 with multiple items sorted", attrs do
      session_templates_count = Templates.count_session_templates(%{filter: attrs})

      s0 = session_template_fixture(Map.merge(attrs, @valid_attrs_to_test_order_1))
      s1 = session_template_fixture(Map.merge(attrs, @valid_attrs_to_test_order_2))

      assert length(Templates.list_session_templates(%{filter: attrs})) ==
               session_templates_count + 2

      [ordered_s0 | _] = Templates.list_session_templates(%{opts: %{order: :asc}, filter: attrs})
      assert s0 == ordered_s0

      [ordered_s1 | _] = Templates.list_session_templates(%{opts: %{order: :desc}, filter: attrs})
      assert s1 == ordered_s1
    end

    test "get_session_template!/1 returns the session_template with given id", attrs do
      session_template = session_template_fixture(attrs)
      assert Templates.get_session_template!(session_template.id) == session_template
    end

    test "create_session_template/1 with valid data creates a message", attrs do
      language = language_fixture()

      attrs =
        attrs
        |> Map.merge(@valid_attrs)
        |> Map.merge(%{language_id: language.id})

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.create_session_template(attrs)

      assert session_template.label == "some label"
      assert session_template.body == "some body"
      assert session_template.shortcode == nil
      assert session_template.is_active == true
      assert session_template.is_reserved == true
      assert session_template.is_source == false
      assert session_template.language_id == language.id
    end

    test "create_session_template/1 with invalid data returns error changeset", attrs do
      assert {:error, %Ecto.Changeset{}} =
               Templates.create_session_template(Map.merge(attrs, @invalid_attrs))
    end

    test "create_session_template/1 for HSM with incomplete data should return error", attrs do
      # shortcode, category and example are required fields
      attrs = %{
        body: "Your train ticket no. {{1}}",
        label: "New Label 2",
        language_id: language_fixture().id,
        type: :text,
        is_hsm: true,
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]",
        organization_id: attrs.organization_id
      }

      assert {:error,
              [
                "HSM approval",
                "for HSM approval shortcode, category and example fields are required"
              ]} = Templates.create_session_template(attrs)

      # wrong shortcode
      attrs_2 = %{
        body: "Your train ticket no. {{1}}",
        label: "New Label 2",
        language_id: language_fixture().id,
        type: :text,
        is_hsm: true,
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]",
        organization_id: attrs.organization_id,
        shortcode: "Wrong Shortcode"
      }

      assert {:error, ["shortcode", "only '_' and alphanumeric characters are allowed"]} =
               Templates.create_session_template(attrs_2)
    end

    test "create_session_template/1 for HSM data should submit it for approval", attrs do
      whatspp_hsm_uuid = "16e84186-97fa-454e-ac3b-8c9b94e53b4b"

      body =
        Jason.encode!(%{
          "status" => "success",
          "token" => "new_partner_token",
          "template" => %{
            "category" => "ACCOUNT_UPDATE",
            "createdOn" => 1_595_904_220_495,
            "data" => "Your train ticket no. {{1}}",
            "elementName" => "ticket_update_status",
            "id" => whatspp_hsm_uuid,
            "languageCode" => "en",
            "languagePolicy" => "deterministic",
            "master" => true,
            "meta" => "{\"example\":\"Your train ticket no. [1234]\"}",
            "modifiedOn" => 1_595_904_220_495,
            "status" => "PENDING",
            "templateType" => "TEXT",
            "vertical" => "ACTION_BUTTON"
          }
        })

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: body
          }

        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "Fake Token"}})
          }
      end)

      language = language_fixture()

      attrs = %{
        body: "Your train ticket no. {{1}}",
        label: "New Label",
        language_id: language.id,
        is_hsm: true,
        type: :text,
        shortcode: "ticket_update_status",
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]",
        organization_id: attrs.organization_id
      }

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.create_session_template(attrs)

      assert session_template.shortcode == "ticket_update_status"
      assert session_template.is_hsm == true
      assert session_template.status == "PENDING"
      assert session_template.uuid == whatspp_hsm_uuid
      assert session_template.language_id == language.id
    end

    test "create_session_template/1 for HSM button template should submit it for approval",
         attrs do
      whatspp_hsm_uuid = "16e84186-97fa-454e-ac3b-8c9c94e53b4b"

      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "Fake Token"}})
          }

        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "template" => %{
                  "category" => "ACCOUNT_UPDATE",
                  "createdOn" => 1_595_904_220_495,
                  "data" => "Your conference ticket no. {{1}}",
                  "elementName" => "conference_ticket_status",
                  "id" => whatspp_hsm_uuid,
                  "languageCode" => "en",
                  "languagePolicy" => "deterministic",
                  "master" => true,
                  "meta" => "{\"example\":\"Your conference ticket no. [1234]\"}",
                  "modifiedOn" => 1_595_904_220_495,
                  "status" => "PENDING",
                  "templateType" => "TEXT",
                  "vertical" => "ACTION_BUTTON"
                }
              })
          }
      end)

      language = language_fixture()

      attrs = %{
        body: "Your conference ticket no. {{1}}",
        label: "New Label",
        language_id: language.id,
        is_hsm: true,
        type: :text,
        shortcode: "conference_ticket_status",
        category: "ACCOUNT_UPDATE",
        example: "Your conference ticket no. [1234]",
        organization_id: attrs.organization_id,
        has_buttons: true,
        button_type: "quick_reply",
        buttons: [%{"text" => "confirm", "type" => "QUICK_REPLY"}]
      }

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.create_session_template(attrs)

      assert session_template.shortcode == "conference_ticket_status"
      assert session_template.is_hsm == true
      assert session_template.status == "PENDING"
      assert session_template.uuid == whatspp_hsm_uuid
      assert session_template.language_id == language.id

      # Applying for button template with incomplete field should return error
      attrs = %{
        body: "Your train ticket no. {{1}}",
        label: "New Label",
        language_id: language.id,
        is_hsm: true,
        type: :text,
        shortcode: "ticket_update_status",
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]",
        organization_id: attrs.organization_id,
        has_buttons: true
      }

      assert {:error,
              [
                "Button Template",
                "for Button Templates has_buttons, button_type and buttons fields are required"
              ]} = Templates.create_session_template(attrs)
    end

    test "create_session_template/1 for HSM data wrong data should return BSP status and error message",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 400,
            body:
              Jason.encode!(%{
                "status" => "error",
                "message" => "Something went wrong"
              })
          }
      end)

      # extra space in example would return error response
      attrs = %{
        body: "Your train ticket no. {{1}}",
        label: "New Label",
        language_id: language_fixture().id,
        is_hsm: true,
        type: :text,
        shortcode: "ticket_update_status",
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]  ",
        organization_id: attrs.organization_id
      }

      assert {:error, ["BSP", "couldn't submit for approval"]} =
               Templates.create_session_template(attrs)
    end

    test "update_session_template/2 with valid data updates the session_template", attrs do
      session_template = session_template_fixture(attrs)
      language = language_fixture(@valid_language_attrs_1)
      attrs = Map.merge(@update_attrs, %{language_id: language.id})

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.update_session_template(session_template, attrs)

      assert session_template.label == @update_attrs.label
      assert session_template.body == @update_attrs.body
      assert session_template.language_id == language.id
    end

    test "update_session_template/2 with invalid data returns error changeset", attrs do
      session_template = session_template_fixture(attrs)

      assert {:error, %Ecto.Changeset{}} =
               Templates.update_session_template(session_template, @invalid_attrs)

      assert session_template == Templates.get_session_template!(session_template.id)
    end

    test "update_session_template/2 for HSM template should not update the Pending HSM",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "Fake Token"}})
          }

        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "template" => %{
                  "category" => "ACCOUNT_UPDATE",
                  "createdOn" => 1_595_904_220_495,
                  "data" => "Your train ticket no. {{1}}",
                  "elementName" => "ticket_update_status",
                  "id" => "16e84186-97fa-454e-ac3b-8c9b94e53b4b",
                  "languageCode" => "en",
                  "languagePolicy" => "deterministic",
                  "master" => true,
                  "meta" => "{\"example\":\"Your train ticket no. [1234]\"}",
                  "modifiedOn" => 1_595_904_220_495,
                  "status" => "PENDING",
                  "templateType" => "TEXT",
                  "vertical" => "ACTION_BUTTON"
                }
              })
          }
      end)

      language = language_fixture()

      attrs = %{
        body: "Your train ticket no. {{1}}",
        label: "New Label",
        language_id: language.id,
        is_hsm: true,
        type: :text,
        shortcode: "ticket_update_status",
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]",
        organization_id: attrs.organization_id
      }

      {:ok, session_template} = Templates.create_session_template(attrs)

      assert {:error, %Ecto.Changeset{}} =
               Templates.update_session_template(session_template, %{
                 is_active: true,
                 body: "updated body"
               })

      assert session_template == Templates.get_session_template!(session_template.id)
    end

    test "update_session_template/2 for HSM template should update only the editable fields",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "Fake Token"}})
          }

        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "template" => %{
                  "category" => "ACCOUNT_UPDATE",
                  "createdOn" => 1_595_904_220_495,
                  "data" => "Your train ticket no. {{1}}",
                  "elementName" => "ticket_update_status",
                  "id" => "16e84186-97fa-454e-ac3b-8c9b94e53b4b",
                  "languageCode" => "en",
                  "languagePolicy" => "deterministic",
                  "master" => true,
                  "meta" => "{\"example\":\"Your train ticket no. [1234]\"}",
                  "modifiedOn" => 1_595_904_220_495,
                  "status" => "APPROVED",
                  "templateType" => "TEXT",
                  "vertical" => "ACTION_BUTTON"
                }
              })
          }
      end)

      language = language_fixture()

      attrs = %{
        body: "Your train ticket no. {{1}}",
        label: "New Label",
        language_id: language.id,
        is_hsm: true,
        type: :text,
        shortcode: "ticket_update_status",
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]",
        organization_id: attrs.organization_id
      }

      {:ok, session_template} = Templates.create_session_template(attrs)

      assert {:ok, %SessionTemplate{} = updated_template} =
               Templates.update_session_template(session_template, %{
                 is_active: true,
                 body: "updated body"
               })

      assert updated_template.is_active == true
      assert updated_template.body == "Your train ticket no. {{1}}"
    end

    test "edit_approved_template/2 should edit the approved template", attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "token" => "some random partner token"
              })
          }

        %{method: :put} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success"
              })
          }

        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success"
              })
          }
      end)

      {:ok, session_template} =
        session_template_fixture(attrs)
        |> Templates.update_session_template(%{bsp_id: Ecto.UUID.generate()})

      Templates.edit_approved_template(session_template.id, %{
        content: "updated template content",
        example: "updated template example",
        organization_id: session_template.organization_id
      })

      assert {:ok, %SessionTemplate{} = updated_hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: session_template.uuid})

      assert updated_hsm.body == "updated template content"
      assert updated_hsm.example == "updated template example"
    end

    test "delete_session_template/1 deletes the session_template", attrs do
      session_template = session_template_fixture(attrs)
      assert {:ok, %SessionTemplate{}} = Templates.delete_session_template(session_template)

      assert_raise Ecto.NoResultsError, fn ->
        Templates.get_session_template!(session_template.id)
      end
    end

    test "change_session_template/1 returns a session_template changeset", attrs do
      session_template = session_template_fixture(attrs)
      assert %Ecto.Changeset{} = Templates.change_session_template(session_template)
    end

    test "ensure that creating session template with out language and/or org_id give an error" do
      assert {:error, %Ecto.Changeset{}} = Templates.create_session_template(@valid_attrs)
    end

    test "bulk_apply_templates/2 should bulk apply templates", attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            headers: %{
              "content-type" => "image",
              "content-length" => "1232"
            }
          }
      end)

      data =
        "Language,Title,Message,Sample Message,Element Name,Category,Attachment Type,Attachment URL,Has Buttons,Button Type,CTA Button 1 Type,CTA Button 1 Title,CTA Button 1 Value,CTA Button 2 Type,CTA Button 2 Title,CTA Button 2 Value,Quick Reply 1 Title,Quick Reply 2 Title,Quick Reply 3 Title\r\nEnglish,Signup Arogya,\"Hi {{1}},\nWelcome to the world\",\"Hi [Akhilesh],\nWelcome to the world\",welcome_arogya,SEMI-UTILITY,,,FALSE,,,,,,,,,,\r\nEnglish,Welcome Arogya,\"Hi {{1}},\nWelcome to the world\",\"Hi [Akhilesh],\nWelcome to the world\",signup_arogya,UTILITY,,,TRUE,QUICK_REPLY,,,,,,,Yes,No,\r\nMandarin,Help Arogya,\"Hi {{1}},Need help?\",\"Hi [Akhilesh],Need help?\",help_arogya,UTILITY,,,TRUE,CALL_TO_ACTION,Phone Number,Call here,8979120220,URL,Visit Here,https://github.com/glific,,,\r\nEnglish,Activity,\"Hi {{1}},\nLook at this image.\",\"Hi [Akhilesh],\nLook at this image.\",activity,UTILITY,image,https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample02.jpg,FALSE,,,,,,,,,,\r\nEnglish,Signout Arogya,\"Hi {{1}},\nSorry to see you go\",\"Hi [Akhilesh],\nSorry to see you move out\",signout_arogya,UTILITY,,,FALSE,,,,,,,,,,\r\nEnglish,Optin Arogya,\"Hi {{1}},\n Reply with yes to optin\",\"Hi [Akhilesh],\Reply with yes to optin\",optin_arogya,UTILITY,,,TRUE,,,,,,,,,,\r\nEnglish,Help Arogya 2,\"Hi {{1}},Need help?\",\"Hi [Akhilesh],Need help?\",help_arogya_2,UTILITY,,,TRUE,CALL_TO_ACTION,Phone Number,Call here,8979120220,URL,Visit Here,https://github.com/glific,,,\r\nEnglish,Signup Arogya 2,\"Hi {{1}},\nWelcome to the world\",\"Hi [Akhilesh],\nWelcome to the world\",welcome_arogya,UTILITY,,,FALSE,,,,,,,,,,\r\nEnglish,Welcome Arogya,\"Hi {{1}},\nWelcome to the world\",\"Hi [Akhilesh],\nWelcome to the world\",signup_arogya_2,UTILITY,,,TRUE,QUICK_REPLY,,,,,,,Yes,No,"

      {:ok, %{csv_rows: csv_rows}} =
        Gupshup.Template.bulk_apply_templates(attrs.organization_id, data)

      assert csv_rows ==
               "Title,Status\r\nSignup Arogya,Invalid Category\r\nWelcome Arogya,Template has been applied successfully\r\nHelp Arogya,Invalid Language\r\nActivity,Template has been applied successfully\r\nSignout Arogya,Message and Sample Message does not match\r\nOptin Arogya,Invalid Button Type\r\nHelp Arogya 2,Template has been applied successfully\r\nSignup Arogya 2,Template has been applied successfully\r\nWelcome Arogya,Template has been applied successfully"
    end

    test "update_hsms/1 should insert newly received HSM", attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "category" => "TICKET_UPDATE",
                    "createdOn" => 1_595_904_220_466,
                    "data" => "Your train ticket no. {{1}}",
                    "elementName" => "ticket_update_status",
                    "id" => "16e84186-97fa-454e-ac3b-8c9b94e53b4b",
                    "languageCode" => "en",
                    "languagePolicy" => "deterministic",
                    "master" => false,
                    "meta" => "{\"example\":\"Your train ticket no. [1234]\"}",
                    "modifiedOn" => 1_595_904_220_466,
                    "status" => "SANDBOX_REQUESTED",
                    "templateType" => "TEXT",
                    "vertical" => "ACTION_BUTTON"
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: "16e84186-97fa-454e-ac3b-8c9b94e53b4b"})

      assert hsm.example != nil
    end

    test "update_hsms/1 should insert newly received button HSM with type as call_to_action",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "category" => "MARKETING",
                    "createdOn" => 1_595_904_220_466,
                    "data" =>
                      "Hey {{1}}, Are you interested in the latest tech stack | [call here,+917302307943] | [visit here,https://github.com/glific]",
                    "elementName" => "tech_concern",
                    "id" => "2f826c4a-cacd-42b6-9536-ece4c459ffea",
                    "languageCode" => "en",
                    "languagePolicy" => "deterministic",
                    "master" => false,
                    "meta" =>
                      "{\"example\":\"Hey [Akhilesh], Are you interested in the latest tech stack | [call here,+917302307943] | [visit here,https://github.com/glific]\"}",
                    "modifiedOn" => 1_595_904_220_466,
                    "status" => "APPROVED",
                    "templateType" => "TEXT",
                    "vertical" => "ACTION_BUTTON"
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: "2f826c4a-cacd-42b6-9536-ece4c459ffea"})

      assert hsm.example != nil
      assert hsm.button_type == :call_to_action

      assert hsm.buttons == [
               %{
                 "phone_number" => "+917302307943 ",
                 "text" => "call here",
                 "type" => "PHONE_NUMBER"
               },
               %{"text" => "visit here", "type" => "URL", "url" => "https://github.com/glific"}
             ]
    end

    test "update_hsms/1 should insert newly received button HSM with type as quick_reply",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "category" => Templates.list_whatsapp_hsm_categories() |> Enum.at(0),
                    "createdOn" => 1_595_904_220_466,
                    "data" => "Hi {{1}}, What is your status | [cold] | [warm]",
                    "elementName" => "status_response",
                    "id" => "eb939119-097d-414d-844d-1fce3adec486",
                    "languageCode" => "en",
                    "languagePolicy" => "deterministic",
                    "master" => false,
                    "meta" =>
                      "{\"example\":\"Hi [M'gann], What is your status | [cold] | [warm]\"}",
                    "modifiedOn" => 1_595_904_220_466,
                    "status" => "APPROVED",
                    "templateType" => "TEXT",
                    "vertical" => "ACTION_BUTTON"
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: "eb939119-097d-414d-844d-1fce3adec486"})

      assert hsm.example != nil
      assert hsm.button_type == :quick_reply

      assert hsm.buttons == [
               %{"text" => "cold ", "type" => "QUICK_REPLY"},
               %{"text" => "warm", "type" => "QUICK_REPLY"}
             ]
    end

    test "update_hsms/1 should return error in case of error response", attrs do
      # in case of error from BSP API
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 400,
            body:
              Jason.encode!(%{
                "status" => "error",
                "message" => "error message"
              })
          }
      end)

      assert {:error, _message} = Templates.sync_hsms_from_bsp(attrs.organization_id)
    end

    test "update_hsms/1 should update status of already existing HSM", attrs do
      [hsm, hsm2 | _] =
        Templates.list_session_templates(%{
          filter: %{organization_id: attrs.organization_id, is_hsm: true}
        })

      # should update irrespective of the last modified time on BSP
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "id" => hsm.uuid,
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(hsm.updated_at, hours: -1), :millisecond),
                    "status" => "APPROVED"
                  },
                  %{
                    "id" => hsm2.uuid,
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(hsm.updated_at, hours: -1), :millisecond),
                    "status" => "PENDING"
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = updated_hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: hsm.uuid})

      assert updated_hsm.status == "APPROVED"
      assert updated_hsm.is_active == true

      assert {:ok, %SessionTemplate{} = updated_hsm2} =
               Repo.fetch_by(SessionTemplate, %{uuid: hsm2.uuid})

      assert updated_hsm2.status == "PENDING"
      assert updated_hsm2.is_active == false

      # should update the existing hsm if it is modified by BSP since last update in the db
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "id" => hsm.uuid,
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(hsm.updated_at, hours: 1), :millisecond),
                    "status" => "APPROVED"
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} = Repo.fetch_by(SessionTemplate, %{uuid: hsm.uuid})
      assert hsm.status == "APPROVED"
      assert hsm.is_active == true
    end

    test "update_hsms/1 should update uuid of already existing HSM", attrs do
      [hsm | _rest] =
        Templates.list_session_templates(%{
          filter: %{organization_id: attrs.organization_id, is_hsm: true}
        })

      updated_uuid = Ecto.UUID.generate()

      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "elementName" => hsm.shortcode,
                    "languageCode" => hsm.language_id,
                    "id" => updated_uuid,
                    "data" => "Hi {{1}}, What is your status | [cold] | [warm]",
                    "templateType" => "TEXT",
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(hsm.updated_at, hours: 1), :millisecond)
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = updated_hsm} =
               Repo.fetch_by(SessionTemplate, %{id: hsm.id})

      assert updated_hsm.uuid == updated_uuid
    end

    test "update_hsms/1 should update the existing hsm if new status is other than APPROVED",
         attrs do
      [hsm | _] =
        Templates.list_session_templates(%{
          filter: %{organization_id: attrs.organization_id, is_hsm: true}
        })

      # should update the existing hsm if new status is other than APPROVED
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "id" => hsm.uuid,
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(hsm.updated_at, hours: 1), :millisecond),
                    "status" => "REJECTED"
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} = Repo.fetch_by(SessionTemplate, %{uuid: hsm.uuid})
      assert hsm.status == "REJECTED"
      assert hsm.is_active == false
    end

    def otp_hsm_fixture(language_id, status) do
      uuid = Ecto.UUID.generate()

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "template" => %{
                  "elementName" => "common_otp",
                  "id" => uuid,
                  "languageCode" => "en",
                  "status" => status
                }
              })
          }
      end)

      Fixtures.session_template_fixture(%{
        body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
        shortcode: "common_otp",
        is_hsm: true,
        category: "AUTHENTICATION",
        example:
          "Your OTP for [adding Anil as a payee] is [1234]. This is valid for [15 minutes].",
        language_id: language_id,
        uuid: uuid,
        bsp_id: uuid
      })
    end

    test "update_hsms/1 should update the hsm as approved if no other translation is approved yet",
         attrs do
      otp_hsm_1 = otp_hsm_fixture(1, "PENDING")
      _otp_hsm_2 = otp_hsm_fixture(2, "PENDING")

      # should update the hsm as approved if no other translation is approved yet
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "id" => otp_hsm_1.uuid,
                    "elementName" => otp_hsm_1.shortcode,
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(otp_hsm_1.updated_at, hours: 1), :millisecond),
                    "status" => "APPROVED"
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_1.uuid})

      assert hsm.status == "APPROVED"
      assert hsm.is_active == true
    end

    test "update_hsms/1 should update the status HSM template", attrs do
      otp_hsm_1 = otp_hsm_fixture(1, "PENDING")

      # should update status of pending template
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "id" => otp_hsm_1.uuid,
                    "elementName" => otp_hsm_1.shortcode,
                    "data" => otp_hsm_1.body,
                    "templateType" => "TEXT",
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(otp_hsm_1.updated_at, hours: 1), :millisecond),
                    "status" => "APPROVED",
                    "meta" => Jason.encode!(%{example: otp_hsm_1.example})
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_1.uuid})

      assert hsm.status == "APPROVED"
      assert hsm.is_active == true
    end

    test "update_hsms/1 should update multiple templates of with same shortcode", attrs do
      l1 = Glific.Settings.get_language!(1)
      l2 = Glific.Settings.get_language!(2)
      otp_hsm_1 = otp_hsm_fixture(l1.id, "PENDING")
      otp_hsm_2 = otp_hsm_fixture(l2.id, "PENDING")

      # should update status of pending template
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "id" => otp_hsm_1.uuid,
                    "elementName" => otp_hsm_1.shortcode,
                    "data" => otp_hsm_1.body,
                    "templateType" => "TEXT",
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(otp_hsm_1.updated_at, hours: 1), :millisecond),
                    "status" => "APPROVED",
                    "meta" => Jason.encode!(%{example: otp_hsm_1.example}),
                    "languageCode" => l1.locale
                  },
                  %{
                    "id" => otp_hsm_2.uuid,
                    "elementName" => otp_hsm_2.shortcode,
                    "data" => otp_hsm_2.body,
                    "templateType" => "TEXT",
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(otp_hsm_2.updated_at, hours: 1), :millisecond),
                    "status" => "REJECTED",
                    "meta" => Jason.encode!(%{example: otp_hsm_2.example}),
                    "languageCode" => l2.locale
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm1} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_1.uuid})

      assert hsm1.status == "APPROVED"
      assert hsm1.is_active == true

      assert {:ok, %SessionTemplate{} = hsm2} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_2.uuid})

      assert hsm2.status == "REJECTED"
      assert hsm2.is_active == false
    end

    test "import_templates/1 should import templates", attrs do
      data =
        "\"TEMPLATEID\",\"NAME\",\"CATEGORY\",\"LANGUAGE\",\"TYPE\",\"HEADER\",\"BODY\",\"FOOTER\",\"BUTTONTYPE\",\"NOOFBUTTONS\",\"BUTTON1\",\"BUTTON2\",\"BUTTON3\",\"QUALITYRATING\",\"REJECTIONREASON\",\"STATUS\",\"CREATEDON\"\n\"6356300\",\"beforedemo\",\"ALERT_UPDATE\",\"en\",\"TEXT\",\"\",\"Hi{{1}},Your demo is about to start in 15 min. We are excited to see you there.🤩\nPlease join 5 min before time.\nClick on this link to attend the session. {{2}}\nIn case you face any issues, please call on +918047190520\",\"\",\"NONE\",\"0\",\"\",\"\",\"\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-03-17\"\n\"6516247\",\"new_feature\",\"UTILITY\",\"en\",\"TEXT\",\"\",\"are you excited for upcoming features?\",\"\",\"CALL_TO_ACTION\",\"2\",\"{\"\"type\"\":\"\"PHONE_NUMBER\"\",\"\"phone_number\"\":\"\"+918979120220\"\",\"\"text\"\":\"\"call here\"\"}\",\"{\"\"type\"\":\"\"URL\"\",\"\"urlType\"\":\"\"STATIC\"\",\"\"url\"\":\"\"https://coloredcow.com/blogs/\"\",\"\"text\"\":\"\"visit here\"\"}\",\"\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-09-28\"\n\"6379777\",\"Gender\",\"ACCOUNT_UPDATE\",\"en\",\"TEXT\",\"\",\"Please share your gender\",\"\",\"QUICK_REPLY\",\"3\",\"{\"\"type\"\":\"\"QUICK_REPLY\"\",\"\"text\"\":\"\"Male\"\"}\",\"{\"\"type\"\":\"\"QUICK_REPLY\"\",\"\"text\"\":\"\"Female\"\"}\",\"{\"\"type\"\":\"\"QUICK_REPLY\"\",\"\"text\"\":\"\"Other\"\"}\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-03-22\"\n\"6122571\",\"2meq_payment_link\",\"ACCOUNT_UPDATE\",\"en\",\"TEXT\",\"\",\"Your OTP for {{1}} is {{2}}. This is valid for {{3}}.\",\"\",\"NONE\",\"0\",\"\",\"\",\"\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-03-10\"\n\"6122572\",\"meq_payment_link2\",\"ACCOUNT_UPDATE\",\"en\",\"TEXT\",\"\",\"You are one step away! Please click the link below to make your payment for the Future Perfect program.\",\"\",\"NONE\",\"0\",\"\",\"\",\"\",\"UNKNOWN\",\"NONE\",\"REJECTED\",\"2022-04-05\""

      Template.import_templates(attrs.organization_id, data)

      assert {:ok, %SessionTemplate{} = imported_template} =
               Repo.fetch_by(SessionTemplate, %{bsp_id: "6122571"})

      assert imported_template.status == "APPROVED"
      assert imported_template.shortcode == "2meq_payment_link"
      assert imported_template.language_id == 1
      assert imported_template.category == "UTILITY"

      assert imported_template.example ==
               "Your OTP for [sample text 1] is [sample text 2]. This is valid for [sample text 3]."

      assert {:ok, %SessionTemplate{} = imported_template2} =
               Repo.fetch_by(SessionTemplate, %{bsp_id: "6122572"})

      assert imported_template2.status == "REJECTED"
      assert imported_template2.shortcode == "meq_payment_link2"

      assert imported_template2.example ==
               "You are one step away! Please click the link below to make your payment for the Future Perfect program."

      assert {:ok, %SessionTemplate{} = imported_template3} =
               Repo.fetch_by(SessionTemplate, %{bsp_id: "6379777"})

      assert imported_template3.status == "APPROVED"
      assert imported_template3.shortcode == "Gender"
      assert imported_template3.has_buttons == true
      assert imported_template3.button_type == :quick_reply
      assert imported_template3.body == "Please share your gender"

      assert imported_template3.buttons == [
               %{"text" => "Male ", "type" => "QUICK_REPLY"},
               %{"text" => "Female ", "type" => "QUICK_REPLY"},
               %{"text" => "Other ", "type" => "QUICK_REPLY"}
             ]

      assert {:ok, %SessionTemplate{} = imported_template4} =
               Repo.fetch_by(SessionTemplate, %{bsp_id: "6516247"})

      assert imported_template4.status == "APPROVED"
      assert imported_template4.shortcode == "new_feature"
      assert imported_template4.has_buttons == true
      assert imported_template4.button_type == :call_to_action
      assert imported_template4.body == "are you excited for upcoming features?"

      assert imported_template4.buttons == [
               %{
                 "text" => "call here",
                 "type" => "PHONE_NUMBER",
                 "phone_number" => "+918979120220 "
               },
               %{
                 "text" => "visit here",
                 "type" => "URL",
                 "url" => "https://coloredcow.com/blogs/ "
               }
             ]

      assert {:ok, %SessionTemplate{} = imported_template5} =
               Repo.fetch_by(SessionTemplate, %{bsp_id: "6356300"})

      assert imported_template5.status == "APPROVED"
      assert imported_template5.shortcode == "beforedemo"

      assert imported_template5.body ==
               "Hi{{1}},Your demo is about to start in 15 min. We are excited to see you there.🤩\r\nPlease join 5 min before time.\r\nClick on this link to attend the session. {{2}}\r\nIn case you face any issues, please call on +918047190520"
    end

    test "update_hsms/1 should update multiple templates same shortcode as translation", attrs do
      l1 = Glific.Settings.get_language!(1)
      l2 = Glific.Settings.get_language!(2)
      otp_hsm_1 = otp_hsm_fixture(l1.id, "PENDING")
      otp_hsm_2 = otp_hsm_fixture(l2.id, "PENDING")
      # should update status of pending template
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
                    "id" => otp_hsm_1.uuid,
                    "elementName" => otp_hsm_1.shortcode,
                    "data" => otp_hsm_1.body,
                    "templateType" => "TEXT",
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(otp_hsm_1.updated_at, hours: 1), :millisecond),
                    "status" => "APPROVED",
                    "meta" => Jason.encode!(%{example: otp_hsm_1.example}),
                    "languageCode" => l1.locale
                  },
                  %{
                    "id" => otp_hsm_2.uuid,
                    "elementName" => otp_hsm_2.shortcode,
                    "data" => otp_hsm_2.body,
                    "templateType" => "TEXT",
                    "modifiedOn" =>
                      DateTime.to_unix(Timex.shift(otp_hsm_2.updated_at, hours: 1), :millisecond),
                    "status" => "APPROVED",
                    "meta" => Jason.encode!(%{example: otp_hsm_2.example}),
                    "languageCode" => l2.locale
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm1} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_1.uuid})

      assert {:ok, %SessionTemplate{} = hsm2} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_2.uuid})

      assert hsm1.status == "APPROVED"
      assert hsm1.is_active == true
      translation = hsm1.translations[Integer.to_string(l2.id)]

      assert translation["status"] == "APPROVED"
      assert translation["uuid"] == hsm2.uuid
    end

    test "template_parameters_count/1 should return number of parameters in a template" do
      template_body = "Hi {{1}}, Here is the report for activity {{2}} sent to Grade {{3}}"
      assert Templates.template_parameters_count(%{body: template_body, has_buttons: false}) == 3
      template_body = "Hi {{1}}, Here is the report for activity {{2}} sent to Grade {{1}}"
      assert Templates.template_parameters_count(%{body: template_body, has_buttons: false}) == 2
      template_body = "Thankyou for joining {{1}}"
      assert Templates.template_parameters_count(%{body: template_body, has_buttons: false}) == 1
      template_body = "Welcome to our program"
      assert Templates.template_parameters_count(%{body: template_body, has_buttons: false}) == 0

      template_body =
        "Hi {{1}}, Here is the report for activity {{2}} sent to Grade {{3}}, School {{4}} on date {{5}}: Chapter: {{6}} Topic: {{7}} No. of students who attempted - {{8}}, Accuracy - {{9}}, Watch Time - {{10}}"

      assert Templates.template_parameters_count(%{body: template_body, has_buttons: false}) == 10
    end

    test "parse_buttons/2 should return updated body with buttons" do
      template_body = "Hi {{1}}, What is your status"

      buttons = [
        %{
          "phone_number" => "+917302307943 ",
          "text" => "call here",
          "type" => "PHONE_NUMBER"
        },
        %{
          "text" => "visit here",
          "type" => "URL",
          "url" => "https://github.com/glific"
        }
      ]

      assert Templates.parse_buttons(%{body: template_body, buttons: buttons}, false, true) == %{
               body:
                 "Hi {{1}}, What is your status| [call here, +917302307943 ] | [visit here, https://github.com/glific] ",
               buttons: buttons
             }

      buttons = [
        %{"text" => "cold ", "type" => "QUICK_REPLY"},
        %{"text" => "warm", "type" => "QUICK_REPLY"}
      ]

      assert Templates.parse_buttons(%{body: template_body, buttons: buttons}, false, true) == %{
               body: "Hi {{1}}, What is your status| [cold ] | [warm] ",
               buttons: buttons
             }
    end

    test "report_to_gupshup/3 report mail to gupshup", attrs do
      template = session_template_fixture(Map.merge(attrs, @valid_attrs_1))

      %{id: temp_id} = template
      %{organization_id: org_id} = attrs

      cc = %{"test" => "test@test.com"}
      assert {:ok, %{message: _}} = Templates.report_to_gupshup(org_id, temp_id, cc)
    end

    test "report_to_gupshup/3 report mail to gupshup should throw error when mail is already sent",
         attrs do
      template = session_template_fixture(Map.merge(attrs, @valid_attrs_1))

      %{id: temp_id} = template
      %{organization_id: org_id} = attrs

      %{
        category: "report_gupshup",
        organization_id: attrs.organization_id,
        status: "sent",
        content: %{data: "test mail regarding template rejection"}
      }
      |> MailLog.create_mail_log()

      cc = %{"test" => "test@test.com"}

      assert {:error, "Already a template has been raised to Gupshup in last 24hrs"} =
               Templates.report_to_gupshup(org_id, temp_id, cc)
    end

    test "template from EEx based on variables should be JSON encoded" do
      result = %{
        uuid: "uuid",
        name: "Template",
        variables: [],
        expression: nil
      }

      assert Templates.template("uuid", []) == Jason.encode!(result)
    end
  end
end
