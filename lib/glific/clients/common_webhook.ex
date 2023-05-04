defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.
  """

  alias Glific.OpenAI.ChatGPT
  alias Glific.Sheets.GoogleSheets

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

  def webhook(_, _fields), do: %{error: "Missing webhook function implementation"}
end
