defmodule Glific.BigqueryTest do
  use Glific.DataCase, async: true
  import Mock

  describe "organization's credentials" do
    alias Glific.{
      Partners,
      Seeds.SeedsDev
    }

    alias GoogleApi.BigQuery.V2.{
      Api.Datasets,
      Connection
    }

    setup do
      default_provider = SeedsDev.seed_providers()
      SeedsDev.seed_organizations(default_provider)

      :ok
    end

    @tag :pending
    test "update_credential/2 for bigquery should create bigquery dataset if active",
         %{organization_id: organization_id} = _attrs do
      with_mocks([
        {
          Goth.Token,
          [:passthrough],
          [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
        },
        {
          Connection,
          [:passthrough],
          [new: fn _token -> %Tesla.Env{__client__: %Tesla.Client{}} end]
        },
        {
          Datasets,
          [:passthrough],
          [bigquery_datasets_insert: fn _conn, _project_id, _dataset_id -> {:ok, "random"} end]
        }
      ]) do
        valid_attrs = %{
          shortcode: "bigquery",
          secrets: %{},
          organization_id: organization_id
        }

        {:ok, credential} = Partners.create_credential(valid_attrs)

        valid_update_attrs = %{
          secrets: %{
            "service_account" => "{\"private_key\":\"test\"}",
            "project_id" => "test"
          },
          is_active: true,
          organization_id: organization_id
        }

        {:ok, _credential} = Partners.update_credential(credential, valid_update_attrs)
      end
    end

    @tag :pending
    test "get_goth_token/2 should return goth token",
         %{organization_id: organization_id} = _attrs do
      with_mocks([
        {
          Goth.Token,
          [:passthrough],
          [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
        }
      ]) do
        valid_attrs = %{
          shortcode: "bigquery",
          secrets: %{
            "service_account" => "{\"private_key\":\"test\"}"
          },
          is_active: true,
          organization_id: organization_id
        }

        {:ok, _credential} = Partners.create_credential(valid_attrs)

        token = Partners.get_goth_token(organization_id, "bigquery")

        assert token != nil
      end
    end
  end
end
