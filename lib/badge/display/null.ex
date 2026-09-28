defmodule Badge.Display.Null do
  @moduledoc """
  A display that draws nothing. Used by the LVGL spike, which owns the panel,
  so `Badge.UI` and its pages keep running without AtomGL.
  """

  @behaviour Badge.Display

  @impl true
  def update(_display, _items), do: :ok

  @impl true
  def register_font(_display, _name, _bytes), do: :ok

  @impl true
  def deregister_font(_display, _name), do: :ok
end
