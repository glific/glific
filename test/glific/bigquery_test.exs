defmodule Glific.BigqueryTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo
  use ExUnit.Case

  alias Glific.{
    Jobs.BigQueryWorker,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    SeedsDev.seed_messages()
    :ok
  end

  test "queue_table_data/4 should create job for messages", attrs do
    BigQueryWorker.queue_table_data("messages", attrs.organization_id, 0, 10)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :bigquery)
  end

end
