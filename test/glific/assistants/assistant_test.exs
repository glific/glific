defmodule Glific.Assistants.AssistantTest do
  @moduledoc """
  Tests for Assistant schema and changesets
  """
  use Glific.DataCase, async: false

  alias Glific.{
    Assistants,
    Assistants.Assistant,
    Partners,
    Repo
  }

  setup %{organization_id: organization_id} do
    Tesla.Mock.mock(fn
      %{method: :get, url: _url} ->
        %Tesla.Env{
          status: 200,
          body: %{
            services: %{
              "kaapi" => %{
                secrets: %{"api_key" => "sk_test_key"}
              }
            }
          }
        }
    end)

    Tesla.Mock.mock(fn
      %{method: :post, url: _url} ->
        %Tesla.Env{
          status: 200,
          body: %{success: true, data: %{id: "kaapi-uuid-123"}}
        }
    end)

    enable_kaapi(%{organization_id: organization_id})

    {:ok, kb} =
      Assistants.create_knowledge_base(%{
        name: "Test KB",
        organization_id: organization_id
      })

    {:ok, kb_version} =
      Assistants.create_knowledge_base_version(%{
        knowledge_base_id: kb.id,
        llm_service_id: "vs_test_123",
        status: :completed,
        organization_id: organization_id,
        files: %{},
        size: 0
      })

    tmp_path =
      Path.join(System.tmp_dir!(), "test_upload_#{System.unique_integer([:positive])}.pdf")

    File.write!(tmp_path, "fake pdf content for testing")

    upload = %Plug.Upload{
      path: tmp_path,
      content_type: "application/pdf",
      filename: "sample.pdf"
    }

    valid_attrs = %{
      name: "Test Assistant",
      description: "A helpful assistant for testing",
      kaapi_uuid: "test-uuid",
      assistant_display_id: "asst-123456",
      organization_id: organization_id
    }

    {:ok,
     %{
       valid_attrs: valid_attrs,
       knowledge_base: kb,
       knowledge_base_version: kb_version,
       upload: upload
     }}
  end

  describe "changeset/2" do
    test "changeset with valid attributes", %{valid_attrs: valid_attrs} do
      changeset = Assistant.changeset(%Assistant{}, valid_attrs)

      assert changeset.valid?
      assert changeset.errors == []
      assert get_change(changeset, :name) == "Test Assistant"
      assert get_change(changeset, :description) == "A helpful assistant for testing"
      assert get_change(changeset, :assistant_display_id) == "asst-123456"
    end

    test "generates a unique assistant_display_id", %{valid_attrs: valid_attrs} do
      valid_attrs = Map.delete(valid_attrs, :assistant_display_id)
      changeset = Assistant.changeset(%Assistant{}, valid_attrs)

      assert changeset.valid?
      assert changeset.errors == []
      assert get_change(changeset, :name) == "Test Assistant"
      assert get_change(changeset, :description) == "A helpful assistant for testing"
      assert get_change(changeset, :assistant_display_id) |> String.match?(~r/asst_\w{24}/)
    end

    test "unique assistant_display_id has to be unique", %{valid_attrs: valid_attrs} do
      assert {:ok, _assistant} =
               Assistant.changeset(%Assistant{}, valid_attrs) |> Glific.Repo.insert()

      assert {:error, changeset} =
               Assistant.changeset(%Assistant{}, valid_attrs) |> Glific.Repo.insert()

      assert %{assistant_display_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "changeset without name returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :name)
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid? == false
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset without organization_id returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :organization_id)
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid? == false
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with only required fields is valid", %{valid_attrs: valid_attrs} do
      attrs = Map.delete(valid_attrs, :description)
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :name) == "Test Assistant"
      assert get_change(changeset, :description) == nil
    end

    test "changeset with empty name returns error", %{valid_attrs: valid_attrs} do
      attrs = Map.put(valid_attrs, :name, "")
      changeset = Assistant.changeset(%Assistant{}, attrs)

      assert changeset.valid? == false
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects duplicate name within the same organization",
         %{organization_id: organization_id} do
      assert {:ok, _} =
               %Assistant{}
               |> Assistant.changeset(%{
                 name: "Unique Name Test",
                 organization_id: organization_id
               })
               |> Repo.insert()

      assert {:error, changeset} =
               %Assistant{}
               |> Assistant.changeset(%{
                 name: "Unique Name Test",
                 organization_id: organization_id
               })
               |> Repo.insert()

      assert {"has already been taken", _} = changeset.errors[:name]
    end

    test "rejects duplicate assistant_display_id",
         %{organization_id: organization_id} do
      assert {:ok, first} =
               %Assistant{}
               |> Assistant.changeset(%{
                 name: "Display ID Test A",
                 organization_id: organization_id
               })
               |> Repo.insert()

      assert {:error, changeset} =
               %Assistant{}
               |> Assistant.changeset(%{
                 name: "Display ID Test B",
                 organization_id: organization_id,
                 assistant_display_id: first.assistant_display_id
               })
               |> Repo.insert()

      assert {"has already been taken", _} = changeset.errors[:assistant_display_id]
    end
  end

  describe "set_active_config_version_changeset/2" do
    test "valid changeset with active_config_version_id", %{valid_attrs: valid_attrs} do
      assistant = struct(Assistant, valid_attrs)

      changeset =
        Assistant.set_active_config_version_changeset(assistant, %{active_config_version_id: 123})

      assert changeset.valid?
      assert get_change(changeset, :active_config_version_id) == 123
    end

    test "invalid changeset without active_config_version_id", %{valid_attrs: valid_attrs} do
      assistant = struct(Assistant, valid_attrs)
      changeset = Assistant.set_active_config_version_changeset(assistant, %{})

      assert changeset.valid? == false
      assert %{active_config_version_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with nil active_config_version_id returns error", %{valid_attrs: valid_attrs} do
      assistant = struct(Assistant, valid_attrs)

      changeset =
        Assistant.set_active_config_version_changeset(assistant, %{active_config_version_id: nil})

      assert changeset.valid? == false
      assert %{active_config_version_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "ExAudit tracking" do
    test "assistant should be audited with ExAudit", %{organization_id: organization_id} do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Audit Test Assistant",
          description: "Testing audit tracking",
          kaapi_uuid: "test-uuid",
          organization_id: organization_id
        })
        |> Repo.insert()

      [created_history] = Repo.history(assistant, skip_organization_id: true)
      assert created_history.action == :created
      assert :name in Map.keys(created_history.patch)

      {:ok, updated_assistant} =
        assistant
        |> Assistant.changeset(%{name: "Updated Audit Test Assistant"})
        |> Repo.update()

      history = Repo.history(updated_assistant, skip_organization_id: true)
      assert length(history) == 2
      update_history = List.last(history)
      assert update_history.action == :updated
      assert :name in Map.keys(update_history.patch)
    end
  end

  describe "upload_file/2" do
    test "uploads the file successfully to Kaapi", %{
      organization_id: organization_id,
      upload: upload
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: "This is not a secret/api/v1/documents/"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              success: true,
              data: %{
                fname: "sample.pdf",
                project_id: 9,
                id: "d33539f6-2196-477c-a127-0f17f04ef133",
                signed_url: "https://kaapi-test.s3.amazonaws.com/test/doc.pdf",
                inserted_at: "2026-01-30T10:51:16.872363",
                updated_at: "2026-01-30T10:51:16.872619",
                transformation_job: nil
              },
              error: nil,
              metadata: nil
            }
          }
      end)

      assert {:ok, %{file_id: file_id, filename: filename, uploaded_at: uploaded_at}} =
               Assistants.upload_file(%{media: upload}, organization_id)

      assert file_id == "d33539f6-2196-477c-a127-0f17f04ef133"
      assert filename == "sample.pdf"
      assert uploaded_at == "2026-01-30T10:51:16.872363"
    end

    test "uploads the file failed due to unsupported file", %{
      organization_id: organization_id,
      upload: upload
    } do
      exe_upload = %{upload | content_type: "application/octet-stream", filename: "sample.exe"}

      assert {:error, "Files with extension '.exe' not supported in Assistants"} =
               Assistants.upload_file(%{media: exe_upload}, organization_id)
    end

    test "uploads file to Kaapi with transformation parameters", %{
      organization_id: organization_id,
      upload: upload
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: "This is not a secret/api/v1/documents/"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              success: true,
              data: %{
                fname: "sample.pdf",
                project_id: 9,
                id: "d33539f6-2196-477c-a127-0f17f04ef133",
                signed_url: "https://kaapi-test.s3.amazonaws.com/test/doc.pdf",
                inserted_at: "2026-01-30T10:51:16.872363",
                updated_at: "2026-01-30T10:51:16.872619",
                transformation_job: nil
              },
              error: nil,
              metadata: nil
            }
          }
      end)

      assert {:ok, %{file_id: file_id, filename: filename, uploaded_at: uploaded_at}} =
               Assistants.upload_file(
                 %{
                   media: upload,
                   target_format: "pdf",
                   callback_url: "https://example.com/webhook"
                 },
                 organization_id
               )

      assert file_id == "d33539f6-2196-477c-a127-0f17f04ef133"
      assert filename == "sample.pdf"
      assert uploaded_at == "2026-01-30T10:51:16.872363"
    end

    test "handles Kaapi upload error gracefully", %{
      organization_id: organization_id,
      upload: upload
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: "This is not a secret/api/v1/documents/"} ->
          %Tesla.Env{
            status: 500,
            body: %{
              success: false,
              error: "Internal server error",
              data: nil,
              metadata: nil
            }
          }
      end)

      assert {:error, error_message} =
               Assistants.upload_file(%{media: upload}, organization_id)

      assert is_binary(error_message)
      assert error_message =~ "status 500"
    end
  end

  defp enable_kaapi(attrs) do
    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_test_key"
        },
        is_active: true
      })
  end
end
