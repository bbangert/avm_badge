defmodule Badge.Autopilot do
  @moduledoc """
  Replays a fixed sequence of key events after boot, for headless testing.

  There is no way into a running badge from outside: AtomVM's ESP32 port has
  no console input, and the one free UART carries the IR beam. So a test that
  nobody is standing over drives the UI from a script compiled into the
  firmware, and reports what it did on the console.

  The script is empty in a normal build and `start/0` does nothing. Fill it
  in, flash, and read the console. Keep it short: a long script will not load
  on AtomVM, and the compiler refuses one past the step limit.

      @script [
        {2_000, {:nav, :diamond}},
        {500, {:move, :right}},
        {500, {:move, :right}}
      ]
  """

  alias Badge.UI

  # {milliseconds to wait first, event to send}
  @script []

  # A long script becomes one large literal, and AtomVM fails loading the
  # module's literals table rather than starting: 1000 steps bricks the boot.
  # The real ceiling is unmeasured, so this sits well under it.
  @step_limit 32

  length(@script) <= @step_limit ||
    raise "autopilot script is #{length(@script)} steps; more than #{@step_limit} will not load"

  @doc "Replays the compiled-in script, or does nothing when there is none."
  @spec start() :: :ok
  def start, do: start(@script)

  @doc "Replays a script in its own process."
  @spec start([{non_neg_integer, tuple}]) :: :ok
  def start([]), do: :ok

  # Unlinked, so a script that outlives its usefulness cannot take the badge down.
  def start(script) do
    spawn(fn -> replay(script) end)

    :ok
  end

  @doc "The script this build was compiled with."
  @spec script() :: [{non_neg_integer, tuple}]
  def script, do: @script

  defp replay([]), do: :io.format(~c"Autopilot: script done~n")

  defp replay([{wait, event} | rest]) do
    Process.sleep(wait)
    :io.format(~c"Autopilot: ~p~n", [event])
    UI.key_event(event)

    replay(rest)
  end
end
