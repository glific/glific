defmodule Glific.ThirdParty.Kaapi.ApiClienTest do
  use Glific.DataCase, async: true

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
          body: "Not Found"
        }
    end)

    assert {:error, %{status: 404, body: "Not Found"}} = ApiClient.onboard_to_kaapi(@params)
  end

  test "returns {:error, msg} when API transport fails" do
    mock(fn
      %Tesla.Env{method: :post} ->
        {:error, :timeout}
    end)

    assert {:error, :timeout} = ApiClient.onboard_to_kaapi(@params)
  end
end
