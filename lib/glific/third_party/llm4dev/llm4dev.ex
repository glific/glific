defmodule Glific.LLM4Dev do
  @moduledoc """
  Glific LLM4Dev module for all API calls to LLM4Dev
  """

  alias Glific.Partners
  alias Tesla.Multipart

  use Tesla

  @doc """
  Making API call to LLM4Dev and adding Authorization token in header
  """
  @spec llm4dev_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def llm4dev_post(url, payload, api_key) do
    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Authorization", api_key}]}
    ]

    middleware
    |> Tesla.client()
    |> post(
      url,
      payload,
      opts: [adapter: [recv_timeout: 120_000]]
    )
  end

  @doc """
  Making Tesla get call and adding api key in header
  """
  @spec llm4dev_get(String.t(), String.t()) :: Tesla.Env.result()
  def llm4dev_get(url, api_key), do: get(url, headers: [{"Authorization", api_key}])

  @doc """
  API call to LLM4Dev
  """
  @spec parse(String.t(), String.t(), map()) :: tuple()
  def parse(api_key, url, params) do
    data = set_params(params)
    chat_url = url <> "/api/chat"

    llm4dev_post(chat_url, data, api_key)
    |> handle_response()
  end

  @spec set_params(map()) :: map()
  defp set_params(%{prompt: prompt, session_id: session_id}) when is_nil(session_id),
    do: %{"prompt" => prompt}

  defp set_params(%{prompt: prompt, session_id: session_id}),
    do: %{"prompt" => prompt, "session_id" => session_id}

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 201, body: body}} ->
        body
        |> Map.put(:success, true)
        |> then(&{:ok, &1})

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @doc """
    Get the credentials for Open LLM with existing configurations.
  """
  @spec get_credentials(non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  def get_credentials(org_id) do
    organization = Partners.organization(org_id)

    organization.services["llm4dev"]
    |> case do
      nil ->
        {:error, "Secret not found."}

      credentials ->
        {:ok, %{api_key: credentials.secrets["api_key"], api_url: credentials.secrets["api_url"]}}
    end
  end

  @doc """
    Set system prompt for Open LLM with existing configurations.
  """
  @spec set_system_prompt(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def set_system_prompt(org_id, system_prompt) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/system_prompt"
      llm4dev_post(url, %{system_prompt: system_prompt}, api_key)
    end
  end

  @doc """
    Set examples text for Open LLM with existing configurations.
    example_text = "Question: What is Glific? \n Chatbot Answer: Glific is a no-code Whatsapp Chatbot building platform"
    set_examples_text(1, examples_text)
  """
  @spec set_examples_text(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def set_examples_text(org_id, examples_text) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/examples_text"
      llm4dev_post(url, %{examples_text: examples_text}, api_key)
    end
  end

  @doc """
    Set document as knowledge base with category
  """
  @spec upload_knowledge_base(non_neg_integer(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def upload_knowledge_base(org_id, params) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/upload"

      data =
        Multipart.new()
        |> Multipart.add_file(params["file_path"], name: "file")
        |> Multipart.add_field("category_id", params["category_id"])

      llm4dev_post(url, data, api_key)
    end
  end

  @doc """
    Delete knowledge base document
  """
  @spec delete_knowledge_base(non_neg_integer(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def delete_knowledge_base(org_id, uuid) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/files/#{uuid}"
      delete(url, headers: [{"Authorization", api_key}])
    end
  end

  @doc """
    Create new category for knowledge base
  """
  @spec create_category(non_neg_integer(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def create_category(org_id, category) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/knowledge/category"

      llm4dev_post(url, %{category: category}, api_key)
    end
  end

  @doc """
    List categories of knowledge base
  """
  @spec list_categories(non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def list_categories(org_id) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/knowledge/category"

      llm4dev_get(url, api_key)
    end
  end

  @doc """
    List knowledge base docs
  """
  @spec list_knowledge_base(non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def list_knowledge_base(org_id) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/files"

      llm4dev_get(url, api_key)
      |> handle_kb_response()
    end
  end

  @spec handle_kb_response(tuple()) :: tuple()
  defp handle_kb_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        response_body = Jason.decode!(body)
        {:ok, response_body["data"]}

        knowledge_base =
          response_body["data"]
          |> Enum.reduce([], fn kb, acc ->
            Map.new(kb, fn {key, value} ->
              if key == "category" do
                category_map =
                  Map.new(value, fn {category_key, category_value} ->
                    {String.to_atom(category_key), category_value}
                  end)

                {String.to_atom(key), category_map}
              else
                {String.to_atom(key), value}
              end
            end)
            |> then(&(acc ++ [&1]))
          end)

        {:ok, %{knowledge_base: knowledge_base}}

      {_status, _response} ->
        {:error, "invalid response"}
    end
  end
end
