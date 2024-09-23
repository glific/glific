defmodule Glific.OpenAI.Filesearch.ApiClient do
  @moduledoc """
  Glific module for API calls to OpenAI related to Filesearch
  """
  alias Tesla.Multipart
  require Logger
  @endpoint "https://api.openai.com/v1"
  use Tesla

  @spec headers() :: list()
  defp headers do
    open_ai_key = Glific.get_open_ai_key()

    [
      {"Authorization", "Bearer #{open_ai_key}"},
      {"Content-Type", "application/json"},
      {"OpenAI-Beta", "assistants=v2"}
    ]
  end

  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])

  @doc """
  Creates vector store
  """
  @spec create_vector_store(String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store(name) do
    url = @endpoint <> "/vector_stores"

    payload =
      %{"name" => name}
      |> Jason.encode!()

    post(url, payload, headers: headers())
    |> parse_response()
  end

  @spec upload_knowledge_base(
          atom()
          | %{
              :media => atom() | %{:path => binary(), optional(any()) => any()},
              optional(any()) => any()
            }
        ) :: {:error, <<_::64, _::_*8>>} | {:ok, map()}
  def upload_knowledge_base(params) do
    url = @endpoint <> "/files"

    data =
      Multipart.new()
      |> Multipart.add_file(params.media.path, name: "file")
      |> Multipart.add_field("purpose", "assistants")

    post(url, data, headers: headers())
    |> IO.inspect()
    |> parse_response()
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %{body: resp_body, status: status}})
       when status >= 200 and status < 300 do
    {:ok, resp_body}
  end

  defp parse_response({:ok, %{body: resp_body, status: status}}) do
    Logger.error("Filesearch api error due to #{inspect(resp_body)} with status #{status}")
    {:error, "OpenAI api failed with status #{status}"}
  end

  defp parse_response({:error, message}) do
    Logger.error("Filesearch api error due to #{inspect(message)}")
    {:error, "OpenAI api failed"}
  end
end
