defmodule Glific.Providers.Gupshup.Enterprise.ApiClient do
  @moduledoc """
  Http API client to interact with Gupshup Enterprise
  """
  alias Glific.Partners
  alias Plug.Conn.Query
  import GlificWeb.Gettext

  @gupshup_enterprise_url "https://media.smsgupshup.com/GatewayAPI/rest"
  @common_params %{"format" => "json", "v" => "1.1", "auth_scheme" => "plain"}
  @default_optin_params %{"method" => "OPT_IN", "channel" => "WHATSAPP"}
  @default_send_template_params %{"msg_type" => "HSM", "method" => "SendMessage"}
  @default_send_interactive_template_params %{"isTemplate" => "true", "method" => "SendMessage"}
  @button_template_params %{"isTemplate" => "true"}
  @default_send_message_params %{"method" => "SendMessage"}
  @default_send_media_message_params %{"method" => "SendMediaMessage", "isHSM" => "false"}

  use Tesla
  plug(Tesla.Middleware.Logger)

  plug(Tesla.Middleware.EncodeFormUrlencoded,
    encode: &Query.encode/1
  )

  @doc """
  Making Tesla post call and adding user_id and password from credentials
  """
  @spec gupshup_post(String.t(), any(), map()) :: Tesla.Env.result()
  def gupshup_post(url, payload, credentials), do: post(url, Map.merge(payload, credentials))

  @spec get_credentials(non_neg_integer()) :: {:error, String.t()} | {:ok, map()}
  defp get_credentials(org_id) do
    organization = Partners.organization(org_id)

    if is_nil(organization.services["bsp"]) do
      {:error, dgettext("errors", "No active BSP available")}
    else
      bsp_credentials = organization.services["bsp"]

      with false <-
             is_nil(bsp_credentials.secrets["hsm_user_id"]) &&
               is_nil(bsp_credentials.secrets["hsm_password"]),
           false <-
             is_nil(bsp_credentials.secrets["two_way_user_id"]) &&
               is_nil(bsp_credentials.secrets["two_way_password"]) do
        hsm_user_id = bsp_credentials.secrets["hsm_user_id"]
        hsm_password = bsp_credentials.secrets["hsm_password"]
        two_way_user_id = bsp_credentials.secrets["two_way_user_id"]
        two_way_password = bsp_credentials.secrets["two_way_password"]

        {:ok,
         %{
           hsm_user_id: hsm_user_id,
           hsm_password: hsm_password,
           two_way_user_id: two_way_user_id,
           two_way_password: two_way_password
         }}
      else
        _ ->
          {:error,
           "Please check your credential settings and ensure you have added the user ID and password also"}
      end
    end
  end

  @doc """
  Sending interactive template to contact
  """
  @spec send_interactive_template(non_neg_integer(), map()) ::
          Tesla.Env.result() | {:error, String.t()}
  def send_interactive_template(org_id, attrs) do
    with {:ok, credentials} <- get_credentials(org_id) do
      message = Jason.decode!(attrs["message"])
      interactive_type = if message["interactive_type"] == "list", do: "list", else: "dr_button"

      %{
        "action" => Jason.encode!(message["interactive_content"]),
        "send_to" => attrs["send_to"],
        "msg" => message["msg"],
        "interactive_type" => interactive_type
      }
      |> Map.merge(@common_params)
      |> check_for_media_interactive(message)
      |> then(
        &gupshup_post(@gupshup_enterprise_url, &1, %{
          "userid" => credentials.two_way_user_id,
          "password" => credentials.two_way_password
        })
      )
    end
  end

  @spec check_for_media_interactive(map(), map()) :: map()
  defp check_for_media_interactive(payload, %{"interactive_media_type" => media_type} = message)
       when media_type in ["image", "video", "document"] do
    payload
    |> Map.merge(%{
      "isTemplate" => "false",
      "method" => "SendMediaMessage",
      "msg_type" => media_type,
      "media_url" => message["media_url"],
      "caption" => message["msg"]
    })
  end

  defp check_for_media_interactive(payload, _message),
    do: Map.merge(payload, @default_send_interactive_template_params)

  @doc """
  Sending HSM template to contact
  """
  @spec send_template(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def send_template(org_id, attrs) do
    with {:ok, credentials} <- get_credentials(org_id) do
      attrs
      |> Map.merge(%{
        "send_to" => attrs["send_to"],
        "msg" => attrs["msg"]
      })
      |> Map.merge(@common_params)
      |> Map.merge(@default_send_template_params)
      |> is_button_template(attrs["has_buttons"])
      |> then(
        &gupshup_post(@gupshup_enterprise_url, &1, %{
          "userid" => credentials.hsm_user_id,
          "password" => credentials.hsm_password
        })
      )
    end
  end

  @doc """
  Sending Media HSM template to contact
  """
  @spec send_media_template(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def send_media_template(org_id, attrs) do
    with {:ok, credentials} <- get_credentials(org_id) do
      attrs
      |> Map.merge(@common_params)
      |> Map.merge(%{"method" => "SendMediaMessage"})
      |> is_button_template(attrs["has_buttons"])
      |> then(
        &gupshup_post(@gupshup_enterprise_url, &1, %{
          "userid" => credentials.hsm_user_id,
          "password" => credentials.hsm_password
        })
      )
    end
  end

  @spec is_button_template(map(), boolean()) :: map()
  defp is_button_template(attrs, false), do: attrs
  defp is_button_template(attrs, true), do: Map.merge(attrs, @button_template_params)

  @doc """
  Sending message to contact
  """
  @spec send_message(non_neg_integer(), map()) :: Tesla.Env.result() | any()
  def send_message(org_id, attrs) do
    with {:ok, credentials} <- get_credentials(org_id),
         {:ok, payload} <- Jason.decode(attrs["message"]) do
      payload
      |> Map.put("send_to", attrs["send_to"])
      |> Map.merge(@common_params)
      |> do_send_message(credentials)
    end
  end

  @spec do_send_message(map(), map()) :: Tesla.Env.result()
  defp do_send_message(%{"msg_type" => "DATA_TEXT"} = payload, credentials) do
    payload
    |> Map.merge(@default_send_message_params)
    |> then(
      &gupshup_post(@gupshup_enterprise_url, &1, %{
        "userid" => credentials.two_way_user_id,
        "password" => credentials.two_way_password
      })
    )
  end

  defp do_send_message(%{"msg_type" => msg_type} = payload, credentials)
       when msg_type in ["DOCUMENT", "VIDEO", "AUDIO", "IMAGE", "STICKER"] do
    payload
    |> Map.merge(@default_send_media_message_params)
    |> then(
      &gupshup_post(@gupshup_enterprise_url, &1, %{
        "userid" => credentials.two_way_user_id,
        "password" => credentials.two_way_password
      })
    )
  end

  @doc """
  Update a contact phone as opted in
  """
  @spec optin_contact(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def optin_contact(org_id, payload) do
    with {:ok, credentials} <- get_credentials(org_id) do
      payload
      |> Map.merge(@common_params)
      |> Map.merge(@default_optin_params)
      |> then(
        &gupshup_post(@gupshup_enterprise_url, &1, %{
          "userid" => credentials.hsm_user_id,
          "password" => credentials.hsm_password
        })
      )
    end
  end
end
