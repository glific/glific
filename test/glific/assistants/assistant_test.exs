defmodule Glific.Assistants.AssistantTest do
  @moduledoc """
  Tests for Assistant schema and changesets
  """
  use Glific.DataCase

  alias Glific.{
    Assistants,
    Assistants.Assistant,
    Partners,
    Repo
  }

  setup %{organization_id: organization_id} do
    enable_kaapi(%{organization_id: organization_id})

    valid_attrs = %{
      name: "Test Assistant",
      description: "A helpful assistant for testing",
      organization_id: organization_id
    }

    %{valid_attrs: valid_attrs}
  end

  describe "changeset/2" do
    test "changeset with valid attributes", %{valid_attrs: valid_attrs} do
      changeset = Assistant.changeset(%Assistant{}, valid_attrs)

      assert changeset.valid?
      assert changeset.errors == []
      assert get_change(changeset, :name) == "Test Assistant"
      assert get_change(changeset, :description) == "A helpful assistant for testing"
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

  describe "upload_file/1" do
    test "upload_file/1, uploads the file successfully to Kaapi", %{
      organization_id: organization_id
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

      assert {:ok, %{file_id: file_id, filename: filename}} =
               Assistants.upload_file(%{
                 media: %Plug.Upload{
                   path:
                     "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
                   content_type: "application/pdf",
                   filename: "sample.pdf"
                 },
                 organization_id: organization_id
               })

      assert file_id == "d33539f6-2196-477c-a127-0f17f04ef133"
      assert filename == "sample.pdf"
    end

    test "upload_file/1, uploads the file failed due to unsupported file", %{
      organization_id: organization_id
    } do
      assert {:error, "Files with extension '.csv' not supported in Assistants"} =
               Assistants.upload_file(%{
                 media: %Plug.Upload{
                   path:
                     "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
                   content_type: "application/csv",
                   filename: "sample.csv"
                 },
                 organization_id: organization_id
               })
    end

    test "upload_file/1, uploads file to Kaapi with transformation parameters", %{
      organization_id: organization_id
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

      assert {:ok, %{file_id: file_id, filename: filename}} =
               Assistants.upload_file(%{
                 media: %Plug.Upload{
                   path:
                     "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
                   content_type: "application/pdf",
                   filename: "sample.pdf"
                 },
                 organization_id: organization_id,
                 target_format: "pdf",
                 callback_url: "https://example.com/webhook"
               })

      assert file_id == "d33539f6-2196-477c-a127-0f17f04ef133"
      assert filename == "sample.pdf"
    end

    test "upload_file/1, handles Kaapi upload error gracefully", %{
      organization_id: organization_id
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: "This is not a secret/api/v1/documents/"} ->
          %Tesla.Env{
            status: 500,
            body: %{
              success: false,
              error: "Internal server error",
              metadata: nil
            }
          }
      end)

      assert {:error, error_message} =
               Assistants.upload_file(%{
                 media: %Plug.Upload{
                   path:
                     "/var/folders/vz/7fp5h9bs69d3kc8lxpbzlf6w0000gn/T/plug-1727-NXFz/multipart-1727169241-575672640710-1",
                   content_type: "application/pdf",
                   filename: "sample.pdf"
                 },
                 organization_id: organization_id
               })

      assert is_binary(error_message)
      assert error_message =~ "status 500"
    end
  end

  defp enable_kaapi(attrs) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{
          "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
        }
      })

    valid_update_attrs = %{
      keys: %{},
      secrets: %{
        "api_key" => "sk_3fa22108-f464-41e5-81d9-d8a298854430"
      },
      is_active: true,
      organization_id: attrs.organization_id,
      shortcode: "kaapi"
    }

    Partners.update_credential(credential, valid_update_attrs)
  end
end
