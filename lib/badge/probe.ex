defmodule Badge.Probe do
  @moduledoc """
  Temporary bring-up probe for the I2C bus (TMP103, SC7A20, NS2009) and the
  ADC battery/VBUS dividers. Console-only, logs on a loop, never touches the
  display. Not meant to ship; remove once real drivers exist for these
  devices.
  """

  use GenServer

  import Bitwise

  alias Badge.Hardware

  @compile {:no_warn_undefined, [Esp.ADC]}

  @tmp103_addr 0x70
  @sc7a20_addr 0x19
  @scan_low 0x08
  @scan_high 0x77

  @sc7a20_whoami 0x0F
  @sc7a20_ctrl_reg1 0x20
  @sc7a20_ctrl_reg1_100hz_xyz 0x57
  @sc7a20_out_x_l 0x28
  @sc7a20_auto_increment 0x80

  @interval 3_000
  @adc_samples 64

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    :io.format(~c"Probe: starting~n")

    i2c = I2C.open(scl: Hardware.i2c_scl(), sda: Hardware.i2c_sda(), clock_speed_hz: 100_000)
    scan(i2c)

    {:ok, adc_unit} = Esp.ADC.init()
    {:ok, battery_chan} = Esp.ADC.acquire(Hardware.adc_battery_pin(), adc_unit, :bit_max, :db_12)
    {:ok, vbus_chan} = Esp.ADC.acquire(Hardware.adc_vbus_pin(), adc_unit, :bit_max, :db_12)

    send(self(), :tick)

    {:ok,
     %{
       i2c: i2c,
       adc_unit: adc_unit,
       battery_chan: battery_chan,
       vbus_chan: vbus_chan
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    tmp103(state.i2c)
    sc7a20(state.i2c)
    adc(state.adc_unit, state.battery_chan, ~c"battery")
    adc(state.adc_unit, state.vbus_chan, ~c"vbus")

    # Sleeps rather than using Process.send_after/3.
    Process.sleep(@interval)
    send(self(), :tick)

    {:noreply, state}
  end

  # Runs once at startup; a full sweep is slow, so it does not belong in the loop.
  defp scan(i2c) do
    found = Enum.filter(@scan_low..@scan_high, &ack?(i2c, &1))
    :io.format(~c"Probe: i2c scan found~s~n", [format_addrs(found)])
  end

  defp ack?(i2c, addr) do
    case I2C.read_bytes(i2c, addr, 1) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp format_addrs([]), do: ~c" nothing"

  defp format_addrs(addrs) do
    chars =
      Enum.reduce(addrs, ~c"", fn addr, acc -> acc ++ :io_lib.format(~c" 0x~2.16.0B", [addr]) end)

    :lists.flatten(chars)
  end

  defp tmp103(i2c) do
    case I2C.read_bytes(i2c, @tmp103_addr, 0x00, 1) do
      {:ok, <<raw>>} ->
        :io.format(~c"Probe: tmp103 raw=0x~2.16.0B temp=~pC~n", [raw, signed_byte(raw)])

      {:error, _reason} ->
        :io.format(~c"Probe: tmp103 no response~n")
    end
  end

  defp sc7a20(i2c) do
    case I2C.read_bytes(i2c, @sc7a20_addr, @sc7a20_whoami, 1) do
      {:ok, <<whoami>>} ->
        :io.format(~c"Probe: sc7a20 whoami=0x~2.16.0B~n", [whoami])
        sc7a20_axes(i2c)

      {:error, _reason} ->
        :io.format(~c"Probe: sc7a20 no response~n")
    end
  end

  defp sc7a20_axes(i2c) do
    case I2C.write_bytes(i2c, @sc7a20_addr, @sc7a20_ctrl_reg1, @sc7a20_ctrl_reg1_100hz_xyz) do
      :ok -> sc7a20_read_axes(i2c)
      {:error, _reason} -> :io.format(~c"Probe: sc7a20 enable failed~n")
    end
  end

  defp sc7a20_read_axes(i2c) do
    case I2C.read_bytes(i2c, @sc7a20_addr, @sc7a20_out_x_l ||| @sc7a20_auto_increment, 6) do
      {:ok, <<x::little-signed-16, y::little-signed-16, z::little-signed-16>>} ->
        :io.format(~c"Probe: sc7a20 x=~p y=~p z=~p~n", [x, y, z])

      {:error, _reason} ->
        :io.format(~c"Probe: sc7a20 auto-increment read failed, reading registers individually~n")
        sc7a20_read_axes_individually(i2c)
    end
  end

  defp sc7a20_read_axes_individually(i2c) do
    case read_axis_bytes(i2c, @sc7a20_out_x_l, 6) do
      {:ok, <<x::little-signed-16, y::little-signed-16, z::little-signed-16>>} ->
        :io.format(~c"Probe: sc7a20 x=~p y=~p z=~p (individual reads)~n", [x, y, z])

      :error ->
        :io.format(~c"Probe: sc7a20 individual axis reads failed~n")
    end
  end

  defp read_axis_bytes(i2c, reg, count) do
    regs = for r <- reg..(reg + count - 1), do: r

    bytes =
      Enum.map(regs, fn r ->
        case I2C.read_bytes(i2c, @sc7a20_addr, r, 1) do
          {:ok, <<byte>>} -> byte
          {:error, _reason} -> nil
        end
      end)

    case :lists.member(nil, bytes) do
      true -> :error
      false -> {:ok, :erlang.list_to_binary(bytes)}
    end
  end

  # TMP103 register 0x00 is a signed 8-bit whole-degree-C reading.
  defp signed_byte(raw) when raw >= 128, do: raw - 256
  defp signed_byte(raw), do: raw

  defp adc(unit, chan, label) do
    case Esp.ADC.sample(chan, unit, [:raw, :voltage, {:samples, @adc_samples}]) do
      {:ok, {raw, mv}} ->
        :io.format(~c"Probe: adc ~s raw=~p mv=~p v=~.2f~n", [label, raw, mv, mv * 2 / 1000])

      {:error, reason} ->
        :io.format(~c"Probe: adc ~s error=~p~n", [label, reason])
    end
  end
end
