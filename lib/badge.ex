defmodule Badge do
  @moduledoc """
  Firmware entry point.

  Opens both SPI buses and passes them to the supervised children as
  arguments; children only add devices to an already-open bus, they never
  open one themselves.

  Two buses are used: the panel and the LED chain need different MOSI pins
  and clock rates.

  `start/0` parks after starting the supervisor, since AtomVM terminates
  when the start function returns.
  """

  alias Badge.Hardware

  def start do
    :io.format(~c"Badge: starting~n")

    display_spi = open_display_spi()
    pixel_spi = open_pixel_spi()

    children = [
      {Badge.Screen, display_spi},
      {Badge.Keyboard, :ok},
      {Badge.Pixels, pixel_spi}
    ]

    {:ok, _supervisor} = Supervisor.start_link(children, strategy: :one_for_one)

    :io.format(~c"Badge: running~n")

    park()
  end

  # AtomGL adds its own SPI device, so device_config is empty here.
  defp open_display_spi do
    :spi.open(%{
      bus_config: %{
        peripheral: Hardware.display_peripheral(),
        sclk: Hardware.display_sclk(),
        mosi: Hardware.display_mosi(),
        miso: Hardware.display_miso()
      },
      device_config: %{}
    })
  end

  # LED chain has no clock line, so SCLK is -1.
  defp open_pixel_spi do
    :spi.open(%{
      bus_config: %{
        peripheral: Hardware.pixel_peripheral(),
        sclk: Hardware.pixel_sclk(),
        mosi: Hardware.pixel_data()
      },
      device_config: %{
        pixels: %{
          clock_speed_hz: Hardware.pixel_clock_hz(),
          mode: 0,
          cs: -1,
          address_len_bits: 0,
          command_len_bits: 0
        }
      }
    })
  end

  defp park do
    Process.sleep(60_000)
    park()
  end
end
