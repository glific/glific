defmodule Glific.Flowex.AgentTest do
  use ExUnit.Case

  import Mock

  alias Glific.Flowex.Agent
  alias Goth.Token

  @agent %{
    "avatarUri" => "https://storage.googleapis.com/l_bot.png",
    "classificationThreshold" => 0.3,
    "defaultLanguageCode" => "es",
    "description" => "Agente de pruebas",
    "displayName" => "LBot",
    "enableLogging" => true,
    "matchMode" => "MATCH_MODE_HYBRID",
    "parent" => "projects/lbot-170198",
    "timeZone" => "America/New_York"
  }

  test "get/0 get agent" do
    with_mocks([
      {
        Token,
        [:passthrough],
        [for_scope: fn(_url) -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
      },
      {
        HTTPoison,
        [:passthrough],
        [request: fn(_method, _url, _params, _headers) ->
          body = Poison.encode!(@agent)
          {:ok, %HTTPoison.Response{status_code: 200, body: body}}
        end]
      }
    ]) do
      assert Agent.get("lbot-170198") == {:ok, @agent}
    end
  end
end
