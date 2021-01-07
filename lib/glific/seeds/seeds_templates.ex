if Code.ensure_loaded?(Faker) do
  defmodule Glific.Seeds.SeedsTemplates do
    @moduledoc """
    Script for populating the database. We can call this from tests and/or /priv/repo
    """
    alias Glific.{
      Partners.Organization,
      Repo,
      Settings,
      Templates.SessionTemplate,
    }

    @doc false
    @spec seed_organizations(non_neg_integer | nil) :: Organization.t() | nil
    def seed_organizations(_organization_id \\ nil) do
      Organization |> Ecto.Query.first() |> Repo.one(skip_organization_id: true)
    end

    @spec get_organization(Organization.t() | nil) :: Organization.t()
    defp get_organization(organization \\ nil) do
      if is_nil(organization),
        do: seed_organizations(),
        else: organization
    end

    @doc false
    @spec seed_session_templates(Organization.t() | nil) :: nil
    def seed_session_templates(organization \\ nil) do
      organization = get_organization(organization)
      [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})
      [hi | _] = Settings.list_languages(%{filter: %{label: "hindi"}})

      translations = %{
        hi.id => %{
          body:
            " अब आप नीचे दिए विकल्पों में से एक का चयन करके {{1}} के साथ समाप्त होने वाले खाते के लिए अपना खाता शेष या मिनी स्टेटमेंट देख सकते हैं। | [अकाउंट बैलेंस देखें] | [देखें मिनी स्टेटमेंट]",
          language_id: hi.id,
          number_parameters: 1
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "General Account Balance",
        type: :text,
        shortcode: "general_account_balance",
        is_hsm: true,
        number_parameters: 1,
        language_id: en_us.id,
        translations: translations,
        status: "REJECTED",
        category: "ACCOUNT_UPDATE",
        organization_id: organization.id,
        # spaces are important here, since gupshup pattern matches on it
        body:
          "You can now view your Account Balance or Mini statement for Account ending with {{1}} simply by selecting one of the options below. | [View Account Balance] | [View Mini Statement]",
        uuid: Ecto.UUID.generate()
      })

      translations = %{
        hi.id => %{
          body:
            "नीचे दिए गए लिंक से अपना {{1}} टिकट डाउनलोड करें। | [वेबसाइट पर जाएं, https: //www.gupshup.io/developer/ {{2}}",
          language_id: hi.id,
          number_parameters: 2
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "General Movie Ticket",
        type: :text,
        shortcode: "general_movie_ticket",
        is_hsm: true,
        number_parameters: 2,
        language_id: en_us.id,
        organization_id: organization.id,
        translations: translations,
        status: "APPROVED",
        category: "TICKET_UPDATE",
        body:
          "Download your {{1}} ticket from the link given below. | [Visit Website,https://www.gupshup.io/developer/{{2}}]",
        uuid: Ecto.UUID.generate()
      })

      translations = %{
        hi.id => %{
          body: " हाय {{1}}, \n कृपया बिल संलग्न करें।",
          language_id: hi.id,
          number_parameters: 1
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Bill",
        type: :text,
        shortcode: "bill",
        is_hsm: true,
        number_parameters: 1,
        language_id: en_us.id,
        organization_id: organization.id,
        translations: translations,
        status: "PENDING",
        category: "ALERT_UPDATE",
        body: "Hi {{1}},\nPlease find the attached bill.",
        uuid: Ecto.UUID.generate()
      })
      translations = %{
        hi.id => %{
          body: "{{1}} के लिए आपका OTP {{2}} है। यह {{3}} के लिए मान्य है।",
          language_id: hi.id,
          number_parameters: 3
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Common OTP Message",
        type: :text,
        shortcode: "common_otp_msg",
        is_hsm: true,
        number_parameters: 3,
        language_id: en_us.id,
        organization_id: organization.id,
        translations: translations,
        status: "APPROVED",
        category: "ALERT_UPDATE",
        body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
        uuid: Ecto.UUID.generate()
      })
    end
        @doc """
    Function to populate some basic data that we need for the system to operate. We will
    split this function up into multiple different ones for test, dev and production
    """
    @spec seed :: nil
    def seed do
      organization = get_organization()

      Repo.put_organization_id(organization.id)

      seed_session_templates(organization)
    end
  end
end
