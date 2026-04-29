defmodule GlificWeb.Resolvers.AIEvaluationsTest do
  use GlificWeb.ConnCase
  import Mock

  alias Glific.{
    AIEvaluations.AIEvaluation,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Partners,
    Repo,
    Users
  }

  alias GlificWeb.Resolvers.AIEvaluations

  @create_golden_qa_success_metric "Golden QA Create Success"
  @create_golden_qa_failure_metric "Golden QA Create Failure"

  describe "list_ai_evaluations/3" do
    setup [:create_ai_evaluation_fixtures]

    test "returns list of evaluations for the organization", %{
      staff: user,
      evaluation: evaluation
    } do
      resolution = %{context: %{current_user: user}}

      assert {:ok, evaluations} = AIEvaluations.list_ai_evaluations(nil, %{}, resolution)
      assert length(evaluations) >= 1
      assert Enum.any?(evaluations, fn e -> e.id == evaluation.id end)
    end

    test "filters by name", %{staff: user, evaluation: evaluation} do
      resolution = %{context: %{current_user: user}}
      args = %{filter: %{name: evaluation.name}}

      assert {:ok, evaluations} = AIEvaluations.list_ai_evaluations(nil, args, resolution)
      assert Enum.any?(evaluations, fn e -> e.id == evaluation.id end)
    end
  end

  describe "count_ai_evaluations/3" do
    setup [:create_ai_evaluation_fixtures]

    test "returns count of evaluations for the organization", %{staff: user} do
      resolution = %{context: %{current_user: user}}

      assert {:ok, count} = AIEvaluations.count_ai_evaluations(nil, %{}, resolution)
      assert count >= 1
    end
  end

  describe "create_golden_qa/3" do
    setup [:enable_kaapi, :create_upload_file]

    test "returns golden_qa on success when Kaapi succeeds", %{
      staff: user,
      upload: upload
    } do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{
                dataset_name: "valid_dataset",
                dataset_id: "12345"
              }
            }
          }
      end)

      args = %{
        input: %{
          name: "valid_dataset",
          file: upload,
          duplication_factor: 3
        }
      }

      resolution = %{context: %{current_user: user}}

      with_mock Glific.Metrics, [:passthrough], increment: fn _, _ -> :ok end do
        assert {:ok, %{golden_qa: golden_qa}} =
                 AIEvaluations.create_golden_qa(nil, args, resolution)

        assert golden_qa.name == "valid_dataset"

        assert called(
                 Glific.Metrics.increment(
                   @create_golden_qa_success_metric,
                   user.organization_id
                 )
               )
      end
    end

    test "returns errors when name contains spaces", %{staff: user, upload: upload} do
      args = %{
        input: %{
          name: "invalid name with spaces",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      with_mock Glific.Metrics, [:passthrough], increment: fn _, _ -> :ok end do
        assert {:ok, %{errors: [%{message: msg}]}} =
                 AIEvaluations.create_golden_qa(nil, args, resolution)

        assert msg == "Name can only contain lowercase alphanumeric characters and underscores"

        assert called(
                 Glific.Metrics.increment(
                   @create_golden_qa_failure_metric,
                   user.organization_id
                 )
               )
      end
    end

    test "returns errors when name contains special characters", %{
      staff: user,
      upload: upload
    } do
      args = %{
        input: %{
          name: "invalid-name-with-dashes",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert msg == "Name can only contain lowercase alphanumeric characters and underscores"
    end

    test "returns errors when name contains non-ASCII characters", %{
      staff: user,
      upload: upload
    } do
      args = %{
        input: %{
          name: "náme_with_unicode",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert msg == "Name can only contain lowercase alphanumeric characters and underscores"
    end

    test "returns errors when duplication_factor is 0", %{staff: user, upload: upload} do
      args = %{
        input: %{
          name: "valid_name",
          file: upload,
          duplication_factor: 0
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert msg == "Duplication factor must be between 1 and 5"
    end

    test "returns errors when duplication_factor is 6", %{staff: user, upload: upload} do
      args = %{
        input: %{
          name: "valid_name",
          file: upload,
          duplication_factor: 6
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert msg == "Duplication factor must be between 1 and 5"
    end

    test "returns errors when file size exceeds 20MB", %{staff: user} do
      large_file_path = create_large_file(21)

      upload = %Plug.Upload{
        path: large_file_path,
        content_type: "text/csv",
        filename: "large_dataset.csv"
      }

      on_exit(fn -> File.rm(large_file_path) end)

      args = %{
        input: %{
          name: "valid_name",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert msg == "File size must not exceed 1MB"
    end

    test "returns errors when file path is unreadable", %{staff: user} do
      upload = %Plug.Upload{
        path: "/nonexistent/path/to/file.csv",
        content_type: "text/csv",
        filename: "missing.csv"
      }

      args = %{
        input: %{
          name: "valid_name",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert msg == "Unable to read uploaded file for size validation"
    end

    test "returns errors when Kaapi API returns 500", %{staff: user, upload: upload} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 500,
            body: %{error: "Internal server error"}
          }
      end)

      args = %{
        input: %{
          name: "valid_name",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: reason}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert reason =~ "Internal server error"
    end

    test "returns errors when Kaapi API returns error body", %{staff: user, upload: upload} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 422,
            body: %{error: "Invalid dataset format"}
          }
      end)

      args = %{
        input: %{
          name: "valid_name",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: reason}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert reason == "Invalid dataset format"
    end

    test "returns errors when Kaapi is not configured", %{upload: upload} do
      # Create an organization without Kaapi credential
      org = Glific.Fixtures.organization_fixture()
      Glific.Repo.put_organization_id(org.id)
      [user_no_kaapi] = Users.list_users(%{})

      args = %{
        input: %{
          name: "valid_name",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user_no_kaapi}}

      assert {:ok, %{errors: [%{message: reason}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert reason == "Kaapi is not active"
    end

    test "returns errors when Kaapi API call times out", %{staff: user, upload: upload} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          {:error, :timeout}
      end)

      args = %{
        input: %{
          name: "valid_name",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: reason}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert reason == "Timeout occurred, please try again."
    end

    test "accepts valid name with underscores and numbers", %{
      staff: user,
      upload: upload
    } do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{dataset_name: "dataset_2024_v1", dataset_id: "12345"}}
          }
      end)

      args = %{
        input: %{
          name: "dataset_2024_v1",
          file: upload,
          duplication_factor: 2
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{golden_qa: golden_qa}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert golden_qa.name == "dataset_2024_v1"
    end
  end

  describe "get_golden_qa/3" do
    setup [:enable_kaapi, :create_golden_qa_fixture]

    test "returns dataset without signed_url by default (no Kaapi call)", %{
      staff: user,
      golden_qa: golden_qa
    } do
      # No Tesla.Mock setup - we should NOT call Kaapi when include_signed_url is false
      args = %{id: golden_qa.id, include_signed_url: false}
      resolution = %{context: %{current_user: user}}

      assert {:ok, %{golden_qa: dataset}} = AIEvaluations.get_golden_qa(nil, args, resolution)
      assert dataset.id == golden_qa.id
      assert dataset.name == golden_qa.name
      assert dataset.inserted_at == golden_qa.inserted_at
      assert dataset.updated_at == golden_qa.updated_at
      refute Map.has_key?(dataset, :signed_url)
    end

    test "returns dataset with signed_url when requested", %{
      staff: user,
      golden_qa: golden_qa
    } do
      Tesla.Mock.mock(fn
        %{method: :get, query: query} ->
          if Enum.any?(query, fn {k, v} -> k == :include_signed_url and v == "true" end) do
            %Tesla.Env{
              status: 200,
              body: %{
                success: true,
                data: %{
                  id: golden_qa.dataset_id,
                  name: golden_qa.name,
                  signed_url: "https://storage.example.com/signed-url-token-12345",
                  created_at: "2024-01-01T00:00:00Z",
                  updated_at: "2024-01-02T00:00:00Z"
                }
              }
            }
          else
            %Tesla.Env{status: 400, body: %{error: "include_signed_url required"}}
          end
      end)

      args = %{id: golden_qa.id, include_signed_url: true}
      resolution = %{context: %{current_user: user}}

      assert {:ok, %{golden_qa: dataset}} = AIEvaluations.get_golden_qa(nil, args, resolution)
      assert dataset.id == golden_qa.id
      assert dataset.name == golden_qa.name
      assert dataset.signed_url == "https://storage.example.com/signed-url-token-12345"
    end

    test "returns error when golden_qa does not exist", %{staff: user} do
      # No Kaapi call needed when include_signed_url is false
      args = %{id: 999_999, include_signed_url: false}
      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.get_golden_qa(nil, args, resolution)

      assert msg == "Golden QA not found."
    end

    test "returns error when Kaapi returns missing signed_url when requested", %{
      staff: user,
      golden_qa: golden_qa
    } do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              success: true,
              data: %{
                id: golden_qa.dataset_id,
                name: golden_qa.name,
                created_at: "2024-01-01T00:00:00Z",
                updated_at: "2024-01-02T00:00:00Z"
              }
            }
          }
      end)

      args = %{id: golden_qa.id, include_signed_url: true}
      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.get_golden_qa(nil, args, resolution)

      assert msg == "Dataset download URL not available"
    end

    test "returns error when Kaapi returns 404 (only when include_signed_url: true)", %{
      staff: user,
      golden_qa: golden_qa
    } do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 404,
            body: %{error: "Dataset not found"}
          }
      end)

      args = %{id: golden_qa.id, include_signed_url: true}
      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.get_golden_qa(nil, args, resolution)

      assert msg == "Dataset not found"
    end

    test "returns error when Kaapi returns 500 (only when include_signed_url: true)", %{
      staff: user,
      golden_qa: golden_qa
    } do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 500,
            body: %{error: "Internal server error"}
          }
      end)

      args = %{id: golden_qa.id, include_signed_url: true}
      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.get_golden_qa(nil, args, resolution)

      assert msg == "Internal server error"
    end

    test "returns error when Kaapi API call times out (only when include_signed_url: true)", %{
      staff: user,
      golden_qa: golden_qa
    } do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          {:error, :timeout}
      end)

      args = %{id: golden_qa.id, include_signed_url: true}
      resolution = %{context: %{current_user: user}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.get_golden_qa(nil, args, resolution)

      assert msg == "Timeout occurred, please try again."
    end

    test "returns error when Kaapi is not configured (only when include_signed_url: true)", %{
      organization_id: _organization_id
    } do
      org = Glific.Fixtures.organization_fixture()
      Repo.put_organization_id(org.id)
      user_no_kaapi = Glific.Fixtures.user_fixture(%{organization_id: org.id})

      {:ok, golden_qa} =
        Glific.AIEvaluations.create_golden_qa(%{
          name: "test_dataset_no_kaapi",
          dataset_id: 99999,
          duplication_factor: 1,
          organization_id: org.id
        })

      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{id: 1, name: "test"}}
          }
      end)

      args = %{id: golden_qa.id, include_signed_url: true}
      resolution = %{context: %{current_user: user_no_kaapi}}

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.get_golden_qa(nil, args, resolution)

      assert msg == "Kaapi is not active"
    end
  end

  describe "create_evaluation/3" do
    setup [:enable_kaapi, :create_config_version]

    test "returns evaluation with status and persists record in the database", %{
      staff: user,
      assistant_config_version: assistant_config_version
    } do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{
                id: 404,
                status: "processing",
                dataset_id: 427
              }
            }
          }
      end)

      count_before = Repo.aggregate(AIEvaluation, :count, :id)

      args = %{
        input: %{
          dataset_id: "427",
          experiment_name: "test_experiment",
          config_id: "2",
          config_version: assistant_config_version.id
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:ok, %{evaluation: evaluation}} =
               AIEvaluations.create_evaluation(nil, args, resolution)

      assert evaluation.status == :processing
      assert evaluation.kaapi_evaluation_id == 404
      assert evaluation.dataset_id == 427
      assert evaluation.name == "test_experiment"
      assert evaluation.assistant_config_version_id == assistant_config_version.id
      assert Repo.aggregate(AIEvaluation, :count, :id) == count_before + 1
    end

    test "returns error when config version does not exist", %{staff: user} do
      args = %{
        input: %{
          dataset_id: "1",
          experiment_name: "test_experiment",
          config_id: "2",
          config_version: 999_999
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:error, reason} = AIEvaluations.create_evaluation(nil, args, resolution)
      assert reason == "The specified config version does not exist."
    end

    test "returns error on timeout", %{
      staff: user,
      assistant_config_version: assistant_config_version
    } do
      Tesla.Mock.mock(fn
        %{method: :post} -> {:error, :timeout}
      end)

      args = %{
        input: %{
          dataset_id: "1",
          experiment_name: "test_experiment",
          config_id: "2",
          config_version: assistant_config_version.id
        }
      }

      resolution = %{context: %{current_user: user}}

      assert {:error, "Timeout occurred, please try again."} =
               AIEvaluations.create_evaluation(nil, args, resolution)
    end
  end

  defp create_config_version(%{organization_id: organization_id}) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant.",
        provider: "openai",
        model: "gpt-4o",
        settings: %{"temperature" => 1.0},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, config_version} = Repo.fetch(AssistantConfigVersion, config_version.id)

    %{assistant: assistant, assistant_config_version: config_version}
  end

  defp create_ai_evaluation_fixtures(%{organization_id: organization_id}) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant.",
        provider: "openai",
        model: "gpt-4o",
        settings: %{"temperature" => 0.7},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, evaluation} =
      %AIEvaluation{}
      |> AIEvaluation.changeset(%{
        name: "test_evaluation",
        status: :completed,
        dataset_id: 1,
        assistant_config_version_id: config_version.id,
        organization_id: organization_id
      })
      |> Repo.insert()

    %{evaluation: evaluation}
  end

  defp enable_kaapi(%{organization_id: organization_id}) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{
        "api_key" => "sk_test_key"
      },
      is_active: true
    })

    :ok
  end

  defp create_upload_file(_context) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "golden_qa_test_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(tmp_path, "question,answer\nWhat is Glific?,A communication platform\n")

    upload = %Plug.Upload{
      path: tmp_path,
      content_type: "text/csv",
      filename: "golden_qa.csv"
    }

    on_exit(fn -> File.rm(tmp_path) end)

    {:ok, upload: upload}
  end

  # Creates a file of size (megabytes) MB for testing file size validation.
  # Returns the path to the temporary file.
  defp create_large_file(megabytes) do
    path =
      Path.join(
        System.tmp_dir!(),
        "large_#{megabytes}mb_#{System.unique_integer([:positive])}.bin"
      )

    chunk = :binary.copy(<<0>>, 1024 * 1024)
    io = File.open!(path, [:write, :raw, :binary])

    try do
      for _ <- 1..megabytes, do: :file.write(io, chunk)
      path
    after
      File.close(io)
    end
  end

  defp create_golden_qa_fixture(%{organization_id: organization_id}) do
    {:ok, golden_qa} =
      Glific.AIEvaluations.create_golden_qa(%{
        name: "test_dataset",
        dataset_id: 12345,
        duplication_factor: 1,
        organization_id: organization_id
      })

    %{golden_qa: golden_qa}
  end
end
