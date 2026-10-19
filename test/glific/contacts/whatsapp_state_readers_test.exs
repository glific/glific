defmodule Glific.Contacts.WhatsAppStateReadersTest do
  use Glific.DataCase

  alias Glific.{
    Contacts,
    Fixtures,
    Groups,
    Reports,
    Searches,
    Searches.CollectionCount
  }

  @optin_time ~U[2025-03-04 05:06:07Z]
  @opted_in %{optin_time: @optin_time, optin_status: true, optin_method: "BSP", bsp_status: :hsm}
  @opted_out %{
    optin_time: nil,
    optin_status: false,
    optout_time: @optin_time,
    optout_method: "user",
    bsp_status: :none
  }
  @never_opted_in %{optin_time: nil, optin_status: false, optout_time: nil, bsp_status: :none}

  defp phone,
    do:
      "9198761" <>
        (System.unique_integer([:positive])
         |> Integer.to_string()
         |> String.pad_leading(5, "0")
         |> String.slice(-5, 5))

  defp with_identity(state), do: Fixtures.contact_fixture(Map.put(state, :phone, phone()))

  defp pre_identity(state),
    do: Fixtures.pre_identity_contact_fixture(Map.put(state, :phone, phone()))

  defp inbox_ids(tab) do
    %{
      filter: %{status: tab, organization_id: 1},
      contact_opts: %{limit: 500, offset: 0},
      message_opts: %{limit: 10, offset: 0}
    }
    |> Searches.search(false)
    |> Enum.map(& &1.contact.id)
  end

  describe "inbox tabs" do
    test "Optin and Optout list contacts by their WhatsApp identity, or their own columns before it exists" do
      in_identity = with_identity(@opted_in)
      in_columns = pre_identity(@opted_in)
      out_identity = with_identity(@opted_out)
      out_columns = pre_identity(@opted_out)
      never = with_identity(@never_opted_in)

      optin = inbox_ids("Optin")
      assert in_identity.id in optin
      assert in_columns.id in optin
      refute out_identity.id in optin
      refute never.id in optin

      optout = inbox_ids("Optout")
      assert out_identity.id in optout
      assert out_columns.id in optout
      refute in_identity.id in optout
      refute never.id in optout
    end

    test "a contact that opts out moves from the Optin tab to the Optout tab, whichever way it was stored" do
      stored_on_identity = with_identity(@opted_in)
      stored_on_contact = pre_identity(@opted_in)

      for contact <- [stored_on_identity, stored_on_contact],
          do: :ok = Contacts.contact_opted_out(contact.phone, 1, DateTime.utc_now())

      optin = inbox_ids("Optin")
      optout = inbox_ids("Optout")

      for contact <- [stored_on_identity, stored_on_contact] do
        refute contact.id in optin
        assert contact.id in optout
      end
    end

    test "searching by term still returns contacts" do
      contact = with_identity(%{})

      assert contact.id in (%{
                              filter: %{term: contact.name, organization_id: 1},
                              contact_opts: %{limit: 50, offset: 0},
                              message_opts: %{limit: 10, offset: 0},
                              search_opts: %{}
                            }
                            |> Searches.search(false)
                            |> Enum.map(& &1.contact.id))
    end
  end

  describe "collection counts" do
    test "count Optin and Optout contacts from either place" do
      before = CollectionCount.collection_stats([], false)[1]

      with_identity(@opted_in)
      pre_identity(@opted_in)
      with_identity(@opted_out)
      pre_identity(@opted_out)
      with_identity(@never_opted_in)

      after_adding = CollectionCount.collection_stats([], false)[1]

      assert after_adding["Optin"] == before["Optin"] + 2
      assert after_adding["Optout"] == before["Optout"] + 2
    end
  end

  describe "collections" do
    setup do
      {:ok, group} =
        Groups.create_group(%{label: "state readers", is_restricted: false, organization_id: 1})

      %{group: group}
    end

    defp add_to_group(contact, group),
      do:
        Groups.create_contact_group(%{
          contact_id: contact.id,
          group_id: group.id,
          organization_id: 1
        })

    test "contact_ids/1 leaves out contacts that opted out and blocked ones", %{group: group} do
      active = with_identity(@opted_in)
      active_columns = pre_identity(@opted_in)
      out = with_identity(@opted_out)
      out_columns = pre_identity(@opted_out)
      blocked = with_identity(%{status: :blocked})

      for contact <- [active, active_columns, out, out_columns, blocked],
          do: add_to_group(contact, group)

      assert Enum.sort([active.id, active_columns.id]) ==
               group.id |> Groups.contact_ids() |> Enum.sort()
    end

    test "info_group_contacts/1 counts the valid contacts by BSP status", %{group: group} do
      for state <- [%{bsp_status: :session}, %{bsp_status: :session}, %{bsp_status: :hsm}],
          do: add_to_group(with_identity(state), group)

      add_to_group(pre_identity(%{bsp_status: :session}), group)
      add_to_group(pre_identity(%{bsp_status: :none}), group)

      assert %{total: 5, session: 3, hsm: 1, none: 1} = Groups.info_group_contacts(group.id)
    end
  end

  describe "reports" do
    @date_range %{
      start_day: ~U[2000-01-01 00:00:00Z],
      end_day: ~U[2099-01-01 00:00:00Z]
    }

    test "KPIs count opt-ins, opt-outs and the rest from either place" do
      kpis = [:opted_in_contacts_count, :opted_out_contacts_count, :non_opted_contacts_count]
      before = Map.new(kpis, &{&1, Reports.get_kpi(&1, 1, @date_range)})

      with_identity(@opted_in)
      pre_identity(@opted_in)
      with_identity(@opted_out)
      pre_identity(@opted_out)
      with_identity(@never_opted_in)
      pre_identity(@never_opted_in)

      assert Reports.get_kpi(:opted_in_contacts_count, 1, @date_range) ==
               before.opted_in_contacts_count + 2

      assert Reports.get_kpi(:opted_out_contacts_count, 1, @date_range) ==
               before.opted_out_contacts_count + 2

      assert Reports.get_kpi(:non_opted_contacts_count, 1, @date_range) ==
               before.non_opted_contacts_count + 2
    end

    test "contact data and exports group contacts by BSP status" do
      with_identity(%{bsp_status: :session})
      pre_identity(%{bsp_status: :session})

      session = fn rows -> rows |> Enum.find(&(hd(&1) == :session)) |> Enum.at(1) end

      before = session.(Reports.get_contact_data(1, @date_range))
      with_identity(%{bsp_status: :session})
      pre_identity(%{bsp_status: :session})

      assert session.(Reports.get_contact_data(1, @date_range)) == before + 2

      export = Reports.get_export_data(:contact_type, 1, @date_range)
      assert Enum.any?(export, &(List.last(&1) == :session))
    end
  end
end
