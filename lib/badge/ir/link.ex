defmodule Badge.Ir.Link do
  @moduledoc """
  Half-duplex UART over the IR beam.

  One process owns the port and alternates between a short blocking read and
  an occasional beacon, because the badge cannot listen while its own LED is
  lit. The beacon phase is offset by the badge's own chip id, so two badges
  tapped together do not transmit in lockstep forever.

  UART1 is used rather than UART0. The pins are UART0's by default, but the
  ESP32-S3 routes any peripheral to any pin through the GPIO matrix, so
  claiming them for UART1 leaves the console with nowhere to drive and no
  base image rebuild is needed.

  A badge that decodes a frame carrying its **own** chip id has proved its
  LED reaches its own sensor, which is the crosstalk answer phase one could
  not get on its own.
  """

  alias Badge.Hardware
  alias Badge.Identity
  alias Badge.Ir.Frame
  alias Badge.Profile

  @compile {:no_warn_undefined, :uart}

  @baud 4800

  @read_ms 100
  # Ten reads between beacons, so roughly one a second.
  @beacon_reads 10

  # Enough for several frames; a stream of noise that never frames up must
  # not grow without bound.
  @buffer_limit 256

  @doc "Opens the link, reporting every badge it hears to the caller."
  @spec start() :: pid
  def start do
    owner = self()

    # Unlinked so a link fault cannot take the display down, monitored so it
    # cannot outlive the page that opened it.
    spawn(fn -> report(owner) end)
  end

  @doc "Closes the link and releases the pins."
  @spec stop(pid | nil) :: :ok
  def stop(pid) when is_pid(pid) do
    send(pid, :stop)

    :ok
  end

  def stop(_pid), do: :ok

  defp report(owner) do
    run(owner)
  catch
    kind, error -> :io.format(~c"link: died ~p ~p~n", [kind, error])
  end

  @doc "The baud this build was compiled for."
  @spec baud() :: pos_integer
  def baud, do: @baud

  defp run(owner) do
    :erlang.monitor(:process, owner)

    mac = Identity.chip_id()
    frame = Frame.encode(mac, Profile.display_name(Profile.load()))
    port = open()

    :io.format(~c"link: up baud=~p mac=~s frame=~p bytes~n", [
      @baud,
      Identity.format(mac),
      byte_size(frame)
    ])

    loop(port, mac, frame, owner, phase(mac), <<>>)
  end

  defp open do
    :uart.open("UART1", [
      tx: Hardware.ir_led(),
      rx: Hardware.ir_sense(),
      speed: @baud,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: :none
    ])
  end

  # The last byte of the chip id is as good a decorrelator as any.
  defp phase(<<_head::binary-5, last>>), do: rem(last, @beacon_reads)
  defp phase(_mac), do: 0

  defp loop(port, mac, frame, owner, n, buffer) do
    buffer = listen(port, mac, owner, buffer)

    case rem(n, @beacon_reads) do
      0 -> :uart.write(port, frame)
      _quiet -> :ok
    end

    case halted?() do
      true -> close(port)
      false -> loop(port, mac, frame, owner, n + 1, buffer)
    end
  end

  # One control message a cycle is plenty; nothing sends them faster.
  defp halted? do
    receive do
      :stop ->
        true

      {:DOWN, _ref, :process, _pid, _reason} ->
        true
    after
      0 -> false
    end
  end

  defp close(port) do
    :uart.close(port)
    :io.format(~c"link: down~n")

    :ok
  end

  defp listen(port, mac, owner, buffer) do
    case :uart.read(port, @read_ms) do
      {:ok, data} ->
        bytes = :erlang.iolist_to_binary(data)

        harvest(mac, owner, cap(buffer <> bytes))

      {:error, :timeout} ->
        buffer

      other ->
        :io.format(~c"link: read returned ~p~n", [other])
        buffer
    end
  end

  defp cap(buffer) when byte_size(buffer) <= @buffer_limit, do: buffer

  defp cap(buffer) do
    :binary.part(buffer, byte_size(buffer) - @buffer_limit, @buffer_limit)
  end

  defp harvest(mac, owner, buffer) do
    case Frame.decode(buffer) do
      {:ok, badge, rest} ->
        announce(mac, owner, badge)
        harvest(mac, owner, rest)

      {:bad, reason, rest} ->
        :io.format(~c"link: bad frame ~p~n", [reason])
        harvest(mac, owner, rest)

      {:more, rest} ->
        rest
    end
  end

  # Our own beam reaching our own sensor would be a hardware finding, not a peer.
  defp announce(mac, _owner, %{mac: mac}) do
    :io.format(~c"link: SELF ECHO, own beam reaches own sensor~n")
  end

  defp announce(_mac, owner, %{mac: from, name: name}) do
    :io.format(~c"link: PEER ~s ~s~n", [Identity.format(from), name])
    send(owner, {:ir_peer, from, name})
  end
end
