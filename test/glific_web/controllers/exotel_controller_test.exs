defmodule GlificWeb.ExotelControllerTest do
  use GlificWeb.ConnCase

  import Mock

  alias Glific.{
    Contacts,
    Fixtures,
    Partners,
    Repo
  }

  alias GlificWeb.ExotelController.Error

  @ngo_exotel_phone "07834811114"
  @beneficiary_phone "09876543210"

  defp add_exotel_credential(organization_id, flow_id, phone \\ @ngo_exotel_phone) do
    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: organization_id,
        shortcode: "exotel",
        keys: %{direction: "incoming", flow_id: "#{flow_id}"},
        secrets: %{phone: phone},
        is_active: true
      })

    organization_id |> Partners.get_organization!() |> Partners.fill_cache()
    :ok
  end

  defp optin_params(overrides \\ %{}) do
    Map.merge(
      %{
        "CallFrom" => @beneficiary_phone,
        "CallTo" => @ngo_exotel_phone,
        "To" => @ngo_exotel_phone
      },
      overrides
    )
  end

  defp reported_error(conn, params) do
    test_process = self()

    with_mock Elixir.Appsignal,
              [:passthrough],
              send_error: fn error, _metadata, _span_function ->
                send(test_process, {:appsignal_error, error})
                :ok
              end do
      conn = get(conn, "/webhook/exotel/optin", params)
      assert json_response(conn, 200) == ""
    end

    assert_received {:appsignal_error, %Error{} = error}
    error
  end

  describe "GET /webhook/exotel/optin" do
    test "optins the contact and starts the configured flow", %{
      conn: conn,
      organization_id: organization_id
    } do
      flow = Fixtures.flow_fixture(%{organization_id: organization_id})
      :ok = add_exotel_credential(organization_id, flow.id)

      conn = get(conn, "/webhook/exotel/optin", optin_params())

      assert json_response(conn, 200) == ""

      {:ok, contact} =
        Repo.fetch_by(Contacts.Contact, %{
          phone: "91" <> String.slice(@beneficiary_phone, -10, 10),
          organization_id: organization_id
        })

      assert contact.optin_status == true
      assert contact.optin_method == "Exotel"
    end

    test "reports an error naming the org and the missing params", %{
      conn: conn,
      organization_id: organization_id
    } do
      error = reported_error(conn, %{"phone" => @beneficiary_phone})

      assert error.message == "Exotel optin request missing expected params"
      assert error.organization_id == organization_id
      assert error.reason =~ "missing: CallFrom, CallTo, To"
      assert error.reason =~ "received: phone"
    end

    test "reports an error when the request has no params at all", %{conn: conn} do
      error = reported_error(conn, %{})

      assert error.message == "Exotel optin request missing expected params"
      assert error.reason =~ "received: none"
    end

    test "reports an error when the exotel credentials are missing", %{
      conn: conn,
      organization_id: organization_id
    } do
      error = reported_error(conn, optin_params())

      assert error.message == "Exotel credentials missing"
      assert error.organization_id == organization_id
    end

    test "reports an error when no flow is configured for the exotel phone", %{
      conn: conn,
      organization_id: organization_id
    } do
      flow = Fixtures.flow_fixture(%{organization_id: organization_id})
      :ok = add_exotel_credential(organization_id, flow.id, "01234567890")

      error = reported_error(conn, optin_params())

      assert error.message == "Exotel credentials mismatch"
      assert error.organization_id == organization_id
    end
  end
end
