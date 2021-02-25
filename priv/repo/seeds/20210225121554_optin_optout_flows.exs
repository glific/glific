defmodule Glific.Repo.Seeds.OptinOptoutFlows do
  use Glific.Seed

  envs([:dev])

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactsField,
    Flows.Flow,
    Flows.FlowLabel,
    Jobs.BigqueryJob,
    Partners,
    Partners.Organization,
    Partners.Provider,
    Repo,
    Searches.SavedSearch,
    Seeds.SeedsDev,
    Seeds.SeedsSim,
    Settings.Language,
    Tags.Tag,
    Users
  }

  def up(_repo) do
    Partners.list_organizations()
    |> Enum.each(fn organization ->
      Glific.Repo.put_organization_id(organization.id)
      add_optin_flow(organization)
    end)
  end

  defp add_optin_flow(organization) do
    uuid_map = %{
      optin: Ecto.UUID.generate()
    }

    flow_labels_id_map =
      FlowLabel.get_all_flowlabel(organization.id)
      |> Enum.reduce(%{}, fn flow_label, acc ->
        acc |> Map.merge(%{flow_label.name => flow_label.uuid})
      end)

    data = [
      {"Optin", ["optin"], uuid_map.optin, true, "optin.json"}
    ]

    Enum.map(data, &flow(&1, organization, uuid_map, flow_labels_id_map))
  end

  defp flow({name, keywords, uuid, ignore_keywords, file}, organization, uuid_map, id_map) do
    f =
      Repo.insert!(%Flow{
        name: name,
        keywords: keywords,
        ignore_keywords: ignore_keywords,
        version_number: "13.1.0",
        uuid: uuid,
        organization_id: organization.id
      })

    SeedsDev.flow_revision(f, organization, file, uuid_map, id_map)
  end
end
