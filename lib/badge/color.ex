defmodule Badge.Color do
  @moduledoc """
  Integer colour maths, shared by the LED chain and the panel.

  Hue is 0..359, saturation and value 0..255. No floats: AtomVM has them,
  but integer maths keeps the LED frame cheap.
  """

  @doc "Converts integer HSV to an `{r, g, b}` byte triple."
  def hsv_to_rgb(h, s, v) do
    sector = div(h, 60)
    offset = div(rem(h, 60) * 255, 60)

    p = div(v * (255 - s), 255)
    q = div(v * (255 - div(s * offset, 255)), 255)
    t = div(v * (255 - div(s * (255 - offset), 255)), 255)

    sector_rgb(sector, v, p, q, t)
  end

  defp sector_rgb(0, v, p, _q, t), do: {v, t, p}
  defp sector_rgb(1, v, p, q, _t), do: {q, v, p}
  defp sector_rgb(2, v, p, _q, t), do: {p, v, t}
  defp sector_rgb(3, v, p, q, _t), do: {p, q, v}
  defp sector_rgb(4, v, p, _q, t), do: {t, p, v}
  defp sector_rgb(_sector, v, p, q, _t), do: {v, p, q}

  @doc "Packs an `{r, g, b}` triple into the `0xRRGGBB` integer AtomGL wants."
  def rgb888({r, g, b}), do: r * 0x10000 + g * 0x100 + b
end
