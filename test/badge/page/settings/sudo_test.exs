defmodule Badge.Page.Settings.SudoTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Settings
  alias Badge.Page.Settings.Sudo
  alias Badge.Rickroll
  alias Badge.Theme

  describe "identity" do
    test "names itself for the tab strip" do
      assert Sudo.title() == "Sudo Mode"
    end

    test "never repaints for the loop, which the panel plays by itself" do
      assert Sudo.refresh(Sudo.init()) >= 10_000
      assert Sudo.tick(Sudo.init()) == Sudo.init()
    end

    test "holds each frame long enough to see" do
      assert Sudo.frame_ms() >= 150
    end
  end

  describe "the loop" do
    test "starts at the beginning" do
      assert Sudo.init() == 0
    end

    test "advances one frame per interval" do
      assert Sudo.frame_at(0) == 0
      assert Sudo.frame_at(Sudo.frame_ms()) == 1
      assert Sudo.frame_at(Sudo.frame_ms() * 2) == 2
    end

    test "holds the same frame throughout its interval, so the panel stays still" do
      for offset <- [0, 1, 99, Sudo.frame_ms() - 1] do
        assert Sudo.frame_at(Sudo.frame_ms() * 3 + offset) == 3
      end
    end

    test "wraps back round rather than growing without bound" do
      count = Rickroll.count()

      assert Sudo.frame_at(Sudo.frame_ms() * count) == 0
      assert Sudo.frame_at(Sudo.frame_ms() * (count * 4 + 2)) == 2
    end

    test "never lands outside the frames it has" do
      for step <- 0..200 do
        frame = Sudo.frame_at(step * 37)

        assert frame >= 0
        assert frame < Rickroll.count()
      end
    end

    test "the flipbook carries every frame, a frame interval each" do
      [{:flipbook, _x, _y, _scale, ms, pictures} | _rest] = Sudo.render(0)

      assert ms == Sudo.frame_ms()
      assert length(pictures) == Rickroll.count()
    end

    test "every frame renders" do
      for frame <- 0..(Rickroll.count() - 1) do
        assert [_image, _caption] = Sudo.render(frame)
      end
    end
  end

  describe "keys" do
    test "escape is not trapped, so you can always get out" do
      assert Sudo.handle_key({:nav, :home}, Sudo.init()) == :ignore
    end

    test "the arrows are left alone, so the carousel still slides" do
      assert Sudo.handle_key({:move, :left}, Sudo.init()) == :ignore
      assert Sudo.handle_key({:move, :right}, Sudo.init()) == :ignore
    end
  end

  describe "render/1" do
    test "the image clears the tab rule rather than butting against it" do
      [{:flipbook, _x, y, _scale, _ms, _pictures} | _rest] =
        Sudo.render(0)

      assert y > Settings.content_top()
    end

    test "the caption lands on the same line other pages put their help on" do
      [_image, {:text, _x, y, _f, _c, _b, _body}] = Sudo.render(0)

      assert y == 216
    end

    test "the image is centred and sits inside the content area" do
      [{:flipbook, x, y, scale, _ms, [{:rgba8888, w, h, _px} | _more]} | _rest] =
        Sudo.render(0)

      {w, h} = {w * scale, h * scale}

      assert x == div(Theme.width() - w, 2)
      assert y >= Settings.content_top()
      assert y + h < Theme.height()
    end

    test "the caption clears the image and fits the panel" do
      [
        {:flipbook, _x, y, scale, _ms, [{:rgba8888, _w, h, _px} | _more]},
        {:text, cx, cy, _f, _c, _b, body}
      ] = Sudo.render(0)

      h = h * scale

      assert cy >= y + h
      assert cy + 16 <= Theme.height()
      assert cx >= 0
      assert cx + 8 * byte_size(body) <= Theme.width()
    end
  end
end
