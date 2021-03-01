defmodule Glific.BigqueryTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Faker.Phone

  alias Glific.{
    Contacts,
    Fixtures,
    Groups.Group,
    Messages,
    Messages.Message,
    Messages.MessageMedia,
    Repo,
    Seeds.SeedsDev,
    Tags.Tag,
    Templates.SessionTemplate
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    SeedsDev.hsm_templates(organization)
    :ok
  end
  test "list_messages/1 with multiple messages filtered", attrs do

  end
end
