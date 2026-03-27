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
        status: :ready
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
                   organization_id: @org_id
                 })

        cloned =
          Assistant
          |> where([a], a.name == ^"Copy of #{assistant.name}")
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
      end
    end

    test "returns error when assistant not found" do
      assert {:error, _} =
               perform_job(AssistantCloneWorker, %{
                 assistant_id: -1,
                 organization_id: @org_id
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
                 organization_id: @org_id
               })

      assert msg =~ "No knowledge base version found"
    end

    test "returns error when OpenAI file listing fails", %{assistant: assistant} do
      with_mock Req,
        get: fn _url, _opts ->
          {:ok, %{status: 500, body: %{"error" => "Internal server error"}}}
        end do
        assert {:error, _} =
                 perform_job(AssistantCloneWorker, %{
                   assistant_id: assistant.id,
                   organization_id: @org_id
                 })
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
                   organization_id: @org_id
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
                   organization_id: @org_id
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
                   organization_id: @org_id
                 })
      end
    end
    
    test "returns error immediately when collection status is FAILED", %{assistant: assistant} do
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
                %Tesla.Env{status: 200, body: %{data: %{job_id: "job_failed_123"}}}
            end

          %{method: :get, url: url} ->
            if String.contains?(url, "collections/jobs/job_failed_123") do
              %Tesla.Env{
                status: 200,
                body: %{data: %{status: "FAILED", collection: nil}}
              }
            end
        end)

        assert {:error, msg} =
                 perform_job(AssistantCloneWorker, %{
                   assistant_id: assistant.id,
                   organization_id: @org_id
                 })

        assert msg =~ "Collection creation failed for job_failed_123"
      end
    end

    test "returns error when get_collection_status API call fails", %{assistant: assistant} do
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
                %Tesla.Env{status: 200, body: %{data: %{job_id: "job_err_123"}}}
            end

          %{method: :get, url: url} ->
            if String.contains?(url, "collections/jobs/job_failed_123") do
              %Tesla.Env{status: 503, body: %{error: "Service unavailable"}}
            end
        end)

        assert {:error, _} =
                 perform_job(AssistantCloneWorker, %{
                   assistant_id: assistant.id,
                   organization_id: @org_id
                 })
      end
    end

    test "retries polling when status is PROCESSING before becoming SUCCESSFUL", %{
      assistant: assistant
    } do
      clone_dir = Path.join(System.tmp_dir!(), "clone/#{@org_id}/#{assistant.name}")
      File.mkdir_p!(clone_dir)
      File.write!(Path.join(clone_dir, "doc.pdf"), "test content")

      {:ok, call_counter} = Agent.start_link(fn -> 0 end)

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
                %Tesla.Env{status: 200, body: %{data: %{job_id: "job_retry_123"}}}

              String.contains?(url, "configs") ->
                %Tesla.Env{
                  status: 200,
                  body: %{data: %{id: "cloned_kaapi_uuid", version: %{version: 1}}}
                }
            end

          %{method: :get, url: url} ->
            if String.contains?(url, "collections/jobs") do
              count = Agent.get_and_update(call_counter, fn n -> {n, n + 1} end)

              if count == 0 do
                %Tesla.Env{
                  status: 200,
                  body: %{data: %{status: "PROCESSING", collection: nil}}
                }
              else
                %Tesla.Env{
                  status: 200,
                  body: %{
                    data: %{
                      status: "SUCCESSFUL",
                      collection: %{knowledge_base_id: "cloned_kb_retry"}
                    }
                  }
                }
              end
            end
        end)

        assert :ok =
                 perform_job(AssistantCloneWorker, %{
                   assistant_id: assistant.id,
                   organization_id: @org_id
                 })

        assert Agent.get(call_counter, & &1) >= 2
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
end
