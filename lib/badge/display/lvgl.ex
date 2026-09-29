defmodule Badge.Display.Lvgl do
  @moduledoc """
  The LVGL display backend: drives the `lvgl` port driver from the AtomVM fork.

  Each frame's items are diffed by `Badge.Display.Lvgl.Frame` against the
  last frame the driver accepted, and only the changes are sent, as one
  batch. The diff state lives in the process that draws, which is
  `Badge.UI`; a new drawing process starts by resetting the panel.

  A driver that is still busy with earlier batches answers `busy` and
  applies nothing; the frame is retried briefly, then dropped, and the next
  frame is diffed against what the panel really shows.
  """

  @behaviour Badge.Display

  alias Badge.Display.Lvgl.Frame
  alias Badge.Hardware

  @compile {:no_warn_undefined, [:port]}

  @key :badge_display_lvgl

  @default16px_path Path.expand("../../../assets/fonts/default16px.bin", __DIR__)
  @external_resource @default16px_path
  @default16px File.read!(@default16px_path)

  @retries 20
  @retry_ms 10

  @doc "Opens the panel and loads the built-in 8x16 font."
  @spec open() :: port
  def open do
    port =
      :erlang.open_port({:spawn, ~c"lvgl"},
        sclk: Hardware.display_sclk(),
        mosi: Hardware.display_mosi(),
        cs: Hardware.display_cs(),
        dc: Hardware.display_dc(),
        reset: Hardware.display_reset(),
        width: Hardware.display_width(),
        height: Hardware.display_height()
      )

    :ok =
      send_batch(port, [{:font, Frame.font_id(:default16px), :raw8x16, @default16px}], @retries)

    port
  end

  @impl true
  def update(port, items) do
    {ops, next} = Frame.frame(state(), items)

    case ops do
      [] ->
        :ok

      ops ->
        if send_batch(port, ops, @retries) == :ok, do: :erlang.put(@key, next)
        :ok
    end
  end

  # Fonts are kept once loaded, so registering one twice or dropping one costs nothing.
  @impl true
  def register_font(port, name, bytes) do
    send_batch(port, [{:font, Frame.font_id(name), :uf, bytes}], @retries)
    :ok
  end

  @impl true
  def deregister_font(_port, _name), do: :ok

  @doc "Internal, DMA and PSRAM memory as the driver sees it, and its refresh count."
  @spec stats(port) :: tuple
  def stats(port), do: :port.call(port, :stats)

  defp state do
    case :erlang.get(@key) do
      :undefined -> Frame.new()
      state -> state
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
