defmodule Badge.Chat.Poll do
  @moduledoc """
  One Phoenix long poll request, start to finish.

  Every call here blocks on the network, so each belongs in a process of its
  own; `Badge.Chat.Link` spawns one per request and takes the answer as a
  message.

  TLS became possible once the external PSRAM was enabled - the handshake
  needs more heap than the badge had internally, and used to abort the board -
  but it is off by default because AtomVM pins the maximum version to TLS 1.2
  (`otp_ssl.c`), and the ngrok edge in front of the development server speaks
  only 1.3. Point `@scheme` at `:https` for a server that accepts 1.2.

  On that path AtomVM offers no certificate verification: `verify_none` is the
  only mode its `ssl` module accepts, so the connection would be encrypted but
  the server unauthenticated. `active: false` is not optional either - `ssl`
  has no clause for `{active, true}`, which `ahttp_client` would otherwise
  default to.

  The host is compiled in. ngrok hands out a new subdomain every time it
  restarts, so a restarted tunnel means reflashing.
  """

  alias Badge.Chat.Wire

  @compile {:no_warn_undefined, :ahttp_client}
  @compile {:no_warn_undefined, :ssl}

  @scheme :http
  @host "a477-2001-7e8-fc14-7001-f8f9-ea8a-ec1f-f130.ngrok-free.app"
  @port 80
  @path "/badge/socket/longpoll"
  @vsn "2.0.0"

  # Responses run to a few hundred bytes; a busy room needs several reads.
  @chunk 512
  @reads 32

  @doc "The server this build talks to."
  @spec host() :: binary
  def host, do: @host

  @doc "Opens a session, which answers 410 and the first token."
  @spec session(binary, binary) :: {:ok, map} | {:error, term}
  def session(chip, name) do
    get(Wire.query([{"vsn", @vsn}, {"chip", chip}, {"name", name}]))
  end

  @doc "Waits for whatever the room has to say."
  @spec poll(binary) :: {:ok, map} | {:error, term}
  def poll(token) do
    get(Wire.query([{"vsn", @vsn}, {"token", token}]))
  end

  @doc "Sends one message and takes the answer."
  @spec push(binary, binary) :: {:ok, map} | {:error, term}
  def push(token, message) do
    request("POST", Wire.query([{"vsn", @vsn}, {"token", token}]), message)
  end

  defp get(query), do: request("GET", query, nil)

  defp request(method, query, body) do
    case connect() do
      {:ok, conn} -> send_request(conn, method, query, body)
      {:error, reason} -> {:error, {:connect, reason}}
    end
  end

  defp connect do
    case @scheme do
      :https ->
        :ssl.start()
        :ahttp_client.connect(:https, @host, @port, active: false, verify: :verify_none)

      :http ->
        :ahttp_client.connect(:http, @host, @port, active: false)
    end
  end

  defp send_request(conn, method, query, body) do
    case :ahttp_client.request(conn, method, @path <> "?" <> query, headers(body), body) do
      {:ok, conn, _ref} -> collect(conn, <<>>, @reads)
      {:error, reason} -> close(conn, {:error, {:request, reason}})
    end
  end

  defp headers(nil), do: []
  defp headers(_body), do: [{"content-type", "application/json"}]

  defp collect(conn, _body, 0), do: close(conn, {:error, :too_many_reads})

  defp collect(conn, body, left) do
    case :ahttp_client.recv(conn, @chunk) do
      {:ok, conn, responses} ->
        {body, done} = harvest(responses, body, false)

        continue(conn, body, done, left)

      {:error, reason} ->
        close(conn, {:error, {:recv, reason}})
    end
  end

  defp continue(conn, body, true, _left), do: close(conn, envelope(body))
  defp continue(conn, body, false, left), do: collect(conn, body, left - 1)

  defp envelope(body) do
    case Wire.decode(body) do
      {:ok, envelope} -> {:ok, envelope}
      :error -> {:error, :undecodable}
    end
  end

  defp harvest([], body, done), do: {body, done}
  defp harvest([{:data, _ref, chunk} | rest], body, done), do: harvest(rest, body <> chunk, done)
  defp harvest([{:done, _ref} | rest], body, _done), do: harvest(rest, body, true)
  defp harvest([:done | rest], body, _done), do: harvest(rest, body, true)
  defp harvest([_other | rest], body, done), do: harvest(rest, body, done)

  defp close(conn, result) do
    :ahttp_client.close(conn)

    result
  end
end
