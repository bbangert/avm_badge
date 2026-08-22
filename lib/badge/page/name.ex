defmodule Badge.Page.Name do
  @moduledoc """
  A name tag to leave on screen.

  The name is set in the editor and kept in NVS. Long names wrap onto a
  second line, and the rule sits under however many lines that takes.

  The share screen beams the name over IR while it is showing, and records
  the badges it hears. Turning away from it stops both.
  """

  use Badge.Page

  alias Badge.Field
  alias Badge.Font
  alias Badge.Identity
  alias Badge.Icons
  alias Badge.Ir
  alias Badge.Peers
  alias Badge.Pixels
  alias Badge.Profile
  alias Badge.Text
  alias Badge.Theme

  @accent Theme.accent()
  @fg Theme.fg()
  @dim Theme.dim()
  @muted Theme.muted()
  @bg Theme.bg()

  @margin 16

  # dogica is fixed width, so its text can be measured and wrapped exactly.
  @name_font :dogica
  @name_w Font.advance(@name_font)

  @name_w != nil ||
    raise "#{@name_font} is proportional; the name cannot be wrapped without glyph widths"

  @name_columns div(Theme.width() - 2 * @margin, @name_w)
  @name_pitch 22

  @char_w 8

  @name_y Theme.content_top() + 10
  @rule_h 2
  @rule_w 200

  @detail_pitch 20
  @icon_w 16

  # Every detail line starts at the same x, icon or not, so they stay aligned.
  @detail_x @margin + @icon_w + 6
  @hint_y 216

  @alert Theme.alert()
  @select Theme.select()

  @row_y Theme.content_top() + 10
  @row_pitch 18
  @marker_x 0
  @label_x 8
  @value_x 88
  @value_columns div(Theme.width() - @value_x - 8, @char_w)

  @screens 4

  @ok Theme.ok()
  @warn Theme.warn()
  @muted_rows 6

  # What meeting a badge looks like, on the panel and on the LED chain.
  @met_name_y 130
  @met_note_y 154
  @met_count_y 186

  @new_hue 120
  @known_hue 200
  @renamed_hue 45

  # The big-name screen, and what it falls back to when a name will not fit.
  @big_font :w95fa
  @big_usable Theme.width() - 2 * @margin
  @dot_y 228
  @dot 6
  @dot_gap 10

  # Every third UI tick, so the beam is quiet four fifths of the time and the
  # other badge can be heard.
  @beam_ticks 3

  @entry_label_y Theme.content_top() + 30
  @entry_value_y Theme.content_top() + 70

  # Sharing repaints whenever a badge is heard; the editor wants the cursor to
  # keep up, and only one of those two can have the panel.
  @impl true
  def refresh(%{screen: 2}), do: 333
  def refresh(_state), do: 100

  # w95fa is 18 kB in the display driver's heap, so it is only asked for on
  # the one screen that draws with it.
  @impl true
  def fonts(%{screen: 1}), do: [@big_font]
  def fonts(_state), do: []

  @impl true
  def title, do: "Name"

  @impl true
  def icon, do: :diamond

  @impl true
  def init do
    %{
      mode: :show,
      screen: 0,
      profile: Profile.blank(),
      peers: [],
      stored: [],
      chip: "",
      beam: 0,
      announced: nil,
      met: nil,
      top: 0,
      cursor: 0,
      field: nil,
      loaded: false,
      saved: nil
    }
  end

  # Hardware is only touched here, never from a key handler.
  @impl true
  def tick(state), do: state |> load() |> beam() |> persist()

  # The saved profile arrives on the first tick, so init/0 stays pure.
  defp load(%{loaded: true} = state), do: state

  defp load(state) do
    profile = Profile.load()
    peers = Peers.load()

    %{
      state
      | profile: profile,
        saved: profile,
        peers: peers,
        stored: peers,
        chip: Identity.format(Identity.chip_id()),
        loaded: true
    }
  end

  # Screen 2 is the whole protocol: on it we beam, off it we are silent.
  defp beam(%{screen: 2} = state) do
    %{state | beam: transmit(rem(state.beam + 1, @beam_ticks), state.profile)}
  end

  defp beam(state), do: %{state | beam: 0}

  defp transmit(0, profile) do
    Ir.send(Profile.display_name(profile))

    0
  end

  defp transmit(count, _profile), do: count

  @doc "How many UI ticks pass between transmissions."
  def beam_ticks, do: @beam_ticks

  # Frames reach Badge.UI, not the page, so they arrive through here.
  #
  # A badge held in front of this one beams three times a second. Reacting to
  # every frame would strobe the LEDs and rewrite NVS continuously, so nothing
  # happens until the chip id or the name actually changes.
  @impl true
  def handle_ir(from, name, %{screen: 2, announced: {from, name}}), do: :ignore

  def handle_ir(from, name, %{screen: 2} = state) do
    greeting = greeting(state.peers, from, name)

    :io.format(~c"Name: ~p ~s ~s~n", [greeting, Identity.format(from), name])

    {:ok, meet(state, from, name, greeting)}
  end

  def handle_ir(_from, _payload, _state), do: :ignore

  @doc """
  What hearing this badge means: unknown, known already, or known under a
  different name because they have edited their profile since.
  """
  @spec greeting([map], binary, binary) :: :new | :known | :renamed
  def greeting(peers, mac, name) do
    case Peers.find(peers, mac) do
      nil -> :new
      peer -> same_name(Profile.display_name(Map.get(peer, :profile, %{})), name)
    end
  end

  defp same_name(name, name), do: :known
  defp same_name(_stored, _heard), do: :renamed

  # Only a change is worth the flash write; hearing a badge again is free.
  defp meet(state, mac, name, :known) do
    Pixels.flash(@known_hue)

    %{state | announced: {mac, name}, met: {name, :known}}
  end

  defp meet(state, mac, name, greeting) do
    peers = Peers.add(state.peers, mac, %{name: name})
    Pixels.flash(hue(greeting))

    %{state | peers: peers, announced: {mac, name}, met: {name, greeting}}
  end

  defp hue(:new), do: @new_hue
  defp hue(:renamed), do: @renamed_hue

  # Both writes are deferred to here, so a key handler and an arriving frame
  # stay pure and NVS is only touched on a tick.
  defp persist(state), do: state |> persist_profile() |> persist_peers()

  # Written once the editor is closed, not on every keystroke.
  defp persist_profile(%{mode: mode} = state) when mode != :show, do: state
  defp persist_profile(%{profile: profile, saved: profile} = state), do: state

  defp persist_profile(state) do
    Profile.save(state.profile)

    %{state | saved: state.profile}
  end

  defp persist_peers(%{peers: peers, stored: peers} = state), do: state

  defp persist_peers(state) do
    Peers.save(state.peers)

    %{state | stored: state.peers}
  end

  @impl true
  def handle_key(event, %{mode: :typing} = state), do: typing_key(event, state)
  def handle_key(event, %{mode: :fields} = state), do: fields_key(event, state)
  def handle_key(event, state), do: show_key(event, state)

  defp show_key({:char, char}, state) when char == ?e or char == ?E do
    {:ok, %{state | mode: :fields, cursor: 0}}
  end

  defp show_key({:move, :down}, %{screen: 3} = state), do: {:ok, scroll(state, 1)}
  defp show_key({:move, :up}, %{screen: 3} = state), do: {:ok, scroll(state, -1)}

  defp show_key({:move, :right}, state), do: {:ok, turn(state, 1)}
  defp show_key({:move, :left}, state), do: {:ok, turn(state, -1)}
  defp show_key(_event, _state), do: :ignore

  defp turn(state, delta) do
    %{state | screen: rem(state.screen + delta + @screens, @screens), top: 0}
  end

  @doc "Moves the window over the collected list, without running off either end."
  @spec scroll(map, integer) :: map
  def scroll(%{peers: peers, top: top} = state, delta) do
    last = max(Peers.count(peers) - @muted_rows, 0)

    %{state | top: min(max(top + delta, 0), last)}
  end

  @doc "How many badge screens there are to page through."
  def screens, do: @screens

  # Escape leaves the editor; the router only sees it once we are back on the badge.
  defp fields_key({:nav, :home}, state), do: {:ok, %{state | mode: :show}}
  defp fields_key({:move, :up}, state), do: {:ok, move(state, -1)}
  defp fields_key({:move, :down}, state), do: {:ok, move(state, 1)}

  defp fields_key({:edit, :newline}, state) do
    key = selected(state)
    value = Map.get(state.profile, key, "")

    {:ok, %{state | mode: :typing, field: fill(value, Profile.capacity(key))}}
  end

  defp fields_key(_event, state), do: {:ok, state}

  defp typing_key({:nav, :home}, state), do: {:ok, %{state | mode: :fields, field: nil}}

  defp typing_key({:edit, :newline}, state) do
    profile = Map.put(state.profile, selected(state), Field.value(state.field))

    {:ok, %{state | mode: :fields, profile: profile, field: nil}}
  end

  defp typing_key({:char, char}, state) do
    {:ok, %{state | field: Field.insert(state.field, char)}}
  end

  defp typing_key({:edit, :backspace}, state) do
    {:ok, %{state | field: Field.backspace(state.field)}}
  end

  defp typing_key(_event, state), do: {:ok, state}

  defp move(state, delta) do
    %{state | cursor: clamp(state.cursor + delta, length(Profile.keys()) - 1)}
  end

  defp clamp(index, _last) when index < 0, do: 0
  defp clamp(index, last) when index > last, do: last
  defp clamp(index, _last), do: index

  @doc "The field the cursor is on."
  def selected(%{cursor: cursor}), do: :lists.nth(cursor + 1, Profile.keys())

  defp fill(value, capacity) do
    :lists.foldl(&Field.insert(&2, &1), Field.new(capacity), :erlang.binary_to_list(value))
  end

  @doc "How many characters of the name fit on one line."
  def columns, do: @name_columns

  @impl true
  def render(%{mode: :typing} = state) do
    key = selected(state)
    value = Field.value(state.field) <> "_"

    [
      centred(Profile.label(key), @entry_label_y, @dim),
      centred(value, @entry_value_y, @select),
      centred("Enter save   Esc cancel", @hint_y, @dim)
    ]
  end

  def render(%{mode: :fields} = state) do
    rows(Profile.keys(), 0, state, @row_y, []) ++
      [centred("up/down pick   Enter edit   Esc done", @hint_y, @dim)]
  end

  def render(%{screen: 1, profile: profile}), do: big_screen(profile) ++ dots(1)

  def render(%{screen: 2} = state), do: share_screen(state) ++ dots(2)

  def render(%{screen: 3} = state), do: peers_screen(state) ++ dots(3)

  def render(%{profile: profile} = state) do
    lines = Text.wrap(Profile.display_name(profile), @name_columns)
    rule_y = @name_y + length(lines) * @name_pitch + 6

    name_items(lines, @name_y, []) ++
      [{:rect, @margin, rule_y, @rule_w, @rule_h, @accent}] ++
      detail_items(Profile.lines(profile), rule_y + 14, []) ++
      [hint()] ++ dots(state.screen)
  end

  # The whole name, as large as it will go. w95fa is proportional, so it is
  # measured rather than guessed, and a name too wide for it drops to dogica.
  defp big_screen(profile) do
    name = Profile.display_name(profile)

    {font, lines} =
      case Font.fits?(@big_font, name, @big_usable) do
        true -> {@big_font, [name]}
        false -> {@name_font, Text.wrap(name, @name_columns)}
      end

    height = Font.line_height(font)
    top = div(Theme.content_top() + Theme.height() - length(lines) * height, 2)

    big_lines(lines, font, height, top, [])
  end

  defp big_lines([], _font, _height, _y, acc), do: :lists.reverse(acc)

  defp big_lines([line | rest], font, height, y, acc) do
    x = div(Theme.width() - Font.width(font, line), 2)
    item = {:text, x, y, font, @fg, @bg, line}

    big_lines(rest, font, height, y + height, [item | acc])
  end

  defp share_screen(state) do
    [
      centred("Share", Theme.content_top() + 16, @fg),
      centred(state.chip, Theme.content_top() + 44, @dim)
    ] ++ met_lines(state.met, Peers.count(state.peers))
  end

  # Before anyone has been heard there is nothing to report but the count.
  defp met_lines(nil, count) do
    [
      centred("hold another badge up to this one", @met_name_y, @dim),
      collected_line(count)
    ]
  end

  defp met_lines({name, greeting}, count) do
    [
      centred(name, @met_name_y, @fg),
      centred(note(greeting), @met_note_y, colour(greeting)),
      collected_line(count)
    ]
  end

  defp note(:new), do: "added to your badges"
  defp note(:known), do: "already in your badges"
  defp note(:renamed), do: "name updated"

  defp colour(:new), do: @ok
  defp colour(:known), do: @select
  defp colour(:renamed), do: @warn

  defp collected_line(count) do
    centred(:erlang.integer_to_binary(count) <> collected(count) <> " collected", @met_count_y, @dim)
  end



  defp peers_screen(%{peers: peers, top: top}) do
    count = Peers.count(peers)

    [
      centred("Collected", Theme.content_top() + 16, @fg),
      centred(:erlang.integer_to_binary(count) <> collected(count), Theme.content_top() + 44, @ok)
    ] ++
      peer_rows(drop(peers, top), @muted_rows, Theme.content_top() + 80, []) ++
      scroll_hint(count, top)
  end

  # There is no Enum.drop on AtomVM, and the list is at most @limit long.
  defp drop(peers, 0), do: peers
  defp drop([], _n), do: []
  defp drop([_peer | rest], n), do: drop(rest, n - 1)

  # Only says so when there is something off-screen in that direction.
  defp scroll_hint(count, _top) when count <= @muted_rows, do: []

  defp scroll_hint(count, top) do
    shown = min(top + @muted_rows, count)
    range = :erlang.integer_to_binary(top + 1) <> "-" <> :erlang.integer_to_binary(shown)

    [centred(range <> " of " <> :erlang.integer_to_binary(count) <> "   up/down", @hint_y, @dim)]
  end

  defp collected(1), do: " badge"
  defp collected(_count), do: " badges"

  defp peer_rows([], _left, _y, acc), do: :lists.reverse(acc)
  defp peer_rows(_peers, 0, _y, acc), do: :lists.reverse(acc)

  defp peer_rows([peer | rest], left, y, acc) do
    name = Profile.display_name(Map.get(peer, :profile, %{}))

    peer_rows(rest, left - 1, y + @detail_pitch, [centred(name, y, @muted) | acc])
  end

  # Which screen you are on, so paging is discoverable without a label.
  defp dots(current) do
    left = div(Theme.width() - (@screens * @dot + (@screens - 1) * (@dot_gap - @dot)), 2)

    for index <- 0..(@screens - 1) do
      colour = if index == current, do: @fg, else: @dim

      {:rect, left + index * @dot_gap, @dot_y, @dot, @dot, colour}
    end
  end

  defp name_items([], _y, acc), do: :lists.reverse(acc)

  defp name_items([line | rest], y, acc) do
    item = {:text, @margin, y, @name_font, @fg, @bg, line}

    name_items(rest, y + @name_pitch, [item | acc])
  end

  # Anything that will not fit above the hint is dropped rather than overlapping it.
  defp detail_items([], _y, acc), do: :lists.reverse(acc)

  defp detail_items(_lines, y, acc) when y + @detail_pitch > @hint_y, do: :lists.reverse(acc)

  defp detail_items([{icon, text} | rest], y, acc) do
    item = {:text, @detail_x, y, :default16px, @muted, @bg, text}

    detail_items(rest, y + @detail_pitch, [item | acc] ++ badge_icon(icon, y))
  end

  # The icon sits a little above the text baseline so the two line up by eye.
  defp badge_icon(nil, _y), do: []
  defp badge_icon(icon, y), do: [Icons.item(icon, @margin, y)]

  defp rows([], _position, _state, _y, acc), do: :lists.reverse(acc)

  defp rows([key | rest], position, state, y, acc) do
    colour = row_colour(state, position, key)
    marker = if position == state.cursor, do: ">", else: " "

    items = [
      {:text, @value_x, y, :default16px, colour, @bg, shown(Map.get(state.profile, key, ""))},
      {:text, @label_x, y, :default16px, label_colour(state, position), @bg, Profile.label(key)},
      {:text, @marker_x, y, :default16px, @select, @bg, marker}
    ]

    rows(rest, position + 1, state, y + @row_pitch, items ++ acc)
  end

  # The one field that must be filled in says so, in the colour used for problems.
  defp row_colour(state, position, key) do
    cond do
      key == Profile.required() and not Profile.complete?(state.profile) -> @alert
      position == state.cursor -> @select
      true -> @fg
    end
  end

  defp label_colour(%{cursor: position}, position), do: @select
  defp label_colour(_state, _position), do: @dim

  # Values are longer than the column, so the list shows as much as fits.
  defp shown(value) when byte_size(value) > @value_columns do
    :binary.part(value, 0, @value_columns)
  end

  defp shown(""), do: "-"
  defp shown(value), do: value

  defp centred(text, y, colour) do
    {:text, div(Theme.width() - @char_w * byte_size(text), 2), y, :default16px, colour, @bg, text}
  end

  defp hint do
    text = "E to edit"

    {:text, div(Theme.width() - @char_w * byte_size(text), 2), @hint_y, :default16px, @dim, @bg,
     text}
  end
end
