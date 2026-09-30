defmodule Badge.Display.Lvgl.FrameTest do
  use ExUnit.Case, async: true

  alias Badge.Display.Lvgl.Frame

  @bg {:rect, 0, 0, 320, 240, 0x000000}
  @title {:text, 6, 3, :pixel_operator, 0xFFFFFF, 0x000000, "Badge"}
  @icon {:image, 280, 3, 0x000000, {:rgba8888, 2, 1, <<1, 2, 3, 255, 4, 5, 6, 255>>}}

  defp run(frames) do
    :lists.foldl(
      fn items, {_ops, state} -> Frame.frame(state, items) end,
      {[], Frame.new()},
      frames
    )
  end

  describe "the first frame" do
    test "resets the panel, then builds every object bottom up" do
      {ops, _state} = Frame.frame(Frame.new(), [@title, @bg])

      assert ops == [
               {:reset},
               {:new, 0, :box},
               {:set, 0, [x: 0, y: 0, w: 320, h: 240, bg: 0x000000]},
               {:new, 1, :label},
               {:set, 1, [x: 6, y: 3, font: 2, fg: 0xFFFFFF, bg: -1, text: "Badge"]}
             ]
    end

    test "uploads an image once, before the object that shows it" do
      {ops, _state} = Frame.frame(Frame.new(), [@icon, @icon, @bg])

      assert [{:reset}, {:img, 0, :rgba8888, 2, 1, _pixels} | rest] = ops
      refute Enum.any?(rest, &match?({:img, _, _, _, _, _}, &1))
      assert {:set, 1, [x: 280, y: 3, w: 2, h: 1, src: 0, sx: 256, sy: 256, ox: 0, oy: 0]} in rest
      assert {:set, 2, [x: 280, y: 3, w: 2, h: 1, src: 0, sx: 256, sy: 256, ox: 0, oy: 0]} in rest
    end
  end

  describe "later frames" do
    test "an unchanged frame sends nothing" do
      {ops, _state} = run([[@title, @icon, @bg], [@title, @icon, @bg]])

      assert ops == []
    end

    test "a changed item sends only the properties that changed" do
      moved = {:text, 6, 3, :pixel_operator, 0xFFFFFF, 0x000000, "Name"}
      {ops, _state} = run([[@title, @bg], [moved, @bg]])

      assert ops == [{:set, 1, [text: "Name"]}]
    end

    test "a different kind of item replaces the object" do
      {ops, _state} = run([[@title, @bg], [{:rect, 10, 10, 5, 5, 0xFF0000}, @bg]])

      assert ops == [{:new, 1, :box}, {:set, 1, [x: 10, y: 10, w: 5, h: 5, bg: 0xFF0000]}]
    end

    test "fewer items delete the objects above them, from the top" do
      {ops, _state} = run([[@title, @icon, @bg], [@bg]])

      assert [{:del, 2}, {:del, 1}, {:unimg, 0}] = ops
    end

    test "more items create objects on top" do
      {ops, _state} = run([[@bg], [@title, @bg]])

      assert [{:new, 1, :label}, {:set, 1, _props}] = ops
    end

    test "an image nothing draws any more is freed after the objects move off it" do
      other = {:image, 280, 3, 0, {:rgba8888, 1, 1, <<9, 9, 9, 255>>}}
      {ops, state} = run([[@icon, @bg], [other, @bg]])

      assert [{:img, 1, :rgba8888, 1, 1, _}, {:set, 1, props}, {:unimg, 0}] = ops
      assert props[:src] == 1
      assert map_size(state.images) == 1
    end
  end

  describe "text" do
    test "the built-in font's code page 437 bytes travel as codepoints of the same value" do
      {ops, _state} = Frame.frame(Frame.new(), [{:text, 0, 0, :default16px, 1, 0, <<0xC9, ?A>>}])

      assert {:set, 0, props} = List.last(ops)
      assert props[:text] == <<0xC9::utf8, ?A>>
      assert props[:font] == 0
    end

    test "plain ASCII is passed through as it is" do
      {ops, _state} = Frame.frame(Frame.new(), [{:text, 0, 0, :default16px, 1, 0, "hi"}])

      assert List.last(ops) |> elem(2) |> Keyword.get(:text) == "hi"
    end

    test "charlists become binaries" do
      {ops, _state} = Frame.frame(Frame.new(), [{:text, 0, 0, :dogica, 1, 0, ~c"hi"}])

      assert List.last(ops) |> elem(2) |> Keyword.get(:text) == "hi"
    end

    test "a background of 0 is none, any other colour fills behind the text" do
      {ops, _state} =
        Frame.frame(Frame.new(), [
          {:text, 0, 0, :dogica, 1, 0x000000, "a"},
          {:text, 0, 0, :dogica, 1, 0x112233, "b"}
        ])

      backgrounds = for {:set, _i, props} <- ops, do: props[:bg]
      assert backgrounds == [0x112233, -1]
    end
  end

  describe "marquees" do
    test "are created once, as LVGL's own scrolling label, and cost nothing after" do
      item = {:marquee, 0, 90, 320, :dogica, 0xFFFFFF, 0, "@Goatmire International", 80}
      {ops, state} = Frame.frame(Frame.new(), [item])

      assert [{:reset}, {:new, 0, :marquee}, {:set, 0, props}] = ops

      assert props == [
               x: 0,
               y: 90,
               w: 320,
               font: 1,
               fg: 0xFFFFFF,
               bg: -1,
               text: "@Goatmire International",
               speed: 80
             ]

      assert Frame.frame(state, [item]) |> elem(0) == []
    end
  end

  describe "effect labels" do
    test "are an LVGL label told which effect to play, sent once" do
      item =
        {:fx_label, 0, 20, :default16px, 0xE85FAF, 0, "GUS",
         {:rain, :out, 19, 200, 4, false, true}}

      {ops, state} = Frame.frame(Frame.new(), [item])

      assert [{:reset}, {:new, 0, :label}, {:set, 0, props}] = ops

      assert props == [
               x: 0,
               y: 20,
               font: 0,
               fg: 0xE85FAF,
               bg: -1,
               text: "GUS",
               fx: 2,
               fx_dir: 1,
               fx_steps: 19,
               fx_ms: 200,
               fx_row: 4,
               fx_left: 0,
               fx_noise: 1
             ]

      assert Frame.frame(state, [item]) |> elem(0) == []
    end
  end

  describe "scaled, cropped images" do
    test "scale by whole factors from the crop's corner" do
      pixels = :binary.copy(<<0, 0, 0, 255>>, 4)
      item = {:scaled_cropped_image, 10, 20, 8, 8, 0, 1, 1, 4, 4, [], {:rgba8888, 2, 2, pixels}}
      {ops, _state} = Frame.frame(Frame.new(), [item])

      assert {:set, 0, [x: 10, y: 20, w: 8, h: 8, src: 0, sx: 1024, sy: 1024, ox: -1, oy: -1]} =
               List.last(ops)
    end
  end

  describe "fonts" do
    test "have fixed ids, with unknown fonts drawn in the built-in one" do
      assert Frame.font_id(:default16px) == 0
      assert Frame.font_id(:dogica) == 1
      assert Frame.font_id(:pixel_operator) == 2
      assert Frame.font_id(:w95fa) == 3
      assert Frame.font_id(:comic_sans) == 0
    end
  end
end
