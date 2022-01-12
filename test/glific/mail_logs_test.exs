defmodule Glific.MailLogTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Mails.MailLog
  }

  describe "mail_logs" do
    @valid_attrs %{
      category: "critical_notification",
      status: "sent",
      content: %{}
    }
    @valid_more_attrs %{
      category: "low_bsp_balance",
      status: "sent",
      content: %{}
    }
    @update_attrs %{
      category: "category_update",
      status: "sent",
      content: %{}
    }
    @invalid_attrs %{
      category: nil,
      status: nil,
      content: nil
    }
  end

  test "count_mail_logs/1 returns count of all notifications", attrs do
    mail_log_count = MailLog.count_mail_logs(%{filter: attrs})

    Map.merge(attrs, @valid_attrs)
    |> Fixtures.mail_log_fixture()

    assert MailLog.count_mail_logs(%{filter: attrs}) == mail_log_count + 1

    Map.merge(attrs, @valid_more_attrs)
    |> Fixtures.mail_log_fixture()

    assert MailLog.count_mail_logs(%{filter: attrs}) == mail_log_count + 2

    assert MailLog.count_mail_logs(%{
             filter: Map.merge(attrs, %{category: "critical_notification"})
           }) == 1
  end

  test "list_mail_logs/1 returns all notifications",
       %{organization_id: organization_id} = attrs do
    mail_log = Fixtures.mail_log_fixture(%{organization_id: organization_id})

    [mail_log_list] =
      Enum.filter(
        MailLog.list_mail_logs(%{filter: attrs}),
        fn t -> t.category == mail_log.category end
      )

    assert mail_log_list.category == mail_log.category
    assert mail_log_list.id == mail_log.id
    assert mail_log_list.status == mail_log.status
    assert mail_log_list.content == mail_log.content
  end

  test "create_mail_log/1 with valid data creates a extension", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})
    assert {:ok, %MailLog{} = mail_log} = MailLog.create_mail_log(attrs)
    assert mail_log.category == @valid_attrs[:category]
    assert mail_log.content == @valid_attrs[:content]
  end

  test "create_mail_log/1 with invalid data returns error changeset", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@invalid_attrs, %{organization_id: organization_id})
    assert {:error, %Ecto.Changeset{}} = MailLog.create_mail_log(attrs)
  end

  test "update_mail_log/2 with valid data updates the extension", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

    assert {:ok, %MailLog{} = mail_log} = MailLog.create_mail_log(attrs)

    attrs = Map.merge(@update_attrs, %{category: "updated_category_2"})

    assert {:ok, %MailLog{} = updated_mail_log} = MailLog.update_mail_log(mail_log, attrs)

    assert updated_mail_log.category == "updated_category_2"
  end

  test "mail_sent_in_past_time?/3 checks if we have sent in a mail in the given time", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})
    assert {:ok, %MailLog{} = mail_log} = MailLog.create_mail_log(attrs)
    old_time = Glific.go_back_time(24)
    assert true == MailLog.mail_sent_in_past_time?(mail_log.category, old_time, organization_id)

    assert {:ok, %MailLog{} = _updated_mail_log} =
             MailLog.update_mail_log(mail_log, %{inserted_at: Glific.go_back_time(25)})

    assert true == MailLog.mail_sent_in_past_time?(mail_log.category, old_time, organization_id)
  end
end
