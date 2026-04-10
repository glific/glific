defmodule GlificWeb.Resolvers.ChatbotDiagnose do
  @moduledoc """
  Resolver for the chatbotDiagnose GraphQL query.
  """

  alias Glific.ChatbotDiagnose

  @doc """
  Resolve the chatbot_diagnose query by delegating to the context module.
  """
  @spec chatbot_diagnose(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, String.t()}
  def chatbot_diagnose(_, %{input: input}, %{context: %{current_user: user}}) do
    ChatbotDiagnose.diagnose(user.organization_id, input)
  rescue
    e ->
      Glific.log_error("ChatbotDiagnose error: #{Exception.message(e)}")
      {:error, "An unexpected error occurred during diagnosis"}
  end
end
