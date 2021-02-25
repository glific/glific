defmodule Glific.Seeds.SeedsFlows do
  @moduledoc false

  alias Glific.{
    Flows.Flow,
    Flows.FlowLabel,
    Flows.FlowRevision,
    Partners.Organization,
    Repo
  }

  @doc false
  @spec opt_in_out_flows([Organization.t()]) :: :ok
  def opt_in_out_flows(organizations) do
    organizations
    |> Enum.each(fn organization ->
      Repo.put_process_state(organization.id)

      # we only check if the optin flow exist, if not, we add both optin and optout
      with {:error, _} <-
             Repo.fetch_by(Flow, %{name: "Optin Workflow", organization_id: organization.id}),
           do: add_opt_flow(organization)
    end)
  end

  @spec add_opt_flow(Organization.t()) :: :ok
  defp add_opt_flow(organization) do
    uuid_map = %{
      optin: Ecto.UUID.generate(),
      optout: Ecto.UUID.generate()
    }

    data = [
      {"Optin Workflow", ["optin"], uuid_map.optin, true, "optin.json"},
      {"Optout Workflow", ["optout", "stop"], uuid_map.optout, true, "optout.json"}
    ]

    add_flow(organization, data, uuid_map)
  end

  @doc false
  @spec add_flow(Organization.t(), list(), map()) :: :ok
  def add_flow(organization, data, uuid_map) do
    flow_labels_id_map =
      FlowLabel.get_all_flowlabel(organization.id)
      |> Enum.reduce(%{}, fn flow_label, acc ->
        acc |> Map.merge(%{flow_label.name => flow_label.uuid})
      end)

    Enum.each(data, &flow(&1, organization, uuid_map, flow_labels_id_map))
  end

  @spec flow(tuple(), Organization.t(), map(), map()) :: nil
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

    flow_revision(f, organization, file, uuid_map, id_map)
  end

  @doc false
  @spec flow_revision(Flow.t(), Organization.t(), String.t(), map(), map()) :: nil
  def flow_revision(f, organization, file, uuid_map, id_map) do
    definition =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/" <> file))
      |> replace_uuids(uuid_map)
      |> replace_label_uuids(id_map)
      |> Jason.decode!()
      |> Map.merge(%{
        "name" => f.name,
        "uuid" => f.uuid
      })

    Repo.insert!(%FlowRevision{
      definition: definition,
      flow_id: f.id,
      status: "published",
      version: 1,
      organization_id: organization.id
    })
  end

  @spec replace_uuids(String.t(), map()) :: String.t()
  defp replace_uuids(json, uuid_map),
    do:
      Enum.reduce(
        uuid_map,
        json,
        fn {key, uuid}, acc ->
          String.replace(
            acc,
            key |> Atom.to_string() |> String.upcase() |> Kernel.<>("_UUID"),
            uuid
          )
        end
      )

  @spec replace_label_uuids(String.t(), map()) :: String.t()
  defp replace_label_uuids(json, flow_labels_id_map),
    do:
      Enum.reduce(
        flow_labels_id_map,
        json,
        fn {key, id}, acc ->
          String.replace(
            acc,
            key |> Kernel.<>(":ID"),
            "#{id}"
          )
        end
      )
end
