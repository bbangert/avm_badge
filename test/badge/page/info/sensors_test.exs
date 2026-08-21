defmodule Badge.Page.Info.SensorsTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Info
  alias Badge.Page.Info.Sensors
  alias Badge.Theme

  defp reading(overrides), do: Map.merge(%{temp: 24, accel: {0, 0, 1000}}, overrides)

  defp texts(state),
    do: for({:text, _x, _y, _f, _fg, _bg, body} <- Sensors.render(state), do: body)

  defp shows?(state, needle) do
    Enum.any?(texts(state), fn body -> :binary.match(body, needle) != :nomatch end)
  end

  describe "identity" do
    test "names itself for the tab strip" do
      assert Sensors.title() == "Sensors"
    end

    test "does not trap escape" do
      assert Sensors.handle_key({:nav, :home}, Sensors.init()) == :ignore
    end

    test "leaves the arrows to the carousel" do
      assert Sensors.handle_key({:move, :left}, Sensors.init()) == :ignore
      assert Sensors.handle_key({:move, :right}, Sensors.init()) == :ignore
    end
  end

  describe "render/1" do
    test "renders from a literal reading with no hardware" do
      state = Sensors.update(Sensors.init(), reading(%{}))

      assert shows?(state, "24")
      assert shows?(state, "1000")
    end

    test "an unavailable temperature does not crash" do
      state = Sensors.update(Sensors.init(), reading(%{temp: :unavailable}))

      assert is_list(Sensors.render(state))
      assert shows?(state, "--")
    end

    test "shows all three accelerometer axes" do
      state = Sensors.update(Sensors.init(), reading(%{accel: {-68, 850, -560}}))

      assert shows?(state, "-60")
      assert shows?(state, "850")
      assert shows?(state, "-560")
    end

    test "the accelerometer readout is rounded, so noise does not repaint" do
      steady = Sensors.update(Sensors.init(), reading(%{accel: {-68, 850, -560}}))
      jittered = Sensors.update(Sensors.init(), reading(%{accel: {-61, 856, -566}}))

      assert steady == jittered
    end

    test "init renders before any reading arrives" do
      assert is_list(Sensors.render(Sensors.init()))
    end

    test "draws below the tab strip and inside the panel" do
      state = Sensors.update(Sensors.init(), reading(%{}))

      for {:text, _x, y, _f, _fg, _bg, _body} <- Sensors.render(state) do
        assert y >= Info.content_top()
        assert y < Theme.height()
      end
    end
  end
end
