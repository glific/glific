defmodule Glific.ThirdParty.Sheets.WorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.Notifications.Notification
  alias Glific.Repo
  alias Glific.Sheets.Sheet
  alias Glific.Sheets.SheetData
  alias Glific.Sheets.Worker

  test "sends notification on media validation failures", %{
    organization_id: organization_id,
    global_schema: global_schema
  } do
    Tesla.Mock.mock(fn
      %{method: :get, url: "http://invalid-domain-for-testing.xyz/bad.mp4"} ->
        %Tesla.Env{
          status: 200,
          headers: [{"content-type", "application/octet-stream"}]
        }

      %{method: :get, url: "http://example.com/video.mp4"} ->
        %Tesla.Env{
          status: 200,
          headers: [{"content-type", "video/mp4"}]
        }

      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            "Key,Value,MediaUrl\r\nkey1,val1,http://invalid-domain-for-testing.xyz/bad.mp4\r\nkey2,val2,http://example.com/video.mp4"
        }
    end)

    attrs = %{
      type: "READ",
      label: "media validation sheet",
      url:
        "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
      organization_id: organization_id
    }

    {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

    Repo.insert_all(SheetData, [
      %{
        sheet_id: sheet.id,
        organization_id: organization_id,
        key: "key1",
        row_data: %{
          "key" => "key1",
          "value" => "val1",
          "media_url" => "http://invalid-domain-for-testing.xyz/bad.mp4"
        },
        last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      },
      %{
        sheet_id: sheet.id,
        organization_id: organization_id,
        key: "key2",
        row_data: %{
          "key" => "key1",
          "value" => "val2",
          "media_url" => "http://example.com/video.mp4"
        },
        last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ])

    # We can verify the sheet data was created correctly
    sheet_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
    assert length(sheet_data) == 2

    Worker.make_media_validation_job(sheet)

    assert_enqueued(
      worker: Worker,
      prefix: global_schema,
      args: %{sheet_id: sheet.id, organization_id: organization_id},
      tags: ["media_validation"]
    )

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :default, with_scheduled: true)

    [notification | _] =
      Notification |> where([n], n.organization_id == ^organization_id) |> Repo.all()

    assert notification.category == "Google sheets"
    assert notification.message == "Google sheet media validation failed"
    assert notification.entity["id"] == sheet.id
    assert notification.entity["url"] == sheet.url
    assert notification.entity["name"] == sheet.label
    assert notification.entity["url"] == sheet.url

    assert notification.entity["media_validation_warnings"] == %{
             "key1" => %{
               "http://invalid-domain-for-testing.xyz/bad.mp4" =>
                 "Media content-type is not valid"
             }
           }
  end
end
