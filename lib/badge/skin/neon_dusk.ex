defmodule Badge.Skin.NeonDusk do
  @moduledoc """
  Synthwave dusk after the Omarchy Neon Dusk theme: violet-ink surfaces,
  lavender text, a magenta-violet-cyan horizon under the title bar and a
  striped gold sun beside the title. Magenta is kept for the cursor.
  """

  @behaviour Badge.Skin

  alias Badge.Icons
  alias Badge.Theme

  @bar 0x07050D
  @surface 0x000000
  @title 0xF0EAFF
  @caption 0xB3A9D2
  @divider 0x3A3154
  @gold 0xEEC06A

  @horizon [0xE85FAF, 0x8A63E8, 0x5CC8F5]
  @segments 10
  @segment_w div(Theme.width(), @segments)

  # Colours are 0xRRGGBB; mix/3 blends a toward b by num/den per channel.
  mix = fn a, b, num, den ->
    channel = fn shift ->
      ca = rem(div(a, shift), 0x100)
      cb = rem(div(b, shift), 0x100)
      ca + div((cb - ca) * num, den)
    end

    channel.(0x10000) * 0x10000 + channel.(0x100) * 0x100 + channel.(1)
  end

  [magenta, violet, cyan] = @horizon
  half = div(@segments - 1, 2)

  @gradient (for i <- 0..(@segments - 1) do
               case i <= half do
                 true -> mix.(magenta, violet, i, half)
                 false -> mix.(violet, cyan, i - half, @segments - 1 - half)
               end
             end)

  @glow for colour <- @gradient, do: mix.(@surface, colour, 3, 10)

  # A striped sun: {dx, dy, w, h} bands, widest at the horizon.
  @sun_x 6
  @sun_y 5
  @sun [
    {4, 0, 4, 1},
    {2, 1, 8, 1},
    {1, 2, 10, 1},
    {0, 3, 12, 2},
    {0, 6, 12, 2},
    {0, 9, 12, 1},
    {0, 11, 12, 1}
  ]

  @status_y 3
  @status_margin 6
  @status_gap 6
  @status_w elem(Icons.size(:battery_100), 0)
  @battery_x Theme.width() - @status_margin - @status_w
  @wifi_x @battery_x - @status_gap - @status_w
  @title_x @sun_x + 12 + 6
  @char_w 8

  @horizon_items (for {colour, glow, i} <-
                        :lists.zip3(@gradient, @glow, Enum.to_list(0..(@segments - 1))) do
                    x = i * @segment_w
                    y = Theme.bar_h()

                    [{:rect, x, y, @segment_w, 2, colour}, {:rect, x, y + 2, @segment_w, 1, glow}]
                  end)
                 |> List.flatten()

  @sun_items for {dx, dy, w, h} <- @sun, do: {:rect, @sun_x + dx, @sun_y + dy, w, h, @gold}

  @impl true
  def name, do: "Neon Dusk"

  @impl true
  def bg, do: @surface
  @impl true
  def fg, do: 0xCFC7E8
  @impl true
  def muted, do: @caption
  @impl true
  def dim, do: 0x7C719C
  @impl true
  def accent, do: 0x5CC8F5
  @impl true
  def ok, do: 0x4BE09A
  @impl true
  def warn, do: @gold
  @impl true
  def alert, do: 0xF2596C
  @impl true
  def select, do: 0xE85FAF
  @impl true
  def glyph, do: 0xFFFFFF

  @impl true
  def chrome(title, status) do
    [
      Icons.item(status.battery, @battery_x, @status_y, glyph(), @bar),
      Icons.item(status.wifi, @wifi_x, @status_y, glyph(), @bar),
      clock_item(status.clock),
      {:text, @title_x, @status_y, :pixel_operator, @title, @bar, title}
    ] ++
      @sun_items ++
      @horizon_items ++
      [
        {:rect, 0, 0, Theme.width(), Theme.bar_h(), @bar},
        {:rect, 0, 0, Theme.width(), Theme.height(), @surface}
      ]
  end

  # A neon rainbow round the panel, a scan beam, and the odd glitch.
  @impl true
  def decor do
    [
      {:border, 3, 90, [0xFF2BD6, 0x8A63E8, 0x2BD9FF, 0x2BFF88, 0xFFE14D, 0xFF6A3D]},
      {:beam, 0x5CC8F5, 7000, 2, 64},
      {:glitch, [0xE85FAF, 0x5CC8F5], 3000, 9000}
    ]
  end

  @impl true
  def rule(x, y, w), do: [{:rect, x, y, w, 1, @divider}]

  defp clock_item(clock) do
    x = div(Theme.width() - @char_w * byte_size(clock), 2)

    {:text, x, @status_y, :default16px, @caption, @bar, clock}
  end
end
