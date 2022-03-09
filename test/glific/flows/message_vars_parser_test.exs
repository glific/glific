defmodule Glific.Flows.MessageVarParserTest do
  use Glific.DataCase, async: true

  alias Glific.Contacts
  alias Glific.Flows.MessageVarParser

  test "parse/2 will parse the string with variable", attrs do
    # binding with 1 dots will replace the variable
    assert "hello Glific" ==
             MessageVarParser.parse("hello @contact.name", %{"contact" => %{"name" => "Glific"}})

    assert "hello Glific" ==
             MessageVarParser.parse("hello @contact.name.", %{"contact" => %{"name" => "Glific"}})

    assert "hello Glific" ==
             MessageVarParser.parse("hello @organization.name", %{
               "organization" => %{"name" => "Glific"}
             })

    assert "admin" ==
             MessageVarParser.parse(
               "@results.set_contact_profile.profile.user_roles.role_type",
               %{
                 "results" => %{
                   "set_contact_profile" => %{
                     "profile" => %{
                       "user_roles" => %{
                         "role_type" => "admin"
                       }
                     }
                   }
                 }
               }
             )

    assert "hello @organization.name" == MessageVarParser.parse("hello @organization.name", [])

    results = %{
      "points" => %{
        "input" => "100",
        "intent" => nil,
        "category" => "Has Number",
        "inserted_at" => "2021-10-19T10:37:36.231523Z"
      }
    }

    assert "You have 100 points" ==
             MessageVarParser.parse("You have @results.points points", %{
               "results" => results
             })

    assert "You have 100 points" ==
             MessageVarParser.parse("You have @results.points.input points", %{
               "results" => results
             })

    assert "hello Help Workflow" ==
             MessageVarParser.parse("hello @flow.name", %{
               "flow" => %{"name" => "Help Workflow"}
             })

    # binding with 2 or 2 dots will replace the variable
    parsed_test =
      MessageVarParser.parse("hello @contact.fields.name", %{
        "contact" => %{"fields" => %{"name" => "Glific"}}
      })

    assert parsed_test == "hello Glific"

    parsed_test =
      MessageVarParser.parse("hello @contact.fields.name.category", %{
        "contact" => %{"fields" => %{"name" => %{"category" => "Glific"}}}
      })

    assert parsed_test == "hello Glific"

    # if variable is not defined then it won't effect the input
    parsed_test =
      MessageVarParser.parse("hello @contact.fields.name", %{
        "results" => %{"fields" => %{"name" => "Glific"}}
      })

    assert parsed_test == "hello @contact.fields.name"

    # atom keys will be convert into string automatically
    parsed_test = MessageVarParser.parse("hello @contact.name", %{"contact" => %{name: "Glific"}})

    assert parsed_test == "hello Glific"

    [contact | _tail] = Contacts.list_contacts(%{filter: attrs})
    contact = Map.from_struct(contact)
    parsed_test = MessageVarParser.parse("hello @contact.name", %{"contact" => contact})
    assert parsed_test == "hello #{contact.name}"

    [contact | _tail] = Contacts.list_contacts(%{filter: attrs})

    {:ok, contact} =
      Contacts.update_contact(contact, %{
        fields: %{
          "name" => %{
            "type" => "string",
            "value" => "Glific Contact",
            "inserted_at" => "2020-08-04"
          },
          "age" => %{
            "type" => "string",
            "value" => "20",
            "inserted_at" => "2020-08-04"
          }
        }
      })

    contact = Map.from_struct(contact)

    parsed_test =
      MessageVarParser.parse(
        "hello @contact.fields.name, your age is @contact.fields.age years.",
        %{"contact" => contact}
      )

    assert parsed_test == "hello Glific Contact, your age is 20 years."

    ## for contact groups
    conatct_fields = Contacts.get_contact_field_map(contact.id)
    assert MessageVarParser.parse("@contact.in_groups", %{"contact" => conatct_fields}) == "[]"
    assert MessageVarParser.parse("@contact.groups", %{"contact" => conatct_fields}) == "[]"
    assert MessageVarParser.parse("Hello world", nil) == "Hello world"
    assert MessageVarParser.parse("Hello world", %{}) == "Hello world"

    ## Parse all the keys and values in a map
    assert MessageVarParser.parse_map("ABC", nil) == "ABC"

    map =
      MessageVarParser.parse_map(%{"key" => "@contact.name"}, %{"contact" => %{"name" => "ABC"}})

    assert Map.get(map, "key") == "ABC"

    ## Parse all the results
    assert MessageVarParser.parse_results("@contact.name", nil) == "@contact.name"

    MessageVarParser.parse(
      "hello @contact.fields.name, your age is @contact.fields.age years.",
      %{"contact" => contact}
    )

    assert MessageVarParser.parse(
             "hello @results.name",
             %{"results" => %{"name" => %{"input" => "Jatin"}}}
           ) == "hello Jatin"

    assert MessageVarParser.parse(
             "hello @results.name.input",
             %{"results" => %{"name" => %{"input" => "Jatin"}}}
           ) == "hello Jatin"

    now = DateTime.utc_now()

    assert MessageVarParser.parse(
             "hello @results.name.inserted_at",
             %{"results" => %{"name" => %{"input" => "Jatin", "inserted_at" => now}}}
           ) == "hello " <> DateTime.to_string(now)

    assert MessageVarParser.parse(
             "hello @results.parent.name",
             %{"results" => %{"parent" => %{"name" => %{"input" => "Jatin"}}}}
           ) == "hello Jatin"

    assert MessageVarParser.parse(
             "hello @results.parent.name.input",
             %{"results" => %{"parent" => %{"name" => %{"input" => "Jatin"}}}}
           ) == "hello Jatin"

    assert MessageVarParser.parse(
             "hello @results.child.name",
             %{"results" => %{"child" => %{"name" => %{"input" => "Jatin"}}}}
           ) == "hello Jatin"

    assert MessageVarParser.parse(
             "hello @results.child.name.input",
             %{"results" => %{"child" => %{"name" => %{"input" => "Jatin"}}, "parent" => %{}}}
           ) == "hello Jatin"

    ## check we re able to replace a list also
    action_body_map = %{
      "param" => "@results.event_category_response.category",
      "searchCriteria" => [
        %{
          "compareOperator" => "=",
          "criteria" => "@results.event_category_response.category",
          "field" => "event_category"
        }
      ],
      "type" => "glific_Query_Test"
    }

    fields = %{
      "contact" => %{
        bsp_status: :session_and_hsm,
        fields: %{language: %{label: "English"}},
        in_groups: ["Restricted Group", "Default Group"],
        inserted_at: ~U[2021-11-08 11:38:39.219209Z],
        language: %Glific.Settings.Language{
          description: nil,
          id: 1,
          inserted_at: ~U[2021-11-08 11:38:38Z],
          is_active: true,
          label: "English",
          label_locale: "English",
          locale: "en",
          localized: true,
          updated_at: ~U[2021-11-08 11:38:38Z]
        },
        name: "Glific Simulator One",
        optin_time: ~U[2021-11-08 11:38:39Z],
        phone: "9876543210_1",
        status: :valid
      },
      "flow" => %{id: 14, name: "New Query Test "},
      "results" => %{
        "event_category_response" => %{
          :intent => nil,
          "category" => "Margadarshi",
          "input" => "1",
          "inserted_at" => ~U[2021-11-15 06:31:19.387352Z]
        },
        "event_optin_response" => %{
          "category" => "1",
          "input" => "1",
          "inserted_at" => "2021-11-15T06:31:18.169743Z",
          "intent" => nil
        }
      }
    }

    output = MessageVarParser.parse_map(action_body_map, fields)

    assert hd(output["searchCriteria"])["criteria"] == "Margadarshi"
  end

  test "test not standard results while passing", _attrs do
    action_body_map = %{
      "type" => "akr issues tracker",
      "updateOrWrite" => "write",
      "fields" => %{
        "sender" => "@contact.phone",
        "category" => "@results.ar_issue_category.category",
        "photo" => "@results.ar_issue_media",
        "othersnumber" => "@results.ar_ir_otherphone",
        "status" => "@results.ar_issues_exitmenu",
        "storedanswer" => "@results.storedanswer.DetectedResponse"
      }
    }

    fields = %{
      "contact" => %{
        bsp_status: :session_and_hsm,
        fields: %{language: %{label: "English"}},
        in_groups: ["Restricted Group", "Default Group"],
        inserted_at: ~U[2021-11-08 11:38:39.219209Z],
        language: %Glific.Settings.Language{
          description: nil,
          id: 1,
          inserted_at: ~U[2021-11-08 11:38:38Z],
          is_active: true,
          label: "English",
          label_locale: "English",
          locale: "en",
          localized: true,
          updated_at: ~U[2021-11-08 11:38:38Z]
        },
        name: "Glific Simulator One",
        optin_time: ~U[2021-11-08 11:38:39Z],
        phone: "9876543210_1",
        status: :valid
      },
      "flow" => %{id: 14, name: "New Query Test "},
      "results" => %{
        "ar_issue_civic_subcategory" => %{
          "intent" => nil,
          "category" => "Waste",
          "inserted_at" => "2022-02-21T13:07:17.313524Z",
          "input" => "1"
        },
        "ar_issue_media" => %{
          "id" => 887_419,
          "caption" => nil,
          "category" => "media",
          "inserted_at" => "2022-02-21T13:07:40.078723Z",
          "url" =>
            "https://filemanager.gupshup.io/fm/wamedia/RBGlificAPI/057dd9d5-2c61-4381-aa7a-fc0a1e3167af?fileName=",
          "source_url" =>
            "https://filemanager.gupshup.io/fm/wamedia/RBGlificAPI/057dd9d5-2c61-4381-aa7a-fc0a1e3167af?fileName=",
          "input" =>
            "https://filemanager.gupshup.io/fm/wamedia/RBGlificAPI/057dd9d5-2c61-4381-aa7a-fc0a1e3167af?fileName="
        },
        "three" => "3",
        "arch_menu" => %{
          "intent" => nil,
          "category" => "reportissue",
          "inserted_at" => "2022-02-21T13:07:06.804975Z",
          "input" => "2"
        },
        "two" => "2",
        "one" => "1",
        "location_link" => %{
          "inserted_at" => "2022-02-21T13:07:18.459747Z",
          "short_link" => "show-map/919917443994?flow_id=1231",
          "link" => "https://locate.solveninja.org/show-map/919917443994?flow_id=1231"
        },
        "ar_issue_category" => %{
          "intent" => nil,
          "category" => "Civic ",
          "inserted_at" => "2022-02-21T13:07:11.722277Z",
          "input" => "2"
        },
        "storedanswer" => %{
          "DetectedResponse" => "",
          "OperationStatus" => "CONTINUED_ASSESSMENT",
          "QuestionResponseID" => 1_083_000_000_113_341
        }
      }
    }

    assert true = MessageVarParser.parse_map(action_body_map, fields) |> is_map()
  end
end
