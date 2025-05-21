defmodule Glific.ClientsTest do
  use Glific.DataCase

  alias Glific.{
    Clients,
    Clients.Atecf,
    Clients.Bandhu,
    Clients.CommonWebhook,
    Clients.KEF,
    Clients.ReapBenefit,
    Clients.Sarc,
    Clients.Sol,
    Contacts,
    Fixtures
  }

  test "plugins returns the right value for test vs prod" do
    map = Clients.plugins()
    # only the main organization is returned
    assert Enum.count(map) == 1

    map = Clients.plugins(:prod)
    # we at least have STiR and TAP
    assert Enum.count(map) > 1
  end

  test "gcs_file_name with contact id" do
    directory =
      Clients.gcs_file_name(%{
        "organization_id" => 1,
        "contact_id" => 2,
        "remote_name" => "remote"
      })

    assert !String.contains?(directory, "/")

    directory =
      Clients.gcs_file_name(%{
        "organization_id" => 43,
        "contact_id" => 1,
        "remote_name" => "remote"
      })

    assert !String.contains?(directory, "/")

    cg = Fixtures.contact_group_fixture(%{organization_id: 1})

    directory =
      Clients.gcs_file_name(%{
        "organization_id" => 1,
        "contact_id" => cg.contact_id,
        "remote_name" => "remote"
      })

    assert String.contains?(directory, "/")

    # ensure Sol Works
    contact = Fixtures.contact_fixture()

    message_media = Fixtures.message_media_fixture(%{contact_id: contact.id, organization_id: 1})

    directory =
      Sol.gcs_file_name(%{
        "contact_id" => contact.id,
        "organization_id" => 1,
        "id" => message_media.id
      })

    assert String.contains?(directory, "/")
    assert String.contains?(directory, contact.phone)

    contact = Fixtures.contact_fixture(%{name: ""})

    directory =
      Sol.gcs_file_name(%{
        "contact_id" => contact.id,
        "organization_id" => 1,
        "id" => message_media.id
      })

    assert String.contains?(directory, "/")

    # also test reap_benefit separately
    directory = ReapBenefit.gcs_file_name(%{"flow_id" => 1, "remote_name" => "foo"})

    assert directory == "Help Workflow/foo"

    directory = ReapBenefit.gcs_file_name(%{"flow_id" => 23, "remote_name" => "foo"})

    assert directory == "foo"
  end

  test "check blocked allow all numbers" do
    assert Clients.blocked?("91123", 1) == false
    assert Clients.blocked?("1123", 1) == false
    assert Clients.blocked?("44123", 1) == false
    assert Clients.blocked?("256123", 1) == false
    assert Clients.blocked?("255123", 1) == false
    assert Clients.blocked?("925123", 1) == false
    assert Clients.blocked?("255123", 2) == false
    assert Clients.blocked?("256123", 2) == false
    assert Clients.blocked?("56123", 2) == false
    assert Clients.blocked?("9256123", 2) == false
  end

  test "check that broadcast returns a different staff id" do
    contact = Fixtures.contact_fixture()

    # a contact not in any group should return the same staff id
    assert Clients.broadcast(nil, contact, 100) == 100

    # lets munge organization_id
    assert Clients.broadcast(nil, Map.put(contact, :organization_id, 103), 107) == 107

    # now lets create a contact group and a user group
    {cg, ug} = Fixtures.contact_user_group_fixture(%{organization_id: 1})
    contact = Contacts.get_contact!(cg.contact_id)
    assert Clients.broadcast(nil, contact, -1) == ug.user.contact_id
  end

  test "check that webhook always returns a map", attrs do
    assert is_map(
             Clients.webhook("daily", %{
               "fields" => "some fields",
               "organization_id" => attrs.organization_id
             })
           )

    assert %{error: "Missing webhook function implementation"} ==
             CommonWebhook.webhook("function", %{fields: "some fields"})
  end

  test "fetch_user_profiles webhook function" do
    fields = %{
      "results" => %{
        "parent" => %{
          "bandhu_profile_check_mock" => %{
            "success" => "true",
            "message" => "List loaded Successfully.",
            "inserted_at" => "2024-04-18T14:19:08.110951Z",
            "data" => %{
              "profile_count" => 2,
              "profiles" => %{
                "19" => %{
                  "user_selected_language" => %{
                    "name" => "English",
                    "language_code" => "en"
                  },
                  "user_roles" => %{
                    "role_type" => "Worker",
                    "role_id" => 3
                  },
                  "name" => "Jacob Worker Odisha",
                  "mobile_no" => "809XXXXXX3",
                  "id" => 14_698,
                  "full_mobile_no" => nil
                },
                "1" => %{
                  "user_selected_language" => %{
                    "name" => "English",
                    "language_code" => "en"
                  },
                  "user_roles" => %{
                    "role_type" => "Employer",
                    "role_id" => 1
                  },
                  "name" => "Jacob Employer",
                  "mobile_no" => "809XXXXXX3",
                  "id" => 11_987,
                  "full_mobile_no" => nil
                }
              }
            }
          }
        }
      }
    }

    assert %{profile_selection_message: _, index_map: index_map} =
             Bandhu.webhook("fetch_user_profiles", fields)

    fields = %{
      "profile_number" => "1",
      "index_map" => index_map
    }

    assert %{profile: _} = Bandhu.webhook("set_contact_profile", fields)
  end

  test "Common webhook function is executed first to ensure that all common functions are accesible for all clients" do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          headers: [
            {"content-type", "image/png"},
            {"content-length", "3209581"}
          ],
          method: :get,
          status: 200
        }

      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "choices" => [
              %{
                "message" => %{
                  "content" =>
                    "This image depicts a scenic view of a sunset or sunrise with a field of flowers silhouetted against the light. The bright sun is low on the horizon, casting a warm glow and causing dramatic lighting and shadows among the silhouetted flowers and stems. The sky has a mix of colors, typical of such time of day, with clouds illuminated by the sun. The text overlaying the image reads \"JPEG This is Sample Image.\"",
                  "role" => "assistant"
                }
              }
            ],
            "created" => 1_717_089_925,
            "model" => "gpt-4o-2024-05-13"
          }
        }
    end)

    %{response: response} =
      Clients.webhook("parse_via_gpt_vision", %{
        "prompt" => "what's in the image",
        "url" => "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample02.jpg"
      })

    assert response ==
             "This image depicts a scenic view of a sunset or sunrise with a field of flowers silhouetted against the light. The bright sun is low on the horizon, casting a warm glow and causing dramatic lighting and shadows among the silhouetted flowers and stems. The sky has a mix of colors, typical of such time of day, with clouds illuminated by the sun. The text overlaying the image reads \"JPEG This is Sample Image.\""
  end

  test "gcs_file_name/1 for ungrouped users, no schoolName in contact.fields" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954"
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 18,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.png",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.png",
      "type" => "image",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "2024/Ungrouped users/Images/" <> image = KEF.gcs_file_name(media)
    [_, _, message_id] = String.split(image, "_")
    [phone_num, ext] = String.split(message_id, ".")
    assert ext == "png"
    assert contact.phone == phone_num
  end

  test "gcs_file_name/1, when contact_id is nil, returns the remote_name" do
    # Doesn't have schoolName in contact.fields

    media = %{
      "contact_id" => nil,
      "flow_id" => 18,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.png",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C_F18_M6.png",
      "type" => "image",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    assert KEF.gcs_file_name(media) == "20240907150900_C_F18_M6.png"
  end

  test "gcs_file_name/1, with invalid contact_type" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954",
        fields: %{
          contact_type: %{
            type: "string",
            label: "contact_type",
            value: "NA",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          }
        }
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 18,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.mp4",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.mp4",
      "type" => "video",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "2024/Ungrouped users/Videos/" <> video = KEF.gcs_file_name(media)
    [_, _, message_id] = String.split(video, "_")
    [phone_num, ext] = String.split(message_id, ".")
    assert ext == "mp4"
    assert contact.phone == phone_num
  end

  test "gcs_file_name/1, with valid contact_type, school name but no worksheet" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954",
        fields: %{
          "contact_type2425" => %{
            type: "string",
            label: "contact_type2425",
            value: "Parent",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "school_name_2425" => %{
            type: "string",
            label: "School Name 2425",
            value: "ABC School",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          }
        }
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 18,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.pdf",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.pdf",
      "type" => "document",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "2024/ABC School/Others/Others/" <> document = KEF.gcs_file_name(media)
    [_, _, message_id] = String.split(document, "_")
    [phone_num, ext] = String.split(message_id, ".")
    assert ext == "pdf"
    assert contact.phone == phone_num
  end

  test "gcs_file_name/1 for ungrouped users, no schoolName in contact.fields but valid worksheet flow" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954"
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 15_955,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.png",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.png",
      "type" => "image",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "2024/Ungrouped users/Images/" <> image = KEF.gcs_file_name(media)
    [_, _, message_id] = String.split(image, "_")
    [phone_num, ext] = String.split(message_id, ".")
    assert ext == "png"
    assert contact.phone == phone_num
  end

  test "gcs_file_name/1, with valid contact_type, school_name and selected worksheets" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954",
        fields: %{
          "contact_type2425" => %{
            type: "string",
            label: "contact_type2425",
            value: "Parent",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "school_name_2425" => %{
            type: "string",
            label: "School Name 2425",
            value: "ABC School",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "current_worksheet_code" => %{
            type: "string",
            label: "current_worksheet_code",
            value: "1234",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          }
        }
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 15_955,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.pdf",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.pdf",
      "type" => "document",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "2024/ABC School/Worksheets/1234/Others/" <> document = KEF.gcs_file_name(media)
    [_, _, message_id] = String.split(document, "_")
    [phone_num, ext] = String.split(message_id, ".")
    assert ext == "pdf"
    assert contact.phone == phone_num
  end

  test "gcs_file_name/1, with valid contact_type, child_school_name and selected flows" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954",
        fields: %{
          "contact_type2425" => %{
            type: "string",
            label: "contact_type2425",
            value: "Parent",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "school_name_2425" => %{
            type: "string",
            label: "School Name 2425",
            value: "ABC School",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "current_worksheet_code" => %{
            type: "string",
            label: "current_worksheet_code",
            value: "1234",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          }
        }
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 16_171,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.pdf",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.pdf",
      "type" => "document",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "2024/ABC School/Worksheets/1234/Others/" <> document = KEF.gcs_file_name(media)
    [_, _, message_id] = String.split(document, "_")
    [phone_num, ext] = String.split(message_id, ".")
    assert ext == "pdf"
    assert contact.phone == phone_num
  end

  test "gcs_file_name/1, for campaign flow" do
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954",
        fields: %{
          "contact_type2425" => %{
            type: "string",
            label: "contact_type2425",
            value: "Parent",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "school_name_2425" => %{
            type: "string",
            label: "School Name 2425",
            value: "ABC School",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "campaign2425" => %{
            type: "string",
            label: "campaign2425",
            value: "EPPE_Campaign",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          }
        }
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 27_579,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.pdf",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.pdf",
      "type" => "document",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "Campaign_24-25/EPPE_Campaign/ABC School/Others/" <> document = KEF.gcs_file_name(media)
    [_, _, message_id] = String.split(document, "_")
    [phone_num, ext] = String.split(message_id, ".")
    assert ext == "pdf"
    assert contact.phone == phone_num
  end

  test "enable_avni_user success" do
    username = "user@ngo"

    Tesla.Mock.mock(fn
      %{method: :post, url: "https://app.rwb.avniproject.org/api/user/generateToken"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            authToken: "authToken"
          }
        }

      %{method: :post, url: "https://app.rwb.avniproject.org/api/user/enable"} ->
        %Tesla.Env{
          status: 200
        }
    end)

    assert %{success: true, username: "user@ngo"} =
             Atecf.webhook("enable_avni_user", %{"username" => username})
  end

  test "enable_avni_user fail due to apis" do
    username = "user@ngo"

    Tesla.Mock.mock(fn
      %{method: :post, url: "https://app.rwb.avniproject.org/api/user/generateToken"} ->
        %Tesla.Env{
          status: 400,
          body: %{
            authToken: "authToken"
          }
        }

      %{method: :post, url: "https://app.rwb.avniproject.org/api/user/enable"} ->
        %Tesla.Env{
          status: 200
        }
    end)

    assert %{success: false, error: "Error due to" <> _} =
             Atecf.webhook("enable_avni_user", %{"username" => username})
  end

  test "enable_avni_user fail due to apis - 2" do
    username = "user@ngo"

    Tesla.Mock.mock(fn
      %{method: :post, url: "https://app.rwb.avniproject.org/api/user/generateToken"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            authToken: "authToken"
          }
        }

      %{method: :post, url: "https://app.rwb.avniproject.org/api/user/enable"} ->
        %Tesla.Env{
          status: 500
        }
    end)

    assert %{success: false, error: "Error due to" <> _} =
             Atecf.webhook("enable_avni_user", %{"username" => username})
  end

  test "gcs_file_name/1, non-default structure for a specific flow - sarc" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954",
        fields: %{
          "name_of_organization" => %{
            type: "string",
            label: "name_of_organization",
            value: "TFI Mumbai",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "acp_submission" => %{
            type: "string",
            label: "acp_submission",
            value: "Grade_1",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "name_of_educator" => %{
            type: "string",
            label: "name_of_educator",
            value: "eduname",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          }
        }
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 26_384,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.pdf",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.pdf",
      "type" => "document",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "acp_submissions_2425/TFI Mumbai/Grade_1/" <> file_name = Sarc.gcs_file_name(media)
    edu_name = String.split(file_name, "_") |> List.last()
    [edu_name, ext] = String.split(edu_name, ".")
    assert ext == "pdf"
    assert edu_name == "eduname"
  end

  test "gcs_file_name/1, default structure, if different flow - sarc" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954",
        fields: %{
          "name_of_organization" => %{
            type: "string",
            label: "name_of_organization",
            value: "TFI Mumbai",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "acp_submission" => %{
            type: "string",
            label: "acp_submission",
            value: "Grade_1",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "name_of_educator" => %{
            type: "string",
            label: "name_of_educator",
            value: "eduname",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          }
        }
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 26_388,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.pdf",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.pdf",
      "type" => "document",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    refute String.starts_with?(
             Sarc.gcs_file_name(media),
             "acp_submissions_2425/TFI Mumbai/Grade_1/"
           )
  end

  @tag :tt
  test "gcs_file_name/1, nil values - sarc" do
    # Doesn't have schoolName in contact.fields
    contact =
      Fixtures.contact_fixture(%{
        phone: "918634278954",
        fields: %{
          "name_of_organization" => %{
            type: "string",
            label: "name_of_organization",
            value: "TFI Mumbai",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          },
          "acp_submission" => %{
            type: "string",
            label: "acp_submission",
            value: "Grade_1",
            inserted_at: ~U[2024-09-07 15:17:53.964448Z]
          }
        }
      })

    media = %{
      "contact_id" => contact.id,
      "flow_id" => 26_384,
      "id" => 6,
      "local_name" =>
        "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T//20240907150900_C20_F18_M6.pdf",
      "organization_id" => 1,
      "remote_name" => "20240907150900_C20_F18_M6.pdf",
      "type" => "document",
      "url" =>
        "https://filemanager.gupshup.io/wa/11b17c2a-0f56-4651-9c9d-4d2e518b8d8c/wa/media/64195750-4a70-48c1-85ae-c2a1bd95193f?download=false"
    }

    "20240907150900_C20_F18_M6.pdf" = Sarc.gcs_file_name(media)
  end
end
