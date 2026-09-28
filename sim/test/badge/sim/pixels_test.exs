defmodule Badge.Sim.PixelsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Badge.Pixels

  setup do
    start_supervised!(Badge.Sim.Nvs)
    on_exit(fn -> Application.delete_env(:avm_badge, :spi_fails) end)
    :ok
  end

  defp start do
    pid = start_supervised!({Pixels, :sim_spi})
    Process.group_leader(pid, Process.group_leader())
    pid
  end

  defp run_ticks, do: Process.sleep(900)

  test "a failed write drops the frame instead of crashing the chain" do
    log =
      capture_io(fn ->
        pid = start()
        Application.put_env(:avm_badge, :spi_fails, true)
        run_ticks()

        assert Process.alive?(pid)
        assert Pixels.mode() == :rainbow
      end)

    assert log =~ "Pixels: write failed {error,257}"
  end

  test "failures are logged once, and recovery once" do
    log =
      capture_io(fn ->
        start()
        Application.put_env(:avm_badge, :spi_fails, true)
        run_ticks()
        Application.put_env(:avm_badge, :spi_fails, false)
        run_ticks()
      end)

    assert length(String.split(log, "write failed")) == 2
    assert length(String.split(log, "writing again")) == 2
  end

  test "a static mode is retried until a write lands" do
    capture_io(fn ->
      pid = start()
      Application.put_env(:avm_badge, :spi_fails, true)
      Pixels.set_mode(:white)
      run_ticks()

      assert :sys.get_state(pid).last == nil

      Application.put_env(:avm_badge, :spi_fails, false)
      run_ticks()

      assert :sys.get_state(pid).last == {40, 40, 40}
    end)
  end
end
