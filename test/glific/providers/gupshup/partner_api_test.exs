defmodule Glific.Providers.Gupshup.PartnerAPITest do
  use Glific.DataCase

  alias Glific.Providers.Gupshup.PartnerAPI

  describe "get_library_templates/1" do
    test "returns the template library on a successful response", attrs do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/token"} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "xyz456"}})
          }

        %{
          method: :get,
          url: "https://partner.gupshup.io/partner/app/Glific42/template/metalibrary"
        } ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "templates" => [
                  %{
                    "elementName" => "welcome_offer",
                    "category" => "MARKETING",
                    "data" => "Hello {{1}}, welcome to our store!",
                    "industry" => "retail",
                    "languageCode" => "en",
                    "topic" => "welcome",
                    "usecase" => "onboarding",
                    "containerMeta" => %{"buttons" => []}
                  }
                ]
              })
          }
      end)

      assert {:ok, %{"templates" => [template]}} =
               PartnerAPI.get_library_templates(attrs.organization_id)

      assert template["elementName"] == "welcome_offer"
      assert template["languageCode"] == "en"
    end

    test "requests the catalog with no query filters", attrs do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/token"} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "xyz456"}})
          }

        %{method: :get, query: query} ->
          assert query == []

          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"templates" => []})
          }
      end)

      assert {:ok, %{"templates" => []}} = PartnerAPI.get_library_templates(attrs.organization_id)
    end

    test "returns Gupshup's decoded error message on a 4xx response", attrs do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/token"} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "xyz456"}})
          }

        %{
          method: :get,
          url: "https://partner.gupshup.io/partner/app/Glific42/template/metalibrary"
        } ->
          %Tesla.Env{
            status: 400,
            body: Jason.encode!(%{"message" => "Invalid request"})
          }
      end)

      assert {:error, "Invalid request"} = PartnerAPI.get_library_templates(attrs.organization_id)
    end

    test "returns a generic error on an unexpected/malformed response", attrs do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/token"} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"token" => %{"token" => "xyz456"}})
          }

        %{
          method: :get,
          url: "https://partner.gupshup.io/partner/app/Glific42/template/metalibrary"
        } ->
          %Tesla.Env{status: 500, body: "internal server error"}
      end)

      assert {:error, "Error while fetching the template library"} =
               PartnerAPI.get_library_templates(attrs.organization_id)
    end
  end
end
