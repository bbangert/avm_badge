defmodule Badge.Page.Settings.PlaceholdersTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Settings
  alias Badge.Theme

  @placeholders [Settings.Update, Settings.Sudo]

  describe "the tabs that are not built yet" do
    test "each names itself for the strip" do
      for module <- @placeholders do
        assert byte_size(module.title()) > 0
      end
    end

    test "each says plainly that it does nothing" do
      for module <- @placeholders do
        bodies = for {:text, _x, _y, _f, _c, _b, body} <- module.render(module.init()), do: body

        assert Enum.any?(bodies, fn body -> :binary.match(body, "not built") != :nomatch end)
      end
    end

    test "none traps escape" do
      for module <- @placeholders do
        assert module.handle_key({:nav, :home}, module.init()) == :ignore
      end
    end

    test "none takes the arrows, so the carousel keeps working" do
      for module <- @placeholders do
        assert module.handle_key({:move, :left}, module.init()) == :ignore
        assert module.handle_key({:move, :right}, module.init()) == :ignore
      end
    end

    test "each draws inside the content area" do
      for module <- @placeholders do
        for {:text, x, y, _f, _c, _b, body} <- module.render(module.init()) do
          assert y >= Settings.content_top()
          assert y < Theme.height()
          assert x >= 0
          assert x + 8 * byte_size(body) <= Theme.width()
        end
      end
    end
  end
end
