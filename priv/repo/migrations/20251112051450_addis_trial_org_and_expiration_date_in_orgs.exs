defmodule Glific.Repo.Migrations.AddisTrialOrgAndExpirationDateInOrgs do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :is_trial_org, :boolean,
        default: false,
        comment: "whether this is a trial org"

      add :trial_expiration_date, :utc_datetime,
        default: nil,
        comment: "When the trial period for this org ends"
    end
  end
end
