defmodule GlificWeb.Flows.WebhookController do
  @moduledoc """
  Experimental approach on trying to handle webhooks for NGOs within the system.
  This bypasses using a third party and hence makes things a lot more efficient
  """

  use GlificWeb, :controller
  alias Glific.Clients.Stir
  @doc """
  Example implementation of survey computation for STiR
  """
  @spec stir_survey(Plug.Conn.t(), map) :: Plug.Conn.t()
  def stir_survey(conn, %{"results" => results} = _params) do
    json =
      Stir.compute_survey_score(results)
      |> Map.merge(%{ art_result: Stir.compute_art_results(results)})
      |> Map.merge(%{ art_content: Stir.compute_art_content(results)})

    conn
    |> json(json)
  end
end
