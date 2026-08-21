defmodule Badge.Screen do
  @moduledoc """
  Owns the AtomGL display port and the text buffer behind it.

  Key casts only accumulate into the buffer and mark it dirty; they never
  render directly. A linked ticker wakes every `@render_interval` and asks
  this process to redraw, and a frame is only pushed when the buffer
  actually changed since the last render.

  AtomGL is declarative: every update replaces the whole scene, so a
  complete display list is pushed on each redraw. `{:update, _}` is
  pre-acked (`display_task.c:35`), so `:port.call/2` returns before any SPI
  happens, and the render queue drops the oldest entry on overflow
  (`display_task.c:76`).
  """

  use GenServer

  alias Badge.Hardware
  alias Badge.TextBuffer

  @fg 0xFFFFFF
  @bg 0x000000
  @margin 4
  @char_w 8
  @char_h 16

  # Ticker redraw interval; a frame is only pushed when content changed.
  @render_interval 100

  def start_link(spi) do
    GenServer.start_link(__MODULE__, spi, name: __MODULE__)
  end

  @doc """
  Applies a decoded key event to the buffer.

  Does not draw. The event only mutates the buffer and marks it dirty; the
  ticker turns that into a frame at the next `@render_interval`, and only if
  the content actually changed.
  """
  def key_event(event) do
    GenServer.cast(__MODULE__, {:key, event})
  end

  @impl true
  def init(spi) do
    port = :erlang.open_port({:spawn, "display"}, display_opts(spi))

    :io.format(~c"Screen: AtomGL port open, ~p cols x ~p rows~n", [cols(), rows()])

    state = %{port: port, buffer: TextBuffer.new(cols(), rows()), dirty: false}

    # Renders once immediately so the cursor is visible before the first tick.
    render(state)

    start_ticker()

    {:ok, state}
  end

  @impl true
  def handle_cast({:key, event}, state) do
    buffer = apply_event(state.buffer, event)

    # Some events, like backspace at the start of the buffer, are no-ops; only a real change marks it dirty.
    {:noreply, %{state | buffer: buffer, dirty: state.dirty or buffer != state.buffer}}
  end

  @impl true
  def handle_info(:render_tick, %{dirty: true} = state) do
    render(state)

    {:noreply, %{state | dirty: false}}
  end

  def handle_info(:render_tick, state) do
    {:noreply, state}
  end

  defp apply_event(buffer, {:char, char}), do: TextBuffer.insert(buffer, char)
  defp apply_event(buffer, {:edit, :backspace}), do: TextBuffer.backspace(buffer)
  defp apply_event(buffer, {:edit, :newline}), do: TextBuffer.newline(buffer)
  defp apply_event(buffer, {:edit, :tab}), do: TextBuffer.tab(buffer)

  # Waits in a linked process, so this GenServer never sleeps in a callback and a dead ticker crashes loudly.
  defp start_ticker do
    screen = self()
    spawn_link(fn -> tick_loop(screen) end)
  end

  defp tick_loop(screen) do
    Process.sleep(@render_interval)
    send(screen, :render_tick)
    tick_loop(screen)
  end

  defp render(%{port: port, buffer: buffer}) do
    :port.call(port, {:update, display_list(buffer)})
  end

  # Z-order runs tail to head: background last, cursor first.
  defp display_list(buffer) do
    background = {:rect, 0, 0, Hardware.display_width(), Hardware.display_height(), @bg}

    [cursor_item(buffer) | text_items(buffer)] ++ [background]
  end

  defp cursor_item(buffer) do
    {col, row} = TextBuffer.cursor(buffer)

    # Clamped so the cursor rect never runs past the right edge.
    x = min(@margin + col * @char_w, Hardware.display_width() - @char_w)

    {:rect, x, @margin + row * @char_h + @char_h - 2, @char_w, 2, @fg}
  end

  # Row index threaded by hand; empty lines are skipped rather than emitted.
  defp text_items(buffer), do: text_items(TextBuffer.lines(buffer), 0, [])

  defp text_items([], _row, acc), do: :lists.reverse(acc)

  defp text_items([<<>> | rest], row, acc), do: text_items(rest, row + 1, acc)

  defp text_items([line | rest], row, acc) do
    item = {:text, @margin, @margin + row * @char_h, :default16px, @fg, @bg, line}

    text_items(rest, row + 1, [item | acc])
  end

  defp cols, do: div(Hardware.display_width() - 2 * @margin, @char_w)
  defp rows, do: div(Hardware.display_height() - 2 * @margin, @char_h)

  # init_seq_type "alt_gamma_2" matches this panel; rotation 3 needs the patch noted in Badge.Hardware.
  defp display_opts(spi) do
    [
      compatible: "sitronix,st7789",
      init_seq_type: "alt_gamma_2",
      enable_tft_invon: true,
      width: Hardware.display_width(),
      height: Hardware.display_height(),
      rotation: Hardware.display_rotation(),
      reset: Hardware.display_reset(),
      dc: Hardware.display_dc(),
      cs: Hardware.display_cs(),
      backlight: Hardware.display_backlight(),
      backlight_active: :low,
      backlight_enabled: true,
      spi_host: spi
    ]
  end
end
