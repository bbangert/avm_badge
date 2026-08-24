defmodule Badge.Chat.Link do
  @moduledoc """
  Keeps a Phoenix channel joined over a websocket.

  Two lifetimes, not one. The socket opens as soon as the radio has an address
  and then stays up for good, reconnecting on its own; the channel is joined
  only while `Badge.Page.Chat` is showing. Leaving the room costs a `phx_leave`
  rather than a disconnection, so coming back does not pay for a TLS handshake.

  `open/0` and `close/0` therefore mean join and leave, not connect and
  disconnect. The page calls them on entry and exit as it always did.

  The socket carries the identity as connect params, so it is fixed for the
  life of the connection: a display name changed while connected reaches the
  server on the next reconnection, not immediately.

  The room keeps no history, so nothing is missed that was not already gone.
  """

  use GenServer

  alias Badge.Chat.Socket
  alias Badge.Chat.Wire
  alias Badge.Identity
  alias Badge.Profile
  alias Badge.Wifi

  @topic "chat:lobby"
  @join_ref "1"

  # Phoenix drops a transport that goes quiet, and the heartbeat is what a
  # quiet room otherwise has nothing to say.
  @heartbeat_topic "phoenix"

  @tick 2_000
  @beats 15

  # What the page can show; a badge cannot scroll far anyway.
  @keep 12

  def start_link(:ok), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Joins the room, if it is not already joined."
  @spec open() :: :ok
  def open, do: GenServer.cast(__MODULE__, :open)

  @doc "Leaves the room. The socket stays up."
  @spec close() :: :ok
  def close, do: GenServer.cast(__MODULE__, :close)

  @doc "Posts a line to the room."
  @spec say(binary) :: :ok
  def say(body), do: GenServer.cast(__MODULE__, {:say, body})

  @doc "Where the link is and what it has heard."
  @spec status() :: %{state: atom, messages: [map], host: binary}
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(:ok) do
    state = %{
      port: nil,
      up: false,
      channel: :out,
      want: false,
      ref: 1,
      beat: 0,
      messages: [],
      chip: nil,
      name: nil
    }

    start_ticker()

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{state: state.channel, messages: state.messages, host: Socket.host()}, state}
  end

  @impl true
  def handle_cast(:open, %{want: true} = state), do: {:noreply, state}

  def handle_cast(:open, state), do: {:noreply, join(%{state | want: true})}

  def handle_cast(:close, %{want: false} = state), do: {:noreply, state}

  def handle_cast(:close, state), do: {:noreply, leave(%{state | want: false})}

  def handle_cast({:say, _body}, %{channel: channel} = state) when channel != :joined do
    {:noreply, state}
  end

  def handle_cast({:say, body}, state) do
    {:noreply, push(state, @topic, "new_msg", %{"body" => body})}
  end

  @impl true
  def handle_info(:tick, state) do
    {:noreply, state |> connect() |> beat()}
  end

  def handle_info({:websocket, _port, :connected}, state) do
    :io.format(~c"Chat: socket up~n")

    # Phoenix keeps channel state with the socket and loses it with the socket,
    # so a reconnection has to re-join rather than assume it is still in.
    {:noreply, join(%{state | up: true, channel: :out})}
  end

  def handle_info({:websocket, _port, {:text, frame}}, state) do
    {:noreply, received(Wire.decode_frame(frame), state)}
  end

  def handle_info({:websocket, _port, {:closed, reason}}, state) do
    :io.format(~c"Chat: socket down ~p~n", [reason])

    {:noreply, %{state | up: false, channel: :out}}
  end

  def handle_info({:websocket, _port, {:error, reason}}, state) do
    :io.format(~c"Chat: socket error ~p~n", [reason])

    {:noreply, %{state | up: false, channel: :out}}
  end

  def handle_info(message, state) do
    :io.format(~c"Chat: unhandled ~p~n", [message])

    {:noreply, state}
  end

  # Nothing can happen before there is an address to reach the server from.
  defp connect(%{port: nil} = state) do
    case Wifi.status() do
      %{radio: :connected} -> opening(state)
      _down -> state
    end
  end

  defp connect(state), do: state

  defp opening(state) do
    chip = Identity.format(Identity.chip_id())
    name = Profile.display_name(Profile.load())

    :io.format(~c"Chat: connecting as ~s ~s~n", [chip, name])

    case Socket.open(chip, name) do
      {:ok, port} ->
        %{state | port: port, chip: chip, name: name}

      {:error, reason} ->
        :io.format(~c"Chat: connect failed ~p~n", [reason])

        state
    end
  end

  defp beat(%{up: true, beat: beat} = state) when beat >= @beats do
    %{push(state, @heartbeat_topic, "heartbeat", %{}, nil) | beat: 0}
  end

  defp beat(%{up: true} = state), do: %{state | beat: state.beat + 1}

  defp beat(state), do: state

  defp join(%{want: true, up: true, channel: :out} = state) do
    %{push(state, @topic, "phx_join", %{}) | channel: :joining}
  end

  defp join(state), do: state

  defp leave(%{channel: :joined} = state) do
    %{push(state, @topic, "phx_leave", %{}) | channel: :out, messages: []}
  end

  defp leave(state), do: %{state | channel: :out, messages: []}

  defp push(state, topic, event, payload, join_ref \\ @join_ref) do
    frame = Wire.encode(join_ref, ref(state), topic, event, payload)

    case Socket.send_frame(state.port, frame) do
      :ok ->
        :ok

      {:error, reason} ->
        :io.format(~c"Chat: ~s refused ~p~n", [event, reason])
    end

    %{state | ref: state.ref + 1}
  end

  defp received(:error, state), do: state

  defp received({:ok, %{topic: @topic, event: "phx_reply", payload: payload}}, state) do
    joined(Map.get(payload, "status"), state)
  end

  defp received({:ok, %{topic: @topic, event: "new_msg", payload: payload}}, state) do
    heard = %{
      from: line(payload, "from"),
      body: line(payload, "body"),
      mine: line(payload, "chip") == state.chip
    }

    :io.format(~c"Chat: ~s: ~s~n", [heard.from, heard.body])

    %{state | messages: keep([heard | state.messages], @keep, [])}
  end

  # The server dropped the channel out from under us; the socket is still fine.
  defp received({:ok, %{topic: @topic, event: event}}, state)
       when event == "phx_error" or event == "phx_close" do
    :io.format(~c"Chat: channel ~s~n", [event])

    join(%{state | channel: :out})
  end

  defp received({:ok, _message}, state), do: state

  defp joined("ok", %{channel: :joining} = state) do
    :io.format(~c"Chat: joined ~s~n", [@topic])

    %{state | channel: :joined}
  end

  defp joined("error", %{channel: :joining} = state) do
    :io.format(~c"Chat: join refused~n")

    %{state | channel: :out}
  end

  defp joined(_status, state), do: state

  defp line(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) -> value
      _absent -> ""
    end
  end

  defp keep(_list, 0, acc), do: :lists.reverse(acc)
  defp keep([], _left, acc), do: :lists.reverse(acc)
  defp keep([head | rest], left, acc), do: keep(rest, left - 1, [head | acc])

  defp ref(%{ref: ref}), do: :erlang.integer_to_binary(ref)

  defp start_ticker do
    link = self()

    spawn_link(fn -> tick_loop(link) end)
  end

  defp tick_loop(link) do
    Process.sleep(@tick)
    send(link, :tick)
    tick_loop(link)
  end
end
