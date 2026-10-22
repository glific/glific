defmodule Glific.WebChannel.JwtSecretTest do
  @moduledoc false

  # Not async: it writes the organization's credential and refills the shared org cache.
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Partners,
    Partners.Credential,
    Repo,
    WebChannel.JwtSecret,
    WebChannelFlagHelpers
  }

  @shortcode "web_channel"

  defp credential(organization_id) do
    {:ok, credential} =
      Partners.get_credential(%{organization_id: organization_id, shortcode: @shortcode})

    credential
  end

  defp create_credential(organization_id, attrs) do
    Partners.create_credential(
      Map.merge(
        %{organization_id: organization_id, shortcode: @shortcode, keys: %{}, secrets: %{}},
        attrs
      )
    )
  end

  defp stored_entries(organization_id),
    do: organization_id |> credential() |> Map.fetch!(:secrets) |> JwtSecret.entries()

  describe "a secret created when the web channel is enabled" do
    test "is made on creating an active credential", %{organization_id: organization_id} do
      assert {:ok, %Credential{is_active: true}} =
               create_credential(organization_id, %{is_active: true})

      assert [%{"name" => "Signing secret", "secret" => secret}] = stored_entries(organization_id)
      assert String.length(secret) >= 32
      assert {:ok, ^secret} = JwtSecret.fetch(organization_id)
    end

    test "is not made for an inactive credential", %{organization_id: organization_id} do
      assert {:ok, _credential} = create_credential(organization_id, %{is_active: false})

      assert stored_entries(organization_id) == []
      assert :error = JwtSecret.fetch(organization_id)
    end

    test "is made on activating an existing credential", %{organization_id: organization_id} do
      {:ok, inactive} = create_credential(organization_id, %{is_active: false})

      assert {:ok, %Credential{}} = Partners.update_credential(inactive, %{is_active: true})
      assert [%{"secret" => _secret}] = stored_entries(organization_id)
      assert {:ok, _secret} = JwtSecret.fetch(organization_id)
    end

    test "is kept when the credential is saved again", %{organization_id: organization_id} do
      {:ok, active} = create_credential(organization_id, %{is_active: true})
      {:ok, secret} = JwtSecret.fetch(organization_id)

      assert {:ok, _credential} = Partners.update_credential(active, %{keys: %{"a" => "b"}})
      assert {:ok, ^secret} = JwtSecret.fetch(organization_id)
    end

    test "persists when the channel is switched off", %{organization_id: organization_id} do
      {:ok, active} = create_credential(organization_id, %{is_active: true})
      {:ok, secret} = JwtSecret.fetch(organization_id)

      assert {:ok, _credential} = Partners.update_credential(active, %{is_active: false})
      assert [%{"secret" => ^secret}] = stored_entries(organization_id)
    end

    test "is not replaced on re-enabling", %{organization_id: organization_id} do
      {:ok, active} = create_credential(organization_id, %{is_active: true})
      {:ok, secret} = JwtSecret.fetch(organization_id)
      {:ok, inactive} = Partners.update_credential(active, %{is_active: false})

      assert {:ok, _credential} = Partners.update_credential(inactive, %{is_active: true})
      assert {:ok, ^secret} = JwtSecret.fetch(organization_id)
    end

    test "is scoped to its own organization", %{organization_id: organization_id} do
      other = Fixtures.organization_fixture(%{shortcode: "secretscope"})
      WebChannelFlagHelpers.activate_web_channel(other.id)
      {:ok, other_secret} = JwtSecret.fetch(other.id)

      assert :error = JwtSecret.fetch(organization_id)
      assert {:ok, ^other_secret} = JwtSecret.fetch(other.id)
    end
  end

  describe "the one-secret rule" do
    @two_secrets %{
      "jwt_signature_secrets" => [
        %{"name" => "first", "secret" => "first-secret-first-secret-0123456"},
        %{"name" => "second", "secret" => "second-secret-second-secret-012345"}
      ]
    }

    test "rejects creating a credential with two secrets", %{organization_id: organization_id} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               create_credential(organization_id, %{is_active: true, secrets: @two_secrets})

      assert "Only one JWT signature secret is allowed" in errors_on(changeset).secrets
    end

    test "rejects saving a second secret and keeps the first", %{organization_id: organization_id} do
      first = %{
        "jwt_signature_secrets" => [
          %{"name" => "first", "secret" => "first-secret-first-secret-0123456"}
        ]
      }

      {:ok, active} = create_credential(organization_id, %{is_active: true, secrets: first})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Partners.update_credential(active, %{secrets: @two_secrets})

      assert "Only one JWT signature secret is allowed" in errors_on(changeset).secrets
      assert {:ok, "first-secret-first-secret-0123456"} = JwtSecret.fetch(organization_id)
    end

    test "rejects a secret shorter than 32 characters", %{organization_id: organization_id} do
      short = %{"jwt_signature_secrets" => [%{"name" => "short", "secret" => "too-short"}]}

      assert {:error, %Ecto.Changeset{} = changeset} =
               create_credential(organization_id, %{is_active: true, secrets: short})

      assert "The JWT signature secret must be at least 32 characters" in errors_on(changeset).secrets
    end

    test "rejects removing a saved secret and keeps it", %{organization_id: organization_id} do
      {:ok, active} = create_credential(organization_id, %{is_active: true})
      {:ok, saved} = JwtSecret.fetch(organization_id)

      for secrets <- [%{"jwt_signature_secrets" => []}, %{}, nil] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Partners.update_credential(active, %{secrets: secrets})

        assert "The JWT signature secret can be replaced but not removed" in errors_on(changeset).secrets
      end

      assert {:ok, ^saved} = JwtSecret.fetch(organization_id)
    end

    test "replacing the single secret takes effect at once", %{organization_id: organization_id} do
      {:ok, active} = create_credential(organization_id, %{is_active: true})
      {:ok, old} = JwtSecret.fetch(organization_id)

      replacement = "replacement-secret-replacement-012"

      {:ok, _credential} =
        Partners.update_credential(active, %{
          secrets: %{"jwt_signature_secrets" => [%{"name" => "new", "secret" => replacement}]}
        })

      assert {:ok, ^replacement} = JwtSecret.fetch(organization_id)
      refute old == replacement
    end
  end

  describe "fetch/1" do
    test "ignores a secret shorter than 32 characters", %{organization_id: organization_id} do
      short = %{"jwt_signature_secrets" => [%{"name" => "short", "secret" => "tiny"}]}
      {:ok, active} = create_credential(organization_id, %{is_active: true})
      {:ok, _credential} = active |> Ecto.Changeset.change(%{secrets: short}) |> Repo.update()

      Partners.remove_organization_cache(
        organization_id,
        Partners.organization(organization_id).shortcode
      )

      assert :error = JwtSecret.fetch(organization_id)
    end

    test "is an error for an organization that does not exist" do
      assert :error = JwtSecret.fetch(0)
    end
  end

  describe "ensure/1" do
    test "gives a credential with no secrets one", %{organization_id: organization_id} do
      {:ok, active} = create_credential(organization_id, %{is_active: true})
      {:ok, bare} = active |> Ecto.Changeset.change(%{secrets: %{}}) |> Repo.update()

      assert {:ok, %Credential{secrets: %{"jwt_signature_secrets" => [_entry]}}} =
               JwtSecret.ensure(bare)
    end
  end
end
