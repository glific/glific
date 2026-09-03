defmodule Glific.Contacts.BulkImportTest do
  @moduledoc """
  Covers the batched import path end to end, through the same entry point the UI uses.
  These mirror the manual scenarios in import_test/harness.exs.
  """
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Ecto.Query
  import Mock

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactHistory,
    Contacts.ContactsField,
    Contacts.Import,
    Flows.ContactField,
    Groups,
    Groups.ContactGroup,
    Groups.Group,
    Jobs.UserJob,
    Partners,
    Profiles,
    Repo,
    Seeds.SeedsDev,
    Settings.Language,
    Users
  }

  setup do
    Tesla.Mock.mock_global(fn
      %{method: :get} -> %Tesla.Env{status: 200}
      %{method: :post} -> %Tesla.Env{status: 200}
    end)

    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_groups()
    SeedsDev.seed_users()
    :ok
  end

  defp admin do
    {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})
    Map.merge(user, %{roles: [:admin], upload_contacts: true})
  end

  defp org_id do
    [organization | _] = Partners.list_organizations()
    organization.id
  end

  defp run(data, type \\ :import_contact, collection \\ "harness") do
    attrs = %{user: admin(), type: type}
    attrs = if is_nil(collection), do: attrs, else: Map.put(attrs, :collection, collection)

    Import.import_contacts(org_id(), attrs, data: data)
    Oban.drain_queue(queue: :contact_import_bulk, with_scheduled: true)
  end

  defp fetch(phone) do
    {:ok, contact} = Repo.fetch_by(Contact, %{phone: phone})
    contact
  end

  # Contacts.count_contacts filters phone with a LIKE, so exact identity needs an exact match
  defp exists?(phone), do: match?({:ok, _}, Repo.fetch_by(Contact, %{phone: phone}))

  defp count_exact(phone) do
    Contact |> where([c], c.phone == ^phone) |> Repo.aggregate(:count, :id)
  end

  defp field(contact, key), do: get_in(contact.fields, [key, "value"])

  defp in_group?(phone, label) do
    contact = fetch(phone)

    ContactGroup
    |> join(:inner, [cg], g in Group, on: g.id == cg.group_id)
    |> where([cg, g], cg.contact_id == ^contact.id and g.label == ^label)
    |> Repo.aggregate(:count, :id) > 0
  end

  describe "import_contact" do
    test "writes every field of a wide row in one pass" do
      headers = Enum.map_join(1..15, ",", &"field_#{&1}")
      values = Enum.map_join(1..15, ",", &"value_#{&1}")

      assert %{success: 1, failure: 0} =
               run("name,phone,language,#{headers}\nWide,+919876500001,english,#{values}\n")

      contact = fetch("919876500001")

      assert field(contact, "field_1") == "value_1"
      assert field(contact, "field_15") == "value_15"

      # cleanup_contact_data/3 only drops phone/group/language/delete/opt_in, so "name"
      # lands as a contact field too. Pinning that here: it predates the batched path.
      assert map_size(contact.fields) == 16
      assert field(contact, "name") == "Wide"
    end

    test "writes one history row per contact, not one per field" do
      headers = Enum.map_join(1..15, ",", &"field_#{&1}")
      values = Enum.map_join(1..15, ",", &"value_#{&1}")

      run("name,phone,language,#{headers}\nHist,+919876500002,english,#{values}\n")

      contact = fetch("919876500002")

      rows =
        ContactHistory
        |> where([h], h.contact_id == ^contact.id and h.event_type == "contact_fields_updated")
        |> Repo.aggregate(:count, :id)

      assert rows == 1
    end

    test "opts in a new contact and sets bsp_status" do
      run("name,phone,language,city\nOptin,+919876500003,english,Pune\n")
      contact = fetch("919876500003")

      assert contact.optin_time != nil
      assert contact.optin_status == true
      assert contact.optin_method == "Import"
      assert contact.bsp_status == :hsm
    end

    test "adds the contact to its collection" do
      run(
        "name,phone,language,city\nColl,+919876500004,english,Pune\n",
        :import_contact,
        "batch_a"
      )

      assert in_group?("919876500004", "batch_a")
    end
  end

  test "trims collection labels so a spaced csv does not create padded groups" do
    run(
      "name,phone,language,collection\nTrim,+919876580501,english,\"trim_one, trim_two\"\n",
      :import_contact,
      nil
    )

    labels =
      Group
      |> where([g], like(g.label, "trim_%"))
      |> select([g], g.label)
      |> Repo.all()
      |> Enum.sort()

    # collection_label_check/2 split on "," without trimming, so " trim_two" became a
    # group of its own
    assert labels == ["trim_one", "trim_two"]
    assert in_group?("919876580501", "trim_two")
  end

  describe "columns insert_all does not get for free" do
    test "sets contact_type so the contact is visible in chats and search" do
      run("name,phone,language,city\nType,+919876580101,english,Pune\n")

      contact = fetch("919876580101")

      assert contact.contact_type == "WABA"
      assert contact.contact_type in ["WABA", "WABA+WA"]
    end

    test "does not downgrade an existing contact_type on re-import" do
      run("name,phone,language,city\nType,+919876580102,english,Pune\n")

      {:ok, contact} = Repo.fetch_by(Contact, %{phone: "919876580102"})
      Contacts.update_contact(contact, %{contact_type: "WABA+WA"})

      run("name,phone,language,city\nType,+919876580102,english,Mumbai\n")

      assert fetch("919876580102").contact_type == "WABA+WA"
      assert field(fetch("919876580102"), "city") == "Mumbai"
    end

    test "sets last_communication_at so imports do not sort above real conversations" do
      run("name,phone,language,city\nComm,+919876580103,english,Pune\n")

      assert fetch("919876580103").last_communication_at != nil
    end

    test "does not bump last_communication_at on re-import" do
      run("name,phone,language,city\nComm,+919876580104,english,Pune\n")
      before = fetch("919876580104").last_communication_at

      run("name,phone,language,city\nComm,+919876580104,english,Mumbai\n")

      assert fetch("919876580104").last_communication_at == before
    end
  end

  describe "blocked contacts" do
    setup do
      run("name,phone,language,city\nBlocked,+919876580201,english,Pune\n")
      {:ok, contact} = Repo.fetch_by(Contact, %{phone: "919876580201"})

      {:ok, _} =
        Contacts.update_contact(contact, %{
          status: :blocked,
          optin_time: nil,
          optin_status: false
        })

      :ok
    end

    test "an import does not unblock or optin a blocked contact" do
      run("name,phone,language,city\nBlocked,+919876580201,english,Mumbai\n")

      contact = fetch("919876580201")

      assert contact.status == :blocked
      assert contact.optin_time == nil
      refute contact.optin_status
    end

    test "the contact's fields are still updated" do
      run("name,phone,language,city\nBlocked,+919876580201,english,Mumbai\n")

      assert field(fetch("919876580201"), "city") == "Mumbai"
    end
  end

  describe "active profiles" do
    test "writes the merged fields to the active profile" do
      run("name,phone,language,city,age\nProf,+919876580301,english,Pune,30\n")
      contact = fetch("919876580301")

      {:ok, profile} =
        Profiles.create_profile(%{
          name: "Profile One",
          type: "student",
          contact_id: contact.id,
          language_id: contact.language_id,
          organization_id: org_id()
        })

      {:ok, _} = Contacts.update_contact(contact, %{active_profile_id: profile.id})

      run("name,phone,language,school\nProf,+919876580301,english,SchoolA\n")

      updated = Repo.get!(Profiles.Profile, profile.id)

      # switch_profile/2 copies profile.fields over contact.fields, so anything missing
      # here is silently discarded on the next profile switch
      assert get_in(updated.fields, ["school", "value"]) == "SchoolA"
      assert get_in(updated.fields, ["city", "value"]) == "Pune"
    end
  end

  describe "error accounting" do
    test "accumulates errors across chunks instead of keeping only the first" do
      user_job =
        UserJob.create_user_job(%{
          status: "pending",
          type: "contact_import",
          total_tasks: 2,
          tasks_done: 0,
          organization_id: org_id(),
          errors: %{}
        })

      Import.update_user_job_progress(user_job.id, %{"111" => "chunk one failed"})
      Import.update_user_job_progress(user_job.id, %{"222" => "chunk two failed"})

      reloaded = Repo.get!(UserJob, user_job.id)

      assert reloaded.tasks_done == 2
      assert reloaded.errors["errors"]["111"] == "chunk one failed"
      assert reloaded.errors["errors"]["222"] == "chunk two failed"
      assert map_size(reloaded.errors) == 1, "an atom :errors key alongside \"errors\" loses one"
    end

    test "a clean chunk leaves the accumulated errors alone" do
      user_job =
        UserJob.create_user_job(%{
          status: "pending",
          type: "contact_import",
          total_tasks: 2,
          tasks_done: 0,
          organization_id: org_id(),
          errors: %{}
        })

      Import.update_user_job_progress(user_job.id, %{"111" => "chunk one failed"})
      Import.update_user_job_progress(user_job.id, %{})

      reloaded = Repo.get!(UserJob, user_job.id)

      assert reloaded.tasks_done == 2
      assert reloaded.errors["errors"]["111"] == "chunk one failed"
    end
  end

  describe "delete flag" do
    test "removes the contact and reports a missing one" do
      run("name,phone,language,city\nGone,+919876580401,english,Pune\n")
      assert exists?("919876580401")

      run("""
      name,phone,language,delete
      Gone,+919876580401,english,1
      Never,+919876580402,english,1
      """)

      refute exists?("919876580401")

      [user_job | _] = UserJob.list_user_jobs(%{}) |> Enum.sort_by(& &1.id, :desc)
      assert user_job.errors["errors"]["919876580402"] == "Contact does not exist"
    end
  end

  describe "atomicity" do
    test "a failure on the last write rolls back the contact and its history" do
      # link_collections/4 is the final write inside the transaction, after the contact
      # upsert and the history insert have already run
      before = Repo.aggregate(ContactHistory, :count, :id)

      result =
        with_mock Groups, [:passthrough],
          get_or_create_group_by_label: fn _label, _org -> raise "collection write failed" end do
          Import.import_contacts(
            org_id(),
            %{user: admin(), collection: "rollback", type: :import_contact},
            data: "name,phone,language,city\nRollback,+919876570001,english,Pune\n"
          )

          Oban.drain_queue(queue: :contact_import_bulk, with_scheduled: true)
        end

      assert %{success: 0, failure: 1} = result

      refute exists?("919876570001")
      assert Repo.aggregate(ContactHistory, :count, :id) == before
    end

    test "a failed write leaves a delete row in the same chunk unapplied" do
      run("name,phone,language,city\nDoomed,+919876570002,english,Pune\n")
      assert exists?("919876570002")

      result =
        with_mock Groups, [:passthrough],
          get_or_create_group_by_label: fn _label, _org -> raise "collection write failed" end do
          Import.import_contacts(
            org_id(),
            %{user: admin(), collection: "rollback", type: :import_contact},
            data: """
            name,phone,language,city,delete
            Fresh,+919876570003,english,Pune,
            Doomed,+919876570002,english,,1
            """
          )

          Oban.drain_queue(queue: :contact_import_bulk, with_scheduled: true)
        end

      assert %{success: 0, failure: 1} = result

      # deletes run after the write transaction commits, so a chunk that rolls back has
      # not deleted anything and the retry sees the same rows it started with
      assert exists?("919876570002")
      refute exists?("919876570003")
    end
  end

  describe "import_contact field merging" do
    setup do
      run("name,phone,language,city,age,school\nMerge,+919876510001,english,Pune,30,SchoolA\n")
      :ok
    end

    test "keeps fields that the second csv does not mention" do
      run("name,phone,language,city,village\nMerge,+919876510001,english,Mumbai,Wagholi\n")
      contact = fetch("919876510001")

      assert field(contact, "school") == "SchoolA"
      assert field(contact, "age") == "30"
      assert field(contact, "city") == "Mumbai"
      assert field(contact, "village") == "Wagholi"
    end

    test "a blank cell does not erase the stored value" do
      run("name,phone,language,city,age,school\nMerge,+919876510001,english,,,\n")
      contact = fetch("919876510001")

      assert field(contact, "city") == "Pune"
      assert field(contact, "age") == "30"
      assert field(contact, "school") == "SchoolA"
    end

    test "re-importing does not create a second contact" do
      run("name,phone,language,city\nMerge,+919876510001,english,Nashik\n")
      assert count_exact("919876510001") == 1
    end
  end

  describe "move_contact" do
    setup do
      run("name,phone,language,city,school\nMove,+919876520001,english,Pune,SchoolA\n")
      :ok
    end

    test "updates an existing contact and keeps its earlier fields" do
      assert %{success: 1, failure: 0} =
               run(
                 "name,phone,language,collection,attendance\nMove,+919876520001,english,moved,80%\n",
                 :move_contact,
                 nil
               )

      contact = fetch("919876520001")

      assert field(contact, "attendance") == "80%"
      assert field(contact, "school") == "SchoolA"
      assert in_group?("919876520001", "moved")
    end

    test "overwrites the name when the csv carries a different one" do
      assert fetch("919876520001").name == "Move"

      run(
        "name,phone,language,collection,attendance\nRenamed,+919876520001,english,moved,80%\n",
        :move_contact,
        nil
      )

      assert fetch("919876520001").name == "Renamed"
    end

    test "rejects a row whose name is blank, so the name is never nulled" do
      run(
        "name,phone,language,collection,attendance\n,+919876520001,english,moved,80%\n",
        :move_contact,
        nil
      )

      contact = fetch("919876520001")
      assert contact.name == "Move"
      refute field(contact, "attendance")
    end

    test "folds a duplicate phone the same way import_contact does, later row winning" do
      run(
        "name,phone,language,collection,city\nMove,+919876520001,english,moved,FIRST\nMove,+919876520001,english,moved,SECOND\n",
        :move_contact,
        nil
      )

      assert count_exact("919876520001") == 1
      assert field(fetch("919876520001"), "city") == "SECOND"
    end

    test "does not change the optin time" do
      before = fetch("919876520001").optin_time

      run(
        "name,phone,language,collection,attendance\nMove,+919876520001,english,moved,80%\n",
        :move_contact,
        nil
      )

      assert fetch("919876520001").optin_time == before
    end

    test "does not create a contact that does not already exist" do
      run(
        "name,phone,language,collection,ghost\nGhost,+919876529999,english,moved,x\n",
        :move_contact,
        nil
      )

      refute exists?("919876529999")
    end

    test "records an error for a phone that does not exist" do
      run(
        "name,phone,language,collection,ghost\nGhost,+919876529999,english,moved,x\n",
        :move_contact,
        nil
      )

      [user_job | _] = UserJob.list_user_jobs(%{}) |> Enum.sort_by(& &1.id, :desc)

      assert user_job.errors["errors"]["919876529999"] =~ "was not found"
    end
  end

  describe "rejected rows" do
    test "a blank phone, an unparseable phone and a missing country code are all rejected" do
      run("""
      name,phone,language,city
      Blank,,english,Pune
      Bad,12345,english,Pune
      NoCountry,9876543210,english,Pune
      """)

      refute exists?("12345")
      refute exists?("9876543210")
    end

    test "a row with no name is rejected" do
      run("name,phone,language,city\n,+919876530001,english,Pune\n")
      refute exists?("919876530001")
    end

    test "one bad row does not stop the good rows in the same chunk" do
      run("""
      name,phone,language,city
      Good One,+919876530002,english,Pune
      Bad,12345,english,Pune
      Good Two,+919876530003,english,Mumbai
      """)

      assert exists?("919876530002")
      assert exists?("919876530003")
    end
  end

  describe "language resolution" do
    test "resolves a label, a locale, and falls back to english for an unknown one" do
      run("""
      name,phone,language,city
      ByLabel,+919876540001,Hindi,Pune
      ByLocale,+919876540002,ta,Pune
      Unknown,+919876540003,klingon,Pune
      Missing,+919876540004,,Pune
      """)

      {:ok, hindi} = Repo.fetch_by(Language, %{label: "Hindi"}, skip_organization_id: true)
      {:ok, tamil} = Repo.fetch_by(Language, %{label: "Tamil"}, skip_organization_id: true)

      {:ok, english} =
        Repo.fetch_by(Language, %{label_locale: "English"}, skip_organization_id: true)

      assert fetch("919876540001").language_id == hindi.id
      assert fetch("919876540002").language_id == tamil.id
      assert fetch("919876540003").language_id == english.id
      assert fetch("919876540004").language_id == english.id
    end

    test "an unresolvable language resets an existing contact to the default" do
      {:ok, hindi} = Repo.fetch_by(Language, %{label: "Hindi"}, skip_organization_id: true)

      {:ok, english} =
        Repo.fetch_by(Language, %{label_locale: "English"}, skip_organization_id: true)

      run("name,phone,language,city\nLang,+919876540006,Hindi,Pune\n")
      assert fetch("919876540006").language_id == hindi.id

      # add_language/2 sent an unknown language to the default rather than keeping the
      # contact's current one. Only a blank cell preserves it.
      run("name,phone,language,city\nLang,+919876540006,klingon,Pune\n")
      assert fetch("919876540006").language_id == english.id
    end

    test "keeps the contact's existing language when the csv leaves it blank" do
      run("name,phone,language,city\nLang,+919876540005,Hindi,Pune\n")
      {:ok, hindi} = Repo.fetch_by(Language, %{label: "Hindi"}, skip_organization_id: true)
      assert fetch("919876540005").language_id == hindi.id

      run("name,phone,language,city\nLang,+919876540005,,Mumbai\n")
      assert fetch("919876540005").language_id == hindi.id
    end
  end

  describe "contacts_fields registry" do
    test "does not overwrite an existing human label with the snake_case header" do
      {:ok, existing} =
        ContactField.create_contact_field(%{
          name: "Date Of Birth",
          shortcode: "date_of_birth",
          organization_id: org_id(),
          scope: :contact
        })

      run("name,phone,language,date_of_birth\nLabel,+919876550001,english,2010-01-01\n")

      assert Repo.get!(ContactsField, existing.id).name == "Date Of Birth"
      assert field(fetch("919876550001"), "date_of_birth") == "2010-01-01"
    end

    test "registers each csv header once, however many contacts carry it" do
      run("""
      name,phone,language,brand_new_field
      One,+919876550002,english,a
      Two,+919876550003,english,b
      Three,+919876550004,english,c
      """)

      count =
        ContactsField
        |> where([f], f.shortcode == "brand_new_field")
        |> Repo.aggregate(:count, :id)

      assert count == 1
    end
  end

  describe "special characters and size" do
    test "keeps commas, quotes and a very long value intact" do
      long = String.duplicate("L", 3000)

      run(
        ~s(name,phone,language,city,notes\nSpecial,+919876560001,english,"Pune, MH","has ""quotes"" and, commas"\n)
      )

      contact = fetch("919876560001")
      assert field(contact, "city") == "Pune, MH"
      assert field(contact, "notes") == ~s(has "quotes" and, commas)

      run("name,phone,language,notes\nSpecial,+919876560001,english,#{long}\n")
      assert String.length(field(fetch("919876560001"), "notes")) == 3000
    end

    test "normalises a phone wrapped in invisible unicode without creating a duplicate" do
      run("name,phone,language,city\nUni,+919876560002,english,Pune\n")
      run("name,phone,language,city\nUni,‎+919876560002‏,english,Mumbai\n")

      assert count_exact("919876560002") == 1
      assert field(fetch("919876560002"), "city") == "Mumbai"
    end
  end
end
