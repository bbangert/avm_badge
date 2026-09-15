defmodule Badge.Skin.Win95 do
  @moduledoc """
  Silver client area, navy caption with a close button, etched rules.

  Colours come from the classic sixteen. Everything is flat rectangles and
  the fonts already in the image; the icons are left as they are.
  """

  @behaviour Badge.Skin

  alias Badge.Icons
  alias Badge.Theme

  @white 0xFFFFFF
  @black 0x000000
  @silver 0xC0C0C0
  @grey 0x808080
  @navy 0x000080

  # The caption sits inside a two pixel frame of client colour.
  @caption_x 2
  @caption_y 2
  @caption_h 18
  @caption_w Theme.width() - 2 * @caption_x

  @text_y 3
  @text_x 6
  @char_w 8

  # A raised button at the caption's right end, one pixel inside it.
  @button_w 16
  @button_h @caption_h
  @button_x Theme.width() - @caption_x - 1 - @button_w
  @button_y @caption_y

  @status_gap 6
  @status_w elem(Icons.size(:battery_100), 0)
  @battery_x @button_x - @status_gap - @status_w
  @wifi_x @battery_x - @status_gap - @status_w

  @impl true
  def name, do: "Win95"

  @impl true
  def bg, do: @silver
  @impl true
  def fg, do: @black
  @impl true
  def muted, do: 0x404040
  @impl true
  def dim, do: @grey
  @impl true
  def accent, do: 0x008080
  @impl true
  def ok, do: 0x008000
  @impl true
  def warn, do: 0x808000
  @impl true
  def alert, do: 0x800000
  @impl true
  def select, do: @navy

  @impl true
  def chrome(title, status) do
    [
      Icons.item(status.battery, @battery_x, @text_y),
      Icons.item(status.wifi, @wifi_x, @text_y),
      clock_item(status.clock),
      {:text, @text_x, @text_y, :pixel_operator, @white, @navy, title}
    ] ++
      close_button() ++
      [{:rect, @caption_x, @caption_y, @caption_w, @caption_h, @navy}] ++
      rule(0, Theme.bar_h(), Theme.width()) ++
      [{:rect, 0, 0, Theme.width(), Theme.height(), @silver}]
  end

  # A groove: shadow above, highlight below.
  @impl true
  def rule(x, y, w) do
    [{:rect, x, y, w, 1, @grey}, {:rect, x, y + 1, w, 1, @white}]
  end

  defp clock_item(clock) do
    x = div(Theme.width() - @char_w * byte_size(clock), 2)

    {:text, x, @text_y, :default16px, @white, @navy, clock}
  end

  # Highlight on the top and left edges, shadow on the bottom and right, face beneath.
  defp close_button do
    right = @button_x + @button_w - 1
    bottom = @button_y + @button_h - 1

    [
      {:text, @button_x + div(@button_w - @char_w, 2), @button_y + 1, :default16px, @black,
       @silver, "x"},
      {:rect, @button_x, @button_y, @button_w, 1, @white},
      {:rect, @button_x, @button_y, 1, @button_h, @white},
      {:rect, @button_x, bottom, @button_w, 1, @black},
      {:rect, right, @button_y, 1, @button_h, @black},
      {:rect, @button_x, @button_y, @button_w, @button_h, @silver}
    ]
  end
end
