defmodule GlificWeb.Resolvers.AIEvaluationsTest do
  use GlificWeb.ConnCase

  alias Glific.Partners
  alias Glific.Users
  alias GlificWeb.Resolvers.AIEvaluations

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
                dataset_name: "valid_dataset"
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

      assert {:ok, %{golden_qa: golden_qa}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert golden_qa.name == "valid_dataset"
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

      assert {:ok, %{errors: [%{message: msg}]}} =
               AIEvaluations.create_golden_qa(nil, args, resolution)

      assert msg == "Name can only contain alphanumeric characters and underscores"
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

      assert msg == "Name can only contain alphanumeric characters and underscores"
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

      assert msg == "Name can only contain alphanumeric characters and underscores"
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

      assert msg == "File size must not exceed 20MB"
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

      assert reason != nil
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

      assert reason != nil
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

      assert reason == :timeout
    end

    test "accepts valid name with underscores and numbers", %{
      staff: user,
      upload: upload
    } do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{dataset_name: "dataset_2024_v1", duplication_factor: 2}}
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
end
