defmodule Badge.LvglSpike do
  @moduledoc """
  SPIKE, not for merge: drives the `lvgl` port driver from the AtomVM fork's
  `lvgl-spike` branch and logs what the go/no-go decision needs.

  Draws a Name-style screen with native marquees, runs a full-screen repaint
  benchmark, logs internal and DMA memory, then opens the chat websocket once
  the clock has synced, to see whether TLS still fits beside LVGL.
  """

  alias Badge.Hardware

  @compile {:no_warn_undefined, [:port]}

  # :chat_only opens the port for memory stats alone, with LVGL never started.
  @mode :display

  @white 0xF0EAFF
  @cyan 0x5CC8F5
  @magenta 0xE85FAF
  @lavender 0xB3A9D2

  @doc "Opens the port and starts the spike in its own process."
  def start do
    spawn(fn -> run() end)
  end

  defp run, do: run(@mode)

  defp run(:chat_only) do
    port = :erlang.open_port({:spawn, ~c"lvgl"}, no_display: true)
    :io.format(~c"LvglSpike: chat only, no LVGL, stats ~p~n", [call(port, :stats)])
    chat(port, 0)
  end

  # Marquees plus chat; once the connection has settled, traces internal RAM
  # that is allocated and never freed for four minutes, then dumps it.
  defp run(:trace) do
    port = display_port()
    draw(port)
    await_sync()
    :io.format(~c"LvglSpike: opening chat~n")
    Badge.Chat.Link.open()
    Process.sleep(60_000)
    :io.format(~c"LvglSpike: tracing, stats ~p~n", [call(port, :stats)])
    call(port, :trace_start)
    Process.sleep(240_000)
    :io.format(~c"LvglSpike: dumping, chat ready=~p stats ~p~n", [Badge.Chat.Link.status().ready, call(port, :stats)])
    call(port, :trace_dump)
    watch(port)
  end

  defp await_sync do
    case Badge.Wifi.status() do
      %{synced: true} -> :ok
      _other -> Process.sleep(2_000) && await_sync()
    end
  end

  # Marquees alone, logging memory every 15 s, to see whether LVGL drifts by itself.
  defp run(:display_only) do
    port = display_port()
    draw(port)
    watch(port)
  end

  defp run(:display) do
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

    :io.format(~c"LvglSpike: port ~p, stats ~p~n", [port, call(port, :stats)])
    draw(port)

    Process.sleep(10_000)
    :io.format(~c"LvglSpike: after 10s of marquees, stats ~p~n", [call(port, :stats)])

    call(port, {:bench, 60})
    Process.sleep(5_000)
    :io.format(~c"LvglSpike: after bench, stats ~p~n", [call(port, :stats)])

    chat(port, 0)
  end

  defp watch(port) do
    Process.sleep(15_000)
    :io.format(~c"LvglSpike: display only, stats ~p~n", [call(port, :stats)])
    watch(port)
  end

  defp display_port do
    :erlang.open_port({:spawn, ~c"lvgl"},
      sclk: Hardware.display_sclk(),
      mosi: Hardware.display_mosi(),
      cs: Hardware.display_cs(),
      dc: Hardware.display_dc(),
      reset: Hardware.display_reset(),
      width: Hardware.display_width(),
      height: Hardware.display_height()
    )
  end

  defp draw(port) do
    call(port, {:bg, 0x16122A})
    call(port, {:label, 0, 16, 20, "Ben Bangert", @white, 1})
    call(port, {:marquee, 1, 16, 80, 288, "@Goatmire International Holdings", @cyan, 1})
    call(port, {:marquee, 2, 16, 140, 288, "synths / climbing / coffee / pixel art / elixir", @lavender, 0})
    call(port, {:label, 3, 16, 190, "github.com/bbangert", @magenta, 0})
  end

  # Opens the chat once the clock is good, then keeps logging memory.
  defp chat(port, n) do
    case Badge.Wifi.status() do
      %{synced: true} when n == 0 ->
        :io.format(~c"LvglSpike: opening chat~n")
        Badge.Chat.Link.open()
        chat(port, 1)

      _other ->
        Process.sleep(15_000)

        if n > 0,
          do:
            :io.format(~c"LvglSpike: chat ready=~p, stats ~p~n", [
              Badge.Chat.Link.status().ready,
              call(port, :stats)
            ])

        chat(port, n + if(n > 0, do: 1, else: 0))
    end
  end

  defp call(port, message), do: :port.call(port, message)
end
