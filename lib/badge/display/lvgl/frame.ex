defmodule Badge.Display.Lvgl.Frame do
  @moduledoc """
  Turns each frame's display items into the few LVGL changes it needs.

  Pages still return AtomGL-style items: `{:rect, ...}`, `{:text, ...}`,
  `{:image, ...}` and `{:scaled_cropped_image, ...}`, plus one of LVGL's own,
  `{:marquee, x, y, w, font, fg, bg, text, speed}`: text that scrolls round by
  itself, `speed` pixels a second, when wider than `w`. Being unchanged from
  frame to frame, a marquee costs nothing once it is on the panel. Each item becomes an
  LVGL object whose id is its z-order, 0 at the bottom, so the last item,
  the background, is object 0. An item equal to last frame's item at the
  same place costs nothing; a changed one sends only the properties that
  differ; a different kind of item replaces the object.

  Images are uploaded once per distinct picture and freed once no item uses
  them. A fresh state starts with `{:reset}`, so a restarted UI never
  inherits objects it does not know about.

  Pure: `Badge.Display.Lvgl` sends the operations and keeps the state.
  """

  @scale_one 256

  # Fonts have fixed ids, so any process can name them without asking.
  @doc "The LVGL font id a font atom is registered under; unknown fonts draw in the built-in one."
  @spec font_id(atom) :: non_neg_integer
  def font_id(:default16px), do: 0
  def font_id(:dogica), do: 1
  def font_id(:pixel_operator), do: 2
  def font_id(:w95fa), do: 3
  def font_id(_font), do: 0

  @doc "A state with nothing drawn; its first frame resets the panel."
  @spec new() :: map
  def new, do: %{items: [], nodes: [], images: %{}, next_image: 0, fresh: true}

  @doc """
  The operations that turn the previous frame into `items`, and the new state.

  Operations are applied in order: uploads, then objects bottom up, then
  deletions from the top, then images no longer used.
  """
  @spec frame(map, [tuple]) :: {[tuple], map}
  def frame(state, items) do
    bottom_up = :lists.reverse(items)

    {nodes, ops, uploads, images, next_image} =
      walk(bottom_up, state.items, state.nodes, 0, state.images, state.next_image, [], [], [])

    count = length(nodes)
    deletes = deletes(length(state.nodes) - 1, count, [])
    {frees, images} = frees(images, used(nodes, []))

    reset = if state.fresh, do: [{:reset}], else: []

    {reset ++ uploads ++ ops ++ deletes ++ frees,
     %{
       state
       | items: bottom_up,
         nodes: nodes,
         images: images,
         next_image: next_image,
         fresh: false
     }}
  end

  # An item equal to last frame's at the same place keeps its node and costs nothing.
  defp walk([], _prev_items, _prev_nodes, _i, images, next, nodes, ops, uploads) do
    {:lists.reverse(nodes), :lists.reverse(ops), :lists.reverse(uploads), images, next}
  end

  defp walk(
         [item | rest],
         [item | prev_items],
         [node | prev_nodes],
         i,
         images,
         next,
         nodes,
         ops,
         uploads
       ) do
    walk(rest, prev_items, prev_nodes, i + 1, images, next, [node | nodes], ops, uploads)
  end

  defp walk([item | rest], prev_items, prev_nodes, i, images, next, nodes, ops, uploads) do
    {node, images, next, uploads} = node(item, images, next, uploads)
    {prev_node, prev_items, prev_nodes} = pop(prev_items, prev_nodes)

    walk(
      rest,
      prev_items,
      prev_nodes,
      i + 1,
      images,
      next,
      [node | nodes],
      change(i, prev_node, node, ops),
      uploads
    )
  end

  defp pop([_item | items], [node | nodes]), do: {node, items, nodes}
  defp pop(_items, _nodes), do: {nil, [], []}

  # A new or different kind of object is created with every property; the same kind sends what changed.
  defp change(i, {type, old}, {type, props}, ops) do
    case changed(old, props, []) do
      [] -> ops
      diff -> [{:set, i, diff} | ops]
    end
  end

  defp change(i, _prev, {type, props}, ops), do: [{:set, i, props}, {:new, i, type} | ops]

  defp changed([], [], acc), do: :lists.reverse(acc)
  defp changed([same | old], [same | new], acc), do: changed(old, new, acc)
  defp changed([_old | old], [prop | new], acc), do: changed(old, new, [prop | acc])

  defp deletes(top, count, acc) when top < count, do: :lists.reverse(acc)
  defp deletes(top, count, acc), do: deletes(top - 1, count, [{:del, top} | acc])

  defp node({:rect, x, y, w, h, colour}, images, next, uploads) do
    {{:box, [x: x, y: y, w: w, h: h, bg: colour]}, images, next, uploads}
  end

  defp node({:text, x, y, font, fg, bg, text}, images, next, uploads) do
    props = [x: x, y: y, font: font_id(font), fg: fg, bg: text_bg(bg), text: text(font, text)]

    {{:label, props}, images, next, uploads}
  end

  defp node({:marquee, x, y, w, font, fg, bg, text, speed}, images, next, uploads) do
    props = [
      x: x,
      y: y,
      w: w,
      font: font_id(font),
      fg: fg,
      bg: text_bg(bg),
      text: text(font, text),
      speed: speed
    ]

    {{:marquee, props}, images, next, uploads}
  end

  defp node({:image, x, y, _bg, {:rgba8888, w, h, pixels}}, images, next, uploads) do
    {src, images, next, uploads} = image(w, h, pixels, images, next, uploads)
    props = [x: x, y: y, w: w, h: h, src: src, sx: @scale_one, sy: @scale_one, ox: 0, oy: 0]

    {{:image, props}, images, next, uploads}
  end

  defp node(
         {:scaled_cropped_image, x, y, w, h, _bg, src_x, src_y, x_scale, y_scale, _opts,
          {:rgba8888, iw, ih, pixels}},
         images,
         next,
         uploads
       ) do
    {src, images, next, uploads} = image(iw, ih, pixels, images, next, uploads)

    props = [
      x: x,
      y: y,
      w: w,
      h: h,
      src: src,
      sx: x_scale * @scale_one,
      sy: y_scale * @scale_one,
      ox: -src_x,
      oy: -src_y
    ]

    {{:image, props}, images, next, uploads}
  end

  # Anything else is drawn as nothing rather than stopping the frame.
  defp node(_item, images, next, uploads),
    do: {{:box, [x: 0, y: 0, w: 0, h: 0, bg: 0]}, images, next, uploads}

  # AtomGL reads a background of 0 as none, so black text can sit on anything.
  defp text_bg(0), do: -1
  defp text_bg(colour), do: colour

  # The built-in font is code page 437 a byte a glyph; each byte travels as the codepoint of that value.
  defp text(:default16px, text) when is_list(text), do: latin(:erlang.list_to_binary(text))
  defp text(:default16px, text), do: latin(text)
  defp text(_font, text) when is_list(text), do: :unicode.characters_to_binary(text)
  defp text(_font, text), do: text

  defp latin(text) do
    case ascii?(text) do
      true -> text
      false -> widen(text, <<>>)
    end
  end

  defp ascii?(<<>>), do: true
  defp ascii?(<<byte, rest::binary>>) when byte < 128, do: ascii?(rest)
  defp ascii?(_text), do: false

  defp widen(<<>>, acc), do: acc
  defp widen(<<byte, rest::binary>>, acc), do: widen(rest, <<acc::binary, byte::utf8>>)

  # One upload per distinct picture, however many items draw it.
  defp image(w, h, pixels, images, next, uploads) do
    key = {w, h, :erlang.crc32(pixels)}

    case Map.get(images, key) do
      nil ->
        {next, Map.put(images, key, next), next + 1,
         [{:img, next, :rgba8888, w, h, pixels} | uploads]}

      id ->
        {id, images, next, uploads}
    end
  end

  defp used([], acc), do: acc

  defp used([{:image, [{:x, _}, {:y, _}, {:w, _}, {:h, _}, {:src, src} | _]} | rest], acc),
    do: used(rest, [src | acc])

  defp used([_node | rest], acc), do: used(rest, acc)

  defp frees(images, used) do
    :lists.foldl(
      fn {key, id}, {ops, kept} ->
        case :lists.member(id, used) do
          true -> {ops, kept}
          false -> {[{:unimg, id} | ops], Map.delete(kept, key)}
        end
      end,
      {[], images},
      Map.to_list(images)
    )
  end
end
