defmodule Glific.OnboardTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Partners.Onboard
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
                        })}
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

end
