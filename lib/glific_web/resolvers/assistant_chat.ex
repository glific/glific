defmodule GlificWeb.Resolvers.AssistantChat do
  @moduledoc """
  Resolver for sending a chat message to a selected (default: live) Kaapi config version of an assistant
  (the "Try It Out" sandbox). Dispatch is synchronous (Kaapi just queues the job);
  the reply arrives later via the `assistant_chat_response` subscription once Kaapi's
  callback fires.
  """

  alias Glific.Assistants

  @doc """
  Dispatches a chat message to the selected (or live) Kaapi config version of an assistant.
  """
  @spec send_message(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def send_message(_, %{input: params}, %{context: %{current_user: user}}) do
    context_params = %{
      assistant_id: params.assistant_id,
      input: params.message,
      conversation_id: params[:conversation_id],
      config_version_id: params[:config_version_id]
    }

    Assistants.send_message(context_params, user.organization_id, user.id)
  end
end
