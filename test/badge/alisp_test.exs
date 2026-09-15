defmodule Badge.AlispTest do
  use ExUnit.Case, async: true

  alias Badge.Alisp

  describe "feed/2" do
    test "a closed form is ready to evaluate and resets the session" do
      assert {:eval, session, [:+, 1, 2]} = Alisp.feed(Alisp.new(), "(+ 1 2)")
      refute Alisp.pending?(session)
    end

    test "an open form waits for more lines" do
      assert {:pending, session} = Alisp.feed(Alisp.new(), "(list 1")
      assert Alisp.pending?(session)
      assert {:eval, _session, [:list, 1, 2]} = Alisp.feed(session, "2)")
    end

    test "an empty line changes nothing" do
      {:pending, session} = Alisp.feed(Alisp.new(), "(list 1")

      assert Alisp.feed(session, "") == {:pending, session}
    end

    test "a stray closing paren is an error and drops what was pending" do
      {:pending, session} = Alisp.feed(Alisp.new(), "(list 1")

      assert {:error, reset, "unbalanced )"} = Alisp.feed(session, "))")
      refute Alisp.pending?(reset)
    end

    test "two forms on one line are refused" do
      assert {:error, _session, "one form at a time"} = Alisp.feed(Alisp.new(), "(+ 1 2) (+ 3 4)")
    end

    test "a lone literal or symbol is a form of its own" do
      assert {:eval, _session, 42} = Alisp.feed(Alisp.new(), "42")
      assert {:eval, _session, "hi"} = Alisp.feed(Alisp.new(), "\"hi\"")
      assert {:eval, _session, :x} = Alisp.feed(Alisp.new(), "x")
    end

    test "a module call parses to a symbol pair" do
      assert {:eval, _session, [[:symbol_pair, :erlang, :length], [:quote, [1, 2]]]} =
               Alisp.feed(Alisp.new(), "(erlang:length (quote (1 2)))")
    end
  end

  describe "run/1" do
    test "evaluates and prints" do
      assert Alisp.run([:+, 1, 2]) == {:ok, "3"}
      assert Alisp.run([:list, 1, "a", [:quote, :b]]) == {:ok, "(1 \"a\" b)"}
    end

    test "an unbound symbol is an error, not a crash" do
      assert {:error, text} = Alisp.run(:nope)
      assert text == "(tuple throw (tuple unbound nope))"
    end

    test "a crash inside a call is an error, not a crash" do
      assert {:error, _text} = Alisp.run([:car, 1])
    end

    test "long output is clipped" do
      {:ok, text} = Alisp.run([:quote, :lists.seq(1, 500)])

      assert byte_size(text) == 240
      assert :binary.part(text, 237, 3) == "..."
    end
  end

  describe "worker" do
    test "answers the owner and keeps variables between forms" do
      worker = Alisp.start(self())

      Alisp.eval(worker, [:setq, :x, 5])
      assert_receive {:alisp, ^worker, {:ok, "5"}}

      Alisp.eval(worker, [:*, :x, 2])
      assert_receive {:alisp, ^worker, {:ok, "10"}}

      Alisp.stop(worker)
    end

    test "survives a form that throws" do
      worker = Alisp.start(self())

      Alisp.eval(worker, :nope)
      assert_receive {:alisp, ^worker, {:error, _text}}

      Alisp.eval(worker, 1)
      assert_receive {:alisp, ^worker, {:ok, "1"}}

      Alisp.stop(worker)
    end

    test "stop kills it" do
      worker = Alisp.start(self())
      ref = Process.monitor(worker)

      Alisp.stop(worker)

      assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
    end
  end
end
