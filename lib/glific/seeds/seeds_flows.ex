defmodule Glific.Seeds.SeedsFlows do
  @moduledoc false

  alias Glific.{
    Flows.Flow,
    Flows.FlowLabel,
    Flows.FlowRevision,
    Groups.Group,
    Partners.Organization,
    Repo,
    Seeds.SeedsDev,
    Templates.InteractiveTemplate
  }

  @doc false
  @spec seed([Organization.t()]) :: :ok
  def seed(organizations) do
    organizations
    |> Enum.each(fn org ->
      Glific.Repo.put_organization_id(org.id)
      {uuid_map, data} = get_data_and_uuid_map(org)
      {opt_uuid_map, opt_data} = get_opt_data(org)

      add_flow(
        org,
        data ++ opt_data,
        Map.merge(uuid_map, opt_uuid_map)
      )
    end)
  end

  @doc false
  @spec opt_in_out_flows([Organization.t()]) :: :ok
  def opt_in_out_flows(organizations) do
    organizations
    |> Enum.each(fn organization ->
      Glific.Repo.put_organization_id(organization.id)
      # we only check if the optin flow exist, if not, we add both optin and optout
      with {:error, _} <-
             Repo.fetch_by(Flow, %{name: "Optin Workflow", organization_id: organization.id}),
           do: add_opt_flow(organization)
    end)
  end

  @spec get_opt_data(Organization.t()) :: {map(), list()}
  defp get_opt_data(organization) do
    ## collections should be present in the db
    {:ok, optin_collection} =
      Repo.fetch_by(Group, %{label: "Optin contacts", organization_id: organization.id})

    {:ok, optout_collection} =
      Repo.fetch_by(Group, %{label: "Optout contacts", organization_id: organization.id})

    uuid_map = %{
      optin: generate_uuid(organization, "dd8d0a16-b8c3-4b61-bf8e-e5cad6fa8a2f"),
      optout: generate_uuid(organization, "9e607fd5-232e-43c8-8fac-d8a99d72561e"),
      optin_collection: Integer.to_string(optin_collection.id),
      optout_collection: Integer.to_string(optout_collection.id)
    }

    data = [
      {"Optin Workflow", ["optin"], uuid_map.optin, true, "optin.json"},
      {"Optout Workflow", ["optout", "stop"], uuid_map.optout, true, "optout.json"}
    ]

    {uuid_map, data}
  end

  @spec add_opt_flow(Organization.t()) :: :ok
  defp add_opt_flow(organization) do
    {uuid_map, data} = get_opt_data(organization)

    add_flow(organization, data, uuid_map)
  end

  @doc false
  @spec generate_uuid(Organization.t(), Ecto.UUID.t()) :: Ecto.UUID.t()
  def generate_uuid(organization, default) do
    # we have static uuids for the first organization since we might have our test cases
    # hardcoded with these uuids
    if organization.id == 1,
      do: default,
      else: Ecto.UUID.generate()
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
      |> replace_interactive_template_id(organization)
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

  @spec replace_interactive_template_id(String.t(), Organization.t()) :: String.t()
  defp replace_interactive_template_id(json, organization) do
    optin_template =
      Repo.fetch_by(InteractiveTemplate, %{label: "Optin template"})
      |> case do
        {:ok, optin_template} -> optin_template
        {:error, _error} -> SeedsDev.seed_optin_interactives(organization)
      end

    Enum.reduce(
      %{"optin_template_id" => optin_template.id},
      json,
      fn {_key, id}, acc ->
        String.replace(
          acc,
          "optin_template_id",
          "#{id}"
        )
      end
    )
  end

  @spec get_data_and_uuid_map(Organization.t()) :: tuple()
  defp get_data_and_uuid_map(organization) do
    uuid_map = %{
      help: generate_uuid(organization, "3fa22108-f464-41e5-81d9-d8a298854429"),
      language: generate_uuid(organization, "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf"),
      newcontact: generate_uuid(organization, "6fe8fda9-2df6-4694-9fd6-45b9e724f545"),
      registration: generate_uuid(organization, "f4f38e00-3a50-4892-99ce-a281fe24d040"),
      activity: generate_uuid(organization, "b050c652-65b5-4ccf-b62b-1e8b3f328676"),
      feedback: generate_uuid(organization, "6c21af89-d7de-49ac-9848-c9febbf737a5"),
      template: generate_uuid(organization, "cceb79e3-106c-4c29-98e5-a7f7a9a01dcd")
    }

    data = [
      {"Help Workflow", ["help", "मदद"], uuid_map.help, true, "help.json"},
      {"Feedback", ["feedback"], uuid_map.feedback, true, "feedback.json"},
      {"Activity", ["activity"], uuid_map.activity, true, "activity.json"},
      {"Language Workflow", ["language", "भाषा"], uuid_map.language, true, "language.json"},
      {"New Contact Workflow", ["newcontact"], uuid_map.newcontact, false, "new_contact.json"},
      {"Registration Workflow", ["registration"], uuid_map.registration, false,
       "registration.json"},
      {"Template Workflow", ["template"], uuid_map.template, false, "template.json"}
    ]

    {uuid_map, data}
  end
end
