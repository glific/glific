defmodule Glific.Repo.Seeds.AddGlificOrganizationData do
  import Ecto.Changeset, only: [change: 2]

  @now DateTime.utc_now() |> DateTime.truncate(:second)
  @password "secret1234"

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactsField,
    Flows.Flow,
    Flows.FlowRevision,
    Partners,
    Partners.Organization,
    Repo,
    Searches.SavedSearch,
    Settings,
    Tags.Tag,
    Templates.SessionTemplate,
    Users
  }

  def seed_data(organization, languages) do
    # calling it gtags, since tags is a macro in philcolumns
    gtags(organization, languages)

    admin = contacts(organization, languages)

    users(admin, organization)

    hsm_templates(organization, languages)

    saved_searches(organization)

    flows(organization)

    opted_in_contacts(organization)

    contacts_field(organization)
  end

  def gtags(organization, languages) do
    [en_us | _] = languages

    # seed tags
    message_tags_mt =
      Repo.insert!(%Tag{
        label: "Messages",
        shortcode: "messages",
        description: "A default message tag",
        is_reserved: true,
        language_id: en_us.id,
        organization_id: organization.id
      })

    message_tags_ct =
      Repo.insert!(%Tag{
        label: "Contacts",
        shortcode: "contacts",
        description: "A contact tag for users that are marked as contacts",
        is_reserved: true,
        language_id: en_us.id,
        organization_id: organization.id
      })

    tags = [
      # Intent of message
      %{
        label: "Good Bye",
        shortcode: "goodbye",
        description:
          "Marking message as good wishes when parting or at the end of a conversation",
        parent_id: message_tags_mt.id,
        keywords: ["bye", "byebye", "goodbye", "goodnight", "goodnite"]
      },
      %{
        label: "Greeting",
        shortcode: "greeting",
        parent_id: message_tags_mt.id,
        description: "Marking message as a sign of welcome",
        keywords: ["hello", "goodmorning", "hi", "hey"]
      },
      %{
        label: "Thank You",
        shortcode: "thankyou",
        description: "Marking message as a expression of thanks",
        parent_id: message_tags_mt.id,
        keywords: ["thanks", "thankyou", "awesome", "great"]
      },

      # Status of Message
      %{
        label: "Important",
        shortcode: "important",
        description: "Marking message as of great significance or value",
        parent_id: message_tags_mt.id
      },
      %{
        label: "New Contact",
        shortcode: "newcontact",
        description: "Marking message as came from a new contact",
        parent_id: message_tags_mt.id
      },
      %{
        label: "Not replied",
        shortcode: "notreplied",
        description: "Marking message as not replied",
        parent_id: message_tags_mt.id
      },
      %{
        label: "Spam",
        shortcode: "spam",
        description: "Marking message as irrelevant or unsolicited message",
        parent_id: message_tags_mt.id
      },
      %{
        label: "Unread",
        shortcode: "unread",
        description: "Marking message as not read",
        parent_id: message_tags_mt.id
      },

      # Status of outbound Message
      %{
        label: "Not Responded",
        shortcode: "notresponded",
        description: "Marking message as not responded",
        parent_id: message_tags_mt.id
      },

      # Languages
      %{
        label: "Language",
        shortcode: "language",
        description: "Marking message as a name of a language",
        parent_id: message_tags_mt.id,
        keywords: ["hindi", "english", "हिंदी", "अंग्रेज़ी"]
      },

      # Optout
      %{
        label: "Optout",
        shortcode: "optout",
        description: "Marking message as a sign of opting out",
        parent_id: message_tags_mt.id,
        keywords: ["stop", "unsubscribe", "halt", "सदस्यता समाप्त"]
      },

      # Help
      %{
        label: "Help",
        shortcode: "help",
        description: "Marking message as a sign of requiring assistance",
        parent_id: message_tags_mt.id,
        keywords: ["help", "मदद"]
      },

      # Tags with Value
      %{
        label: "Numeric",
        shortcode: "numeric",
        description: "Marking message as a numeric type",
        parent_id: message_tags_mt.id,
        is_value: true
      },

      # Intent of message
      %{
        label: "Yes",
        shortcode: "yes",
        description: "Marking message as an affirmative response",
        parent_id: message_tags_mt.id,
        keywords: ["yes", "yeah", "okay", "ok"]
      },
      %{
        label: "No",
        shortcode: "no",
        description: "Marking message as a negative response",
        parent_id: message_tags_mt.id,
        keywords: ["no", "nope", "nay"]
      },

      # Type of Contact
      %{
        label: "Child",
        shortcode: "child",
        description: "Marking message as a child of a parent",
        parent_id: message_tags_ct.id
      },
      %{
        label: "Parent",
        shortcode: "parent",
        description: "Marking message as a parent of a child",
        parent_id: message_tags_ct.id
      },
      %{
        label: "Participant",
        shortcode: "participant",
        description: "Marking message as a participant",
        parent_id: message_tags_ct.id
      },
      %{
        label: "Staff",
        shortcode: "staff",
        description: "Marking message sent from a member of staff",
        parent_id: message_tags_ct.id
      }
    ]

    tags =
      Enum.map(
        tags,
        fn tag ->
          tag
          |> Map.put(:organization_id, organization.id)
          |> Map.put(:language_id, en_us.id)
          |> Map.put(:is_reserved, true)
          |> Map.put(:inserted_at, @now)
          |> Map.put(:updated_at, @now)
        end
      )

    # seed multiple tags
    Repo.insert_all(Tag, tags)
  end

  def contacts(organization, languages) do
    [en_us | _] = languages

    admin =
      Repo.insert!(%Contact{
        phone: organization.provider_phone,
        name: "Glific Admin",
        organization_id: organization.id,
        language_id: en_us.id,
        last_message_at: @now
      })

    Repo.update!(change(organization, contact_id: admin.id))
  end

  def users(admin, organization) do
    Users.create_user(%{
      name: "Glific Admin",
      phone: organization.provider_phone,
      password: @password,
      confirm_password: @password,
      roles: ["admin"],
      contact_id: admin.id,
      organization_id: organization.id
    })
  end

  def hsm_templates(organization, languages) do
    [en_us | _] = languages

    Repo.insert!(%SessionTemplate{
      label: "Missed Message Apology",
      type: :text,
      shortcode: "missed_message",
      is_hsm: true,
      number_parameters: 0,
      language_id: en_us.id,
      organization_id: organization.id,
      body: """
      I'm sorry that I wasn't able to respond to your concerns yesterday but I’m happy to assist you now.
      If you’d like to continue this discussion, please reply with ‘yes’
      """,
      uuid: Ecto.UUID.generate()
    })

    Repo.insert!(%SessionTemplate{
      label: "OTP Message",
      type: :text,
      shortcode: "otp",
      is_hsm: true,
      number_parameters: 3,
      language_id: en_us.id,
      organization_id: organization.id,
      body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
      uuid: Ecto.UUID.generate()
    })

    Repo.insert!(%SessionTemplate{
      label: "User Registration",
      body: """
      Please click on the link to register with the phone number @contact.phone
      @global.registration.url
      """,
      type: :text,
      shortcode: "user-registration",
      is_reserved: true,
      language_id: en_us.id,
      organization_id: organization.id,
      uuid: Ecto.UUID.generate()
    })
  end

  def saved_searches(organization) do
    labels =
      Repo.label_id_map(
        Tag,
        ["Not replied", "Not Responded", "Optout", "Unread"],
        organization.id,
        :label
      )

    data = [
      {"All conversations", "All"},
      {"All unread conversations", "Unread"},
      {"Conversations read but not replied", "Not replied"},
      {"Conversations where the contact has opted out", "Optout"},
      {"Conversations read but not responded", "Not Responded"}
    ]

    Enum.each(data, &saved_search(&1, organization, labels))
  end

  defp saved_search({label, shortcode}, organization, _labels) when shortcode == "All",
    do:
      Repo.insert!(%SavedSearch{
        label: label,
        shortcode: shortcode,
        args: %{
          filter: %{term: ""},
          contactOpts: %{limit: 20, offset: 0},
          messageOpts: %{limit: 10, offset: 0}
        },
        is_reserved: true,
        organization_id: organization.id
      })

  defp saved_search({label, shortcode}, organization, labels),
    do:
      Repo.insert!(%SavedSearch{
        label: label,
        shortcode: shortcode,
        args: %{
          filter: %{includeTags: [to_string(labels[shortcode])], term: ""},
          contactOpts: %{limit: 20, offset: 0},
          messageOpts: %{limit: 10, offset: 0}
        },
        is_reserved: true,
        organization_id: organization.id
      })

  def flows(organization) do
    data = [
      {"Help Workflow", ["help", "मदद"], true, "help.json"},
      {"Language Workflow", ["language", "भाषा"], true, "language.json"},
      {"Preferences Workflow", ["preference"], false, "preference.json"},
      {"New Contact Workflow", ["newcontact"], false, "new_contact.json"},
      {"Registration Workflow", ["registration"], false, "registration.json"},
      {"Out of Office Workflow", ["outofoffice"], false, "out_of_office.json"},
      {"Activity", ["activity"], false, "sol_activity.json"},
      {"Feedback", ["feedback"], false, "sol_feedback.json"}
    ]

    Enum.map(data, &flow(&1, organization))
  end

  defp flow({name, keywords, ignore_keywords, file}, organization) do
    f =
      Repo.insert!(%Flow{
        name: name,
        keywords: keywords,
        ignore_keywords: ignore_keywords,
        version_number: "13.1.0",
        uuid: Ecto.UUID.generate(),
        organization_id: organization.id
      })

    definition =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/" <> file))
      |> Jason.decode!()
      |> Map.merge(%{
        "name" => f.name,
        "uuid" => f.uuid
      })

    Repo.insert(%FlowRevision{
      definition: definition,
      flow_id: f.id,
      status: "done"
    })
  end

  def opted_in_contacts(organization) do
    with {:ok, url} <- Application.fetch_env(:glific, :provider_optin_list_url),
         {:ok, api_key} <- Application.fetch_env(:glific, :provider_key),
         {:ok, response} <- HTTPoison.get(url, [{"apikey", api_key}]),
         {:ok, response_data} <- Poison.decode(response.body),
         false <- is_nil(response_data["users"]) do
      users = response_data["users"]

      Enum.each(users, fn user ->
        {:ok, last_message_at} = DateTime.from_unix(user["lastMessageTimeStamp"], :millisecond)
        {:ok, optin_time} = DateTime.from_unix(user["optinTimeStamp"], :millisecond)

        phone = user["countryCode"] <> user["phoneCode"]

        Contacts.upsert(%{
          phone: phone,
          last_message_at: last_message_at |> DateTime.truncate(:second),
          optin_time: optin_time |> DateTime.truncate(:second),
          provider_status: check_provider_status(last_message_at),
          organization_id: organization.id,
          language_id: organization.default_language_id
        })
      end)
    end
  end

  defp check_provider_status(last_message_at) do
    if Timex.diff(DateTime.utc_now(), last_message_at, :hours) < 24 do
      :session_and_hsm
    else
      :hsm
    end
  end

  def contacts_field(organization) do
    data = [
      {"Name", "name", :text, :contact},
      {"Age Group", "age_group", :text, :contact},
      {"Gender", "gender", :text, :contact},
      {"Date of Birth", "dob", :text, :contact},
      {"Settings", "settings", :text, :contact}
    ]

    Enum.map(data, &contacts_field(&1, organization))
  end

  defp contacts_field({name, shortcode, value_type, scope}, organization) do
    Repo.insert!(%ContactsField{
      name: name,
      shortcode: shortcode,
      value_type: value_type,
      scope: scope,
      organization_id: organization.id
    })
  end
end
