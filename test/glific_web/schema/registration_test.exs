defmodule GlificWeb.Schema.Query.RegistrationTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  load_gql(:send_otp, GlificWeb.Schema, "assets/gql/registration/send_otp.gql")

  test "send_otp returns the response with otp" do
    {:ok, query_data} =
      query_gql_by(:send_otp,
        variables: %{"input" => %{"name" => "John", "phone" => "919820198765"}}
      )

    response = get_in(query_data, [:data, "sendOtp"]) != nil
  end
end
