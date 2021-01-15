defmodule Glific.Providers.Gupshup.ApiClient do
  @moduledoc """
  Http API client to intract with Gupshup
  """
  alias Plug.Conn.Query
  alias Glific.Partners

  @gupshup_url "https://api.gupshup.io/sm/api/v1"

  use Tesla
  # you can add , log_level: :debug to the below if you want debugging info
  plug Tesla.Middleware.Logger

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1

  def get_template(org_id) do
    bsp_creds = get_bsp(org_id)
    api_key = bsp_creds.secrets["api_key"]

    template_url =
      bsp_creds.keys["api_end_point"] <> "/template/list/" <> bsp_creds.secrets["app_name"]

    case Tesla.get(template_url, headers: [{"apikey", api_key}]) do
      {:ok, response} -> IO.inspect(response)
      {:error, %{reason: reason}} -> IO.inspect("error")
    end
  end

  defp get_bsp(org_id) do
    organization = Partners.organization(org_id)
    bsp_creds = organization.services["bsp"]
  end
end
