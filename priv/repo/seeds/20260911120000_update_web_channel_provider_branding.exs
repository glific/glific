defmodule Glific.Repo.Seeds.UpdateWebChannelProviderBranding do
  @moduledoc """
  Replaces the web channel provider's named-theme key with the two brand colours the Settings
  page now asks for, and adds the business profile contacts open from the chat menu.
  """

  use Glific.Seeds.Seed

  alias Glific.{
    Partners.Provider,
    Repo,
    WebChannel.Branding
  }

  envs([:dev, :test, :prod])

  tags([:web_channel])

  @doc """
  Rewrites the web channel provider's keys.
  """
  @spec up(Ecto.Repo.t(), Keyword.t()) :: any()
  def up(_repo, _opts) do
    case Repo.fetch_by(Provider, %{shortcode: "web_channel"}) do
      {:ok, provider} ->
        provider
        |> Ecto.Changeset.change(%{keys: keys()})
        |> Repo.update!()

      _not_seeded ->
        :ok
    end
  end

  # `position` drives field order on the Settings page; jsonb hands the keys back sorted by
  # length, which bears no relation to the order an admin reads them in.
  @spec keys() :: map()
  defp keys do
    %{
      logo_url: %{
        type: :upload,
        label: "Display picture",
        default: nil,
        view_only: false,
        position: 1,
        max_size_kb: 2048,
        upload_folder: "org_logo",
        accept: "image/png,image/jpeg",
        helper_text:
          "PNG or JPG, square (1:1) and shown as a circle. 512x512 recommended, 128x128 minimum, 2MB maximum."
      },
      display_name: %{
        type: :string,
        label: "Display name",
        default: nil,
        view_only: false,
        position: 2,
        helper_text:
          "The organisation name contacts see in the chat header and on the sign-in page."
      },
      primary_color: %{
        type: :color,
        label: "Primary",
        default: Branding.default_primary(),
        view_only: false,
        position: 3
      },
      secondary_color: %{
        type: :color,
        label: "Secondary",
        default: Branding.default_secondary(),
        view_only: false,
        position: 4
      },
      about_description: %{
        type: :text,
        label: "Description",
        default: nil,
        view_only: false,
        position: 5
      },
      about_address: %{
        type: :string,
        label: "Address",
        default: nil,
        view_only: false,
        position: 6
      },
      about_website: %{
        type: :string,
        label: "Website",
        default: nil,
        view_only: false,
        position: 7
      },
      about_email: %{
        type: :string,
        label: "Contact email",
        default: nil,
        view_only: false,
        position: 8
      },
      about_hours: %{
        type: :string,
        label: "Hours",
        default: nil,
        view_only: false,
        position: 9
      }
    }
  end
end
