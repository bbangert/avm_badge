defmodule Badge.Nvs do
  @moduledoc """
  Reads provisioned settings out of the `:badge` NVS namespace.

  Values are written either by `tools/provision.py` or by the wifi settings
  page once a connection succeeds.
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

  @doc "Stores a value for a provisioned key."
  @spec put(atom, binary) :: :ok | {:error, term}
  def put(key, value) do
    :esp.nvs_set_binary(@namespace, key, value)
  end

  @doc "Removes a provisioned key."
  @spec delete(atom) :: :ok | {:error, term}
  def delete(key) do
    :esp.nvs_erase_key(@namespace, key)
  end
end
