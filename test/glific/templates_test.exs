defmodule Glific.TemplatesTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Mails.MailLog,
    Messages,
    Messages.Message,
    Messages.MessageMedia,
    Notifications,
    Notifications.Notification,
    Partners,
    Providers.Gupshup,
    Providers.Gupshup.PartnerAPI,
    Providers.GupshupEnterprise.Template,
    Seeds.SeedsDev,
    Seeds.SeedsMigration,
    Settings,
    Templates,
    Templates.SessionTemplate,
    Templates.TemplateWorker
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

    test "validates template length with total length exceeding limit", attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "template" => %{
                  "category" => "ACCOUNT_UPDATE",
                  "templateType" => "TEXT"
                }
              })
          }
      end)

      attrs = %{
        body: String.duplicate("a", 1020),
        label: "New Label",
        language_id: language_fixture().id,
        type: :text,
        is_hsm: true,
        category: "ACCOUNT_UPDATE",
        shortcode: "some_shortcode",
        example: String.duplicate("a", 1000),
        organization_id: attrs.organization_id,
        buttons: [%{"text" => "buttontext"}]
      }

      assert {:error, ["Character Limit", "Exceeding character limit"]} =
               Templates.create_session_template(attrs)
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

    test "create_session_template/1 for HSM data with image url, should submit it for approval",
         attrs do
      whatspp_hsm_uuid = "16e84186-97fa-454e-ac3b-8c9b94e53b4b"

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
        "Language,Title,Message,Sample Message,Element Name,Category,Attachment Type,Attachment URL,Has Buttons,Button Type,CTA Button 1 Type,CTA Button 1 Title,CTA Button 1 Value,CTA Button 2 Type,CTA Button 2 Title,CTA Button 2 Value,Quick Reply 1 Title,Quick Reply 2 Title,Quick Reply 3 Title\r\nEnglish,Activity,\"Hi {{1}},\nLook at this image.\",\"Hi [Akhilesh],\nLook at this image.\",activity,UTILITY,image,https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample101.jpg,FALSE,,,,,,,,,,"

      {:ok, %{csv_rows: _csv_rows}} =
        Gupshup.Template.bulk_apply_templates(attrs.organization_id, data)

      %{id: msg_id} =
        MessageMedia
        |> where(
          [msg],
          msg.url == "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample101.jpg"
        )
        |> Repo.one()

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
          },
          "handleId" => %{"message" => "some_handle"}
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
        type: :image,
        shortcode: "ticket_update_status",
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]",
        organization_id: attrs.organization_id,
        message_media_id: msg_id
      }

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.create_session_template(attrs)

      assert session_template.shortcode == "ticket_update_status"
      assert session_template.is_hsm == true
      assert session_template.status == "PENDING"
      assert session_template.uuid == whatspp_hsm_uuid
      assert session_template.language_id == language.id
    end

    test "create_session_template/1 for HSM data with image url but get_media_handle_id raises error ",
         attrs do
      whatspp_hsm_uuid = "16e84186-97fa-454e-ac3b-8c9b94e53b4b"

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
        "Language,Title,Message,Sample Message,Element Name,Category,Attachment Type,Attachment URL,Has Buttons,Button Type,CTA Button 1 Type,CTA Button 1 Title,CTA Button 1 Value,CTA Button 2 Type,CTA Button 2 Title,CTA Button 2 Value,Quick Reply 1 Title,Quick Reply 2 Title,Quick Reply 3 Title\r\nEnglish,Activity,\"Hi {{1}},\nLook at this image.\",\"Hi [Akhilesh],\nLook at this image.\",activity,UTILITY,image,https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample02.jpg,FALSE,,,,,,,,,,"

      {:ok, %{csv_rows: _csv_rows}} =
        Gupshup.Template.bulk_apply_templates(attrs.organization_id, data)

      %{id: msg_id} =
        MessageMedia
        |> where(
          [msg],
          msg.url == "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample02.jpg"
        )
        |> Repo.one()

      # get_media_handle_id raises because the body doesnt have correct response
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
        type: :image,
        shortcode: "ticket_update_status",
        category: "ACCOUNT_UPDATE",
        example: "Your train ticket no. [1234]",
        organization_id: attrs.organization_id,
        message_media_id: msg_id
      }

      resp =
        try do
          Templates.create_session_template(attrs)
        rescue
          _ ->
            "Invalid response"
        end

      assert resp == "Invalid response"

      # need explicit cleanup, since the test raises error (and should be), so auto cleanup won't happen
      PartnerAPI.delete_local_resource(
        "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample02.jpg",
        attrs.shortcode
      )
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

    test "create_session_template/1 for HSM button template should submit it for approval if the button type is whatsapp form",
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
        button_type: :whatsapp_form,
        buttons: [%{"text" => "confirm", "type" => "FLOW"}]
      }

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.create_session_template(attrs)

      assert session_template.shortcode == "conference_ticket_status"
      assert session_template.is_hsm == true
      assert session_template.status == "PENDING"
      assert session_template.uuid == whatspp_hsm_uuid
      assert session_template.language_id == language.id

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

      assert {:error, ["BSP", "Couldn't submit for approval: Something went wrong"]} =
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
        %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/token"} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "xyz456"}})
          }

        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{}),
            headers: %{
              "content-type" => "image",
              "content-length" => "1232"
            }
          }

        %{method: :post, url: "https://partner.gupshup.io/partner/account/login"} ->
          %Tesla.Env{
            status: 200,
            body: "{\"token\":\"abc123\"}"
          }

        %{method: :post, url: "https://partner.gupshup.io/partner/app/Glific42/templates"} ->
          uuid = Ecto.UUID.generate()

          %Tesla.Env{
            status: 200,
            body: "{\"template\":{\"id\":\"#{uuid}\"}}"
          }

        %{method: :post, url: "https://partner.gupshup.io/partner/app/Glific42/upload/media"} ->
          %Tesla.Env{
            status: 200,
            body: "{\"handleId\":{\"message\":\"123\"},\"status\":\"success\"}"
          }
      end)

      data =
        "Language,Title,Message,Sample Message,Element Name,Category,Attachment Type,Attachment URL,Has Buttons,Button Type,CTA Button 1 Type,CTA Button 1 Title,CTA Button 1 Value,CTA Button 2 Type,CTA Button 2 Title,CTA Button 2 Value,Quick Reply 1 Title,Quick Reply 2 Title,Quick Reply 3 Title\r\nEnglish,Signup Arogya,\"Hi {{1}},\nWelcome to the world\",\"Hi [Akhilesh],\nWelcome to the world\",welcome_arogya,SEMI-UTILITY,,,FALSE,,,,,,,,,,\r\nEnglish,Welcome Arogya,\"Hi {{1}},\nWelcome to the world\",\"Hi [Akhilesh],\nWelcome to the world\",signup_arogya,UTILITY,,,TRUE,QUICK_REPLY,,,,,,,Yes,No,\r\nMandarin,Help Arogya,\"Hi {{1}},Need help?\",\"Hi [Akhilesh],Need help?\",help_arogya,UTILITY,,,TRUE,CALL_TO_ACTION,PHONE_NUMBER,Call here,8979120220,URL,Visit Here,https://github.com/glific,,,\r\nEnglish,Activity,\"Hi {{1}},\nLook at this image.\",\"Hi [Akhilesh],\nLook at this image.\",activity,UTILITY,image,https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample02.jpg,FALSE,,,,,,,,,,\r\nEnglish,Signout Arogya,\"Hi {{1}},\nSorry to see you go\",\"Hi [Akhilesh],\nSorry to see you move out\",signout_arogya,UTILITY,,,FALSE,,,,,,,,,,\r\nEnglish,Optin Arogya,\"Hi {{1}},\n Reply with yes to optin\",\"Hi [Akhilesh],\Reply with yes to optin\",optin_arogya,UTILITY,,,TRUE,,,,,,,,,,\r\nEnglish,Help Arogya 2,\"Hi {{1}},Need help?\",\"Hi [Akhilesh],Need help?\",help_arogya_2,UTILITY,,,TRUE,CALL_TO_ACTION,PHONE_NUMBER,Call here,8979120220,URL,Visit Here,https://github.com/glific,,,\r\nEnglish,Signup Arogya 2,\"Hi {{1}},\nWelcome to the world\",\"Hi [Akhilesh],\nWelcome to the world\",welcome_arogya,UTILITY,,,FALSE,,,,,,,,,,\r\nEnglish,Welcome Arogya 2,\"Hi {{1}},\nWelcome to the world\",\"Hi [Akhilesh],\nWelcome to the world\",signup_arogya_2,UTILITY,,,TRUE,QUICK_REPLY,,,,,,,Yes,No,"

      {:ok, %{csv_rows: csv_rows}} =
        Gupshup.Template.bulk_apply_templates(attrs.organization_id, data)

      assert csv_rows ==
               "Title,Status\r\nSignup Arogya,Invalid Category\r\nWelcome Arogya,Template has been applied successfully\r\nHelp Arogya,Invalid Language\r\nActivity,Template has been applied successfully\r\nSignout Arogya,Message and Sample Message does not match\r\nOptin Arogya,Invalid Button Type\r\nHelp Arogya 2,Template has been applied successfully\r\nSignup Arogya 2,Template has been applied successfully\r\nWelcome Arogya 2,Template has been applied successfully"

      assert %{success: 5, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :default)
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

    test "update_hsms/1 should insert newly received whatsapp form button HSM with type as whatsapp_form",
         attrs do
      whatspp_hsm_uuid = "16e84186-97fa-454e-ac3b-8c9c94e53b4b"

      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
                  %{
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
                    "vertical" => "ACTION_BUTTON",
                    "buttonSupported" => "FLOW",
                    "containerMeta" =>
                      Jason.encode!(%{
                        "buttons" => [%{"text" => "confirm", "type" => "FLOW"}]
                      })
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: whatspp_hsm_uuid})

      assert hsm.button_type == :whatsapp_form

      assert hsm.buttons == [
               %{"text" => "confirm", "type" => "FLOW"}
             ]
    end

    test "update_hsms/1 should handle whatsapp form responses when containerMeta is empty",
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
                    "category" => "ACCOUNT_UPDATE",
                    "createdOn" => 1_595_904_220_495,
                    "data" => "Body without buttons",
                    "elementName" => "missing_meta_flow_template",
                    "id" => "0f7c7e51-f611-4dbf-b4d3-4962f8f79351",
                    "languageCode" => "en",
                    "languagePolicy" => "deterministic",
                    "master" => true,
                    "meta" => "{\"example\":\"Body without buttons\"}",
                    "modifiedOn" => 1_595_904_220_495,
                    "status" => "PENDING",
                    "templateType" => "TEXT",
                    "vertical" => "ACTION_BUTTON",
                    "buttonSupported" => "FLOW",
                    "containerMeta" => Jason.encode!(%{})
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{shortcode: "missing_meta_flow_template"})

      refute hsm.has_buttons
      assert hsm.button_type == nil
      assert hsm.buttons == []
    end

    test "update_hsms/1 should handle whatsapp form responses without containerMeta gracefully",
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
                    "category" => "ACCOUNT_UPDATE",
                    "createdOn" => 1_595_904_220_495,
                    "data" => "Body without buttons",
                    "elementName" => "missing_meta_flow_template",
                    "id" => "0f7c7e51-f611-4dbf-b4d3-4962f8f79351",
                    "languageCode" => "en",
                    "languagePolicy" => "deterministic",
                    "master" => true,
                    "meta" => "{\"example\":\"Body without buttons\"}",
                    "modifiedOn" => 1_595_904_220_495,
                    "status" => "PENDING",
                    "templateType" => "TEXT",
                    "vertical" => "ACTION_BUTTON",
                    "buttonSupported" => "FLOW"
                  }
                ]
              })
          }
      end)

      Templates.sync_hsms_from_bsp(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{shortcode: "missing_meta_flow_template"})

      refute hsm.has_buttons
      assert hsm.button_type == nil
      assert hsm.buttons == []
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
                  "elementName" => "verify_otp",
                  "id" => uuid,
                  "languageCode" => "en",
                  "status" => status
                }
              })
          }
      end)

      Fixtures.session_template_fixture(%{
        body: """
        {{1}} is your verification code. For your security, do not share this code.
        """,
        shortcode: "verify_otp",
        is_hsm: true,
        category: "AUTHENTICATION",
        example: """
        [112233] is your verification code. For your security, do not share this code.
        """,
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
        "\"TEMPLATEID\",\"NAME\",\"CATEGORY\",\"LANGUAGE\",\"TYPE\",\"HEADER\",\"BODY\",\"FOOTER\",\"BUTTONTYPE\",\"NOOFBUTTONS\",\"BUTTON1\",\"BUTTON2\",\"BUTTON3\",\"QUALITYRATING\",\"REJECTIONREASON\",\"STATUS\",\"CREATEDON\"\n\"6356300\",\"beforedemo\",\"ALERT_UPDATE\",\"en\",\"TEXT\",\"\",\"Hi{{1}},Your demo is about to start in 15 min. We are excited to see you there.🤩\nPlease join 5 min before time.\nClick on this link to attend the session. {{2}}\nIn case you face any issues, please call on +918047190520\",\"\",\"NONE\",\"0\",\"\",\"\",\"\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-03-17\"\n\"6516247\",\"new_feature\",\"UTILITY\",\"en\",\"TEXT\",\"\",\"are you excited for upcoming features?\",\"\",\"CALL_TO_ACTION\",\"2\",\"{\"\"type\"\":\"\"PHONE_NUMBER\"\",\"\"phone_number\"\":\"\"+918979120220\"\",\"\"text\"\":\"\"call here\"\"}\",\"{\"\"type\"\":\"\"URL\"\",\"\"urlType\"\":\"\"STATIC\"\",\"\"url\"\":\"\"https://glific.com/blogs/\"\",\"\"text\"\":\"\"visit here\"\"}\",\"\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-09-28\"\n\"6379777\",\"Gender\",\"ACCOUNT_UPDATE\",\"en\",\"TEXT\",\"\",\"Please share your gender\",\"\",\"QUICK_REPLY\",\"3\",\"{\"\"type\"\":\"\"QUICK_REPLY\"\",\"\"text\"\":\"\"Male\"\"}\",\"{\"\"type\"\":\"\"QUICK_REPLY\"\",\"\"text\"\":\"\"Female\"\"}\",\"{\"\"type\"\":\"\"QUICK_REPLY\"\",\"\"text\"\":\"\"Other\"\"}\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-03-22\"\n\"6122571\",\"2meq_payment_link\",\"ACCOUNT_UPDATE\",\"en\",\"TEXT\",\"\",\"Your OTP for {{1}} is {{2}}. This is valid for {{3}}.\",\"\",\"NONE\",\"0\",\"\",\"\",\"\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-03-10\"\n\"6122572\",\"meq_payment_link2\",\"ACCOUNT_UPDATE\",\"en\",\"TEXT\",\"\",\"You are one step away! Please click the link below to make your payment for the Future Perfect program.\",\"\",\"NONE\",\"0\",\"\",\"\",\"\",\"UNKNOWN\",\"NONE\",\"REJECTED\",\"2022-04-05\""

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
                 "url" => "https://glific.com/blogs/ "
               }
             ]

      assert {:ok, %SessionTemplate{} = imported_template5} =
               Repo.fetch_by(SessionTemplate, %{bsp_id: "6356300"})

      assert imported_template5.status == "APPROVED"
      assert imported_template5.shortcode == "beforedemo"

      assert imported_template5.body ==
               "Hi{{1}},Your demo is about to start in 15 min. We are excited to see you there.🤩\nPlease join 5 min before time.\nClick on this link to attend the session. {{2}}\nIn case you face any issues, please call on +918047190520"
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

  test "import_templates/1 should not update the uuid of already existing template",
       attrs do
    enable_gupshup_enterprise(attrs)

    data =
      "\"TEMPLATEID\",\"NAME\",\"PREVIOUSCATEGORY\",\"CATEGORY\",\"LANGUAGE\",\"TYPE\",\"HEADER\",\"BODY\",\"FOOTER\",\"BUTTONTYPE\",\"NOOFBUTTONS\",\"BUTTON1\",\"BUTTON2\",\"BUTTON3\",\"QUALITYRATING\",\"REJECTIONREASON\",\"STATUS\",\"CREATEDON\",\"LASTUPDATEDON\"\n\"6379781\",\"multiline_daily_status\",\"ACCOUNT_UPDATE\",\"MARKETING\",\"en\",\"TEXT\",\"\",\"Hey there!\nHow is your day today?\",\"\",\"NONE\",\"0\",\"\",\"\",\"\",\"UNKNOWN\",\"NONE\",\"ENABLED\",\"2022-04-05\",\"2023-04-27 03:05:41\"\n"

    Template.import_templates(attrs.organization_id, data)

    [hsm1 | _rest] =
      Templates.list_session_templates(%{
        filter: %{
          organization_id: attrs.organization_id,
          is_hsm: true,
          shortcode: "multiline_daily_status"
        }
      })

    # again importing the same template
    Template.import_templates(attrs.organization_id, data)

    [hsm2 | _rest] =
      Templates.list_session_templates(%{
        filter: %{
          organization_id: attrs.organization_id,
          is_hsm: true,
          shortcode: "multiline_daily_status"
        }
      })

    assert hsm1.uuid == hsm2.uuid
  end

  defp enable_gupshup_enterprise(attrs) do
    updated_attrs = %{
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "gupshup_enterprise"
    }

    {:ok, cred} =
      Partners.get_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "gupshup_enterprise"
      })

    Partners.update_credential(cred, updated_attrs)
  end

  test "create_session_template/1 for HSM button template should not accept improper input",
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

    # Test with variables
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
      buttons: [%{"text" => "{{user_name}}", "type" => "QUICK_REPLY"}]
    }

    assert {:error,
            [
              "Button Template",
              "Button texts cannot contain any variables, newlines, emojis or formatting characters (e.g., bold, italics)."
            ]} =
             Templates.create_session_template(attrs)

    # Test with newlines
    attrs_2 = %{
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
      buttons: [%{"text" => "Line 1\nLine 2", "type" => "QUICK_REPLY"}]
    }

    assert {:error,
            [
              "Button Template",
              "Button texts cannot contain any variables, newlines, emojis or formatting characters (e.g., bold, italics)."
            ]} =
             Templates.create_session_template(attrs_2)

    # Test with emojis
    attrs_3 = %{
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
      buttons: [%{"text" => "Hello 😊", "type" => "QUICK_REPLY"}]
    }

    assert {:error,
            [
              "Button Template",
              "Button texts cannot contain any variables, newlines, emojis or formatting characters (e.g., bold, italics)."
            ]} =
             Templates.create_session_template(attrs_3)

    # Test with formatting characters (bold and italics)
    attrs_4 = %{
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
      buttons: [%{"text" => "**Bold Text**", "type" => "QUICK_REPLY"}]
    }

    assert {:error,
            [
              "Button Template",
              "Button texts cannot contain any variables, newlines, emojis or formatting characters (e.g., bold, italics)."
            ]} =
             Templates.create_session_template(attrs_4)

    # Test with a combination of different cases
    attrs_5 = %{
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
      buttons: [
        %{
          "text" => "Hello {{user_name}}, here is a new line\nand an emoji 😊",
          "type" => "QUICK_REPLY"
        }
      ]
    }

    assert {:error,
            [
              "Button Template",
              "Button texts cannot contain any variables, newlines, emojis or formatting characters (e.g., bold, italics)."
            ]} =
             Templates.create_session_template(attrs_5)

    # check for hindi content
    attrs = %{
      body: "इनमें से कौन सा विकल्प आपके आवासीय स्थिति का सबसे अच्छा वर्णन करता है?",
      label: "New Label",
      language_id: language.id,
      is_hsm: true,
      type: :text,
      shortcode: "conference_ticket_status",
      category: "UTILITY",
      example: "इनमें से कौन सा विकल्प आपके आवासीय स्थिति का सबसे अच्छा वर्णन करता है?",
      organization_id: attrs.organization_id,
      has_buttons: true,
      button_type: "quick_reply",
      buttons: [%{"text" => "खुद के घर में रहते हैं ", "type" => "QUICK_REPLY"}]
    }

    assert {:ok, %SessionTemplate{} = session_template} =
             Templates.create_session_template(attrs)

    assert session_template.shortcode == "conference_ticket_status"
    assert session_template.is_hsm == true
    assert session_template.language_id == language.id
  end

  @org_id 1

  test "successful HSM sync from BSP", attrs do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://partner.gupshup.io/partner/account/login"} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"token" => "sk_test_partner_token"})
        }

      %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/token"} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "data" => %{
                "partner_app_token" => "fake-token"
              }
            })
        }

      %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/templates"} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "templates" => [
                %{
                  "id" => "51eddb1e-8e36-44df-a9e5-2815e4f8463b",
                  "elementName" => "qa_automation_qa_automation_112907flejpaiqah9z",
                  "languageCode" => "en",
                  "category" => "MARKETING",
                  "status" => "APPROVED",
                  "templateType" => "TEXT",
                  "data" =>
                    "Dear {{1}}\nExclusive deals on car and train bookings. Book now..!!\nThank you"
                }
              ]
            })
        }
    end)

    context = %{context: %{current_user: attrs}}

    assert {:ok, %{message: "HSM sync job queued successfully"}} =
             GlificWeb.Resolvers.Templates.sync_hsm_template(nil, %{}, context)

    assert_enqueued(worker: TemplateWorker, prefix: "global")

    assert {:ok, %{message: "HSM sync job already in progress"}} =
             GlificWeb.Resolvers.Templates.sync_hsm_template(nil, %{}, context)

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :default, with_safety: false)

    notifications =
      Repo.all(
        from n in Notification,
          where: n.organization_id == ^@org_id and n.category == "HSM template",
          order_by: [desc: n.inserted_at]
      )

    messages = Enum.map(notifications, & &1.message)

    assert "Syncing of HSM templates has started in the background." in messages
    assert "HSM template sync completed successfully." in messages

    severities = Enum.map(notifications, & &1.severity)
    assert Notifications.types().info in severities
  end

  test "handle the failure case when the sync fails", attrs do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://partner.gupshup.io/partner/account/login"} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"token" => "sk_test_partner_token"})
        }

      %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/token"} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "data" => %{
                "partner_app_token" => "fake-token"
              }
            })
        }

      %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/templates"} ->
        %Tesla.Env{
          status: 500,
          body: "Internal Server Error"
        }
    end)

    context = %{context: %{current_user: attrs}}

    assert {:ok, %{message: "HSM sync job queued successfully"}} =
             GlificWeb.Resolvers.Templates.sync_hsm_template(nil, %{}, context)

    assert_enqueued(worker: TemplateWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :default)

    notifications =
      Repo.all(
        from n in Notification,
          where: n.organization_id == ^@org_id and n.category == "HSM template",
          order_by: [desc: n.inserted_at]
      )

    messages = Enum.map(notifications, & &1.message)

    assert "Syncing of HSM templates has started in the background." in messages

    assert Enum.any?(messages, fn msg ->
             String.contains?(msg, "Failed to sync HSM templates")
           end)

    severities = Enum.map(notifications, & &1.severity)
    assert Notifications.types().critical in severities
  end

  test "submit_otp_template_for_org/1 should submit verify_otp template for approval", attrs do
    otp_uuid = Ecto.UUID.generate()

    token_response =
      Jason.encode!(%{
        "data" => %{
          "partner_app_token" => "fake-partner-token"
        }
      })

    body =
      Jason.encode!(%{
        "status" => "success",
        "template" => %{
          "category" => "AUTHENTICATION",
          "createdOn" => 1_695_904_220_000,
          # returning additional content beyond what we are passing to the template
          # because of the addSecurityRecommendation check. In the OTP template,
          # this adds the default security message: “For your security, do not share this code.”
          "data" => "{{1}} is your verification code. For your security, do not share this code.",
          "elementName" => "verify_otp",
          "id" => otp_uuid,
          "languageCode" => "en",
          "languagePolicy" => "deterministic",
          "master" => true,
          "meta" =>
            "{\"example\":\"[112233] is your verification code. For your security, do not share this code.\"}",
          "modifiedOn" => 1_695_904_220_000,
          "status" => "PENDING",
          "templateType" => "TEXT",
          "vertical" => "AUTHENTICATION"
        }
      })

    Tesla.Mock.mock(fn
      %{method: :post, url: "https://partner.gupshup.io/partner/account/login"} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"token" => "sk_test_partner_token"})
        }

      %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/token"} ->
        %Tesla.Env{status: 200, body: token_response}

      %{method: :post, url: "https://partner.gupshup.io/partner/app/Glific42/templates"} ->
        uuid = otp_uuid

        %Tesla.Env{
          status: 200,
          body: "{\"template\":{\"id\":\"#{uuid}\"}}"
        }

      %{method: :post, url: "https://partner.gupshup.io/partner/message/template"} ->
        %Tesla.Env{status: 200, body: body}
    end)

    assert {:ok, %SessionTemplate{} = template} =
             SeedsMigration.submit_otp_template_for_org(attrs.organization_id)

    assert template.label == "verify_otp"
    assert template.uuid == otp_uuid
    assert template.category == "AUTHENTICATION"

    assert template.buttons == [
             %{"otp_type" => "COPY_CODE", "text" => "Copy code", "type" => "OTP"}
           ]
  end

  test "create_and_send_otp_template_message/2 validates parameters and sends OTP", attrs do
    contact = Fixtures.contact_fixture(attrs)

    template =
      Fixtures.session_template_fixture(%{
        organization_id: attrs.organization_id,
        label: "verify_otp",
        shortcode: "verify_otp",
        body: "{{1}} is your verification code.",
        example: "[112233] is your verification code.",
        number_parameters: 1
      })

    body =
      Jason.encode!(%{
        "status" => "success",
        "template" => %{
          "category" => "AUTHENTICATION",
          "createdOn" => 1_695_904_220_000,
          "data" => "{{1}} is your verification code. For your security, do not share this code.",
          "elementName" => "verify_otp",
          "id" => template.uuid,
          "languageCode" => "en",
          "languagePolicy" => "deterministic",
          "master" => true,
          "meta" =>
            "{\"example\":\"[112233] is your verification code. For your security, do not share this code.\"}",
          "modifiedOn" => 1_695_904_220_000,
          "status" => "PENDING",
          "templateType" => "TEXT",
          "vertical" => "AUTHENTICATION"
        }
      })

    Tesla.Mock.mock(fn
      %{method: :post, url: "https://partner.gupshup.io/partner/message/template"} ->
        %Tesla.Env{status: 200, body: body}
    end)

    # Incorrect number of parameters should give an error
    parameters = ["registration", "otp"]

    {:error, error_message} =
      %{template_id: template.id, receiver_id: contact.id, parameters: parameters}
      |> Messages.create_and_send_hsm_message()

    assert error_message == "Please provide the right number of parameters for the template."

    # Correct number of parameters should create and send hsm message
    parameters = ["otp"]

    assert {:ok, %Message{}} =
             %{template_id: template.id, receiver_id: contact.id, parameters: parameters}
             |> Messages.create_and_send_hsm_message()
  end

  test "info notification created on existing HSM template status change to FAILED",
       %{organization_id: organization_id} = attrs do
    whatspp_hsm_uuid = "16e84186-97fa-454e-ac3b-8c9c94e53b4b"

    Tesla.Mock.mock(fn
      %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/templates"} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "templates" => [
                %{
                  "id" => whatspp_hsm_uuid,
                  "elementName" => "conference_ticket_status",
                  "languageCode" => "en",
                  "category" => "UTILITY",
                  "status" => "FAILED",
                  "templateType" => "TEXT",
                  "data" => "Your conference ticket no. {{1}}"
                }
              ]
            })
        }

      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"token" => %{"token" => "Fake Token"}})
        }

      %{method: :post, url: "https://partner.gupshup.io/partner/account/login"} ->
        %Tesla.Env{status: 200, body: Jason.encode!(%{"token" => "sk_test_partner_token"})}

      %{method: :post, url: "https://partner.gupshup.io/partner/app/Glific42/templates"} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "success",
              "template" => %{
                "category" => "UTILITY",
                "createdOn" => 1_595_904_220_495,
                "data" => "Your conference ticket no. {{1}}",
                "elementName" => "conference_ticket_status",
                "id" => whatspp_hsm_uuid,
                "languageCode" => "en",
                "languagePolicy" => "deterministic",
                "bsp_id" => 1,
                "master" => true,
                "meta" => "{\"example\":\"Your conference ticket no. [1234]\"}",
                "modifiedOn" => 1_595_904_220_495,
                "status" => "PENDING",
                "templateType" => "TEXT"
              }
            })
        }
    end)

    Fixtures.session_template_fixture(%{
      body: "Your conference ticket no. {{1}}",
      label: "New Label",
      language_id: 1,
      is_hsm: true,
      type: :text,
      shortcode: "conference_ticket_status",
      category: "UTILITY",
      example: "Your conference ticket no. 1234",
      organization_id: attrs.organization_id,
      has_buttons: false,
      bsp_id: whatspp_hsm_uuid
    })

    Templates.sync_hsms_from_bsp(attrs.organization_id)

    notifications =
      Repo.all(
        from n in Notification,
          where: n.organization_id == ^organization_id and n.category == "Templates",
          order_by: [desc: n.inserted_at]
      )

    messages = Enum.map(notifications, & &1.message)

    assert [
             "Template conference_ticket_status has been failed"
           ] = messages
  end

  test "attach_footer adds the footer to the template if provided", attrs do
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
      footer: "footer",
      type: :text,
      shortcode: "ticket_update_status",
      category: "ACCOUNT_UPDATE",
      example: "Your train ticket no. [1234]",
      organization_id: attrs.organization_id
    }

    assert {:ok, %SessionTemplate{} = session_template} =
             Templates.create_session_template(attrs)

    assert session_template.footer == "footer"
  end
end
