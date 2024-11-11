defmodule Glific.Notion do
  @moduledoc """
  Notion API integration Utilities
  """
  alias Glific.Registrations.Registration

  @doc """
  Utilities to interact with Notion
  """

  @ngo_database_id "880cf3440d4c4e3f80453103e712f897"

  @notion_base_url "https://api.notion.com/v1"
  require Logger
  use Tesla

  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])

  @spec headers :: list()
  defp headers,
    do: [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer " <> Application.get_env(:glific, :notion_secret)},
      {"Notion-Version", "2022-02-22"}
    ]

  @doc """
  Creates a new entry in notion ngo onboarded database
  """
  @spec create_database_entry(map()) :: {:ok, String.t()} | {:error, String.t()}
  def create_database_entry(properties) do
    case create_page(properties) do
      {:ok, %{id: page_id}} ->
        {:ok, page_id}

      {:error, message} ->
        Logger.error("Error on creating notion database entry due to #{message}")
        {:error, message}
    end
  end

  @doc """
  Updates a database entry with given page_id and properties
  """
  @spec update_database_entry(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def update_database_entry(page_id, properties) do
    case update_page(page_id, properties) do
      {:ok, _} ->
        {:ok, "success"}

      {:error, message} ->
        Logger.error("Error on updating notion database entry due to #{message}")
        {:error, message}
    end
  end

  @doc """
  Create registration notion table properties for table row creation
  """
  @spec init_table_properties(Registration.t()) :: map()
  def init_table_properties(registration) do
    %{
      "Name" => %{
        "type" => "title",
        "title" => [
          %{"type" => "text", "text" => %{"content" => "#{registration.org_details.name}"}}
        ]
      },
      "T&C Agreed" => %{
        "type" => "checkbox",
        "checkbox" => false
      },
      "Created At" => %{
        "type" => "date",
        "date" => %{
          "start" => convert(registration),
          "end" => nil
        }
      }
    }
  end

  @doc """
  Create T&C dispute property to update it in Notion
  """
  @spec update_tc_dispute_property :: map()
  def update_tc_dispute_property do
    %{
      "Dispute in T&C" => %{
        "type" => "checkbox",
        "checkbox" => true
      }
    }
  end

  @doc """
  Created registration notion table properties for table row updation
  """
  @spec update_table_properties(Registration.t()) :: map()
  def update_table_properties(registration) do
    %{
      "Name" => %{
        "type" => "title",
        "title" => [
          %{"type" => "text", "text" => %{"content" => "#{registration.org_details["name"]}"}}
        ]
      },
      "T&C Agreed" => %{
        "type" => "checkbox",
        "checkbox" => registration.terms_agreed
      },
      "Current Address" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => format_address(registration.org_details["current_address"])}
          }
        ]
      },
      "Registered Address" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{
              "content" => format_address(registration.org_details["registered_address"])
            }
          }
        ]
      },
      "GSTIN" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.org_details["gstin"]}"}
          }
        ]
      },
      "BOT Number" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.platform_details["phone"]}"}
          }
        ]
      },
      "Gupshup App Name" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.platform_details["app_name"]}"}
          }
        ]
      },
      "Shortcode" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.platform_details["shortcode"]}"}
          }
        ]
      },
      "Billing Frequency" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.billing_frequency}"}
          }
        ]
      },
      "Finance POC Name" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.finance_poc["name"]}"}
          }
        ]
      },
      "Finance POC Phone" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.finance_poc["phone"]}"}
          }
        ]
      },
      "Finance POC Designation" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.finance_poc["designation"]}"}
          }
        ]
      },
      "Finance POC Email" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.finance_poc["email"]}"}
          }
        ]
      },
      "Submitter Name" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.submitter["name"]}"}
          }
        ]
      },
      "Submitter Email" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.submitter["email"]}"}
          }
        ]
      },
      "Signing Authority Name" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.signing_authority["name"]}"}
          }
        ]
      },
      "Signing Authority Designation" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.signing_authority["designation"]}"}
          }
        ]
      },
      "Signing Authority Email" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.signing_authority["email"]}"}
          }
        ]
      },
      "Has Submitted Form" => %{
        "type" => "checkbox",
        "checkbox" => registration.has_submitted
      },
      "IP Address" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "#{registration.ip_address}"}
          }
        ]
      },
      "Support Staff Account" => %{
        "type" => "checkbox",
        "checkbox" => registration.support_staff_account
      }
    }
  end

  @spec format_address(nil | map()) :: String.t()
  defp format_address(address) when is_map(address) do
    address
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{value}" end)
  end

  defp format_address(nil), do: ""

  # simple function to handle FunctionClauseError when date conversion fail to return empty string
  @spec convert(Registration.t()) :: String.t()
  defp convert(registration) do
    Date.to_iso8601(registration.inserted_at)
  catch
    FunctionClauseError -> ""
  end

  @spec create_page(map()) :: {:ok, map()} | {:error, String.t()}
  defp create_page(properties) do
    body = %{
      parent: %{
        database_id: @ngo_database_id
      },
      properties: properties
    }

    post(@notion_base_url <> "/pages", Jason.encode!(body), headers: headers())
    |> parse_response()
  end

  @spec update_page(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  defp update_page(page_id, properties) do
    body = %{
      properties: properties
    }

    patch(@notion_base_url <> "/pages/#{page_id}", body, headers: headers())
    |> parse_response()
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %{body: resp_body, status: status}})
       when status >= 200 and status < 300 do
    {:ok, resp_body}
  end

  defp parse_response({:ok, %{body: resp_body}}) do
    {:error, inspect(resp_body)}
  end

  defp parse_response({:error, message}), do: {:error, inspect(message)}
end
