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
  def parse(api_key, api_url, params) do
    data =
      params
      |> add_session_id()
      |> add_category_id(params)
      |> add_system_prompt(params)

    url = api_url <> "/api/chat"

    llm4dev_post(url, data, api_key)
    |> handle_response()
  end

  @spec add_session_id(map()) :: map()
  defp add_session_id(%{question: question, session_id: session_id}) when is_nil(session_id),
    do: %{"question" => question}

  defp add_session_id(%{question: question, session_id: session_id}),
    do: %{"question" => question, "session_id" => session_id}

  @spec add_category_id(map(), map()) :: map()
  defp add_category_id(data, %{category_id: category_id}) when is_nil(category_id),
    do: data

  defp add_category_id(data, %{category_id: category_id}),
    do: Map.put(data, "category_id", category_id)

  @spec add_system_prompt(map(), map()) :: map()
  defp add_system_prompt(data, %{system_prompt: system_prompt}) when is_nil(system_prompt),
    do: data

  defp add_system_prompt(data, %{system_prompt: system_prompt}),
    do: Map.put(data, "system_prompt", system_prompt)

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
        {:error, "Credentials not found for LLM4Dev, Kindly update from Settings"}

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
        |> Multipart.add_file(params.media.path, name: "file")
        |> Multipart.add_field("category_id", params.category_id)
        |> Multipart.add_field("filename", params.media.filename)

      llm4dev_post(url, data, api_key)
      |> case do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          {:ok, %{msg: body["msg"]}}

        {_status, _response} ->
          {:error, "invalid response"}
      end
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
      |> handle_common_response()
      |> parse_common_response()
    end
  end

  @spec parse_common_response({:ok, map()} | {:error, any()}) :: {:ok, map()} | {:error, any()}
  defp parse_common_response({:error, error}), do: {:error, error}
  defp parse_common_response({:ok, response}), do: {:ok, %{msg: response["msg"]}}

  @doc """
    Create new category for knowledge base
  """
  @spec create_category(non_neg_integer(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def create_category(org_id, params) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/knowledge/category"

      llm4dev_post(url, %{"name" => params.name}, api_key)
      |> case do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          body
          |> Glific.atomize_keys()
          |> then(&{:ok, &1})

        {_status, _response} ->
          {:error, "invalid response"}
      end
    end
  end

  @doc """
    List categories of knowledge base
  """
  @spec list_categories(non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def list_categories(org_id) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/knowledge/category/get"

      llm4dev_get(url, api_key)
      |> handle_common_response()
      |> parse_category_response()
    end
  end

  defp parse_category_response({:error, error}), do: {:error, error}

  defp parse_category_response({:ok, response}) do
    response["data"]
    |> Enum.reduce([], fn category, acc ->
      category
      |> Glific.atomize_keys()
      |> then(&(acc ++ [&1]))
    end)
    |> then(&{:ok, &1})
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
      |> handle_common_response()
      |> parse_list_knowledgebase_response()
    end
  end

  defp parse_list_knowledgebase_response({:error, error}), do: {:error, error}

  defp parse_list_knowledgebase_response({:ok, response}) do
    knowledge_base =
      response["data"]
      |> Enum.reduce([], fn kb, acc ->
        Map.new(kb, fn {key, value} ->
          if key == "category" do
            Glific.atomize_keys(value)
            |> then(&{String.to_atom(key), &1})
          else
            {String.to_atom(key), value}
          end
        end)
        |> then(&(acc ++ [&1]))
      end)

    {:ok, knowledge_base}
  end

  defp handle_common_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %Tesla.Env{status: 400, body: body}} ->
        Jason.decode!(body)

      {:ok, %Tesla.Env{status: 404, body: body}} ->
        error = Jason.decode!(body)
        {:error, error["error"]}

      {_status, _response} ->
        {:error, "invalid response"}
    end
  end
end
