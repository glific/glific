defmodule Glific.AI.CredentialsTest do
  use Glific.DataCase

  alias Glific.AI.Credentials
  alias Glific.Partners
  alias Glific.Partners.Provider
  alias Glific.Repo

  describe "fetch/2 — no organisation credential configured" do
    test "falls back to the platform-wide Anthropic key", %{organization_id: organization_id} do
      assert {:ok, key} = Credentials.fetch(organization_id, :anthropic)
      assert is_binary(key)
      assert key != ""
    end

    test "falls back to the platform-wide OpenAI key", %{organization_id: organization_id} do
      assert {:ok, key} = Credentials.fetch(organization_id, :openai)
      assert is_binary(key)
      assert key != ""
    end

    test "falls back to the platform-wide Google key", %{organization_id: organization_id} do
      assert {:ok, key} = Credentials.fetch(organization_id, :google)
      assert is_binary(key)
      assert key != ""
    end

    test "openrouter has no platform fallback configured", %{organization_id: organization_id} do
      assert {:error, message} = Credentials.fetch(organization_id, :openrouter)
      assert message =~ "no platform credential configured"
    end
  end

  describe "fetch/2 — organisation credential configured" do
    test "an organisation's own key wins over the platform fallback", %{
      organization_id: organization_id
    } do
      organization = Partners.get_organization!(organization_id)

      {:ok, _provider} =
        %Provider{}
        |> Provider.changeset(%{
          name: "Anthropic",
          shortcode: "anthropic",
          keys: %{},
          secrets: %{}
        })
        |> Repo.insert()

      {:ok, credential} =
        Partners.create_credential(%{
          organization_id: organization_id,
          shortcode: "anthropic",
          keys: %{},
          secrets: %{"api_key" => "sk-org-specific-key"}
        })

      {:ok, _credential} = Partners.update_credential(credential, %{is_active: true})

      Partners.fill_cache(organization)

      assert {:ok, "sk-org-specific-key"} = Credentials.fetch(organization_id, :anthropic)
    end

    test "an org credential with a blank api_key still falls back to the platform key", %{
      organization_id: organization_id
    } do
      organization = Partners.get_organization!(organization_id)

      {:ok, _provider} =
        %Provider{}
        |> Provider.changeset(%{
          name: "Google",
          shortcode: "google",
          keys: %{},
          secrets: %{}
        })
        |> Repo.insert()

      {:ok, credential} =
        Partners.create_credential(%{
          organization_id: organization_id,
          shortcode: "google",
          keys: %{},
          secrets: %{"api_key" => ""}
        })

      {:ok, _credential} = Partners.update_credential(credential, %{is_active: true})

      Partners.fill_cache(organization)

      assert {:ok, key} = Credentials.fetch(organization_id, :google)
      assert key == Glific.get_google_api_key()
    end
  end
end
