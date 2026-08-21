defmodule Badge.IconsTest do
  use ExUnit.Case, async: true

  alias Badge.Icons
  alias Badge.Theme

  @expected [:circle, :clover, :cross, :diamond, :dot, :square, :triangle]

  defp accent_pixel do
    accent = Theme.accent()

    <<div(accent, 0x10000), div(rem(accent, 0x10000), 0x100), rem(accent, 0x100), 0xFF>>
  end

  defp bg_pixel do
    bg = Theme.bg()

    <<div(bg, 0x10000), div(rem(bg, 0x10000), 0x100), rem(bg, 0x100), 0xFF>>
  end

  describe "names/0" do
    test "every shape key has an icon, plus the tilt marker" do
      assert :lists.sort(Icons.names()) == @expected
    end
  end

  describe "binary/1" do
    test "every icon is exactly 16x16 rgba8888" do
      for name <- Icons.names() do
        assert byte_size(Icons.binary(name)) == 16 * 16 * 4
      end
    end

    test "every pixel is fully opaque" do
      for name <- Icons.names() do
        alphas = for <<_r, _g, _b, a <- Icons.binary(name)>>, do: a

        assert :lists.usort(alphas) == [0xFF]
      end
    end

    test "only the accent and background colours appear" do
      expected = :lists.usort([accent_pixel(), bg_pixel()])

      for name <- Icons.names() do
        pixels = for <<px::binary-4 <- Icons.binary(name)>>, do: px

        assert :lists.usort(pixels) == expected
      end
    end

    test "an unknown name is nil rather than a crash" do
      assert Icons.binary(:nonesuch) == nil
    end

    test "shapes are actually different from each other" do
      binaries = for name <- Icons.names(), do: Icons.binary(name)

      assert length(:lists.usort(binaries)) == length(binaries)
    end

    test "no icon is blank" do
      lit = accent_pixel()

      for name <- Icons.names() do
        pixels = for <<px::binary-4 <- Icons.binary(name)>>, do: px
        on = :lists.filter(fn px -> px == lit end, pixels)

        assert length(on) > 20
      end
    end
  end

  describe "item/3" do
    test "is a scaled_cropped_image scaled 2x to 32px" do
      assert {:scaled_cropped_image, 10, 20, 32, 32, bg, 0, 0, 2, 2, [],
              {:rgba8888, 16, 16, binary}} = Icons.item(:square, 10, 20)

      assert bg == Theme.bg()
      assert binary == Icons.binary(:square)
    end

    test "size/0 matches the item bounding box" do
      {:scaled_cropped_image, _x, _y, w, h, _bg, _sx, _sy, _xs, _ys, _opts, _img} =
        Icons.item(:circle, 0, 0)

      assert Icons.size() == w
      assert Icons.size() == h
    end
  end
end
