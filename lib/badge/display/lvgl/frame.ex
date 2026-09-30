defmodule Badge.Display.Lvgl.Frame do
  @moduledoc """
  Turns each frame's display items into the few LVGL changes it needs.

  Pages still return AtomGL-style items: `{:rect, ...}`, `{:text, ...}`,
  `{:image, ...}` and `{:scaled_cropped_image, ...}`, plus one of LVGL's own,
  `{:marquee, x, y, w, font, fg, bg, text, speed}`: text that scrolls round by
  itself, `speed` pixels a second, when wider than `w`, and
  `{:fx_label, x, y, font, fg, bg, text, {effect, :in | :out, steps, ms, row,
  from_left, block}}`: text that plays a decrypt, rain, wipe or slide effect
  on itself, a step every `ms`. Being unchanged from frame to frame, either
  costs nothing once it is on the panel. Any item can also be wrapped as
  `{:motion, item, {mx, my, :in | :out, delay_ms, ms, ease}}`: LVGL glides it
  in from `mx, my` away once `delay_ms` has passed, or out to there and hides
  it, eased `:linear`, `:ease_out`, `:overshoot` or `:bounce`, or as
  `{:glide, item, ms}`: once placed, a new position is slid to over `ms`
  rather than jumped to. `{:flipbook, x, y, scale, frame_ms, [picture]}`
  shows each `{:rgba8888, w, h, pixels}` picture in turn, enlarged `scale`
  times, for `frame_ms` each, and loops. Each item becomes an
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
  def new, do: %{items: [], nodes: [], images: %{}, recent: [], next_image: 0, fresh: true}

  @doc """
  The operations that turn the previous frame into `items`, and the new state.

  Operations are applied in order: uploads, then objects bottom up, then
  deletions from the top, then images no longer used.
  """
  @spec frame(map, [tuple]) :: {[tuple], map}
  def frame(state, items) do
    bottom_up = :lists.reverse(items)

    {nodes, ops, uploads, {images, recent}, next_image} =
      walk(
        bottom_up,
        state.items,
        state.nodes,
        0,
        {state.images, state.recent},
        state.next_image,
        [],
        [],
        []
      )

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
         recent: recent,
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

  defp change(i, _prev, {type, props}, ops),
    do: [{:set, i, props}, {:new, i, lvgl_type(type)} | ops]

  # An effect label is an ordinary LVGL label playing an effect; a moving object is its own kind.
  defp lvgl_type({:moving, type}), do: lvgl_type(type)
  defp lvgl_type({:gliding, type}), do: lvgl_type(type)
  defp lvgl_type(:fx), do: :label
  defp lvgl_type(type), do: type

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

  defp node(
         {:fx_label, x, y, font, fg, bg, text, {effect, direction, steps, ms, row, left, block}},
         images,
         next,
         uploads
       ) do
    props = [
      x: x,
      y: y,
      font: font_id(font),
      fg: fg,
      bg: text_bg(bg),
      text: text(font, text),
      fx: effect_id(effect),
      fx_dir: if(direction == :out, do: 1, else: 0),
      fx_steps: steps,
      fx_ms: ms,
      fx_row: row,
      fx_left: if(left, do: 1, else: 0),
      fx_noise: if(block, do: 1, else: 0)
    ]

    {{:fx, props}, images, next, uploads}
  end

  defp node({:motion, item, {mx, my, direction, delay, ms, ease}}, images, next, uploads) do
    {{type, props}, images, next, uploads} = node(item, images, next, uploads)

    motion = [
      mx: mx,
      my: my,
      mdir: if(direction == :out, do: 1, else: 0),
      mdelay: delay,
      mms: ms,
      mease: ease_id(ease)
    ]

    {{{:moving, type}, props ++ motion}, images, next, uploads}
  end

  # The glide time goes last, so a new object is put in place before it starts gliding.
  defp node({:glide, item, ms}, images, next, uploads) do
    {{type, props}, images, next, uploads} = node(item, images, next, uploads)

    {{{:gliding, type}, props ++ [glide: ms]}, images, next, uploads}
  end

  defp node(
         {:flipbook, x, y, scale, frame_ms, [{:rgba8888, w, h, _pixels} | _more] = pictures},
         images,
         next,
         uploads
       ) do
    {ids, images, next, uploads} = pictures(pictures, scale, images, next, uploads, <<>>)
    props = [x: x, y: y, w: w * scale, h: h * scale, frames: ids, frame_ms: frame_ms]

    {{:flipbook, props}, images, next, uploads}
  end

  defp node({:image, x, y, _bg, {:rgba8888, w, h, pixels}}, images, next, uploads) do
    {src, images, next, uploads} = image(w, h, pixels, 1, images, next, uploads)
    props = [x: x, y: y, w: w, h: h, src: src, sx: @scale_one, sy: @scale_one, ox: 0, oy: 0]

    {{:image, props}, images, next, uploads}
  end

  # An even scale is done once, when the picture is uploaded, so it draws as a plain copy.
  defp node(
         {:scaled_cropped_image, x, y, w, h, _bg, src_x, src_y, scale, scale, _opts,
          {:rgba8888, iw, ih, pixels}},
         images,
         next,
         uploads
       )
       when is_integer(scale) and scale >= 1 do
    {src, images, next, uploads} = image(iw, ih, pixels, scale, images, next, uploads)

    props = [
      x: x,
      y: y,
      w: w,
      h: h,
      src: src,
      sx: @scale_one,
      sy: @scale_one,
      ox: -src_x * scale,
      oy: -src_y * scale
    ]

    {{:image, props}, images, next, uploads}
  end

  defp node(
         {:scaled_cropped_image, x, y, w, h, _bg, src_x, src_y, x_scale, y_scale, _opts,
          {:rgba8888, iw, ih, pixels}},
         images,
         next,
         uploads
       ) do
    {src, images, next, uploads} = image(iw, ih, pixels, 1, images, next, uploads)

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

  defp pictures([], _scale, images, next, uploads, ids), do: {ids, images, next, uploads}

  defp pictures([{:rgba8888, w, h, pixels} | rest], scale, images, next, uploads, ids) do
    {id, images, next, uploads} = image(w, h, pixels, scale, images, next, uploads)
    pictures(rest, scale, images, next, uploads, <<ids::binary, id::16-little>>)
  end

  defp ease_id(:ease_out), do: 1
  defp ease_id(:overshoot), do: 2
  defp ease_id(:bounce), do: 3
  defp ease_id(_linear), do: 0

  defp effect_id(:decrypt), do: 1
  defp effect_id(:rain), do: 2
  defp effect_id(:wipe), do: 3
  defp effect_id(:slide), do: 4
  defp effect_id(_effect), do: 0

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
  # The same picture drawn many times costs one fingerprint: a recent binary is matched by comparison.
  @recent 8

  defp image(w, h, pixels, scale, {images, recent}, next, uploads) do
    {key, recent} = fingerprint(w, h, pixels, recent)

    {src, images, next, uploads} =
      register({key, scale}, w, h, scale, pixels, images, next, uploads)

    {src, {images, recent}, next, uploads}
  end

  defp fingerprint(w, h, pixels, recent) do
    case seen(pixels, recent) do
      nil ->
        key = {w, h, :erlang.crc32(pixels)}
        {key, :lists.sublist([{pixels, key} | recent], @recent)}

      key ->
        {key, recent}
    end
  end

  defp seen(_pixels, []), do: nil
  defp seen(pixels, [{pixels, key} | _rest]), do: key
  defp seen(pixels, [_other | rest]), do: seen(pixels, rest)

  # The driver holds a fixed number of pictures, so the lowest id not in use is taken.
  defp register(key, w, h, scale, pixels, images, next, uploads) do
    case Map.get(images, key) do
      nil ->
        id = free_id(Map.values(images), 0)
        {id, Map.put(images, key, id), next, [upload(id, w, h, pixels, scale) | uploads]}

      id ->
        {id, images, next, uploads}
    end
  end

  defp free_id(taken, id) do
    case :lists.member(id, taken) do
      true -> free_id(taken, id + 1)
      false -> id
    end
  end

  defp upload(id, w, h, pixels, 1), do: {:img, id, :rgba8888, w, h, pixels}
  defp upload(id, w, h, pixels, scale), do: {:img, id, :rgba8888, w, h, pixels, scale}

  defp used([], acc), do: acc

  defp used([{:image, [{:x, _}, {:y, _}, {:w, _}, {:h, _}, {:src, src} | _]} | rest], acc),
    do: used(rest, [src | acc])

  defp used([{:flipbook, [_x, _y, _w, _h, {:frames, ids} | _]} | rest], acc),
    do: used(rest, frame_ids(ids, acc))

  defp used([{{wrap, type}, props} | rest], acc) when wrap == :moving or wrap == :gliding,
    do: used([{type, props} | rest], acc)

  defp used([_node | rest], acc), do: used(rest, acc)

  defp frame_ids(<<>>, acc), do: acc
  defp frame_ids(<<id::16-little, rest::binary>>, acc), do: frame_ids(rest, [id | acc])

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
