defmodule Glific.Providers.Gupshup.V3.TemplatePayloadTest do
  use ExUnit.Case, async: true

  alias Glific.Providers.Gupshup.V3.TemplatePayload
  alias Glific.Templates.SessionTemplate

  @form_template %SessionTemplate{
    shortcode: "feedback_form",
    buttons: [
      %{"type" => "QUICK_REPLY", "text" => "Later"},
      %{"type" => "FLOW", "text" => "Open form", "flow_id" => "1787478395302778"}
    ]
  }

  test "build/2 sends the template by name and language with the flow_token on the flow button" do
    payload =
      TemplatePayload.build(@form_template, %{
        destination: "919917443994",
        language: "en",
        params: ["Asha", 3],
        flow_token: "encrypted-token"
      })

    assert %{
             "messaging_product" => "whatsapp",
             "recipient_type" => "individual",
             "to" => "919917443994",
             "type" => "template",
             "template" => %{
               "name" => "feedback_form",
               "language" => %{"policy" => "deterministic", "code" => "en"},
               "components" => [
                 %{
                   "type" => "body",
                   "parameters" => [
                     %{"type" => "text", "text" => "Asha"},
                     %{"type" => "text", "text" => "3"}
                   ]
                 },
                 %{
                   "type" => "button",
                   "sub_type" => "flow",
                   "index" => "1",
                   "parameters" => [
                     %{"type" => "action", "action" => %{"flow_token" => "encrypted-token"}}
                   ]
                 }
               ]
             }
           } = payload
  end

  test "build/2 adds a media header and skips the body when there are no params" do
    payload =
      TemplatePayload.build(@form_template, %{
        destination: "919917443994",
        language: "hi",
        params: [],
        media: {"document", %{"link" => "https://example.com/a.pdf", "filename" => "a.pdf"}},
        flow_token: "encrypted-token"
      })

    assert [
             %{
               "type" => "header",
               "parameters" => [
                 %{
                   "type" => "document",
                   "document" => %{"link" => "https://example.com/a.pdf", "filename" => "a.pdf"}
                 }
               ]
             },
             %{"type" => "button", "sub_type" => "flow"}
           ] = payload["template"]["components"]
  end

  test "build/2 leaves out the button component when the template has no flow button" do
    template = %SessionTemplate{shortcode: "welcome", buttons: []}

    payload =
      TemplatePayload.build(template, %{
        destination: "919917443994",
        language: "en",
        params: ["Asha"],
        flow_token: "encrypted-token"
      })

    assert [%{"type" => "body"}] = payload["template"]["components"]
  end
end
