defmodule Badge.Chat.Link do
  @moduledoc """
  Keeps a Phoenix channel joined over long polling.

  Every request blocks for as long as the server holds it open - ten seconds
  when the room is quiet - so each runs in a worker of its own and answers
  with a message. This process only ever holds state.

  Phoenix hands back a fresh token on every response and expires the old one,
  so the token is taken from whatever arrived last. A 410 means the session is
  gone and the whole thing starts again.

  Nothing is polled until a page asks. Holding the session open costs about
  7 kB of heap, which this badge cannot spare while it is doing something
  else, so `Badge.Page.Chat` opens the link on entry and closes it on the way
  out. The room keeps no history, so nothing is missed that was not already
  gone.
  """

  use GenServer

  alias Badge.Chat.Poll
  alias Badge.Chat.Wire
  alias Badge.Identity
  alias Badge.Profile
  alias Badge.Wifi

  @topic "chat:lobby"
  @join_ref "1"

  # Long enough that a failed request does not hammer the tunnel.
  @tick 2_000

  # What the page can show; a badge cannot scroll far anyway.
  @keep 12

  def start_link(:ok), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Starts polling, if it is not already."
  @spec open() :: :ok
  def open, do: GenServer.cast(__MODULE__, :open)

  @doc "Stops polling and forgets the session."
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
      state: :idle,
      token: nil,
      ref: 1,
      messages: [],
      worker: nil,
      chip: nil,
      name: nil
    }

    start_ticker()

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{state: state.state, messages: state.messages, host: Poll.host()}, state}
  end

  @impl true
  def handle_cast(:open, %{state: :idle} = state), do: {:noreply, %{state | state: :offline}}

  def handle_cast(:open, state), do: {:noreply, state}

  # An answer from a request still in flight is dropped by the :idle guard below.
  def handle_cast(:close, state) do
    {:noreply, %{state | state: :idle, token: nil, messages: []}}
  end

  def handle_cast({:say, _body}, %{state: joined} = state) when joined != :joined do
    {:noreply, state}
  end

  def handle_cast({:say, body}, state) do
    message = Wire.encode(@join_ref, ref(state), @topic, "new_msg", %{"body" => body})
    token = state.token

    {:noreply, work(%{state | ref: state.ref + 1}, :push, fn -> Poll.push(token, message) end)}
  end

  @impl true
  # One request at a time: a second poll on the same token is refused anyway.
  def handle_info(:tick, %{worker: worker} = state) when worker != nil, do: {:noreply, state}

  def handle_info(:tick, %{state: :idle} = state), do: {:noreply, state}

  def handle_info(:tick, %{state: :offline} = state), do: {:noreply, start(state)}

  def handle_info(:tick, %{state: :joined} = state) do
    token = state.token

    {:noreply, work(state, :poll, fn -> Poll.poll(token) end)}
  end

  def handle_info(:tick, state), do: {:noreply, state}

  # Closed while a request was in flight: its answer is no longer wanted.
  def handle_info({:chat, _kind, _result}, %{state: :idle} = state) do
    {:noreply, %{state | worker: nil}}
  end

  def handle_info({:chat, kind, result}, state) do
    {:noreply, answered(kind, result, %{state | worker: nil})}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{worker: pid} = state) do
    {:noreply, %{state | worker: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Nothing can happen before there is an address to reach the server from.
  defp start(state) do
    case Wifi.status() do
      %{radio: :connected} -> opening(state)
      _down -> state
    end
  end

  defp opening(state) do
    profile = Profile.load()
    chip = Identity.format(Identity.chip_id())
    name = Profile.display_name(profile)

    :io.format(~c"Chat: opening as ~s ~s~n", [chip, name])

    work(%{state | chip: chip, name: name, state: :opening}, :session, fn ->
      Poll.session(chip, name)
    end)
  end

  # 410 on a fresh session is Phoenix handing over the first token, not a fault.
  defp answered(:session, {:ok, %{status: 410, token: token}}, state) when is_binary(token) do
    join(%{state | token: token})
  end

  defp answered(:join, {:ok, envelope}, state) do
    :io.format(~c"Chat: joined ~s~n", [@topic])

    %{keep_token(state, envelope) | state: :joined}
  end

  defp answered(:poll, {:ok, %{status: 410} = envelope}, state) do
    :io.format(~c"Chat: session expired, opening a new one~n")

    %{keep_token(state, envelope) | state: :offline, token: nil}
  end

  defp answered(:poll, {:ok, envelope}, state) do
    state |> keep_token(envelope) |> receive_messages(envelope.messages)
  end

  defp answered(:push, {:ok, envelope}, state), do: keep_token(state, envelope)

  defp answered(kind, {:ok, envelope}, state) do
    :io.format(~c"Chat: ~p answered ~p~n", [kind, envelope.status])

    %{keep_token(state, envelope) | state: :offline}
  end

  defp answered(kind, {:error, reason}, state) do
    :io.format(~c"Chat: ~p failed ~p~n", [kind, reason])

    %{state | state: :offline, token: nil}
  end

  defp join(state) do
    message = Wire.encode(@join_ref, ref(state), @topic, "phx_join", %{})
    token = state.token

    work(%{state | ref: state.ref + 1, state: :joining}, :join, fn ->
      Poll.push(token, message)
    end)
  end

  # Phoenix expires the old token on every answer, so the newest one wins.
  defp keep_token(state, %{token: token}) when is_binary(token), do: %{state | token: token}
  defp keep_token(state, _envelope), do: state

  defp receive_messages(state, []), do: state

  defp receive_messages(state, [%{event: "new_msg", payload: payload} | rest]) do
    :io.format(~c"Chat: ~s: ~s~n", [line(payload, "from"), line(payload, "body")])

    heard = %{from: line(payload, "from"), body: line(payload, "body")}

    receive_messages(%{state | messages: keep([heard | state.messages], @keep, [])}, rest)
  end

  defp receive_messages(state, [_other | rest]), do: receive_messages(state, rest)

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

  # Unlinked and monitored, so a request that dies cannot take the link down.
  defp work(state, kind, request) do
    link = self()
    {pid, _ref} = :erlang.spawn_monitor(fn -> send(link, {:chat, kind, attempt(request)}) end)

    %{state | worker: pid}
  end

  defp attempt(request) do
    request.()
  catch
    kind, error -> {:error, {kind, error}}
  end

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
