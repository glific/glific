defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.
  """

  alias Glific.{
    ASR.Bhasini,
    ASR.GoogleASR,
    Contacts.Contact,
    OpenAI.ChatGPT,
    Repo,
    Sheets.GoogleSheets
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("parse_via_chat_gpt", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    question_text = fields["question_text"]

    if question_text in [nil, ""] do
      %{
        success: false,
        parsed_msg: "Could not parsed"
      }
    else
      ChatGPT.parse(org_id, question_text)
      |> case do
        {:ok, text} ->
          %{
            success: true,
            parsed_msg: text
          }

        {_, error} ->
          %{
            success: false,
            parsed_msg: error
          }
      end
    end
  end

  def webhook("sheets.insert_row", fields) do
    org_id = fields["organization_id"]
    range = fields["range"] || "A:Z"
    spreadsheet_id = fields["spreadsheet_id"]
    row_data = fields["row_data"]

    with {:ok, response} <-
           GoogleSheets.insert_row(org_id, spreadsheet_id, %{range: range, data: [row_data]}) do
      %{response: "#{inspect(response)}"}
    end
  end

  def webhook("jugalbandi", fields) do
    prompt = if Map.has_key?(fields, "prompt"), do: [prompt: fields["prompt"]], else: []

    query =
      [
        query_string: fields["query_string"],
        uuid_number: fields["uuid_number"]
      ] ++ prompt

    Tesla.get(fields["url"],
      headers: [{"Accept", "application/json"}],
      query: query,
      opts: [adapter: [recv_timeout: 100_000]]
    )
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> Map.take(["answer"])
        |> Map.merge(%{success: true})

      {_status, response} ->
        %{success: false, response: "Invalid response #{response}"}
    end
  end

  def webhook("openllm", fields) do
    mp = Tesla.Multipart.add_field(Tesla.Multipart.new(), "prompt", fields["prompt"])

    Tesla.post(fields["url"], mp, opts: [adapter: [recv_timeout: 100_000]])
    |> case do
      {:ok, %Tesla.Env{status: 201, body: body}} ->
        Jason.decode!(body)
        |> Map.take(["answer", "session_id"])

      {_status, response} ->
        %{success: false, response: "Invalid response #{response}"}
    end
  end

  def webhook("jugalbandi-voice", %{"query_text" => query_text} = fields),
    do: query_jugalbandi_api(fields, query_text: query_text)

  def webhook("jugalbandi-voice", %{"audio_url" => audio_url} = fields),
    do: query_jugalbandi_api(fields, audio_url: audio_url)

  # This webhook will call Google speech-to-text API
  def webhook("speech_to_text", fields) do
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    contact = get_contact_language(contact_id)

    Glific.parse_maybe_integer!(fields["organization_id"])
    |> GoogleASR.speech_to_text(fields["results"], contact.language.locale)
  end

  # This webhook will call Bhasini speech-to-text API
  def webhook("speech_to_text_with_bhasini", fields) do
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    contact = get_contact_language(contact_id)

    Bhasini.with_config_request(
      fields,
      contact.language.locale
    )
  end

  def webhook("get_buttons", fields) do
    buttons =
      fields["buttons_data"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    }
  end

  def webhook("check_response", fields) do
    %{
      response: String.equivalent?(fields["correct_response"], fields["user_response"])
    }
  end

  def webhook(_, _fields), do: %{error: "Missing webhook function implementation"}

  defp get_contact_language(contact_id) do
    case Repo.fetch(Contact, contact_id) do
      {:ok, contact} -> contact |> Repo.preload(:language)
      {:error, error} -> error
    end
  end

  @spec query_jugalbandi_api(map(), list()) :: map()
  defp query_jugalbandi_api(fields, input) do
    query =
      [
        uuid_number: fields["uuid_number"],
        input_language: fields["input_language"],
        output_format: fields["output_format"]
      ] ++ input

    Tesla.get(fields["url"],
      headers: [{"Accept", "application/json"}],
      query: query,
      opts: [adapter: [recv_timeout: 200_000]]
    )
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> Map.take(["answer", "audio_output_url"])
        |> Map.merge(%{success: true})

      {_status, response} ->
        %{success: false, response: "Invalid response #{response}"}
    end
  end
end
