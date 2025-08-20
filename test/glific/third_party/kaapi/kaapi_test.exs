defmodule Glific.ThirdParty.Kaapi.ApiClienTest do
  alias Glific.Partners

  use GlificWeb.ConnCase
  import Tesla.Mock
  alias Glific.ThirdParty.Kaapi.ApiClient

  @params %{
    organization_id: 1,
    user_name: "glific",
    organization_name: "GLific_org",
    project_name: "Glific"
  }

  test "onboard_to_kaapi/1 returns {:ok, %{api_key: key}} on 200 with api_key" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{api_key: "ApiKey XoxxxxabcDefGhfKSDrs"}
        }
    end)

    assert {:ok, %{api_key: key}} = ApiClient.onboard_to_kaapi(@params)
    assert key == "ApiKey XoxxxxabcDefGhfKSDrs"
  end

  test "returns {:error, msg} when API returns body with error field (200)" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{error: "API key already exists for this user and project."}
        }
    end)

    assert {:error, "API key already exists for this user and project."} =
             ApiClient.onboard_to_kaapi(@params)
  end

  test "returns {:error, msg} when API returns error status code (400+)" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{error: "Bad request"}
        }
    end)

    assert {:error, "Bad request"} = ApiClient.onboard_to_kaapi(@params)
  end

  test "returns {:error, msg} when API returns error status code without error field" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 404,
          body: %{}
        }
    end)

    assert {:error, "HTTP 404"} = ApiClient.onboard_to_kaapi(@params)
  end

  test "returns {:error, msg} when API transport fails" do
    mock(fn
      %Tesla.Env{method: :post} ->
        {:error, :timeout}
    end)

    assert {:error, "API request failed"} = ApiClient.onboard_to_kaapi(@params)
  end

  test "create_assistant/2 successfully creates assistant in kaapi", %{user: user} do
    enable_kaapi(%{organization_id: user.organization_id})

    params = %{
      name: "Assistant-f11ead89",
      instructions: "this is a story telling assistant that tells story",
      id: "asst_123",
      model: "gpt-4o",
      temperature: 1.0
    }

    mock(fn
      %Tesla.Env{method: :post, url: "This is not a secret/api/v1/assistant/"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            error: nil,
            data: %{
              id: 86,
              name: "Assistant-f78f4392",
              instructions: "you are a helpful asssitant",
              organization_id: 1,
              project_id: 1,
              assistant_id: "asst_5TtScw1DwabcDBjvrvY",
              vector_store_ids: [],
              temperature: 0.1,
              model: "gpt-4o",
              is_deleted: false,
              deleted_at: nil
            },
            metadata: nil,
            success: true
          }
        }
    end)

    assert {:ok, resp} = ApiClient.create_assistant(params, 1)
    assert resp.name == "Assistant-f78f4392"
    assert resp.id == "asst_5TtScw1DwabcDBjvrvY"
  end

  test "update_assistant/2 successfully updates assistant in kaapi", %{user: user} do
    enable_kaapi(%{organization_id: user.organization_id})

    mock(fn
      %Tesla.Env{
        method: :patch,
        url: "This is not a secret/api/v1/assistant/asst_5TtScw1DwabcDBjvrv"
      } ->
        %Tesla.Env{
          status: 200,
          body: %{
            error: nil,
            data: %{
              id: 86,
              name: "Assistant-f78f4392",
              instructions: "you are a helpful asssitant",
              organization_id: 1,
              project_id: 1,
              assistant_id: "asst_5TtScw1DwabcDBjvrvY",
              vector_store_ids: ["vs_1"],
              temperature: 0.1,
              model: "gpt-4o",
              is_deleted: false,
              deleted_at: nil
            },
            metadata: nil,
            success: true
          }
        }
    end)

    params = %{
      id: "asst_5TtScw1DwabcDBjvrv",
      name: "Updated Assistant",
      model: "gpt-4o",
      instructions: "new instructions",
      temperature: 0.7,
      tool_resources: %{file_search: %{vector_store_ids: ["vs_1"]}}
    }

    assert {:ok, resp} = ApiClient.update_assistant(params, 1)
    assert resp.id == "asst_5TtScw1DwabcDBjvrvY"
    assert resp.vector_store_ids == ["vs_1"]
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
