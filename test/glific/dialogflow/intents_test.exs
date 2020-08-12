defmodule Glific.Dialogflow.IntentsTest do
  use ExUnit.Case

  import Mock

  alias Glific.Dialogflow.Intents
  alias Goth.Token

  @intents %{
    "intents" => [
      %{
        "displayName" => "Acción (Despedida)",
        "messages" => [%{"text" => %{"text" => ["Bye", "Nos vemos"]}}],
        "name" => "projects/lbot-170189/agent/intents/4cff39af-ba13-4a62-ba6f-8a79f4f5b324",
        "priority" => 500_000
      }
    ]
  }

  @intent %{
    "displayName" => "Acción (Despedida)",
    "messages" => [%{"text" => %{"text" => ["Bye", "Nos vemos"]}}],
    "name" => "projects/lbot-170189/agent/intents/4cff39af-ba13-4a62-ba6f-8a79f4f5b324",
    "priority" => 500_000
  }

  @intent_view_full %{
    "displayName" => "Información Personal - En que ando",
    "messages" => [
      %{
        "text" => %{
          "text" => [
            "Aquí no más",
            "Esperando a que preguntes algo",
            "Trabajando ¿y tú?"
          ]
        }
      }
    ],
    "name" => "projects/lbot-170189/agent/intents/32d433a0-6542-4cbe-acc9-8e4af253cc26",
    "priority" => 500_000,
    "trainingPhrases" => [
      %{
        "name" => "cecaf1ee-c5b3-456c-8ff5-7c17eeb33acb",
        "parts" => [%{"text" => "Qué onda, Coyote, qué cuentas o qué"}],
        "type" => "EXAMPLE"
      },
      %{
        "name" => "661e0ded-7817-47f8-ab87-09ef4f548115",
        "parts" => [%{"text" => "¿Qué haces?"}],
        "type" => "EXAMPLE"
      }
    ]
  }

  @create_attrs %{
    displayName: "test"
  }

  @invalid_intent %{
    "error" => %{
      "code" => 400,
      "message" => "Intent with the display_name 'test' already exists.",
      "status" => "FAILED_PRECONDITION"
    }
  }

  test "list list all intents" do
    with_mocks([
      {
        Token,
        [:passthrough],
        [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
      },
      {
        HTTPoison,
        [:passthrough],
        [
          request: fn _method, _url, _params, _headers ->
            body = Poison.encode!(@intents)
            {:ok, %HTTPoison.Response{status_code: 200, body: body}}
          end
        ]
      }
    ]) do
      assert Intents.list("lbot-170198") == {:ok, @intents["intents"]}
    end
  end

  test "get/3 get an intent by id" do
    with_mocks([
      {
        Token,
        [:passthrough],
        [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
      },
      {
        HTTPoison,
        [:passthrough],
        [
          request: fn _method, _url, _params, _headers ->
            body = Poison.encode!(@intent)
            {:ok, %HTTPoison.Response{status_code: 200, body: body}}
          end
        ]
      }
    ]) do
      assert Intents.get("lbot-170198", "5eec5344-8a09-40ba-8f46-1d2ed3f7b0df") == {:ok, @intent}
    end
  end

  test "create/3 create valid intent" do
    with_mocks([
      {
        Token,
        [:passthrough],
        [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
      },
      {
        HTTPoison,
        [:passthrough],
        [
          request: fn _method, _url, _params, _headers ->
            body =
              @create_attrs
              |> Map.put(
                :name,
                "projects/lbot-170198/agent/intents/05f93e97-194d-469b-8721-70b5b6df9c82"
              )
              |> Map.put(:priority, 500_000)
              |> Poison.encode!()

            {:ok, %HTTPoison.Response{status_code: 200, body: body}}
          end
        ]
      }
    ]) do
      assert {:ok, intent} = Intents.create("lbot-170198", %{displayName: "test"})

      assert intent["displayName"] == @create_attrs.displayName
    end
  end

  test "create/3 create invalid intent" do
    with_mocks([
      {
        Token,
        [:passthrough],
        [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
      },
      {
        HTTPoison,
        [:passthrough],
        [
          request: fn _method, _url, _params, _headers ->
            body = Poison.encode!(@invalid_intent)
            {:ok, %HTTPoison.Response{status_code: 400, body: body}}
          end
        ]
      }
    ]) do
      assert {:error, errors} = Intents.create("lbot-170198", %{displayName: "test"})

      assert errors["error"]["message"] == @invalid_intent["error"]["message"]
    end
  end

  test "update/3 update an intent view full" do
    with_mocks([
      {
        Token,
        [:passthrough],
        [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
      },
      {
        HTTPoison,
        [:passthrough],
        [
          request: fn _method, _url, _params, _headers ->
            body = Poison.encode!(@intent_view_full)
            {:ok, %HTTPoison.Response{status_code: 200, body: body}}
          end
        ]
      }
    ]) do
      assert Intents.update(
               "lbot-170198",
               "5eec5344-8a09-40ba-8f46-1d2ed3f7b0df",
               @intent_view_full
             ) == {:ok, @intent_view_full}
    end
  end
end
