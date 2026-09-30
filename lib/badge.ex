defmodule Badge do
  @moduledoc """
  Firmware entry point.

  Opens both SPI buses and the display port, and passes them to the supervised
  children as arguments; children only add devices to an already-open bus, and
  never open a bus or a port themselves. A child that opened its own would leak
  it every time the supervisor restarted the child.

  `Badge.Ir.Link` is the exception and opens its own UART, because it holds
  those pins for the life of the badge rather than sharing them.

  Two buses are used: the panel and the LED chain need different MOSI pins
  and clock rates.

  `start/0` parks after starting the supervisor, since AtomVM terminates
  when the start function returns.
  """

  @compile {:no_warn_undefined, [:atomvm, :spi]}

  # Which display driver the base image carries: AtomGL, or the LVGL port.
  @display Application.compile_env(:avm_badge, :display, :atomgl)

  def start do
    # First, so every process below prints through the log ring.
    {:ok, _log} = Badge.Log.start_link(:ok)
    Badge.Log.capture()

    :io.format(~c"Badge: starting~n")

    # Rickroll frames live in their own partition, shared by both OTA slots.
    case :atomvm.add_avm_pack_file(~c"/dev/partition/by-name/assets.avm", name: :assets) do
      :ok -> :ok
      {:error, reason} -> :io.format(~c"Badge: no assets partition: ~p~n", [reason])
    end

    # Opened here, not in the child, so a Badge.UI restart reuses the display
    # instead of orphaning its framebuffer.
    display = open_display()

    children = [
      {Badge.UI, display},
      {Badge.Backlight, :ok},
      {Badge.Keyboard, :ok},
      {Badge.Wifi, :ok},
      {Badge.Pixels, Badge.Pixels.Port},
      {Badge.Sensors, :ok},
      {Badge.Power, :ok},
      {Badge.Ir.Link, :ok},
      {Badge.Chat.Link, :ok},
      {Badge.Update.Link, :ok},
      {Badge.Cluster.Link, :ok},
      {Badge.Schedule.Link, :ok}
    ]

    {:ok, _supervisor} = Supervisor.start_link(children, strategy: :one_for_one)

    :io.format(~c"Badge: running~n")

    Badge.Autopilot.start()

    park()
  end

  case @display do
    :atomgl ->
      defp open_display, do: Badge.UI.open_display(open_display_spi())

      # AtomGL adds its own SPI device, so device_config is empty here.
      defp open_display_spi do
        :spi.open(%{
          bus_config: %{
            peripheral: Badge.Hardware.display_peripheral(),
            sclk: Badge.Hardware.display_sclk(),
            mosi: Badge.Hardware.display_mosi(),
            miso: Badge.Hardware.display_miso()
          },
          device_config: %{}
        })
      end

    # The LVGL port brings up its own SPI bus.
    :lvgl ->
      defp open_display, do: Badge.UI.open_display(:lvgl)
  end

  defp park do
    Process.sleep(60_000)
    park()
  end
end
