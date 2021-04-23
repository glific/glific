defmodule Glific.OnboardTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Partners.Organization,
    Saas.Onboard
  }

  @valid_attrs %{
    "name" => "First Organization",
    "phone" => "+911234567890",
    "api_key" => "fake api key",
    "app_name" => "fake app name",
    "email" => "lobo@yahoo.com",
    "shortcode" => "short"
  }

  setup do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "ok",
              "users" => [1, 2, 3]
            })
        }
    end)

    :ok
  end

  test "ensure that sending in valid parameters, creates an organization, contact and credential" do
    result = Onboard.setup(@valid_attrs)

    assert result.is_valid == true
    assert result.organization != nil
    assert result.contact != nil
    assert result.credential != nil

    # lets remove a couple and mess up the others to get most of the errors
    attrs =
      @valid_attrs
      |> Map.delete("app_name")
      |> Map.put("email", "foobar")
      |> Map.put("phone", "93'#$%^")
      |> Map.put("shortcode", "glific")

    result = Onboard.setup(attrs)

    assert result.is_valid == false
    assert result.messages != []
  end

  test "ensure that sending in valid parameters, update organization status" do
    result = Onboard.setup(@valid_attrs)
    {:ok, organization} = Repo.fetch_by(Organization, %{name: result.organization.name})

    updated_organization =
      %{
        update_organization_id: organization.id,
        is_active: true,
        is_approved: nil
      }
      |> Onboard.status()

    assert updated_organization.is_active == true

    # should update is_approveds
    updated_organization =
      %{
        update_organization_id: organization.id,
        is_active: true,
        is_approved: true
      }
      |> Onboard.status()

    assert updated_organization.is_approved == true
  end

  test "ensure that sending in valid parameters, delete inactive organization" do
    result = Onboard.setup(@valid_attrs)
    {:ok, organization} = Repo.fetch_by(Organization, %{name: result.organization.name})
    Onboard.delete(%{delete_organization_id: organization.id, is_confirmed: true})

    assert {:error, ["Elixir.Glific.Partners.Organization", "Resource not found"]} ==
             Repo.fetch_by(Organization, %{name: result.organization.name})
  end
end
