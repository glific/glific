defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients
  """

  import Ecto.Query, warn: false

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("parse_via_chat_gpt", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    question_text = fields["question_text"]

    if(question_text not in [nil, ""]) do
      Glific.ChatGPT.parse(org_id, question_text)
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
    else
      %{
        success: false,
        parsed_msg: "Could not parsed"
      }
    end
  end

  def webhook(_, _fields), do: %{}
end
