defmodule Glific.Repo.Migrations.IndexContactIdentitiesIdentifierPrefix do
  @moduledoc """
  Serves the "username starts with" search: `identifier LIKE 'term%'` within an organization and
  channel, which the plain unique index cannot use for a prefix match under a non-C collation.
  """
  use Ecto.Migration

  def change do
    create index(
             :contact_identities,
             ["organization_id", "channel", "identifier varchar_pattern_ops"],
             name: :contact_identities_org_channel_identifier_prefix_index
           )
  end
end
