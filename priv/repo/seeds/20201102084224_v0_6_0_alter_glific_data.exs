defmodule Glific.Repo.Seeds.AddGlificData_v0_6_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Flows.FlowContext,
    Flows.FlowCount,
    Flows.FlowRevision,
    Messages.Message,
    Messages.MessageMedia,
    Repo,
    Settings.Language
  }

  import Ecto.Query, warn: false

  def up(_repo) do
    add_languages()

    update_organization_id()
  end

  defp add_languages() do
    if {:error, ["Elixir.Glific.Settings.Language", "Resource not found"]} ==
         Repo.fetch_by(Language, %{label: "Urdu"}) do
      Repo.insert!(%Language{
        label: "Urdu",
        label_locale: "اُردُو",
        locale: "ur"
      })
    end
  end

  defp update_organization_id do
    from([fc] in FlowContext,
      join: f in assoc(fc, :flow),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Glific.Repo.update_all([])

    from([fc] in FlowCount,
      join: f in assoc(fc, :flow),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Glific.Repo.update_all([])

    from([fc] in FlowRevision,
      join: f in assoc(fc, :flow),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Glific.Repo.update_all([])

    messages =
      Message
      |> where([m], not is_nil(m.media_id))
      |> preload(:media)
      |> Repo.all()

    messages
    |> Enum.each(fn message ->
      from([mm] in MessageMedia,
        where: mm.id == ^message.media_id,
        update: [set: [organization_id: ^message.organization_id]]
      )
      |> Repo.update_all([])
    end)
  end
end
