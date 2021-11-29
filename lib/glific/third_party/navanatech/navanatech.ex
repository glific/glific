defmodule Glific.Navanatech do
  @moduledoc """
  Glific Navanatech for all api calls to navatech
  """

  alias Glific.Partners
  alias Tesla.Multipart

  ## params =  %{media_url: "https://storage.googleapis.com/cc-tides/uploads/20210721140700_C717_F0_M539582.mp3", case_id: "b9296e58-ebf5-462f-a83b-6753f604ad69", organization_id: 1}
  ## params_text =  %{text: "ఎందుక", case_id: "501e75a0-3b12-46de-b785-5c1e897ab0f2", organization_id: 1}
  # Glific.Navanatech.decode_message(params)
  # Glific.Navanatech.decode_message(params_text)

  @doc """
  Decode a text or audio file
  """

  @spec decode_message(map()) :: tuple()
  def decode_message(%{media_url: media_url, case_id: case_id, organization_id: org_id} = _attrs) do
    extension =
      Path.extname(media_url)
      |> String.replace(".", "")

    extension = if extension in [""], do: "mp3", else: extension

    mp =
      Multipart.new()
      |> Multipart.add_field("id", case_id)
      |> Multipart.add_field("file_extension", extension)
      |> Multipart.add_field("url", media_url)

    client(org_id)
    |> Tesla.post("/usecase/decode/url", mp)
    |> handle_response()
  end

  def decode_message(%{text: nil, case_id: _case_id, organization_id: _org_id} = _attrs),
    do: handle_response({:error, "Invalid text"})

  def decode_message(%{text: text, case_id: case_id, organization_id: org_id} = _attrs) do
    mp =
      Multipart.new()
      |> Multipart.add_field("id", case_id)
      |> Multipart.add_field("text", text)
      |> Multipart.add_field("filter", "{\"type\": \"LongestKeyword\"}")

    client(org_id)
    |> Tesla.post("/usecase/decode/text", mp)
    |> handle_response()
  end

  def decode_message(_), do: {:error, "invalid params"}

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @doc """
    Get the tesla client with existing configurations.
  """
  @spec client(non_neg_integer()) :: Tesla.Client.t()
  def client(org_id) do
    {:ok, %{url: base_url, token: token}} = credentials(org_id)

    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> token}]}
    ]

    Tesla.client(middleware)
  end

  @spec credentials(non_neg_integer()) :: tuple()
  defp credentials(org_id) do
    organization = Partners.organization(org_id)

    organization.services["navana_tech"]
    |> case do
      nil ->
        {:error, "Secret not found."}

      credentials ->
        {:ok, %{url: credentials.keys["url"], token: credentials.secrets["token"]}}
    end
  end
end
