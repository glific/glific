defmodule GlificWeb.KaapiController do
  @moduledoc """
  The controller to process callbacks received from Kaapi.
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.Assistants

  @doc """
  Handles the callback from Kaapi upon successful or failure of collection creation.
  """
  @spec knowledge_base_version_creation_callback(map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def knowledge_base_version_creation_callback(conn, params) do
    Logger.info("Received knowledge base creation callback")
    Assistants.handle_kaapi_knowledge_base_callback(params)
    send_resp(conn, 200, "Knowledge base version creation callback handled successfully")
  end
end
