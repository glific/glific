defmodule Glific.Repo.Migrations.AddOtpToButtonTypeEnum do
  use Ecto.Migration

  def change do
    execute("ALTER TYPE template_button_type_enum ADD VALUE IF NOT EXISTS 'otp'")
  end
end
