defmodule Badge.Display.Lvgl do
  @moduledoc """
  The LVGL display backend: drives the `lvgl` port driver from the AtomVM fork.

  The display is a painter process that owns the port. `update/2` hands it a
  frame and returns at once; the painter diffs the frame with
  `Badge.Display.Lvgl.Frame` against the last one the driver accepted and
  sends only the changes, as one batch. Diffing there keeps its state off
  the drawing process's heap, and a frame that arrives while an older one is
  still waiting replaces it, so the panel never falls behind.

  A driver still busy with earlier batches answers `busy` and applies
  nothing; the batch is retried briefly, then dropped, and the next frame is
  diffed against what the panel really shows.
  """

  @behaviour Badge.Display

  alias Badge.Display.Lvgl.Frame
  alias Badge.Hardware

  @compile {:no_warn_undefined, [:port]}

  @default16px_path Path.expand("../../../assets/fonts/default16px.bin", __DIR__)
  @external_resource @default16px_path
  @default16px File.read!(@default16px_path)

  @retries 20
  @retry_ms 10

  @doc "Starts the painter, which opens the panel and loads the built-in 8x16 font."
  @spec open() :: pid
  def open do
    caller = self()
    painter = spawn(fn -> start(caller) end)

    receive do
      {^painter, :ready} -> painter
    end
  end

  @impl true
  def update(painter, items) do
    send(painter, {:frame, items})
    :ok
  end

  # Fonts are kept once loaded, so registering one twice or dropping one costs nothing.
  @impl true
  def register_font(painter, name, bytes) do
    send(painter, {:font, Frame.font_id(name), bytes})
    :ok
  end

  @impl true
  def deregister_font(_painter, _name), do: :ok

  @impl true
  def decor(painter, specs) do
    send(painter, {:decor, specs})
    :ok
  end

  @doc "Internal, DMA and PSRAM memory as the driver sees it, and its refresh count."
  @spec stats(pid) :: tuple
  def stats(painter) do
    ref = make_ref()
    send(painter, {:stats, self(), ref})

    receive do
      {^ref, stats} -> stats
    end
  end

  defp start(caller) do
    port =
      :erlang.open_port({:spawn, ~c"lvgl"},
        sclk: Hardware.display_sclk(),
        mosi: Hardware.display_mosi(),
        cs: Hardware.display_cs(),
        dc: Hardware.display_dc(),
        reset: Hardware.display_reset(),
        clock_hz: Hardware.display_clock_hz(),
        width: Hardware.display_width(),
        height: Hardware.display_height()
      )

    send_batch(port, [{:font, Frame.font_id(:default16px), :raw8x16, @default16px}], @retries)
    send(caller, {self(), :ready})
    loop(port, Frame.new())
  end

  defp loop(port, state) do
    receive do
      {:frame, items} -> loop(port, paint(port, state, latest(port, items)))
      {:font, id, bytes} -> font(port, id, bytes, state)
      {:decor, specs} -> decor(port, specs, state)
      {:stats, from, ref} -> stats(port, from, ref, state)
    end
  end

  defp font(port, id, bytes, state) do
    send_batch(port, [{:font, id, :uf, bytes}], @retries)
    loop(port, state)
  end

  defp decor(port, specs, state) do
    send_batch(port, [{:decor, specs}], @retries)
    loop(port, state)
  end

  defp stats(port, from, ref, state) do
    send(from, {ref, :port.call(port, :stats)})
    loop(port, state)
  end

  # Only the newest waiting frame is worth drawing; a font sent before it is loaded on the way.
  defp latest(port, items) do
    receive do
      {:frame, newer} ->
        latest(port, newer)

      {:font, id, bytes} ->
        send_batch(port, [{:font, id, :uf, bytes}], @retries)
        latest(port, items)
    after
      0 -> items
    end
  end

  defp paint(port, state, items) do
    case Frame.frame(state, items) do
      {[], next} ->
        next

      {ops, next} ->
        case send_batch(port, ops, @retries) do
          :ok -> next
          :busy -> state
        end
    end
  end

  defp send_batch(_port, _ops, 0), do: :busy

  defp send_batch(port, ops, tries) do
    case :port.call(port, {:batch, ops}) do
      :ok ->
        :ok

      :busy ->
        Process.sleep(@retry_ms)
        send_batch(port, ops, tries - 1)
    end
  end
end
