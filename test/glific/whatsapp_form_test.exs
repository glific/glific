defmodule Glific.WhatsappFormTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Mails.MailLog,
    Seeds.SeedsDev,
    Seeds.SeedsMigration
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_whatsapp_forms(organization)
  end
end
