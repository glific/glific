defmodule GlificWeb.ExotelControllerTest do
  @moduledoc false

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

  # Runs `request` with every AppSignal sink the controller writes to captured as a
  # message: the error incident (`send_error/3`), the namespace and tags its span
  # function applies, and the optin outcome counter (`increment_counter/3`).
  defp with_appsignal(request) do
    test_process = self()

    with_mocks([
      {Elixir.Appsignal, [:passthrough],
       [
         send_error: fn error, _metadata, span_function ->
           span_function.(:span)
           send(test_process, {:appsignal_error, error})
           :ok
         end,
         increment_counter: fn metric, count, tags ->
           send(test_process, {:appsignal_counter, metric, count, tags})
           :ok
         end
       ]},
      {Elixir.Appsignal.Span, [:passthrough],
       [
         set_namespace: fn span, namespace ->
           send(test_process, {:appsignal_namespace, namespace})
           span
         end,
         set_sample_data: fn span, key, data ->
           send(test_process, {:appsignal_sample_data, key, data})
           span
         end
       ]}
    ]) do
      request.()
    end
  end

  # Issues the optin callback, asserts the response is still 200 with an empty body,
  # and asserts the failure reached AppSignal as an incident under the `exotel`
  # namespace, tagged with the org, plus a `failure` outcome counter. Returns the
  # reported `%Error{}` so each test can assert on its message and reason.
  defp reported_error(conn, params) do
    with_appsignal(fn ->
      conn = get(conn, "/webhook/exotel/optin", params)
      assert json_response(conn, 200) == ""
    end)

    assert_received {:appsignal_error, %Error{} = error}
    assert_received {:appsignal_namespace, "exotel"}

    assert_received {:appsignal_sample_data, "tags", tags}
    assert tags == %{organization_id: error.organization_id, reason: error.reason}

    organization_id_tag = to_string(error.organization_id)

    assert_received {:appsignal_counter, "provider_action_count", 1,
                     %{
                       provider: "exotel",
                       action: "optin",
                       status: "failure",
                       organization_id: ^organization_id_tag
                     }}

    error
  end

  describe "GET /webhook/exotel/optin" do
    test "optins the contact and starts the configured flow", %{
      conn: conn,
      organization_id: organization_id
    } do
      flow = Fixtures.flow_fixture(%{organization_id: organization_id})
      :ok = add_exotel_credential(organization_id, flow.id)

      with_appsignal(fn ->
        conn = get(conn, "/webhook/exotel/optin", optin_params())
        assert json_response(conn, 200) == ""
      end)

      {:ok, contact} =
        Repo.fetch_by(Contacts.Contact, %{
          phone: "91" <> String.slice(@beneficiary_phone, -10, 10),
          organization_id: organization_id
        })

      assert contact.optin_status == true
      assert contact.optin_method == "Exotel"

      organization_id_tag = to_string(organization_id)

      assert_received {:appsignal_counter, "provider_action_count", 1,
                       %{
                         provider: "exotel",
                         action: "optin",
                         status: "success",
                         organization_id: ^organization_id_tag
                       }}

      refute_received {:appsignal_counter, "provider_action_count", 1, %{status: "failure"}}
      refute_received {:appsignal_error, _error}
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

    test "treats a blank expected param as missing", %{
      conn: conn,
      organization_id: organization_id
    } do
      flow = Fixtures.flow_fixture(%{organization_id: organization_id})
      :ok = add_exotel_credential(organization_id, flow.id)

      error = reported_error(conn, optin_params(%{"CallFrom" => "  "}))

      assert error.message == "Exotel optin request missing expected params"
      assert error.reason =~ "missing: CallFrom"
      refute error.reason =~ "missing: CallFrom, CallTo"

      assert {:error, _} =
               Repo.fetch_by(Contacts.Contact, %{
                 phone: "91" <> String.slice(@beneficiary_phone, -10, 10),
                 organization_id: organization_id
               })
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
