defmodule Badge.Nvs do
  @moduledoc """
  Reads provisioned settings out of the `:badge` NVS namespace.

  Values are written by `tools/provision_wifi.py` and never by the firmware,
  so this module is read-only.
  """

  @compile {:no_warn_undefined, :esp}

  @namespace :badge

  @doc "Value for a provisioned key, or nil when it is absent."
  @spec get(atom) :: binary | nil
  def get(key) do
    # AtomVM answers :undefined rather than nil, so || defaults would not work.
    case :esp.nvs_get_binary(@namespace, key) do
      :undefined -> nil
      value -> value
    end
  end
end
