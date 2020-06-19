defmodule GlificWeb.API.V1.RegistrationControllerTest do
  use GlificWeb.ConnCase

  @password "secret1234"

  describe "create/2" do
    @valid_params %{
      "user" => %{
        "phone" => "+919820198765",
        "password" => @password,
        "password_confirmation" => @password
      }
    }
    @invalid_params %{
      "user" => %{
        "phone" => "+919820198765",
        "password" => @password,
        "password_confirmation" => ""
      }
    }

    test "with valid params", %{conn: conn} do
      phone = get_in(@valid_params, ["user", "phone"])
      {:ok, otp} = PasswordlessAuth.create_and_send_verification_code(phone)

      valid_params =
        @valid_params
        |> put_in(["user", "otp"], otp)

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, valid_params))

      assert json = json_response(conn, 200)
      assert json["data"]["access_token"]
      assert json["data"]["renewal_token"]
    end

    test "with invalid params", %{conn: conn} do
      phone = get_in(@invalid_params, ["user", "phone"])
      {:ok, otp} = PasswordlessAuth.create_and_send_verification_code(phone)

      invalid_params =
        @invalid_params
        |> put_in(["user", "otp"], otp)

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, invalid_params))

      assert json = json_response(conn, 500)
      assert json["error"]["message"] == "Couldn't create user"
      assert json["error"]["status"] == 500
      assert json["error"]["errors"]["password_confirmation"] == ["does not match confirmation"]
      # assert json["error"]["errors"]["phone"] == ["has invalid format"]
    end
  end
end
