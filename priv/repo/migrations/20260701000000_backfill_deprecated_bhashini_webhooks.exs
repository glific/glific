defmodule Glific.Repo.Migrations.BackfillDeprecatedBhashiniWebhooks do
  use Ecto.Migration

  alias Glific.Flows.BhashiniWebhookBackfill

  # Rewrites existing flow_revisions still referencing the removed Bhashini
  # FUNCTION webhooks (speech_to_text_with_bhasini / text_to_speech_with_bhasini /
  # nmt_tts_with_bhasini) onto their async Kaapi replacements, so those
  # organizations' flows can publish again without hitting the "Critical"
  # deprecated-webhook validation error added alongside the webhook removal.
  #
  # All the actual transform logic (and its safety/idempotency guarantees) lives
  # in `Glific.Flows.BhashiniWebhookBackfill` — see its moduledoc for exactly
  # what is and is not rewritten.

  def up do
    BhashiniWebhookBackfill.run()
  end

  def down do
    # No-op. This is a forward-only content fix (deprecated webhook name ->
    # replacement); the deprecated webhooks no longer exist to roll back to,
    # and organizations may have kept editing their flows since.
    :ok
  end
end
