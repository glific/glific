defmodule Glific.Clients.SunoSunao do
  @moduledoc """
  This module will focus on suno sunao usecase
  """

  alias Glific.{GoogleASR}

  def webhook("speech_to_text", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"]) |>
    GoogleASR.speech_to_text(fields["results"])
  end
end
