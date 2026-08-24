defmodule Badge.Chat.Socket do
  @moduledoc """
  The websocket the chat rides on.

  A thin wrapper over `websocket_client`, which is an ESP-IDF component: the
  TCP connection, the TLS session and the framing all live on its own FreeRTOS
  task, and Erlang sees whole messages. `Badge.Chat.Link` owns the port this
  hands back and receives:

      {:websocket, port, :connected}
      {:websocket, port, {:text, binary}}
      {:websocket, port, {:closed, reason}}
      {:websocket, port, {:error, reason}}

  The client reconnects on its own, so `:connected` arrives on every
  reconnection rather than once. Phoenix keeps channel state on the server and
  loses it with the socket, so the channel has to be re-joined every time.

  TLS is the component's, not AtomVM's. `:ssl` pins TLS 1.2 and could not
  reach an ngrok edge that speaks only 1.3, which is why the long poll this
  replaced ran in the clear; esp-tls does 1.3 and verifies against the
  certificate bundle already in the image.

  The host is compiled in. ngrok hands out a new subdomain every time it
  restarts, so a restarted tunnel means reflashing.
  """

  @compile {:no_warn_undefined, :websocket_client}

  @host "192.168.178.119:4443"
  @path "/badge/socket/websocket"
  @vsn "2.0.0"

  @network_timeout 30_000

  # The dev CA from avm_badge_server/priv/cert, pinned. TLS terminates at
  # Phoenix, not at a tunnel edge, and the chain is P-256 end to end - an
  # all-software P-384 chain was slower than ngrok's edge would wait.
  @cacert File.read!("assets/certs/badge-ca.pem")

  @doc "The server this build talks to."
  @spec host() :: binary
  def host, do: @host

  @doc "Where to connect, carrying the serializer version and who is asking."
  @spec url(binary, binary) :: binary
  def url(chip, name) do
    "wss://" <> @host <> @path <> "?" <> query([{"vsn", @vsn}, {"chip", chip}, {"name", name}])
  end

  @doc """
  Opens the connection, answering once the port exists rather than once it is
  up. Wait for `:connected` before sending.
  """
  @spec open(binary, binary) :: {:ok, port} | {:error, term}
  def open(chip, name) do
    :websocket_client.open(%{
      url: url(chip, name),
      owner: self(),
      # Without an explicit verify the driver disables verification and warns.
      verify: {:cacert_pem, @cacert},
      # A TLS 1.3 handshake against the tunnel takes the badge past the ten
      # second default, and a timeout there looks like a dead server.
      network_timeout_ms: @network_timeout
    })
  end

  @doc "Sends one frame, refusing rather than queueing while the link is down."
  @spec send_frame(port, binary) :: :ok | {:error, term}
  def send_frame(port, frame), do: :websocket_client.send_text(port, frame)

  @doc "Closes the connection and destroys the port."
  @spec close(port) :: :ok
  def close(port), do: :websocket_client.close(port)

  defp query(pairs), do: query(pairs, <<>>)

  defp query([], acc), do: acc

  defp query([{key, value} | rest], <<>>), do: query(rest, key <> "=" <> escape(value, <<>>))

  defp query([{key, value} | rest], acc),
    do: query(rest, acc <> "&" <> key <> "=" <> escape(value, <<>>))

  defp escape(<<>>, acc), do: acc

  defp escape(<<char, rest::binary>>, acc) when char >= ?a and char <= ?z,
    do: escape(rest, acc <> <<char>>)

  defp escape(<<char, rest::binary>>, acc) when char >= ?A and char <= ?Z,
    do: escape(rest, acc <> <<char>>)

  defp escape(<<char, rest::binary>>, acc) when char >= ?0 and char <= ?9,
    do: escape(rest, acc <> <<char>>)

  defp escape(<<char, rest::binary>>, acc)
       when char == ?- or char == ?_ or char == ?. or char == ?~,
       do: escape(rest, acc <> <<char>>)

  defp escape(<<char, rest::binary>>, acc) do
    escape(rest, acc <> "%" <> <<hex(div(char, 16)), hex(rem(char, 16))>>)
  end

  defp hex(value) when value < 10, do: ?0 + value
  defp hex(value), do: ?A + value - 10
end
