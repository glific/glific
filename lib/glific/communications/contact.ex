defmodule Glific.Communication.Contact do
  defmacro __using__(_opts \\ []) do
    quote do
    end
  end

  def status(args) do
    provider_module()
    |> apply(:status, [args])
  end

  def provider_module() do
    provider = Glific.Communications.effective_provider()
    String.to_existing_atom(to_string(provider) <> ".Contact")
  end
end
