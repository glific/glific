defmodule Glific.Scripts.BigQueryColumnModesTest do
  use Glific.DataCase
  import Mock

  alias Glific.{BigQuery.Schema, Partners, Scripts.BigQueryColumnModes}

  @columns %{"contacts" => ["phone"], "messages" => ["sender_phone", "receiver_phone"]}

  setup_with_mocks([
    {Goth.Token, [:passthrough],
     [
       fetch: fn _source ->
         {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
       end
     ]}
  ]) do
    :ok
  end

  setup %{organization_id: organization_id} do
    service_account = Jason.encode!(%{"project_id" => "qa-project", "private_key" => "key"})
    Tesla.Mock.mock(fn _ -> %Tesla.Env{status: 200, body: "{}"} end)

    {:ok, _} =
      Partners.create_credential(%{
        secrets: %{"service_account" => service_account},
        is_active: true,
        shortcode: "bigquery",
        organization_id: organization_id
      })

    :ok
  end

  defp mock_tables(fields_by_table) do
    Tesla.Mock.mock(fn %{method: :get, url: url} ->
      table = url |> String.split("/") |> List.last()

      case Map.fetch(fields_by_table, table) do
        {:ok, fields} ->
          %Tesla.Env{status: 200, body: Jason.encode!(%{"schema" => %{"fields" => fields}})}

        :error ->
          %Tesla.Env{status: 404, body: Jason.encode!(%{"error" => %{"code" => 404}})}
      end
    end)
  end

  test "an organization whose columns all have the expected mode has nothing to report",
       %{organization_id: organization_id} do
    mock_tables(%{
      "contacts" => [%{"name" => "phone", "type" => "STRING", "mode" => "NULLABLE"}],
      "messages" => [
        %{"name" => "sender_phone", "type" => "STRING", "mode" => "NULLABLE"},
        %{"name" => "receiver_phone", "type" => "STRING"}
      ]
    })

    assert %{organization_id: ^organization_id, mismatches: [], errors: []} =
             BigQueryColumnModes.check(organization_id, @columns, "NULLABLE")
  end

  test "reports each column still in another mode, and a missing column",
       %{organization_id: organization_id} do
    mock_tables(%{
      "contacts" => [%{"name" => "phone", "type" => "STRING", "mode" => "REQUIRED"}],
      "messages" => [%{"name" => "sender_phone", "type" => "STRING", "mode" => "NULLABLE"}]
    })

    assert %{mismatches: mismatches, errors: []} =
             BigQueryColumnModes.check(organization_id, @columns, "NULLABLE")

    assert [
             %{table: "contacts", column: "phone", mode: "REQUIRED"},
             %{table: "messages", column: "receiver_phone", mode: nil}
           ] == Enum.sort_by(mismatches, & &1.table)
  end

  test "reports a table that can't be read", %{organization_id: organization_id} do
    mock_tables(%{
      "contacts" => [%{"name" => "phone", "type" => "STRING", "mode" => "NULLABLE"}]
    })

    assert %{mismatches: [], errors: [%{table: "messages"}]} =
             BigQueryColumnModes.check(organization_id, @columns, "NULLABLE")
  end

  test "check_all/2 checks every organization with an active BigQuery credential",
       %{organization_id: organization_id} do
    mock_tables(%{
      "contacts" => [%{"name" => "phone", "type" => "STRING", "mode" => "NULLABLE"}],
      "messages" => [
        %{"name" => "sender_phone", "type" => "STRING", "mode" => "NULLABLE"},
        %{"name" => "receiver_phone", "type" => "STRING", "mode" => "NULLABLE"}
      ]
    })

    assert [%{organization_id: ^organization_id, mismatches: [], errors: []}] =
             BigQueryColumnModes.check_all(@columns, "NULLABLE")
  end

  test "the BigQuery schema allows a missing phone wherever a contact's phone is exported" do
    nullable = %{
      contact_schema: ["phone"],
      message_schema: ["sender_phone", "receiver_phone", "contact_phone"],
      flow_result_schema: ["contact_phone"],
      profile_schema: ["phone"],
      contact_history_schema: ["phone"],
      wa_message_schema: ["contact_phone"],
      issued_certificates_schema: ["phone"],
      whatsapp_form_response_schema: ["contact_phone"]
    }

    for {schema_fn, names} <- nullable, name <- names do
      field = schema_fn |> then(&apply(Schema, &1, [])) |> Enum.find(&(&1.name == name))
      assert %{mode: "NULLABLE"} = field, "#{schema_fn}.#{name} must be NULLABLE"
    end
  end
end
