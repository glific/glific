defmodule Glific.Flows.Translate.Translate do
  @moduledoc """
  This module is the behavior interface for translation

  The rest of the code uses this as the API and is unaware of who the underlying
  translation API provider is
  """

  alias Glific.{
    OpenAI.ChatGPT,
    Repo
  }

  @callback translate(strings :: [String.t()], src :: String.t(), dst :: String.t()) ::
              {:ok, [String.t()]} | {:error, String.t()}

  @spec translate([String.t()], String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def translate(strings, src, dst), do: impl().translate(strings, src, dst)

  defp impl, do: Application.get_env(:glific, :adaptors)[:translators]

  @doc """
  Translate a list of strings from language 'src' to language 'dst'
  Returns, either ok with the translated list in the same order,
  or error with a error message
  Glific.Flows.Translate.Translate.translate_one(["thankyou for joining", "correct answer"], "english", "hindi")
  """
  @spec translate_one(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def translate_one(string, src, dst) do
    length = Enum.count(string)
    org_id = Repo.get_organization_id()

    prompt =
      "I'm going to give you a template for your output.CAPTALIZED WORDS are my placeholders. Please preserve the overall formatting of my template to convert list of strings from #{src} to #{dst}\n\n***[\"CONVERTED_TEXT_1\",\"CONVERTED_TEXT_2\",\"CONVERTED_TEXT_3**\n\nPlease return only the list. Here's sample\n\nUser: [\"hello there\", \"oops wrong answer\", \"Great to meet you\"]\nThink: there are 3 comma separated strings list in english to 3 comma separated strings list in hindi \nSystem: [\"नमस्ते\", \"उफ़ ग़लत उत्तर\", \"बड़ा अच्छा लगा आपसे मिल के\"]\nUser: [\"welcome\", \"correct answer, keep it up\", \"you won 1 point\"]\nThink: there are 3 comma separated strings list in english to 3 comma separated strings list in tamil\nSystem: [\"வரவேற்பு\", \"சரியான பதில், தொடருங்கள்\", \"நீங்கள் 1 புள்ளியை வென்றீர்கள்\"]"

    ChatGPT.parse(
      org_id,
      "#{prompt} \nUser: #{string}\nThink: there are #{length} comma separated strings list in #{src} to #{length} comma separated strings list in #{dst}\nSystem:"
    )
    |> case do
      {:ok, result} -> {:ok, Jason.decode!(result)}
      rest -> rest
    end
  end
end
