defmodule Glific.Providers.TemplateBehaviour do
  @moduledoc """
  The message behaviour which all the providers needs to implement for communication
  """

  @callback submit_for_approval(attrs :: map()) ::
              {:ok, Glific.Templates.SessionTemplate.t()} | {:error, any()}

  @callback delete(org_id :: non_neg_integer(), attrs :: map()) ::
              {:ok, any()} | {:error, any()}

  @callback update_hsm_templates(org_id :: non_neg_integer()) ::
              :ok | {:error, String.t()}

  @callback import_templates(org_id :: non_neg_integer(), data :: String.t()) ::
              :ok | {:ok, any}
end
