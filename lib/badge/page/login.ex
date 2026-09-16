defmodule Badge.Page.Login do
  @moduledoc """
  Signs the badge in to Goatmire with a ticket holder's email.

  Enter sends the email to the site, which mails a link; the page then
  waits for the link to be opened and shows who the badge is signed in as.
  The account is kept in NVS, so a signed-in badge opens straight on the
  account with X to sign out.

  The exchange runs in a worker spawned on a tick, never from a key
  handler, and reports through `handle_info/2`. Leaving the page kills the
  worker, so Escape is how a wait is cancelled.
  """

  use Badge.Page

  alias Badge.Field
  alias Badge.Login
  alias Badge.Profile
  alias Badge.Theme
  alias Badge.Wifi

  @char_w 8
  @margin 8
  @columns div(Theme.width() - 2 * @margin, @char_w)

  # One column is the caret's.
  @capacity @columns - 1

  @label_y Theme.content_top() + 14
  @value_y @label_y + 26
  @note_y @value_y + 44
  @pitch 20
  @hint_y 216

  # How many ticks each step of the waiting dots lasts.
  @dot_ticks 3
  @dots 4

  @impl true
  def title, do: "Login"

  @impl true
  def init do
    %{
      mode: :entry,
      field: Field.new(@capacity),
      account: nil,
      worker: nil,
      error: nil,
      loaded: false,
      pending: nil,
      ticks: 0
    }
  end

  @doc "Which screen the page is on: entry, sending, waiting, signed_in or failed."
  @spec mode(map) :: atom
  def mode(%{mode: mode}), do: mode

  @doc "The account the badge is signed in as, or nil."
  @spec account(map) :: map | nil
  def account(%{account: account}), do: account

  @doc "The email typed so far."
  @spec email(map) :: binary
  def email(%{field: field}), do: Field.value(field)

  # The waiting dots are the only thing that moves on their own.
  @impl true
  def refresh(%{mode: :waiting}), do: 250
  def refresh(_state), do: 100

  @impl true
  def handle_key({:nav, _key}, _state), do: :ignore
  def handle_key(event, %{mode: :entry} = state), do: entry_key(event, state)
  def handle_key(event, %{mode: :signed_in} = state), do: signed_in_key(event, state)
  def handle_key(event, %{mode: :failed} = state), do: failed_key(event, state)
  def handle_key(_event, _state), do: :ignore

  defp entry_key({:char, char}, state),
    do: {:ok, %{state | field: Field.insert(state.field, char)}}

  defp entry_key({:edit, :backspace}, state),
    do: {:ok, %{state | field: Field.backspace(state.field)}}

  defp entry_key({:move, :left}, state), do: {:ok, %{state | field: Field.left(state.field)}}
  defp entry_key({:move, :right}, state), do: {:ok, %{state | field: Field.right(state.field)}}

  # Nothing to send is not a login; let the router keep the key.
  defp entry_key({:edit, :newline}, state) do
    case Field.value(state.field) do
      "" -> :ignore
      _email -> {:ok, %{state | mode: :sending, error: nil}}
    end
  end

  defp entry_key(_event, _state), do: :ignore

  # The old email stays in the field, since it is usually the one to sign back in with.
  defp signed_in_key({:char, char}, state) when char == ?x or char == ?X do
    {:ok,
     %{state | mode: :entry, account: nil, pending: :clear, field: fill(state.account.email)}}
  end

  defp signed_in_key(_event, _state), do: :ignore

  defp failed_key({:edit, :newline}, state), do: {:ok, %{state | mode: :entry}}
  defp failed_key(_event, _state), do: :ignore

  defp fill(value) do
    :lists.foldl(&Field.insert(&2, &1), Field.new(@capacity), :erlang.binary_to_list(value))
  end

  # Hardware and processes are only touched here, never from a key handler.
  @impl true
  def tick(state), do: state |> load() |> persist() |> start() |> animate()

  # The stored account arrives on the first tick, so init/0 stays pure.
  defp load(%{loaded: true} = state), do: state

  defp load(state) do
    case Login.load() do
      nil -> %{state | loaded: true, field: fill(Map.get(Profile.load(), :email, ""))}
      account -> %{state | loaded: true, mode: :signed_in, account: account}
    end
  end

  defp persist(%{pending: :save, account: account} = state) do
    Login.save(account)

    %{state | pending: nil}
  end

  defp persist(%{pending: :clear} = state) do
    Login.clear()

    %{state | pending: nil}
  end

  defp persist(state), do: state

  # Nothing can be sent before there is an address to send it from.
  defp start(%{mode: :sending, worker: nil} = state) do
    case Wifi.status() do
      %{radio: :connected} -> spawn_worker(state)
      _down -> failed(state, :no_wifi)
    end
  end

  defp start(state), do: state

  defp spawn_worker(state) do
    base = Login.server()
    email = Field.value(state.field)

    :io.format(~c"Login: starting for ~s at ~s~n", [email, base])

    pid = spawn(fn -> Login.flow(base, email, &deliver/1) end)
    Process.monitor(pid)

    %{state | worker: pid}
  end

  # Badge.UI owns the mailbox every page reads through, and it can restart.
  defp deliver(message) do
    case Process.whereis(Badge.UI) do
      nil -> :ok
      ui -> Kernel.send(ui, message)
    end
  end

  defp animate(%{mode: :waiting} = state), do: %{state | ticks: state.ticks + 1}
  defp animate(state), do: state

  @impl true
  def handle_info({:login, {:sent, _token}}, %{mode: :sending} = state) do
    :io.format(~c"Login: sent, waiting for the link~n")

    {:ok, %{state | mode: :waiting, ticks: 0}}
  end

  def handle_info({:login, {:verified, account}}, %{mode: mode} = state)
      when mode in [:sending, :waiting] do
    :io.format(~c"Login: verified ~s as ~s~n", [account.email, Login.role_name(account.role)])

    {:ok, %{state | mode: :signed_in, account: account, pending: :save, worker: nil}}
  end

  def handle_info({:login, {:failed, reason}}, %{mode: mode} = state)
      when mode in [:sending, :waiting] do
    :io.format(~c"Login: failed ~p~n", [reason])

    {:ok, failed(state, reason)}
  end

  # A worker that died without answering is a failure; one that answered has just finished.
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{worker: pid, mode: mode} = state)
      when mode in [:sending, :waiting] do
    {:ok, failed(state, {:down, reason})}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{worker: pid} = state) do
    {:ok, %{state | worker: nil}}
  end

  def handle_info(_message, _state), do: :ignore

  defp failed(state, reason), do: %{state | mode: :failed, error: reason, worker: nil}

  # A wait that is walked away from is over; the server forgets it on its own.
  @impl true
  def leave(%{worker: nil}), do: :ok

  def leave(%{worker: pid}) do
    :erlang.exit(pid, :kill)

    :ok
  end

  @impl true
  def render(%{mode: :entry} = state) do
    [
      text(@margin, @label_y, "Email", Theme.dim()),
      text(@margin, @value_y, caret(state.field), Theme.select()),
      text(@margin, @note_y, "We mail you a link. Open it", Theme.muted()),
      text(@margin, @note_y + @pitch, "and this badge signs in.", Theme.muted()),
      centred(@hint_y, "Enter send   Esc home", Theme.dim())
    ]
  end

  def render(%{mode: :sending} = state) do
    [
      text(@margin, @label_y, "Email", Theme.dim()),
      text(@margin, @value_y, Field.value(state.field), Theme.fg()),
      text(@margin, @note_y, "Asking the site for a link...", Theme.muted()),
      centred(@hint_y, "Esc cancel", Theme.dim())
    ]
  end

  def render(%{mode: :waiting} = state) do
    [
      text(@margin, @label_y, "Check your inbox", Theme.fg()),
      text(@margin, @value_y, Field.value(state.field), Theme.muted()),
      text(@margin, @note_y, "Open the link we sent, then", Theme.muted()),
      text(@margin, @note_y + @pitch, "look back here.", Theme.muted()),
      text(@margin, @note_y + 2 * @pitch, "Waiting" <> dots(state.ticks), Theme.dim()),
      centred(@hint_y, "Esc cancel", Theme.dim())
    ]
  end

  def render(%{mode: :signed_in, account: account}) do
    [
      centred(@label_y, "Signed in", Theme.dim()),
      centred(@value_y, account.email, Theme.fg()),
      centred(@value_y + @pitch + 4, Login.role_name(account.role), Theme.ok()),
      centred(@hint_y, "X sign out   Esc home", Theme.dim())
    ]
  end

  def render(%{mode: :failed} = state) do
    [
      text(@margin, @label_y, "Could not sign in", Theme.alert()),
      text(@margin, @value_y, Login.describe(state.error), Theme.muted()),
      centred(@hint_y, "Enter retry   Esc home", Theme.dim())
    ]
  end

  defp caret(field) do
    value = Field.value(field)
    at = Field.cursor(field)

    :binary.part(value, 0, at) <> "_" <> :binary.part(value, at, byte_size(value) - at)
  end

  defp dots(ticks) do
    :erlang.list_to_binary(:lists.duplicate(rem(div(ticks, @dot_ticks), @dots), ?.))
  end

  defp text(x, y, body, colour), do: {:text, x, y, :default16px, colour, Theme.bg(), body}

  defp centred(y, body, colour) do
    text(div(Theme.width() - @char_w * byte_size(body), 2), y, body, colour)
  end
end
