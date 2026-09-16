defmodule Badge.Page.LoginTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Login

  @account %{email: "me@example.com", role: :attendee}

  defp type(state, string) do
    :lists.foldl(
      fn char, acc ->
        {:ok, next} = Login.handle_key({:char, char}, acc)
        next
      end,
      state,
      :erlang.binary_to_list(string)
    )
  end

  defp press(state, event) do
    {:ok, next} = Login.handle_key(event, state)
    next
  end

  defp texts(items) do
    for {:text, _x, _y, _font, _fg, _bg, body} <- items, do: body
  end

  defp entered, do: type(Login.init(), "me@example.com")

  defp sending, do: press(entered(), {:edit, :newline})

  defp waiting do
    {:ok, state} = Login.handle_info({:login, {:sent, "tok"}}, %{sending() | worker: self()})
    state
  end

  defp signed_in do
    {:ok, state} = Login.handle_info({:login, {:verified, @account}}, waiting())
    state
  end

  describe "identity" do
    test "announces itself for the apps grid" do
      assert Login.title() == "Login"
    end

    test "opens on an empty email, not yet loaded" do
      state = Login.init()

      assert Login.mode(state) == :entry
      assert Login.email(state) == ""
      assert Login.account(state) == nil
      refute state.loaded
    end

    test "only the wait animates faster than the default" do
      assert Login.refresh(Login.init()) == 100
      assert Login.refresh(waiting()) == 250
    end
  end

  describe "typing" do
    test "builds the email with a caret on the panel" do
      state = entered()

      assert Login.email(state) == "me@example.com"
      assert "me@example.com_" in texts(Login.render(state))
    end

    test "backspace and the arrows edit in place" do
      state =
        entered() |> press({:move, :left}) |> press({:move, :left}) |> press({:edit, :backspace})

      assert Login.email(state) == "me@example.om"

      state = state |> press({:move, :right}) |> type("x")

      assert Login.email(state) == "me@example.oxm"
    end

    test "stops at the width of the panel less the caret" do
      state = type(Login.init(), :erlang.list_to_binary(:lists.duplicate(60, ?a)))

      assert byte_size(Login.email(state)) == 37
    end

    test "enter on an empty email is left to the router" do
      assert Login.handle_key({:edit, :newline}, Login.init()) == :ignore
    end

    test "enter with an email starts sending" do
      assert Login.mode(sending()) == :sending
      assert "Sending..." in texts(Login.render(sending()))
    end

    test "shape keys and escape are never trapped, on any screen" do
      for state <- [Login.init(), entered(), sending(), waiting(), signed_in()],
          key <- [:home, :square, :triangle, :cross, :circle, :clover, :diamond] do
        assert Login.handle_key({:nav, key}, state) == :ignore
      end
    end

    test "typing while sending or waiting does nothing" do
      assert Login.handle_key({:char, ?a}, sending()) == :ignore
      assert Login.handle_key({:edit, :newline}, waiting()) == :ignore
    end
  end

  describe "messages from the worker" do
    test "sent moves to waiting and shows the inbox hint" do
      state = waiting()

      assert Login.mode(state) == :waiting
      assert "Check your inbox" in texts(Login.render(state))
      assert "me@example.com" in texts(Login.render(state))
    end

    test "verified signs in, shows the account and asks for it to be saved" do
      state = signed_in()

      assert Login.mode(state) == :signed_in
      assert Login.account(state) == @account
      assert state.pending == :save
      assert state.worker == nil

      shown = texts(Login.render(state))

      assert "Signed in" in shown
      assert "me@example.com" in shown
      assert "attendee" in shown
    end

    test "failed shows the reason and offers a retry" do
      {:ok, state} = Login.handle_info({:login, {:failed, :timeout}}, waiting())

      assert Login.mode(state) == :failed
      assert state.worker == nil
      assert "no confirmation in time" in texts(Login.render(state))

      assert Login.mode(press(state, {:edit, :newline})) == :entry
      assert Login.email(press(state, {:edit, :newline})) == "me@example.com"
    end

    test "a worker that dies mid-wait is a failure" do
      state = waiting()
      {:ok, next} = Login.handle_info({:DOWN, make_ref(), :process, self(), :killed}, state)

      assert Login.mode(next) == :failed
      assert next.error == {:down, :killed}
    end

    test "a worker finishing after it answered is merely forgotten" do
      state = %{signed_in() | worker: self()}
      {:ok, next} = Login.handle_info({:DOWN, make_ref(), :process, self(), :normal}, state)

      assert Login.mode(next) == :signed_in
      assert next.worker == nil
    end

    test "anything stale or unknown is ignored" do
      assert Login.handle_info({:login, {:sent, "tok"}}, Login.init()) == :ignore
      assert Login.handle_info({:login, {:verified, @account}}, signed_in()) == :ignore

      assert Login.handle_info({:DOWN, make_ref(), :process, self(), :normal}, waiting()) ==
               {:ok, %{waiting() | mode: :failed, error: {:down, :normal}, worker: nil}}

      assert Login.handle_info(:whatever, waiting()) == :ignore
    end
  end

  describe "signing out" do
    test "x clears the account, asks for it to be forgotten and keeps the email" do
      state = press(%{signed_in() | pending: nil}, {:char, ?x})

      assert Login.mode(state) == :entry
      assert Login.account(state) == nil
      assert state.pending == :clear
      assert Login.email(state) == "me@example.com"
    end

    test "any other key while signed in is left alone" do
      assert Login.handle_key({:char, ?a}, signed_in()) == :ignore
      assert Login.handle_key({:edit, :newline}, signed_in()) == :ignore
    end
  end

  describe "render/1" do
    test "every screen renders text items only, with a hint at the bottom" do
      {:ok, failed} = Login.handle_info({:login, {:failed, {:http, 500}}}, waiting())

      for state <- [Login.init(), entered(), sending(), waiting(), signed_in(), failed] do
        items = Login.render(state)

        for item <- items do
          assert {:text, _x, _y, :default16px, _fg, _bg, body} = item
          assert byte_size(body) <= 38
        end

        assert Enum.any?(items, fn {:text, _x, y, _f, _fg, _bg, _b} -> y == 216 end)
      end
    end

    test "the waiting dots advance with the ticks" do
      state = %{waiting() | loaded: true}

      lines =
        for n <- 0..12,
            do:
              hd(
                for t <- texts(Login.render(%{state | ticks: n})),
                    match?("Waiting" <> _, t),
                    do: t
              )

      assert Enum.uniq(lines) == ["Waiting", "Waiting.", "Waiting..", "Waiting..."]
    end
  end

  describe "leave/1" do
    test "with no worker there is nothing to do" do
      assert Login.leave(Login.init()) == :ok
    end

    test "kills the worker" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      assert Login.leave(%{Login.init() | worker: pid}) == :ok

      Process.sleep(10)
      refute Process.alive?(pid)
    end
  end

  describe "tick/1" do
    test "with nothing pending on a loaded page is a no-op" do
      state = %{entered() | loaded: true}

      assert Login.tick(state) == state
    end

    test "counts ticks only while waiting" do
      state = %{waiting() | loaded: true}

      assert Login.tick(state).ticks == 1
      assert Login.tick(%{signed_in() | loaded: true, pending: nil}).ticks == 0
    end
  end
end
