defmodule GlificWeb.KaapiController do
  @moduledoc """
  The controller to process callbacks received from Kaapi.
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.Assistants
  alias Glific.PromptGenerator

  @doc """
  Handles the callback from Kaapi upon successful or failure of collection creation.
  """
  @spec knowledge_base_version_creation_callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def knowledge_base_version_creation_callback(conn, params) do
    Logger.info("Received knowledge base creation callback", params: params)
    Assistants.handle_knowledge_base_callback(params)
    send_resp(conn, 200, "Knowledge base version creation callback handled successfully")
  end

  @doc """
  Handles the async callback POSTed by Kaapi after LLM-based prompt generation completes.

  Always returns 200 — Kaapi does not retry on non-2xx, and the request_id is treated as an
  unguessable token (matching the auth posture of the knowledge_base_version callback above).
  """
  @spec prompt_generation_callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def prompt_generation_callback(conn, params) do
    PromptGenerator.handle_callback(params)
    send_resp(conn, 200, "")
  end
end
