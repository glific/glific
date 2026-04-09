defmodule Glific.ThirdParty.Kaapi.AssistantCloneWorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  import Mock
  import Ecto.Query

  alias Glific.{
    Assistants,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Partners,
    Repo
  }

  alias Glific.ThirdParty.Kaapi.AssistantCloneWorker

  @org_id 1
  @api_key "sk_test_key"

  setup do
    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: @org_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => @api_key},
        is_active: true
      })

    Partners.get_organization!(@org_id) |> Partners.fill_cache()

    {:ok, kb} =
      Assistants.create_knowledge_base(%{
        name: "Source KB",
        organization_id: @org_id
      })

    {:ok, kbv} =
      Assistants.create_knowledge_base_version(%{
        knowledge_base_id: kb.id,
        organization_id: @org_id,
        files: %{"file_1" => %{"name" => "doc.pdf"}},
        status: :completed,
        llm_service_id: "vs_source_123",
        size: 500
      })

    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Source Assistant",
        organization_id: @org_id,
        kaapi_uuid: "kaapi_source_uuid"
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        organization_id: @org_id,
        provider: "openai",
        model: "gpt-4o",
        prompt: "You are a helpful assistant",
        settings: %{"temperature" => 0.7},
        status: :ready,
        version_number: 1
      })
      |> Repo.insert()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("assistant_config_version_knowledge_base_versions", [
      %{
        assistant_config_version_id: config_version.id,
        knowledge_base_version_id: kbv.id,
        organization_id: @org_id,
        inserted_at: now,
        updated_at: now
      }
    ])

    {:ok, assistant} =
      assistant
      |> Assistant.set_active_config_version_changeset(%{
        active_config_version_id: config_version.id
      })
      |> Repo.update()

    on_exit(fn ->
      File.rm_rf(Path.join(System.tmp_dir!(), "clone/#{@org_id}"))
    end)

    %{assistant: assistant, config_version: config_version, knowledge_base_version: kbv}
  end

  describe "perform/1" do
    test "successfully clones assistant end-to-end", %{assistant: assistant} do
      # Create temp files to simulate downloaded files
      clone_dir = Path.join(System.tmp_dir!(), "clone/#{@org_id}/#{assistant.name}")
      File.mkdir_p!(clone_dir)
      File.write!(Path.join(clone_dir, "doc.pdf"), "test content")

      with_mock Req,
        get: fn url, _opts ->
          cond do
            String.contains?(url, "/files/file_001/content") ->
              {:ok,
               %{
                 status: 200,
                 body: %{"data" => [%{"type" => "text", "text" => "Hello world"}]}
               }}

            String.contains?(url, "/files/file_001") ->
              {:ok, %{status: 200, body: %{"filename" => "doc.pdf"}}}

            String.contains?(url, "/files") ->
              {:ok,
               %{
                 status: 200,
                 body: %{"data" => [%{"id" => "file_001"}], "has_more" => false}
               }}

            true ->
              {:ok, %{status: 404, body: %{"error" => "not found"}}}
          end
        end do
        Tesla.Mock.mock(fn
          # upload document to kaapi
          %{method: :post, url: url} ->
            cond do
              String.contains?(url, "documents") ->
                %Tesla.Env{
                  status: 200,
                  body: %{
                    data: %{
                      id: "kaapi_doc_001",
                      fname: "doc.pdf",
                      inserted_at: "2026-03-23T12:00:00Z"
                    }
                  }
                }

              String.contains?(url, "collections") ->
                %Tesla.Env{
                  status: 200,
                  body: %{data: %{job_id: "clone_job_123"}}
                }

              String.contains?(url, "configs") ->
                %Tesla.Env{
                  status: 200,
                  body: %{
                    data: %{id: "cloned_kaapi_uuid", version: %{version: 1}}
                  }
                }
            end

          # poll collection status
          %{method: :get, url: url} ->
            if String.contains?(url, "collections/jobs") do
              %Tesla.Env{
                status: 200,
                body: %{
                  data: %{
                    status: "SUCCESSFUL",
                    collection: %{knowledge_base_id: "cloned_kb_id_456"}
                  }
                }
              }
            end
        end)

        assert :ok =
                 perform_job(AssistantCloneWorker, %{
                   assistant_id: assistant.id,
                   version_id: assistant.active_config_version_id,
                   organization_id: @org_id,
                   is_legacy: true
                 })

        cloned =
          Assistant
          |> where([a], a.name == ^"Copy of #{assistant.name} Version 1")
          |> Repo.one()

        assert cloned != nil
        assert cloned.kaapi_uuid == "cloned_kaapi_uuid"
        assert cloned.id != assistant.id

        cloned_config =
          AssistantConfigVersion
          |> where([acv], acv.assistant_id == ^cloned.id)
          |> Repo.one()

        assert cloned_config != nil
        assert cloned_config.model == "gpt-4o"
        assert cloned_config.prompt == "You are a helpful assistant"
        assert cloned_config.status == :ready

        refreshed = Repo.get!(Assistant, assistant.id)
        assert refreshed.clone_status == "completed"

        notification =
          Repo.one(from n in Glific.Notifications.Notification, order_by: [desc: n.id], limit: 1)

        assert notification.message =~ "cloned successfully"
      end
    end

    test "returns error when assistant not found" do
      assert {:error, _} =
               perform_job(AssistantCloneWorker, %{
                 assistant_id: -1,
                 version_id: -1,
                 organization_id: @org_id,
                 is_legacy: true
               })
    end

    test "returns error when assistant has no knowledge base" do
      {:ok, no_kb_assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "No KB Assistant",
          organization_id: @org_id,
          kaapi_uuid: "no_kb_kaapi"
        })
        |> Repo.insert()

      {:ok, config} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: no_kb_assistant.id,
          organization_id: @org_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "test",
          settings: %{},
          status: :ready
        })
        |> Repo.insert()

      {:ok, _} =
        no_kb_assistant
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: config.id
        })
        |> Repo.update()

      assert {:error, msg} =
               perform_job(AssistantCloneWorker, %{
                 assistant_id: no_kb_assistant.id,
                 version_id: config.id,
                 organization_id: @org_id,
                 is_legacy: true
               })

      assert msg =~ "No knowledge base version found"
    end

    test "returns error when OpenAI file listing fails", %{assistant: assistant} do
      with_mock Req,
        get: fn _url, _opts ->
          {:ok, %{status: 500, body: %{"error" => "Internal server error"}}}
        end do
        assert {:error, _} =
                 perform_job(
                   AssistantCloneWorker,
                   %{
                     assistant_id: assistant.id,
                     version_id: assistant.active_config_version_id,
                     organization_id: @org_id,
                     is_legacy: true
                   },
                   attempt: 2
                 )

        refreshed = Repo.get!(Assistant, assistant.id)
        assert refreshed.clone_status == "failed"

        notif =
          Glific.Repo.one(
            from n in Glific.Notifications.Notification, order_by: [desc: n.id], limit: 1
          )

        assert notif.message =~ "Assistant cloning failed"
      end
    end

    test "handles file content download failure gracefully", %{assistant: assistant} do
      with_mock Req,
        get: fn url, _opts ->
          cond do
            String.contains?(url, "/files/file_001/content") ->
              {:ok, %{status: 500, body: %{"error" => "content unavailable"}}}

            String.contains?(url, "/files/file_001") ->
              {:ok, %{status: 200, body: %{"filename" => "doc.pdf"}}}

            String.contains?(url, "/files") ->
              {:ok,
               %{status: 200, body: %{"data" => [%{"id" => "file_001"}], "has_more" => false}}}

            true ->
              {:ok, %{status: 404, body: %{}}}
          end
        end do
        Tesla.Mock.mock(fn
          %{method: :post} ->
            %Tesla.Env{status: 500, body: %{error: "No documents provided"}}
        end)

        # Content download fails, so no files are saved.
        # upload_files_to_kaapi finds empty dir, returns [].
        # create_collection is called with empty file_ids and fails.
        assert {:error, _} =
                 perform_job(AssistantCloneWorker, %{
                   assistant_id: assistant.id,
                   version_id: assistant.active_config_version_id,
                   organization_id: @org_id,
                   is_legacy: true
                 })
      end
    end

    test "returns error when Kaapi collection creation fails", %{assistant: assistant} do
      clone_dir = Path.join(System.tmp_dir!(), "clone/#{@org_id}/#{assistant.name}")
      File.mkdir_p!(clone_dir)
      File.write!(Path.join(clone_dir, "doc.pdf"), "test content")

      with_mock Req,
        get: fn url, _opts ->
          cond do
            String.contains?(url, "/files/file_001/content") ->
              {:ok, %{status: 200, body: %{"data" => [%{"type" => "text", "text" => "content"}]}}}

            String.contains?(url, "/files/file_001") ->
              {:ok, %{status: 200, body: %{"filename" => "doc.pdf"}}}

            String.contains?(url, "/files") ->
              {:ok,
               %{status: 200, body: %{"data" => [%{"id" => "file_001"}], "has_more" => false}}}

            true ->
              {:ok, %{status: 404, body: %{}}}
          end
        end do
        Tesla.Mock.mock(fn
          %{method: :post, url: url} ->
            cond do
              String.contains?(url, "documents") ->
                %Tesla.Env{
                  status: 200,
                  body: %{
                    data: %{id: "doc_001", fname: "doc.pdf", inserted_at: "2026-03-23T12:00:00Z"}
                  }
                }

              String.contains?(url, "collections") ->
                %Tesla.Env{status: 500, body: %{error: "Internal server error"}}
            end
        end)

        assert {:error, _} =
                 perform_job(AssistantCloneWorker, %{
                   assistant_id: assistant.id,
                   version_id: assistant.active_config_version_id,
                   organization_id: @org_id,
                   is_legacy: true
                 })
      end
    end

    test "returns error when Kaapi config creation fails", %{assistant: assistant} do
      clone_dir = Path.join(System.tmp_dir!(), "clone/#{@org_id}/#{assistant.name}")
      File.mkdir_p!(clone_dir)
      File.write!(Path.join(clone_dir, "doc.pdf"), "test content")

      with_mock Req,
        get: fn url, _opts ->
          cond do
            String.contains?(url, "/files/file_001/content") ->
              {:ok, %{status: 200, body: %{"data" => [%{"type" => "text", "text" => "content"}]}}}

            String.contains?(url, "/files/file_001") ->
              {:ok, %{status: 200, body: %{"filename" => "doc.pdf"}}}

            String.contains?(url, "/files") ->
              {:ok,
               %{status: 200, body: %{"data" => [%{"id" => "file_001"}], "has_more" => false}}}

            true ->
              {:ok, %{status: 404, body: %{}}}
          end
        end do
        Tesla.Mock.mock(fn
          %{method: :post, url: url} ->
            cond do
              String.contains?(url, "documents") ->
                %Tesla.Env{
                  status: 200,
                  body: %{
                    data: %{id: "doc_001", fname: "doc.pdf", inserted_at: "2026-03-23T12:00:00Z"}
                  }
                }

              String.contains?(url, "collections") ->
                %Tesla.Env{status: 200, body: %{data: %{job_id: "job_123"}}}

              String.contains?(url, "configs") ->
                %Tesla.Env{status: 500, body: %{error: "Config creation failed"}}
            end

          %{method: :get, url: url} ->
            if String.contains?(url, "collections/jobs") do
              %Tesla.Env{
                status: 200,
                body: %{
                  data: %{
                    status: "SUCCESSFUL",
                    collection: %{knowledge_base_id: "kb_123"}
                  }
                }
              }
            end
        end)

        assert {:error, _} =
                 perform_job(AssistantCloneWorker, %{
                   assistant_id: assistant.id,
                   version_id: assistant.active_config_version_id,
                   organization_id: @org_id,
                   is_legacy: true
                 })
      end
    end
  end

  describe "clone_assistant/1 enqueues job" do
    test "returns success message for valid assistant", %{assistant: assistant} do
      assert {:ok, %{message: "Assistant clone initiated"}} =
               Assistants.clone_assistant(assistant.id)
    end

    test "returns error for non-existent assistant" do
      assert {:error, _} = Assistants.clone_assistant(-1)
    end
  end

  describe "perform/1 non-legacy path" do
    setup %{assistant: assistant} do
      {:ok, non_legacy_knowledge_base} =
        Assistants.create_knowledge_base(%{
          name: "Non-Legacy KB",
          organization_id: @org_id
        })

      {:ok, non_legacy_knowledge_base_version} =
        Assistants.create_knowledge_base_version(%{
          knowledge_base_id: non_legacy_knowledge_base.id,
          organization_id: @org_id,
          files: %{"file_1" => %{"name" => "doc.pdf"}},
          status: :completed,
          llm_service_id: "kaapi_kb_id_789",
          kaapi_job_id: "kaapi_job_123",
          size: 500
        })

      {:ok, non_legacy_config_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: @org_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "You are a non-legacy assistant",
          settings: %{"temperature" => 0.5},
          status: :ready,
          version_number: 2
        })
        |> Repo.insert()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("assistant_config_version_knowledge_base_versions", [
        %{
          assistant_config_version_id: non_legacy_config_version.id,
          knowledge_base_version_id: non_legacy_knowledge_base_version.id,
          organization_id: @org_id,
          inserted_at: now,
          updated_at: now
        }
      ])

      %{
        non_legacy_config_version: non_legacy_config_version,
        non_legacy_knowledge_base_version: non_legacy_knowledge_base_version
      }
    end

    test "successfully clones non-legacy assistant", %{
      assistant: assistant,
      non_legacy_config_version: non_legacy_config_version,
      non_legacy_knowledge_base_version: non_legacy_knowledge_base_version
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "configs") do
            %Tesla.Env{
              status: 200,
              body: %{data: %{id: "cloned_kaapi_uuid", version: %{version: 1}}}
            }
          end
      end)

      assert :ok =
               perform_job(AssistantCloneWorker, %{
                 assistant_id: assistant.id,
                 version_id: non_legacy_config_version.id,
                 organization_id: @org_id,
                 is_legacy: false
               })

      cloned =
        Assistant
        |> where([a], a.name == ^"Copy of #{assistant.name} Version 2")
        |> Repo.one()

      assert cloned != nil
      assert cloned.kaapi_uuid == "cloned_kaapi_uuid"
      assert cloned.id != assistant.id

      cloned_config =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^cloned.id)
        |> Repo.one()

      assert cloned_config.model == "gpt-4o"
      assert cloned_config.prompt == "You are a non-legacy assistant"
      assert cloned_config.status == :ready

      linked_kb_version_ids =
        from(j in "assistant_config_version_knowledge_base_versions",
          where: j.assistant_config_version_id == ^cloned_config.id,
          select: j.knowledge_base_version_id
        )
        |> Repo.all()

      assert linked_kb_version_ids == [non_legacy_knowledge_base_version.id]

      refreshed = Repo.get!(Assistant, assistant.id)
      assert refreshed.clone_status == ""
    end

    test "auto-generates unique name with counter when clone name already exists", %{
      assistant: assistant,
      non_legacy_config_version: non_legacy_config_version
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "configs") do
            %Tesla.Env{
              status: 200,
              body: %{data: %{id: "cloned_kaapi_uuid_counter", version: %{version: 1}}}
            }
          end
      end)

      # Pre-create an assistant with the base clone name to force counter usage
      {:ok, _existing} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Copy of #{assistant.name} Version 2",
          organization_id: @org_id,
          kaapi_uuid: "existing_uuid"
        })
        |> Repo.insert()

      assert :ok =
               perform_job(AssistantCloneWorker, %{
                 assistant_id: assistant.id,
                 version_id: non_legacy_config_version.id,
                 organization_id: @org_id,
                 is_legacy: false
               })

      cloned =
        Assistant
        |> where([a], a.name == ^"Copy of #{assistant.name} Version 2 (2)")
        |> Repo.one()

      assert cloned != nil
      assert cloned.kaapi_uuid == "cloned_kaapi_uuid_counter"
    end

    test "successfully clones non-legacy assistant that has no knowledge base at all" do
      {:ok, assistant_without_kb} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Assistant Without KB",
          organization_id: @org_id,
          kaapi_uuid: "kaapi_no_kb_uuid"
        })
        |> Repo.insert()

      {:ok, config_version_without_kb} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant_without_kb.id,
          organization_id: @org_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "Assistant with no KB at all",
          settings: %{"temperature" => 0.5},
          status: :ready,
          version_number: 1
        })
        |> Repo.insert()

      {:ok, assistant_without_kb} =
        assistant_without_kb
        |> Assistant.set_active_config_version_changeset(%{
          active_config_version_id: config_version_without_kb.id
        })
        |> Repo.update()

      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "configs") do
            %Tesla.Env{
              status: 200,
              body: %{data: %{id: "cloned_no_kb_uuid", version: %{version: 1}}}
            }
          end
      end)

      assert :ok =
               perform_job(AssistantCloneWorker, %{
                 assistant_id: assistant_without_kb.id,
                 version_id: config_version_without_kb.id,
                 organization_id: @org_id,
                 is_legacy: false
               })

      cloned =
        Assistant
        |> where([a], a.name == ^"Copy of #{assistant_without_kb.name} Version 1")
        |> Repo.one()

      assert cloned != nil
      assert cloned.kaapi_uuid == "cloned_no_kb_uuid"

      cloned_config =
        AssistantConfigVersion
        |> where([acv], acv.assistant_id == ^cloned.id)
        |> Repo.one()

      assert cloned_config.model == "gpt-4o"
      assert cloned_config.prompt == "Assistant with no KB at all"

      linked_kb_version_ids =
        from(j in "assistant_config_version_knowledge_base_versions",
          where: j.assistant_config_version_id == ^cloned_config.id,
          select: j.knowledge_base_version_id
        )
        |> Repo.all()

      assert linked_kb_version_ids == []

      refreshed = Repo.get!(Assistant, assistant_without_kb.id)
      assert refreshed.clone_status == ""
    end

    test "returns error when Kaapi config creation fails", %{
      assistant: assistant,
      non_legacy_config_version: non_legacy_config_version
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "configs") do
            %Tesla.Env{status: 500, body: %{error: "Config creation failed"}}
          end
      end)

      assert {:error, _} =
               perform_job(AssistantCloneWorker, %{
                 assistant_id: assistant.id,
                 version_id: non_legacy_config_version.id,
                 organization_id: @org_id,
                 is_legacy: false
               })
    end
  end
end
