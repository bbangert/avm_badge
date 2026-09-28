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

  @white 0xF0EAFF
  @cyan 0x5CC8F5
  @magenta 0xE85FAF
  @lavender 0xB3A9D2

  @doc "Opens the port and starts the spike in its own process."
  def start do
    spawn(fn -> run() end)
  end

  defp run do
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

    call(port, {:bg, 0x16122A})
    call(port, {:label, 0, 16, 20, "Ben Bangert", @white, 1})
    call(port, {:marquee, 1, 16, 80, 288, "@Goatmire International Holdings", @cyan, 1})
    call(port, {:marquee, 2, 16, 140, 288, "synths / climbing / coffee / pixel art / elixir", @lavender, 0})
    call(port, {:label, 3, 16, 190, "github.com/bbangert", @magenta, 0})

    Process.sleep(10_000)
    :io.format(~c"LvglSpike: after 10s of marquees, stats ~p~n", [call(port, :stats)])

    call(port, {:bench, 60})
    Process.sleep(5_000)
    :io.format(~c"LvglSpike: after bench, stats ~p~n", [call(port, :stats)])

    chat(port, 0)
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
            :io.format(~c"LvglSpike: chat ~p, stats ~p~n", [
              Badge.Chat.Link.status(),
              call(port, :stats)
            ])

        chat(port, n + if(n > 0, do: 1, else: 0))
    end
  end

  defp call(port, message), do: :port.call(port, message)
end
