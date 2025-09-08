defmodule Glific.ThirdParty.OpenAI.AskmeBot do
  @moduledoc """
  Glific AskMeBot module for all API calls to openAI
  """

  @endpoint "https://api.openai.com/v1"

  @doc """
  Calls the OpenAI resposne api and fetch the answer for AskMe bot
  """
  @spec askme(map()) :: {:ok, map(), {:error, map()}}
  def askme(params) do
    api_key = Glific.get_open_ai_key()
    url = @endpoint <> "/responses"
    model = Map.get(params, :model, "gpt-4o-mini")

    vector_store_ids =
      Map.get(params, :vector_store_ids) ||
        case Map.get(params, :vector_store_id) do
          nil -> nil
          id when is_binary(id) -> [id]
        end

    attachments =
      case Map.get(params, :file_ids) do
        nil ->
          nil

        ids when is_list(ids) ->
          Enum.map(ids, fn fid -> %{"file_id" => fid, "tools" => [%{"type" => "file_search"}]} end)
      end

    base = %{
      "model" => model,
      "input" => params["input"],
      "store" => true
    }

    data =
      cond do
        is_list(vector_store_ids) ->
          base
          |> Map.put("tools", [%{"type" => "file_search"}])
          |> Map.put("tool_config", %{
            "file_search" => %{"vector_store_ids" => "vector_store_id"}
          })

        is_list(attachments) ->
          base
          |> Map.put("tools", [%{"type" => "file_search"}])
          |> Map.put("attachments", attachments)

        true ->
          base
      end

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

    Tesla.client(middleware)
    |> Tesla.post(url, data, opts: [adapter: [recv_timeout: 120_000]])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        get_in(body, ["output", Access.at(0), "content", Access.at(0), "text"])

      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, get_in(body, ["error", "message"]) || "OpenAI client error (#{status})"}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Unexpected OpenAI response (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error calling OpenAI: #{inspect(reason)}"}
    end
  end
end
