defmodule Badge.IconsTest do
  use ExUnit.Case, async: true

  alias Badge.Icons
  alias Badge.Theme

  @shapes [:circle, :clover, :cross, :diamond, :square, :triangle]
  @status [
    :battery_0,
    :battery_100,
    :battery_25,
    :battery_50,
    :battery_75,
    :battery_charging,
    :messages,
    :wifi,
    :wifi_slash,
    :signal_0,
    :signal_1,
    :signal_2,
    :signal_3
  ]

  defp pixels(name), do: for(<<px::binary-4 <- Icons.binary(name)>>, do: px)

  defp bg_pixel do
    bg = Theme.bg()

    <<div(bg, 0x10000), div(rem(bg, 0x10000), 0x100), rem(bg, 0x100), 0xFF>>
  end

  describe "names/0" do
    test "is sorted" do
      assert Icons.names() == :lists.sort(Icons.names())
    end

    test "holds every shape and every status icon" do
      assert Icons.names() == :lists.sort(@shapes ++ @status)
    end

    test "the retired dot marker is gone" do
      refute :dot in Icons.names()
    end
  end

  describe "size/1" do
    test "shapes are 32x32" do
      for name <- @shapes do
        assert Icons.size(name) == {32, 32}
      end
    end

    test "status icons are 16x16" do
      for name <- @status do
        assert Icons.size(name) == {16, 16}
      end
    end

    test "an unknown name is nil rather than a crash" do
      assert Icons.size(:nonesuch) == nil
    end
  end

  describe "binary/1" do
    test "every icon is exactly w * h * 4 bytes for its declared size" do
      for name <- Icons.names() do
        {w, h} = Icons.size(name)

        assert byte_size(Icons.binary(name)) == w * h * 4
      end
    end

    test "every pixel is fully opaque" do
      for name <- Icons.names() do
        alphas = for <<_r, _g, _b, a <- Icons.binary(name)>>, do: a

        assert :lists.usort(alphas) == [0xFF]
      end
    end

    test "an unknown name is nil rather than a crash" do
      assert Icons.binary(:nonesuch) == nil
    end

    test "icons are actually different from each other" do
      binaries = for name <- Icons.names(), do: Icons.binary(name)

      assert length(:lists.usort(binaries)) == length(binaries)
    end

    test "no icon is blank" do
      background = bg_pixel()

      for name <- Icons.names() do
        {w, h} = Icons.size(name)
        lit = :lists.filter(fn px -> px != background end, pixels(name))

        assert length(lit) > div(w * h, 20)
      end
    end
  end

  describe "item/3" do
    test "is an image at native size on the page background" do
      assert {:image, 10, 20, bg, {:rgba8888, 32, 32, binary}} = Icons.item(:square, 10, 20)

      assert bg == Theme.bg()
      assert binary == Icons.binary(:square)
    end

    test "declared dimensions match size/1 for every icon" do
      for name <- Icons.names() do
        assert {:image, 0, 0, _bg, {:rgba8888, w, h, binary}} = Icons.item(name, 0, 0)

        assert {w, h} == Icons.size(name)
        assert byte_size(binary) == w * h * 4
      end
    end

    test "a 16x16 status icon keeps its own size" do
      assert {:image, 1, 2, _bg, {:rgba8888, 16, 16, _binary}} = Icons.item(:wifi, 1, 2)
    end
  end
end
