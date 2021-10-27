defmodule Glific.Clients.NayiDisha do
  @moduledoc """
  Custom webhook implementation specific to NayiDisha usecase
  """

  @hsm %{
    day_1: %{
      shortcode: "Will need to add"
    },
    day_2: %{
      shortcode: "Will need to add"
    },
    day_3: %{
      shortcode: "Will need to add"
    },
    day_4: %{
      shortcode: "Will need to add"
    },
    day_5: %{
      shortcode: "Will need to add"
    },
    day_6: %{
      shortcode: "Will need to add"
    },
    day_7: %{
      shortcode: "Will need to add"
    },
    day_8: %{
      shortcode: "Will need to add"
    },
    day_9: %{
      shortcode: "Will need to add"
    },
    day_10: %{
      shortcode: "Will need to add"
    },
    day_11: %{
      shortcode: "Will need to add"
    },
    day_12: %{
      shortcode: "Will need to add"
    },
    day_13: %{
      shortcode: "Will need to add"
    },
    day_14: %{
      shortcode: "Will need to add"
    },
    day_15: %{
      shortcode: "Will need to add"
    },
    day_16: %{
      shortcode: "Will need to add"
    },
    day_17: %{
      shortcode: "Will need to add"
    },
    day_18: %{
      shortcode: "Will need to add"
    },
    day_19: %{
      shortcode: "Will need to add"
    },
    day_20: %{
      shortcode: "Will need to add"
    },
    day_21: %{
      shortcode: "Will need to add"
    },
    day_22: %{
      shortcode: "Will need to add"
    },
    day_23: %{
      shortcode: "Will need to add"
    },
    day_24: %{
      shortcode: "Will need to add"
    },
    day_25: %{
      shortcode: "Will need to add"
    },
    day_26: %{
      shortcode: "Will need to add"
    },
    day_26: %{
      shortcode: "Will need to add"
    },
    day_27: %{
      shortcode: "Will need to add"
    },
    day_28: %{
      shortcode: "Will need to add"
    },
    day_29: %{
      shortcode: "Will need to add"
    },
    day_30: %{
      shortcode: "Will need to add"
    }
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook(_, _fields),
    do: %{}
end
