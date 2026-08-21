defmodule Badge.UI do
  @moduledoc """
  Owns the AtomGL port and decides what is on it.

  Pages are modules, not processes: this process holds the current page's
  state and calls `render/1`, `tick/1` and `handle_key/2` on it. Shape keys
  and Esc are intercepted here and never reach a page, so no page has to
  know that navigation exists.

  Rendering stays decoupled from input: key events only mutate page state
  and mark it dirty, and a linked ticker asks for a redraw at a bounded
  rate. The link is load-bearing — a silently dead ticker would freeze the
  panel behind a healthy-looking supervision tree.
  """

  use GenServer

  alias Badge.Hardware
  alias Badge.Page.Home
  alias Badge.Pages
  alias Badge.Theme

  @accent Theme.accent()
  @dim Theme.dim()
  @bg Theme.bg()
  @width Theme.width()
  @height Theme.height()
  @bar_h Theme.bar_h()

  @render_interval 100

  @font_dogica File.read!("priv/fonts/dogica.uf")
  @font_pixel_operator File.read!("priv/fonts/pixel_operator.uf")

  def start_link(spi) do
    GenServer.start_link(__MODULE__, spi, name: __MODULE__)
  end

  @doc """
  Applies a decoded key event.

  Does not draw. Navigation is handled here; anything else goes to the
  current page, and the ticker turns the result into a frame.
  """
  def key_event(event) do
    GenServer.cast(__MODULE__, {:key, event})
  end

  @impl true
  def init(spi) do
    port = :erlang.open_port({:spawn, "display"}, display_opts(spi))

    :port.call(port, {:register_font, :dogica, @font_dogica})
    :port.call(port, {:register_font, :pixel_operator, @font_pixel_operator})

    :io.format(~c"UI: AtomGL port open, ~p slots~n", [length(Pages.all())])

    state = %{port: port, page: Home, page_state: Home.init(), dirty: false}

    # Renders once immediately so the home grid is up before the first tick.
    render(state)

    start_ticker()

    {:ok, state}
  end

  @impl true
  def handle_cast({:key, {:nav, :home}}, state) do
    {:noreply, goto(state, Home)}
  end

  def handle_cast({:key, {:nav, key}}, state) do
    case Pages.for_key(key) do
      nil -> {:noreply, state}
      module -> {:noreply, goto(state, module)}
    end
  end

  def handle_cast({:key, event}, state) do
    case state.page.handle_key(event, state.page_state) do
      {:ok, page_state} ->
        dirty = state.dirty or page_state != state.page_state

        {:noreply, %{state | page_state: page_state, dirty: dirty}}

      :ignore ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:render_tick, state) do
    page_state = state.page.tick(state.page_state)

    case state.dirty or page_state != state.page_state do
      true ->
        next = %{state | page_state: page_state}
        render(next)

        {:noreply, %{next | dirty: false}}

      false ->
        {:noreply, state}
    end
  end

  # Re-entering the current page would reset it, and key repeat fires a held key 8 times a second.
  defp goto(%{page: page} = state, page), do: state

  defp goto(state, page) do
    %{state | page: page, page_state: page.init(), dirty: true}
  end

  defp render(%{port: port, page: page, page_state: page_state}) do
    :port.call(port, {:update, page.render(page_state) ++ chrome(page.title())})
  end

  # Z-order runs tail to head: background last.
  defp chrome(title) do
    [
      {:text, 6, 3, :pixel_operator, @accent, @bg, title},
      {:rect, 0, @bar_h, @width, 1, @dim},
      {:rect, 0, 0, @width, @height, @bg}
    ]
  end

  # Waits in a linked process, so this GenServer never sleeps in a callback and a dead ticker crashes loudly.
  defp start_ticker do
    ui = self()
    spawn_link(fn -> tick_loop(ui) end)
  end

  defp tick_loop(ui) do
    Process.sleep(@render_interval)
    send(ui, :render_tick)
    tick_loop(ui)
  end

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
