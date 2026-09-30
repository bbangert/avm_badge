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

  describe "motion" do
    test "adds LVGL's glide to any item, as an object of its own kind" do
      item = {:motion, {:rect, 10, 20, 5, 5, 0xFF0000}, {8, 0, :in, 300, 200, :overshoot}}
      {ops, _state} = Frame.frame(Frame.new(), [item])

      assert [{:reset}, {:new, 0, :box}, {:set, 0, props}] = ops

      assert props == [
               x: 10,
               y: 20,
               w: 5,
               h: 5,
               bg: 0xFF0000,
               mx: 8,
               my: 0,
               mdir: 0,
               mdelay: 300,
               mms: 200,
               mease: 2
             ]
    end

    test "a moving image keeps its picture alive" do
      pixels = <<1, 2, 3, 255>>
      image = {:image, 0, 0, 0, {:rgba8888, 1, 1, pixels}}
      {_ops, state} = Frame.frame(Frame.new(), [{:motion, image, {0, 4, :out, 0, 100, :linear}}])
      {ops, _state} = Frame.frame(state, [{:motion, image, {0, 4, :out, 0, 100, :linear}}])

      assert ops == []
      assert map_size(state.images) == 1
    end
  end

  describe "fingerprints" do
    test "one picture drawn many times is uploaded once" do
      pixels = :binary.copy(<<7, 7, 7, 255>>, 64)
      items = for x <- 1..20, do: {:image, x, 0, 0, {:rgba8888, 8, 8, pixels}}
      {ops, state} = Frame.frame(Frame.new(), items)

      assert length(for {:img, _, _, _, _, _} <- ops, do: 1) == 1
      assert [{^pixels, _key}] = state.recent
    end
  end

  describe "scaled, cropped images" do
    @pixels :binary.copy(<<0, 0, 0, 255>>, 4)

    test "an even scale is uploaded enlarged once, then drawn from the crop's corner unscaled" do
      item = {:scaled_cropped_image, 10, 20, 8, 8, 0, 1, 1, 4, 4, [], {:rgba8888, 2, 2, @pixels}}
      {ops, _state} = Frame.frame(Frame.new(), [item])

      assert {:img, 0, :rgba8888, 2, 2, @pixels, 4} in ops

      assert {:set, 0, [x: 10, y: 20, w: 8, h: 8, src: 0, sx: 256, sy: 256, ox: -4, oy: -4]} =
               List.last(ops)
    end

    test "the same picture at another scale is a separate upload" do
      twice = {:scaled_cropped_image, 0, 0, 4, 4, 0, 0, 0, 2, 2, [], {:rgba8888, 2, 2, @pixels}}
      thrice = {:scaled_cropped_image, 0, 0, 6, 6, 0, 0, 0, 3, 3, [], {:rgba8888, 2, 2, @pixels}}
      {ops, _state} = Frame.frame(Frame.new(), [twice, thrice])

      assert length(for {:img, _, _, _, _, _, _} <- ops, do: 1) == 2
    end

    test "uneven scales are left to LVGL" do
      item = {:scaled_cropped_image, 0, 0, 4, 6, 0, 0, 0, 2, 3, [], {:rgba8888, 2, 2, @pixels}}
      {ops, _state} = Frame.frame(Frame.new(), [item])

      assert {:img, 0, :rgba8888, 2, 2, @pixels} in ops

      assert {:set, 0, [x: 0, y: 0, w: 4, h: 6, src: 0, sx: 512, sy: 768, ox: 0, oy: 0]} =
               List.last(ops)
    end
  end

  describe "flipbooks" do
    @red {:rgba8888, 1, 1, <<255, 0, 0, 255>>}
    @blue {:rgba8888, 1, 1, <<0, 0, 255, 255>>}
    @book {:flipbook, 10, 20, 3, 200, [@red, @blue]}

    test "uploads every picture enlarged, then names them in order" do
      {ops, _state} = Frame.frame(Frame.new(), [@book, @bg])

      assert {:img, 0, :rgba8888, 1, 1, _red, 3} = :lists.nth(2, ops)
      assert {:img, 1, :rgba8888, 1, 1, _blue, 3} = :lists.nth(3, ops)
      assert {:new, 1, :flipbook} in ops

      assert {:set, 1,
              [x: 10, y: 20, w: 3, h: 3, frames: <<0::16-little, 1::16-little>>, frame_ms: 200]} in ops
    end

    test "keeps its pictures while it shows and frees them once it goes" do
      {_ops, state} = run([[@book, @bg]])
      {same, state} = Frame.frame(state, [@book, @bg])
      {gone, _state} = Frame.frame(state, [@bg])

      assert same == []
      assert {:unimg, 0} in gone and {:unimg, 1} in gone
    end
  end

  describe "gliding" do
    test "sends the glide time after the position, and later only the new position" do
      {ops, state} = Frame.frame(Frame.new(), [{:glide, @icon, 300}, @bg])
      {moved, _state} = Frame.frame(state, [{:glide, put_elem(@icon, 1, 290), 300}, @bg])

      assert {:set, 1,
              [x: 280, y: 3, w: 2, h: 1, src: 0, sx: 256, sy: 256, ox: 0, oy: 0, glide: 300]} in ops

      assert moved == [{:set, 1, [x: 290]}]
    end
  end

  describe "image ids" do
    test "reuse the lowest one freed, so a slideshow never runs out" do
      pictures = for n <- 1..300, do: {:image, 0, 0, 0, {:rgba8888, 1, 1, <<n::32>>}}

      {ops, _state} = run(for picture <- pictures, do: [picture, @bg])

      assert [{:img, id, :rgba8888, 1, 1, _}] = for({:img, _, _, _, _, _} = op <- ops, do: op)
      assert id < 2
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
