defmodule GlificWeb.API.V1.FlowEditorController do
  @moduledoc """
  The Pow User Registration Controller
  """

  use GlificWeb, :controller

  alias Glific.Flows
  alias Glific.Flows.Flow


  @doc false
  def globals(conn, data) do
    conn
    |> json(%{results: []})
  end

  def groups(conn, data) do
    conn
    |> json(%{results: []})
  end

  def groups_post(conn, params) do
    conn
    |> json(%{
      uuid: generate_uuid(),
      query: nil,
      status: "ready",
      count: 0,
      name: params["name"]
    })
  end

  def fields(conn, data) do
    conn
    |> json(%{results: []})
  end

  @spec fields_post(Plug.Conn.t(), nil | maybe_improper_list | map) :: Plug.Conn.t()
  def fields_post(conn, params) do
    conn
    |> json(%{
      key: Slug.slugify(params["label"], separator: "_"),
      name: params["label"],
      value_type: "text"
    })
  end

  def labels(conn, data) do
    conn
    |> json(%{results: []})
  end

  def labels_post(conn, params) do
    conn
    |> json(%{
      uuid: generate_uuid(),
      name: params["name"],
      count: 0
    })
  end

  def channels(conn, params) do
    channels = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "WhatsApp",
          address: "+18005234545",
          schemes: ["whatsapp"],
          roles: ["send", "receive"]
        }
      ]
    }

    json(conn, channels)
  end

  def classifiers(conn, params) do
    classifiers = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "Travel Agency",
          type: "wit",
          intents: ["book flight", "rent car"],
          created_on: "2019-10-15T20:07:58.529130Z"
        }
      ]
    }

    json(conn, classifiers)
  end

  def ticketers(conn, params) do
    ticketers = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "Email",
          type: "mailgun",
          created_on: "2019-10-15T20:07:58.529130Z"
        }
      ]
    }

    json(conn, ticketers)
  end

  def resthooks(conn, params) do
    resthooks = %{
      results: [
        %{resthook: "my-first-zap", subscribers: []},
        %{resthook: "my-other-zap", subscribers: []}
      ]
    }

    json(conn, resthooks)
  end

  def templates(conn, params) do
    templates = %{
      results: [
        %{
          uuid: generate_uuid(),
          name: "sample_template",
          created_on: "2019-04-02T22:14:31.549213Z",
          modified_on: "2019-04-02T22:14:31.569739Z",
          translations: [
            %{
              language: "eng",
              content: "Hi {{1}}, are you still experiencing problems with {{2}}?",
              variable_count: 2,
              status: "approved",
              channel: %{
                uuid: "0f661e8b-ea9d-4bd3-9953-d368340acf91",
                name: "WhatsApp"
              }
            },
            %{
              language: "fra",
              content: "Bonjour {{1}}, a tu des problems avec {{2}}?",
              variable_count: 2,
              status: "pending",
              channel: %{
                uuid: "0f661e8b-ea9d-4bd3-9953-d368340acf91",
                name: "WhatsApp"
              }
            }
          ]
        }
      ]
    }

    json(conn, templates)
  end

  def languages(conn, params) do
    languages = %{
      results: [
        %{
          iso: "eng",
          name: "English"
        },
        %{
          iso: "Hi",
          name: "Hindi"
        }
      ]
    }

    json(conn, languages)
  end

  def environment(conn, params) do
    environment = %{
      date_format: "YYYY-MM-DD",
      time_format: "hh:mm",
      timezone: "Africa/Kigali",
      languages: ["eng", "spa", "fra"]
    }

    json(conn, environment)
  end

  def recipients(conn, params) do
    recipients = %{
      results: [
        %{
          name: "Cat Fanciers",
          id: "eae05fb1-3021-4df2-a443-db8356b953fa",
          type: "group",
          extra: 212
        },
        %{
          name: "Anne",
          id: "673fa0f6-dffd-4e7d-bcc1-e5709374354f",
          type: "contact"
        }
      ]
    }

    json(conn, recipients)
  end

  def completion(conn, params) do
    json(conn, %{})
  end

  def activity(conn, params) do
    activity = %{
      nodes: %{},
      segments: %{}
    }

    json(conn, activity)
  end

  def flows(conn, %{"vars" => vars}) do
    results =
      case vars do
        [] ->
          [
            %{
              uuid: "9ecc8e84-6b83-442b-a04a-8094d5de997b",
              name: "Customer Service",
              type: "message",
              archived: false,
              labels: [],
              parent_refs: ["order_number", "customer_id"],
              expires: 10080
            }
          ]

        [uuid] ->
          %{
            name: "Customer Service",
            type: "message",
            uuid: "9ecc8e84-6b83-442b-a04a-8094d5de997b",
            nodes: []
          }
      end

    json(conn, results)
  end

  def revisions(conn, %{"vars" => vars}) do
    user = %{email: "chancerton@nyaruka.com", name: "Chancellor von Frankenbean"}
    assetList = [%{user: user, created_on: "2020-07-08T19:18:43.253Z", id: 1, version: "13.0.0", revision: 1}]


    case vars do
      [] -> json(conn, %{ results: assetList })
      [flow_id] ->
        flow = Flows.get_flow_revision(4)
       revision =  List.last(flow.revisions)
      json(conn, %{ definition: revision.definition, metadata: %{ issues: [] } })
    end
  end

  def save_revisions(conn, params) do

    user = %{email: "chancerton@nyaruka.com", name: "Chancellor von Frankenbean"}
    asset = %{user: user, created_on: "2020-07-08T19:18:43.253Z", id: 1, version: "13.0.0", revision: 1}
    Flows.create_flow_revision(params)

    json(conn, asset)
  end

  def functions(conn, _) do
    functions = File.read!("assets/flows/functions.json")
    |> Jason.decode!()

    json(conn, functions)

  end

  defp help_flow do
    %{
      name: "Favorites",
      language: "eng",
      type: "message",
      spec_version: "13.1.0",
      uuid: "a4f64f1b-85bc-477e-b706-de313a022978",
      localization: %{},
      nodes: [
        %{
          uuid: "3ea030e9-41c4-4c6c-8880-68bc2828d67b",
          actions: [
            %{
              attachments: [],
              text:
                "Hello please select your option: \n\n1 Glific objectives\n2 How can Glific help you\n3 Glific website\n4 Opt-out. \n\nPlease just send the number, e.g. 1",
              type: "send_msg",
              quick_replies: [],
              uuid: "e319cd39-f764-4680-9199-4cb7da647166"
            }
          ],
          exits: [
            %{
              uuid: "a8311645-482e-4d35-b300-c92a9b18798b",
              destination_uuid: "6f68083e-2340-449e-9fca-ac57c6835876"
            }
          ]
        },
        %{
          uuid: "6f68083e-2340-449e-9fca-ac57c6835876",
          actions: [],
          router: %{
            type: "switch",
            default_category_uuid: "65da0a4d-2bcc-42a2-99f5-4c9ed147f8a6",
            cases: [
              %{
                arguments: ["1", "one"],
                type: "has_any_word",
                uuid: "0345357f-dbfa-4946-9249-5828b58161a0",
                category_uuid: "de13e275-a05f-41bf-afd8-73e9ed32f3bf"
              },
              %{
                arguments: ["2", "two"],
                type: "has_any_word",
                uuid: "bc425dbf-d50c-48cf-81ba-622c06e153b0",
                category_uuid: "d3f0bf85-dac1-4b7d-8084-5c1ad2575f12"
              },
              %{
                arguments: ["3", "Three"],
                type: "has_any_word",
                uuid: "be6bc73d-6108-405c-9f88-c317c05311ad",
                category_uuid: "243766e5-e353-4d65-b87a-4405dbc24b1d"
              },
              %{
                arguments: ["4", "Four"],
                type: "has_any_word",
                uuid: "ebacc52f-a9b0-406d-837e-9e5ca1557d17",
                category_uuid: "3ce58365-61f2-4a6c-9b03-1eeccf988952"
              }
            ],
            categories: [
              %{
                uuid: "de13e275-a05f-41bf-afd8-73e9ed32f3bf",
                name: "One",
                exit_uuid: "744b1082-4d95-40d0-839a-89fc1bb99d30"
              },
              %{
                uuid: "d3f0bf85-dac1-4b7d-8084-5c1ad2575f12",
                name: "Two",
                exit_uuid: "77cd0e42-6a13-4122-a5fc-84b2e2daa1d4"
              },
              %{
                uuid: "243766e5-e353-4d65-b87a-4405dbc24b1d",
                name: "Three",
                exit_uuid: "0caba4c7-0955-41c9-b8dc-6c58112503a0"
              },
              %{
                uuid: "3ce58365-61f2-4a6c-9b03-1eeccf988952",
                name: "Four",
                exit_uuid: "1da8bf0a-827f-43d8-8222-a3c79bcace46"
              },
              %{
                uuid: "65da0a4d-2bcc-42a2-99f5-4c9ed147f8a6",
                name: "Other",
                exit_uuid: "d11aaf4b-106f-4646-a15d-d18f3a534e38"
              }
            ],
            operand: "@input.text",
            wait: %{
              type: "msg"
            },
            result_name: "Result 1"
          },
          exits: [
            %{
              uuid: "744b1082-4d95-40d0-839a-89fc1bb99d30",
              destination_uuid: "f189f142-6d39-40fa-bf11-95578daeceea"
            },
            %{
              uuid: "77cd0e42-6a13-4122-a5fc-84b2e2daa1d4",
              destination_uuid: "85e897d2-49e4-42b7-8574-8dc2aee97121"
            },
            %{
              uuid: "0caba4c7-0955-41c9-b8dc-6c58112503a0",
              destination_uuid: "6d39df59-4572-4f4c-99b7-f667ea112e03"
            },
            %{
              uuid: "1da8bf0a-827f-43d8-8222-a3c79bcace46",
              destination_uuid: "93a3335b-8909-406f-9ea2-af48d7947857"
            },
            %{
              uuid: "d11aaf4b-106f-4646-a15d-d18f3a534e38",
              destination_uuid: nil
            }
          ]
        },
        %{
          uuid: "93a3335b-8909-406f-9ea2-af48d7947857",
          actions: [
            %{
              uuid: "cb0b1ffc-2a42-4785-946d-a1e9b064b961",
              type: "enter_flow",
              flow: %{
                uuid: "9ecc8e84-6b83-442b-a04a-8094d5de997b",
                name: "Customer Service"
              }
            }
          ],
          router: %{
            type: "switch",
            operand: "@child.run.status",
            cases: [
              %{
                uuid: "300760a1-f94f-48c7-9f83-abb68380b2a5",
                type: "has_only_text",
                arguments: ["completed"],
                category_uuid: "5af22d80-be8c-4284-bda8-681b98284d3f"
              },
              %{
                uuid: "9c452875-79e4-4a8b-9817-1ab15886131f",
                arguments: ["expired"],
                type: "has_only_text",
                category_uuid: "332d1e71-8d39-4dca-b63b-c5c178f7ff8c"
              }
            ],
            categories: [
              %{
                uuid: "5af22d80-be8c-4284-bda8-681b98284d3f",
                name: "Complete",
                exit_uuid: "fa763fe5-cdd6-40ea-a06b-790556a50b7e"
              },
              %{
                uuid: "332d1e71-8d39-4dca-b63b-c5c178f7ff8c",
                name: "Expired",
                exit_uuid: "17a47ce6-a762-4690-b1f2-4dbcc99a9caf"
              }
            ],
            default_category_uuid: "332d1e71-8d39-4dca-b63b-c5c178f7ff8c"
          },
          exits: [
            %{
              uuid: "fa763fe5-cdd6-40ea-a06b-790556a50b7e",
              destination_uuid: "3ea030e9-41c4-4c6c-8880-68bc2828d67b"
            },
            %{
              uuid: "17a47ce6-a762-4690-b1f2-4dbcc99a9caf",
              destination_uuid: "3ea030e9-41c4-4c6c-8880-68bc2828d67b"
            }
          ]
        },
        %{
          uuid: "6d39df59-4572-4f4c-99b7-f667ea112e03",
          actions: [
            %{
              attachments: [],
              text: "https://glific.io/",
              type: "send_msg",
              quick_replies: [],
              uuid: "10196f43-87f0-4205-aabd-1549aaa7e242"
            }
          ],
          exits: [
            %{
              uuid: "b913ee73-87d2-495b-8a2d-6e7c40f31fd5",
              destination_uuid: nil
            }
          ]
        },
        %{
          uuid: "f189f142-6d39-40fa-bf11-95578daeceea",
          actions: [
            %{
              attachments: [],
              text:
                "Glific is designed specifically for NGOs in the social sector to enable them to interact with their users on a regular basis",
              type: "send_msg",
              quick_replies: [],
              uuid: "ed7d10f7-6298-4d84-a8d2-7b1f6e91da07"
            }
          ],
          exits: [
            %{
              uuid: "d002db23-a51f-4183-81d6-b1e93c5132fb",
              destination_uuid: nil
            }
          ]
        },
        %{
          uuid: "85e897d2-49e4-42b7-8574-8dc2aee97121",
          actions: [
            %{
              attachments: [],
              text:
                "If you are interested in using Glific, let us know. You can find more information on our website",
              type: "send_msg",
              quick_replies: [],
              uuid: "a970d5d9-2951-48dc-8c66-ee6833c4b21e"
            }
          ],
          exits: [
            %{
              uuid: "37a545df-825b-4611-a7fe-b17dfb62c430",
              destination_uuid: nil
            }
          ]
        }
      ],
      _ui: %{
        nodes: %{
          "3ea030e9-41c4-4c6c-8880-68bc2828d67b": %{
            position: %{
              left: 600,
              top: 0
            },
            type: "execute_actions"
          },
          "6f68083e-2340-449e-9fca-ac57c6835876": %{
            type: "wait_for_response",
            position: %{
              left: 120,
              top: 300
            },
            config: %{
              cases: %{}
            }
          },
          "f189f142-6d39-40fa-bf11-95578daeceea": %{
            position: %{
              left: 0,
              top: 500
            },
            type: "execute_actions"
          },
          "85e897d2-49e4-42b7-8574-8dc2aee97121": %{
            position: %{
              left: 340,
              top: 520
            },
            type: "execute_actions"
          },
          "6d39df59-4572-4f4c-99b7-f667ea112e03": %{
            position: %{
              left: 740,
              top: 460
            },
            type: "execute_actions"
          },
          "93a3335b-8909-406f-9ea2-af48d7947857": %{
            type: "split_by_subflow",
            position: %{
              left: 1020,
              top: 400
            },
            config: %{}
          }
        },
        languages: [
          %{
            eng: "English"
          },
          %{
            spa: "Spanish"
          }
        ]
      }
    }
  end

  defp inital_flow do
    %{"name" => "Flow9", "uuid" => "04c74c58-94ff-45d3-9bfa-98611d7214d5", "spec_version" => "13.1.0", "language" => "base", "type" => "messaging", "nodes" => [], "_ui" => %{}, "revision" => 1, "expire_after_minutes" => 10080}
  end

  defp generate_uuid() do
    Faker.UUID.v4()
  end
end
