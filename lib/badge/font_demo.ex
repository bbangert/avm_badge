defmodule Badge.FontDemo do
  @moduledoc """
  Throwaway screen that pages through candidate pixel fonts on the panel so
  they can be compared side by side. Not meant to ship; remove once a font
  is chosen. Reuses `Badge.Screen`'s already-open AtomGL port rather than
  opening a second one. While this process is alive, `Badge.Keyboard`
  routes every decoded key event here instead of to `Badge.Screen`, so
  ordinary typing cannot repaint over the demo page.
  """

  use GenServer

  alias Badge.Hardware
  alias Badge.Screen

  @fg 0xFFFFFF
  @bg 0x000000
  @margin 8
  @label_y @margin

  @font_dogica File.read!("priv/fonts/dogica.uf")
  @font_pixel_operator File.read!("priv/fonts/pixel_operator.uf")
  @font_tengoku File.read!("priv/fonts/tengoku.uf")

  # Line pitch is per-font: a single pitch leaves the shorter fonts looking sparse.
  @fonts [
    {:dogica, "dogica", @font_dogica, 22},
    {:pixel_operator, "pixel_operator", @font_pixel_operator, 19},
    {:tengoku, "tengoku", @font_tengoku, 16}
  ]

  @page_count length(@fonts) + 1

  # Per-line items, not one \n-joined block, to avoid a large contiguous surface malloc under heap fragmentation.
  @sample_lines [
    "ABCDEFGHIJKLM",
    "NOPQRSTUVWXYZ",
    "abcdefghijklm",
    "nopqrstuvwxyz",
    "0123456789 .,",
    "!?:;'\"-()"
  ]
  @sample_first_y 32

  # One row per font, all rendering the same short sentence; tags stand in for the full names, mapping logged once at startup.
  @comparison_sentence "Quick fox 0123"
  @tags ["DOG", "POP", "TNG"]
  # Row pitch 34px covers the tallest row (mac_minecraft, 20px) with room to spare.
  @row_ys [28, 62, 96]
  @sample_x 32
  @tag_mapping "Font tags: DOG=dogica POP=pixel_operator TNG=tengoku"

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Feeds a decoded keyboard event to the demo; only space does anything."
  def key_event(event) do
    GenServer.cast(__MODULE__, {:key, event})
  end

  @impl true
  def init(:ok) do
    port = Screen.port()

    for {handle, _name, binary, _pitch} <- @fonts do
      :port.call(port, {:register_font, handle, binary})
    end

    :io.format(~c"~s~n", [@tag_mapping])

    state = %{port: port, fonts: @fonts, index: 0}
    render(state)

    {:ok, state}
  end

  @impl true
  def handle_cast({:key, {:char, ?\s}}, state) do
    next = %{state | index: rem(state.index + 1, @page_count)}
    render(next)

    {:noreply, next}
  end

  def handle_cast({:key, _event}, state) do
    {:noreply, state}
  end

  # Page 0 is the comparison page; pages 1..6 are the individual fonts.
  defp render(%{index: 0} = state) do
    :io.format(~c"Font: comparison~n")

    :port.call(state.port, {:update, comparison_display_list()})
  end

  defp render(%{port: port, fonts: fonts, index: index}) do
    {handle, name, _binary, pitch} = :lists.nth(index, fonts)

    :io.format(~c"Font: ~s~n", [name])

    :port.call(port, {:update, display_list(handle, name, pitch)})
  end

  defp display_list(handle, name, pitch) do
    background = {:rect, 0, 0, Hardware.display_width(), Hardware.display_height(), @bg}
    label = {:text, @margin, @label_y, :default16px, @fg, :transparent, "Font: " <> name}
    lines = sample_line_items(@sample_lines, @sample_first_y, pitch, handle, [])

    [label | lines] ++ [background]
  end

  defp sample_line_items([], _y, _pitch, _handle, acc), do: :lists.reverse(acc)

  defp sample_line_items([line | lines], y, pitch, handle, acc) do
    item = {:text, @margin, y, handle, @fg, :transparent, line}

    sample_line_items(lines, y + pitch, pitch, handle, [item | acc])
  end

  defp comparison_display_list do
    background = {:rect, 0, 0, Hardware.display_width(), Hardware.display_height(), @bg}
    title_item = {:text, @margin, @margin, :default16px, @fg, :transparent, "Font comparison"}
    rows = comparison_row_items(@tags, @fonts, @row_ys, [])

    [title_item | rows] ++ [background]
  end

  # Threaded by hand (tag, font, y) so a row's label always matches its sample line.
  defp comparison_row_items([], [], [], acc), do: :lists.reverse(acc)

  defp comparison_row_items([tag | tags], [{handle, _name, _bin, _pitch} | fonts], [y | ys], acc) do
    tag_item = {:text, @margin, y, :default16px, @fg, :transparent, tag}
    sample_item = {:text, @sample_x, y, handle, @fg, :transparent, @comparison_sentence}

    comparison_row_items(tags, fonts, ys, [sample_item, tag_item | acc])
  end
end
