defmodule Badge.Skin.Dark do
  @moduledoc """
  White on black, with a thin rule under the title bar.
  """

  @behaviour Badge.Skin

  alias Badge.Icons
  alias Badge.Theme

  @status_y 3
  @status_margin 6
  @status_gap 6
  @status_w elem(Icons.size(:battery_100), 0)
  @battery_x Theme.width() - @status_margin - @status_w
  @wifi_x @battery_x - @status_gap - @status_w
  @char_w 8

  @impl true
  def name, do: "Dark"

  @impl true
  def bg, do: 0x000000
  @impl true
  def fg, do: 0xFFFFFF
  @impl true
  def muted, do: 0xA8A8A8
  @impl true
  def dim, do: 0x606060
  @impl true
  def accent, do: 0x00E5A0
  @impl true
  def ok, do: 0x4CD964
  @impl true
  def warn, do: 0xFFCC00
  @impl true
  def alert, do: 0xFF3B30
  @impl true
  def select, do: 0x5AC8FA
  @impl true
  def glyph, do: fg()

  @impl true
  def chrome(title, status) do
    [
      Icons.item(status.battery, @battery_x, @status_y, glyph(), bg()),
      Icons.item(status.wifi, @wifi_x, @status_y, glyph(), bg()),
      clock_item(status.clock),
      {:text, @status_margin, @status_y, :pixel_operator, accent(), bg(), title}
    ] ++
      rule(0, Theme.bar_h(), Theme.width()) ++
      [{:rect, 0, 0, Theme.width(), Theme.height(), bg()}]
  end

  @impl true
  def decor, do: []

  @impl true
  def rule(x, y, w), do: [{:rect, x, y, w, 1, dim()}]

  # default16px is 8px per character, so this is the one thing in the bar that can be centred.
  defp clock_item(clock) do
    x = div(Theme.width() - @char_w * byte_size(clock), 2)

    {:text, x, @status_y, :default16px, dim(), bg(), clock}
  end
end
