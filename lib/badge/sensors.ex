defmodule Badge.Sensors do
  @moduledoc """
  Owns the I2C bus shared by the SC7A20 accelerometer and TMP103
  temperature sensor.

  The accelerometer is interrupt-driven: GPIO12 carries its INT1 line,
  configured for data-ready, so a fresh sample is read and averaged on
  each rising edge rather than by polling. Reading the output registers
  clears the data-ready condition, so every interrupt is followed by a
  read or interrupts stop arriving.

  TMP103 has no interrupt; a linked ticker samples it every
  `@temp_interval` and logs a status line at the same cadence.
  """

  use GenServer

  import Bitwise

  alias Badge.Accel
  alias Badge.Hardware

  @sc7a20_addr Hardware.sc7a20_addr()
  @tmp103_addr Hardware.tmp103_addr()
  @accel_int_pin Hardware.accel_int_pin()

  @sc7a20_ctrl_reg1 0x20
  @sc7a20_ctrl_reg1_25hz_xyz 0x37
  @sc7a20_ctrl_reg3 0x22
  @sc7a20_ctrl_reg3_i1_zyxda 0x10
  @sc7a20_ctrl_reg4 0x23
  @sc7a20_ctrl_reg4_bdu_2g 0x80
  @sc7a20_out_x_l 0x28
  @sc7a20_auto_increment 0x80

  @tmp103_reg 0x00

  @temp_interval 2_000

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Latest averaged accelerometer reading, in milli-g."
  @spec acceleration() :: Accel.mg()
  def acceleration do
    GenServer.call(__MODULE__, :acceleration)
  end

  @doc "Roll and pitch in whole degrees, from the latest averaged reading."
  @spec orientation() :: {integer, integer}
  def orientation do
    GenServer.call(__MODULE__, :orientation)
  end

  @doc "Latest TMP103 reading in whole degrees C, or :unavailable before the first read."
  @spec temperature() :: integer | :unavailable
  def temperature do
    GenServer.call(__MODULE__, :temperature)
  end

  @impl true
  def init(:ok) do
    i2c = I2C.open(scl: Hardware.i2c_scl(), sda: Hardware.i2c_sda(), clock_speed_hz: 100_000)

    :ok = I2C.write_bytes(i2c, @sc7a20_addr, @sc7a20_ctrl_reg1, @sc7a20_ctrl_reg1_25hz_xyz)
    :ok = I2C.write_bytes(i2c, @sc7a20_addr, @sc7a20_ctrl_reg4, @sc7a20_ctrl_reg4_bdu_2g)
    :ok = I2C.write_bytes(i2c, @sc7a20_addr, @sc7a20_ctrl_reg3, @sc7a20_ctrl_reg3_i1_zyxda)

    # Clears any data-ready already latched before CTRL_REG3 routed it to
    # INT1, so the pin starts low and the first sample is a rising edge
    # rather than a level already high with nothing to trigger on.
    _ = I2C.read_bytes(i2c, @sc7a20_addr, @sc7a20_out_x_l ||| @sc7a20_auto_increment, 6)

    gpio = GPIO.open()
    :ok = GPIO.set_int(gpio, @accel_int_pin, :rising)

    :io.format(~c"Sensors: sc7a20 25Hz data-ready interrupt on GPIO~p, tmp103 every ~ps~n", [
      @accel_int_pin,
      div(@temp_interval, 1000)
    ])

    send(self(), :temp_tick)
    start_temp_ticker()

    {:ok, %{i2c: i2c, accel: nil, temp: :unavailable}}
  end

  @impl true
  def handle_call(:acceleration, _from, state) do
    {:reply, state.accel || {0, 0, 0}, state}
  end

  def handle_call(:orientation, _from, state) do
    {:reply, Accel.orientation(state.accel || {0, 0, 0}), state}
  end

  def handle_call(:temperature, _from, state) do
    {:reply, state.temp, state}
  end

  @impl true
  def handle_info({:gpio_interrupt, @accel_int_pin}, state) do
    case I2C.read_bytes(state.i2c, @sc7a20_addr, @sc7a20_out_x_l ||| @sc7a20_auto_increment, 6) do
      {:ok, bytes} ->
        sample = Accel.decode(bytes)
        {:noreply, %{state | accel: Accel.average(state.accel, sample)}}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  def handle_info(:temp_tick, state) do
    temp =
      case I2C.read_bytes(state.i2c, @tmp103_addr, @tmp103_reg, 1) do
        {:ok, <<raw>>} -> signed_byte(raw)
        {:error, _reason} -> :unavailable
      end

    {roll, pitch} = Accel.orientation(state.accel || {0, 0, 0})

    :io.format(~c"Sensors: accel=~p orientation=roll~p/pitch~p temp=~pC~n", [
      state.accel || {0, 0, 0},
      roll,
      pitch,
      temp
    ])

    # Sleeps rather than using Process.send_after/3.
    Process.sleep(@temp_interval)
    send(self(), :temp_tick)

    {:noreply, %{state | temp: temp}}
  end

  # TMP103 register 0x00 is a signed 8-bit whole-degree-C reading.
  defp signed_byte(raw) when raw >= 128, do: raw - 256
  defp signed_byte(raw), do: raw

  defp start_temp_ticker do
    sensors = self()
    spawn_link(fn -> temp_tick_loop(sensors) end)
  end

  defp temp_tick_loop(sensors) do
    Process.sleep(@temp_interval)
    send(sensors, :temp_tick)
    temp_tick_loop(sensors)
  end
end
