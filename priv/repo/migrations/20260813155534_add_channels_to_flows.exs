defmodule Glific.Repo.Migrations.AddChannelsToFlows do
  use Ecto.Migration

  def up do
    alter table(:flows) do
      add :channels, {:array, :string},
        default: ["whatsapp", "web"],
        null: false,
        comment:
          "Derived set of channels this flow reaches (contract §11.1): [\"web\"] once any node " <>
            "sends a blocks interactive template (monotonic — never cleared), [\"whatsapp\"] " <>
            "when any node is send_broadcast or a templated (HSM) send_msg, or the omnichannel " <>
            "default [\"whatsapp\", \"web\"]. Recomputed at Glific.Flows.maybe_update_flow_type_and_channels/2."
    end

    execute("""
    UPDATE flows SET channels = ARRAY['web'] WHERE flow_type = 'web_message'
    """)
  end

  def down do
    alter table(:flows) do
      remove :channels
    end
  end
end
