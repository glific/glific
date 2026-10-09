defmodule Glific.Providers.Gupshup.V3.TemplatePayload do
  @moduledoc """
  Builds the Meta Cloud API template payload sent through the Gupshup V3 message API.
  """

  alias Glific.Templates.SessionTemplate

  @doc """
  Builds the template message body for the given template, recipient and send-time values.
  """
  @spec build(SessionTemplate.t(), map()) :: map()
  def build(template, %{destination: destination, language: language} = attrs) do
    %{
      "messaging_product" => "whatsapp",
      "recipient_type" => "individual",
      "to" => destination,
      "type" => "template",
      "template" => %{
        "name" => template.shortcode,
        "language" => %{"policy" => "deterministic", "code" => language},
        "components" => components(template, attrs)
      }
    }
  end

  @spec components(SessionTemplate.t(), map()) :: list(map())
  defp components(template, attrs) do
    [
      header(attrs[:media]),
      body(attrs[:params] || []),
      flow_button(template.buttons, attrs[:flow_token])
    ]
    |> Enum.reject(&is_nil/1)
  end

  @spec header({String.t(), map()} | nil) :: map() | nil
  defp header({type, media}) do
    %{"type" => "header", "parameters" => [%{"type" => type, type => media}]}
  end

  defp header(nil), do: nil

  @spec body(list()) :: map() | nil
  defp body([]), do: nil

  defp body(params) do
    %{
      "type" => "body",
      "parameters" => Enum.map(params, &%{"type" => "text", "text" => to_string(&1)})
    }
  end

  @spec flow_button(list(map()), String.t() | nil) :: map() | nil
  defp flow_button(_buttons, nil), do: nil

  defp flow_button(buttons, flow_token) do
    case Enum.find_index(buttons, &(&1["type"] == "FLOW")) do
      nil ->
        nil

      index ->
        %{
          "type" => "button",
          "sub_type" => "flow",
          "index" => to_string(index),
          "parameters" => [%{"type" => "action", "action" => %{"flow_token" => flow_token}}]
        }
    end
  end
end
