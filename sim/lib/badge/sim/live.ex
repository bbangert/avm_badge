defmodule Badge.Sim.Live do
  @moduledoc """
  The browser side: the badge drawn from `priv/badge.svg`, the panel canvas over
  its screen, and both the browser's keyboard and the drawn keys feeding the pages.

  A drawn key sends its matrix label through `Badge.Keymap`, as the scanner
  does. Modifiers toggle instead: a toggled key stays held, so shift applies to
  the keys clicked after it and `Badge.Keyboard.holding?/1` sees it.
  """

  use Phoenix.LiveView

  alias Badge.Keymap
  alias Badge.Sim.Board
  alias Badge.Sim.Display
  alias Badge.Theme

  @shapes for {key, n} <- Enum.with_index(Badge.Pages.keys(), 1),
              into: %{},
              do: {"F#{n}", key}

  @svg_path Path.expand("../../../priv/badge.svg", __DIR__)
  @external_resource @svg_path
  @svg File.read!(@svg_path)

  # The screen rect as percentages of the viewBox, where the panel canvas sits.
  @screen (fn ->
             number = fn text -> text |> Float.parse() |> elem(0) end
             [box] = Regex.run(~r/viewBox="([^"]+)"/, @svg, capture: :all_but_first)
             [vx, vy, vw, vh] = box |> String.split() |> Enum.map(number)
             [rect] = Regex.run(~r/<rect id="screen"[^>]*>/, @svg)

             attr = fn name ->
               [value] = Regex.run(~r/ #{name}="([^"]+)"/, rect, capture: :all_but_first)
               number.(value)
             end

             pct = fn value -> "#{Float.round(value * 100, 3)}%" end

             "left: #{pct.((attr.("x") - vx) / vw)}; top: #{pct.((attr.("y") - vy) / vh)}; " <>
               "width: #{pct.(attr.("width") / vw)}; height: #{pct.(attr.("height") / vh)}"
           end).()

  @modifiers ["LShift", "RShift", "Fn", "Ctrl", "SP", "Alt", "AltGr"]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Display.attach(self())
    {:ok, assign(socket, held: [])}
  end

  @impl true
  def handle_info({:asset, asset}, socket), do: {:noreply, push_event(socket, "asset", asset)}

  def handle_info({:backlight, level}, socket),
    do: {:noreply, push_event(socket, "backlight", %{level: level})}

  def handle_info({:frame, frame}, socket),
    do: {:noreply, push_event(socket, "frame", %{items: frame})}

  @impl true
  def handle_event("key", %{"key" => key}, socket) do
    case event(key) do
      nil -> :ok
      event -> Badge.UI.key_event(event)
    end

    {:noreply, socket}
  end

  def handle_event("press", %{"label" => label}, socket) when label in @modifiers do
    held =
      if label in socket.assigns.held,
        do: List.delete(socket.assigns.held, label),
        else: [label | socket.assigns.held]

    {:noreply, hold(socket, held)}
  end

  def handle_event("press", %{"label" => label}, socket) do
    shifted = "LShift" in socket.assigns.held or "RShift" in socket.assigns.held

    case Keymap.decode(String.to_charlist(label), shifted) do
      :ignore -> :ok
      event -> Badge.UI.key_event(event)
    end

    {:noreply, socket}
  end

  def handle_event("reboot", _params, socket) do
    Board.reboot()
    Display.attach(self())
    {:noreply, hold(socket, [])}
  end

  defp hold(socket, held) do
    GenServer.cast(Badge.Keyboard, {:held, Enum.map(held, &String.to_charlist/1)})

    socket
    |> assign(held: held)
    |> push_event("held", %{labels: held})
  end

  defp event("Enter"), do: {:edit, :newline}
  defp event("Backspace"), do: {:edit, :backspace}
  defp event("Tab"), do: {:edit, :tab}
  defp event("Escape"), do: {:nav, :home}
  defp event("ArrowUp"), do: {:move, :up}
  defp event("ArrowDown"), do: {:move, :down}
  defp event("ArrowLeft"), do: {:move, :left}
  defp event("ArrowRight"), do: {:move, :right}

  defp event(key) do
    case {Map.get(@shapes, key), String.length(key)} do
      {nil, 1} -> {:char, hd(String.to_charlist(key))}
      {nil, _} -> nil
      {shape, _} -> {:nav, shape}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        svg: {:safe, @svg},
        screen: @screen,
        panel_width: Theme.width(),
        panel_height: Theme.height()
      )

    ~H"""
    <div id="badge" phx-hook="Badge" phx-window-keydown="key" tabindex="0">
      <div class="board" id="board" phx-update="ignore">
        {@svg}
        <canvas id="panel" width={@panel_width} height={@panel_height} style={@screen}></canvas>
      </div>
      <div class="bar">
        <p>Click the keys, or type. Arrows move, Enter, Backspace and Tab edit, Esc goes home, F1 to F6 are the shape keys. Shift, Fn, Ctrl and Alt toggle when clicked.</p>
        <button phx-click="reboot" class="reboot">Reboot</button>
      </div>
    </div>

    <script>
    window.hooks.Badge = {
      mounted() {
        const canvas = this.el.querySelector("#panel");
        const ctx = canvas.getContext("2d");
        ctx.imageSmoothingEnabled = false;
        this.assets = {};
        this.handleEvent("asset", ({id, w, h, rgba}) => {
          const bytes = Uint8ClampedArray.from(atob(rgba), c => c.charCodeAt(0));
          const off = document.createElement("canvas");
          off.width = w; off.height = h;
          off.getContext("2d").putImageData(new ImageData(bytes, w, h), 0, 0);
          this.assets[id] = off;
        });
        this.handleEvent("frame", ({items}) => {
          ctx.clearRect(0, 0, canvas.width, canvas.height);
          for (const it of items) {
            if (it.t === "rect") {
              ctx.fillStyle = it.c; ctx.fillRect(it.x, it.y, it.w, it.h);
            } else if (it.t === "img") {
              if (it.bg) { ctx.fillStyle = it.bg; ctx.fillRect(it.x, it.y, it.w, it.h); }
              const img = this.assets[it.id];
              if (img) ctx.drawImage(img, it.sx, it.sy, it.w / it.xs, it.h / it.ys, it.x, it.y, it.w, it.h);
            }
          }
        });
        this.handleEvent("backlight", ({level}) => { canvas.style.filter = `brightness(${level})`; });
        const keys = this.el.querySelectorAll("rect[data-key]");
        for (const key of keys) {
          key.addEventListener("pointerdown", (e) => {
            e.preventDefault();
            key.classList.add("down");
            this.pushEvent("press", {label: key.dataset.key});
          });
          for (const up of ["pointerup", "pointerleave"]) {
            key.addEventListener(up, () => key.classList.remove("down"));
          }
        }
        this.handleEvent("held", ({labels}) => {
          for (const key of keys) key.classList.toggle("held", labels.includes(key.dataset.key));
        });
        // Keys the badge takes must not also scroll or move focus in the browser.
        window.addEventListener("keydown", (e) => {
          const taken = e.key.startsWith("Arrow") || e.key.startsWith("F") ||
            ["Tab", "Backspace", " ", "Enter", "Escape"].includes(e.key);
          if (taken) e.preventDefault();
        });
      }
    }
    </script>

    <style type="text/css">
      body { background: #222; color: #ccc; font-family: sans-serif; padding: 1em; margin: 0; }
      #badge { outline: none; }
      .board { position: relative; height: calc(100vh - 6em); aspect-ratio: 508 / 608; max-width: 100%; }
      .board svg { display: block; width: 100%; height: 100%; }
      .board svg * { pointer-events: none; }
      .board svg rect[data-key] { pointer-events: all; cursor: pointer; }
      .board svg rect[data-key]:hover { fill: #3A3842; }
      .board svg rect[data-key].held { fill: #5B5470; stroke: #F6F2EA; }
      .board svg rect[data-key].down { fill: #15141A; }
      #panel { position: absolute; image-rendering: pixelated; transition: filter 0.3s; }
      .bar { display: flex; gap: 1em; align-items: center; max-width: 60em; }
      .bar p { margin: 0; font-size: 0.9em; }
      button { padding: 0.4em 0.8em; background: #111; color: #ccc; border: 1px solid #444; border-radius: 4px; cursor: pointer; }
    </style>
    """
  end
end
