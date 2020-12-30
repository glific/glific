defmodule Glific.TemplatesTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Settings,
    Templates,
    Templates.SessionTemplate
  }

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
      label: "English (United States)",
      label_locale: "English",
      locale: "en_US",
      is_active: true
    }
    @valid_language_attrs_1 %{
      label: "Hindi (United States)",
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

    test "list_session_templates/1 with term filter on session_templates", attrs do
      # Match term with labe/body/shortcode of template
      session_template_fixture(Map.merge(attrs, %{label: "filterterm"}))
      session_template_fixture(Map.merge(attrs, %{label: "label2", body: "filterterm"}))
      session_template_fixture(Map.merge(attrs, %{label: "label3", shortcode: "filterterm"}))

      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{term: "filterterm"})})

      assert length(session_template_list) == 3

      # Match term with label/shortcode of associated tag
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

      session_template_list =
        Templates.list_session_templates(%{filter: Map.merge(attrs, %{term: "filterterm"})})

      assert length(session_template_list) == 5

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

      Tesla.Mock.mock(fn
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
                  "id" => whatspp_hsm_uuid,
                  "languageCode" => "en_US",
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

      assert {:ok, %SessionTemplate{} = session_template} =
               Templates.create_session_template(attrs)

      assert session_template.shortcode == "ticket_update_status"
      assert session_template.is_hsm == true
      assert session_template.status == "PENDING"
      assert session_template.uuid == whatspp_hsm_uuid
      assert session_template.language_id == language.id
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
                "message" => "Template Not Supported On Gupshup Platform"
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

      assert {:error,
              [
                "BSP response status: 400",
                "{\"message\":\"Template Not Supported On Gupshup Platform\",\"status\":\"error\"}"
              ]} = Templates.create_session_template(attrs)
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
                  "languageCode" => "en_US",
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
                  "languageCode" => "en_US",
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
                    "languageCode" => "en_US",
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

      Templates.update_hsms(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: "16e84186-97fa-454e-ac3b-8c9b94e53b4b"})

      assert hsm.example != nil
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

      assert {:error, _message} = Templates.update_hsms(attrs.organization_id)
    end

    test "update_hsms/1 should update status of already existing HSM", attrs do
      [hsm | _] =
        Templates.list_session_templates(%{
          filter: %{organization_id: attrs.organization_id, is_hsm: true}
        })

      # shouldn't update if BSP hasn't updated it since last update in the db
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
                  }
                ]
              })
          }
      end)

      Templates.update_hsms(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = updated_hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: hsm.uuid})

      assert updated_hsm.status == hsm.status
      assert updated_hsm.is_active == hsm.is_active

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

      Templates.update_hsms(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} = Repo.fetch_by(SessionTemplate, %{uuid: hsm.uuid})
      assert hsm.status == "APPROVED"
      assert hsm.is_active == true
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

      Templates.update_hsms(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} = Repo.fetch_by(SessionTemplate, %{uuid: hsm.uuid})
      assert hsm.status == "REJECTED"
      assert hsm.is_active == false
    end

    def otp_hsm_fixture(language_id, status) do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "template" => %{
                  "elementName" => "common_otp",
                  "id" => Ecto.UUID.generate(),
                  "languageCode" => "en_US",
                  "status" => status
                }
              })
          }
      end)

      Fixtures.session_template_fixture(%{
        body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
        shortcode: "common_otp",
        is_hsm: true,
        category: "ALERT_UPDATE",
        example:
          "Your OTP for [adding Anil as a payee] is [1234]. This is valid for [15 minutes].",
        language_id: language_id
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

      Templates.update_hsms(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_1.uuid})

      assert hsm.status == "APPROVED"
      assert hsm.is_active == true
    end

    test "update_hsms/1 should update the translation of already approved HSM", attrs do
      otp_hsm_1 = otp_hsm_fixture(1, "PENDING")
      otp_hsm_2 = otp_hsm_fixture(2, "APPROVED")

      # should update tranlations of already approved HSM
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

      Templates.update_hsms(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_2.uuid})

      assert hsm.status == "APPROVED"
      assert hsm.is_active == true
      assert hsm.translations["#{otp_hsm_1.language_id}"] != nil
      assert hsm.translations["#{otp_hsm_1.language_id}"]["uuid"] == otp_hsm_1.uuid

      # should delete old entry
      assert {:error, _} = Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_1.uuid})
    end

    test "update_hsms/1 should update multiple translations of already approved HSM", attrs do
      [l1, l2 | _] = Glific.Settings.list_languages()

      otp_hsm_1 = otp_hsm_fixture(l1.id, "APPROVED")
      otp_hsm_2 = otp_hsm_fixture(l2.id, "PENDING")

      # should update tranlations of already approved HSM
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "templates" => [
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

      Templates.update_hsms(attrs.organization_id)

      assert {:ok, %SessionTemplate{} = hsm} =
               Repo.fetch_by(SessionTemplate, %{uuid: otp_hsm_1.uuid})

      assert hsm.translations["#{otp_hsm_2.language_id}"] != nil
    end
  end
end
