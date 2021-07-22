defmodule Glific.Navanatech do
  @moduledoc """
  Glific Navanatech for all api calls to navatech
  """

  ## params =  %{media_url: "https://storage.googleapis.com/cc-tides/uploads/20210721140700_C717_F0_M539582.mp3", case_id: "b9296e58-ebf5-462f-a83b-6753f604ad69", organization_id: 1}
  ## params_text =  %{text: "వుంది", case_id: "b9296e58-ebf5-462f-a83b-6753f604ad69", organization_id: 1}
  # Glific.Navanatech.decode_message(params)
  # Glific.Navanatech.decode_message(params_text)

  @doc """
  Decode a text or audio file
  """
  @spec decode_message(map()) :: tuple()
  def decode_message(%{media_url: media_url, case_id: case_id, organization_id: org_id} = _attrs) do
    extension =
      Path.extname(media_url)
      |> String.replace( ".", "")

    params =  %{use_case_id: case_id, url: media_url, extension:  extension}

    client(org_id)
    |> Tesla.post("/usecase/decode/audio", params)
    |> handle_response()
  end

  def decode_message(%{text: text, case_id: case_id, organization_id: org_id} = _attrs) do
    params =  %{use_case_id: case_id, text: text}

    client(org_id)
    |> Tesla.post("/usecase/decode/text", params)
    |> handle_response()
  end

  def decode_message(_), do: {:error, "invalid params"}

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {_status, response}
        -> {:error, "invalid response #{inspect response}"}
    end
  end

  @doc """
    Get the tesla client with existing configurations.
  """
  @spec client(non_neg_integer()) :: Tesla.Client.t()
  def client(_org_id) do
    token =  Application.get_env(:glific, :navanatech_token, "")
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://speechapi.southeastasia.cloudapp.azure.com/digigreen"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> token }]}
    ]
    Tesla.client(middleware)
  end

end
