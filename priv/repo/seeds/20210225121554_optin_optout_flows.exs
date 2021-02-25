defmodule Glific.Repo.Seeds.OptinOptoutFlows do
  use Glific.Seeds.Seed

  envs([:dev])

  alias Glific.{
    Flows.Flow,
    Flows.FlowLabel,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  def up(_repo) do
    Partners.list_organizations()
    |> Enum.each(fn organization ->
      Repo.put_organization_id(organization.id)

      with {:error, _} <-
             Repo.fetch_by(Flow, %{name: "Optin Workflow", organization_id: organization.id}) do
        add_optin_flow(organization)
      end

      with {:error, _} <-
             Repo.fetch_by(Flow, %{name: "Optout Workflow", organization_id: organization.id}) do
        add_optout_flow(organization)
      end
    end)
  end

  defp add_optin_flow(organization) do
    uuid_map = %{
      optin: Ecto.UUID.generate()
    }

    data = [
      {"Optin Workflow", ["optin"], uuid_map.optin, true, "optin.json"}
    ]

    add_flow(organization, data, uuid_map)
  end

  defp add_optout_flow(organization) do
    uuid_map = %{
      optout: Ecto.UUID.generate()
    }

    data = [
      {"Optout Workflow", ["optout"], uuid_map.optout, true, "optout.json"}
    ]

    add_flow(organization, data, uuid_map)
  end

  defp add_flow(organization, data, uuid_map) do
    flow_labels_id_map =
      FlowLabel.get_all_flowlabel(organization.id)
      |> Enum.reduce(%{}, fn flow_label, acc ->
        acc |> Map.merge(%{flow_label.name => flow_label.uuid})
      end)

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
