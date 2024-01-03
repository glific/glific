defmodule Glific.Flows.Translate.OpenAI do
  @moduledoc """
  Code to translate using OpenAI as the translation engine
  """
  @behaviour Glific.Flows.Translate.Translate

  alias Glific.{
    OpenAI.ChatGPT,
    Repo
  }

  @doc """
  Translate a list of strings from language 'src' to language 'dst'
  Returns, either ok with the translated list in the same order,
  or error with a error message

  ## Examples

  iex> Glific.Flows.Translate.OpenAI.translate(["thankyou for joining", "correct answer"], "english", "hindi")
    {:ok, ["hindi thankyou for joining english", "hindi correct answer english"]}
  """
  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst) do
    length = Enum.count(strings)
    org_id = Repo.get_organization_id()

    prompt =
      """
      I'm going to give you a template for your output. CAPTALIZED WORDS are my placeholders.
      Please preserve the overall formatting of my template to convert list of strings from #{src} to #{dst}

      ***["CONVERTED_TEXT_1", "CONVERTED_TEXT_2","CONVERTED_TEXT_3"]**

      Please return only the list. Here's sample

      User: ["hello there", "oops wrong answer", "Great to meet you"]
      Think: there are 3 comma separated strings list in english to 3 comma separated strings list in hindi
      System: ["नमस्ते", "उफ़ ग़लत उत्तर", "बड़ा अच्छा लगा आपसे मिल के"]
      User: ["welcome", "correct answer, keep it up", "you won 1 point"]
      Think: there are 3 comma separated strings list in english to 3 comma separated strings list in tamil
      System: ["வரவேற்பு", "சரியான பதில், தொடருங்கள்", "நீங்கள் 1 புள்ளியை வென்றீர்கள்"]
      """

    ChatGPT.parse(
      org_id,
      """
      #{prompt}
      User: #{strings}
      Think: there are #{length} comma separated strings list in #{src} to #{length} comma separated strings list in #{dst}
      System:
      """
    )
    |> IO.inspect()
    |> case do
      {:ok, result} -> {:ok, Jason.decode!(result)}
      rest -> rest
    end
  end
end
