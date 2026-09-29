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
  alias Badge.Sim.Console
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
    if connected?(socket) do
      Display.attach(self())
      Console.subscribe(self())
    end

    {:ok, assign(socket, held: [])}
  end

  @impl true
  def handle_info({:asset, asset}, socket), do: {:noreply, push_event(socket, "asset", asset)}

  def handle_info({:log, lines}, socket),
    do: {:noreply, push_event(socket, "log", %{lines: lines})}

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
    <main id="badge" phx-hook="Badge" phx-window-keydown="key" tabindex="0">
      <section class="device">
        <div class="board" id="board" phx-update="ignore">
          {@svg}
          <canvas id="panel" width={@panel_width} height={@panel_height} style={@screen}></canvas>
        </div>
        <footer class="hint">
          <p>Click or type. F1–F6 are the shape keys.</p>
          <button phx-click="reboot" class="cap">Reboot</button>
        </footer>
      </section>

      <section class="bench" id="bench" phx-update="ignore" data-view="screen">
        <nav class="views" aria-label="Side panel">
          <button class="cap" data-show="screen" aria-pressed="true">Screen</button>
          <button class="cap" data-show="log" aria-pressed="false">Log</button>
          <button class="cap" data-show="both" aria-pressed="false">Both</button>
        </nav>
        <div class="stage">
          <canvas id="big" width={@panel_width} height={@panel_height}></canvas>
        </div>
        <ol class="log" id="log" aria-live="off"></ol>
      </section>
    </main>

    <script>
    window.hooks.Badge = {
      mounted() {
        const canvas = this.el.querySelector("#panel");
        const ctx = canvas.getContext("2d");
        ctx.imageSmoothingEnabled = false;
        const big = this.el.querySelector("#big");
        const bigCtx = big.getContext("2d");
        bigCtx.imageSmoothingEnabled = false;
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
          bigCtx.clearRect(0, 0, big.width, big.height);
          bigCtx.drawImage(canvas, 0, 0);
        });
        this.handleEvent("backlight", ({level}) => {
          for (const c of [canvas, big]) c.style.filter = `brightness(${level})`;
        });

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

        const bench = this.el.querySelector("#bench");
        const views = bench.querySelectorAll("[data-show]");
        const show = (view) => {
          bench.dataset.view = view;
          for (const b of views) b.setAttribute("aria-pressed", String(b.dataset.show === view));
          try { localStorage.setItem("sim-view", view); } catch (_) {}
        };
        for (const b of views) b.addEventListener("click", () => show(b.dataset.show));
        try { const saved = localStorage.getItem("sim-view"); if (saved) show(saved); } catch (_) {}

        const log = bench.querySelector("#log");
        this.handleEvent("log", ({lines}) => {
          const pinned = log.scrollHeight - log.scrollTop - log.clientHeight < 24;
          for (const line of lines) {
            const li = document.createElement("li");
            const m = line.match(/^([\w.]+:)(.*)$/);
            if (m) {
              const tag = document.createElement("span");
              tag.className = "tag"; tag.textContent = m[1];
              li.append(tag, m[2]);
            } else {
              li.textContent = line;
            }
            log.append(li);
          }
          while (log.children.length > 1000) log.firstChild.remove();
          if (pinned) log.scrollTop = log.scrollHeight;
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
      :root {
        --desk: #1D1C21;
        --board: #DDD7CC;
        --key: #2A2830;
        --key-edge: #15141A;
        --bezel: #3A3842;
        --legend: #F6F2EA;
        --dim: #9A96A6;
        --mono: 'DejaVu Sans Mono', Menlo, 'SF Mono', Monaco, Consolas, 'Liberation Mono', monospace;
        --gap: 24px;
        --hint: 44px;
        --board-w: min(calc((100vh - 2 * var(--gap) - var(--hint) - 12px) * 508 / 608), calc(100vw - 2 * var(--gap)));
      }
      html, body { height: 100%; }
      body { margin: 0; background: var(--desk); color: var(--legend); font-family: var(--mono); }
      #badge { outline: none; box-sizing: border-box; height: 100vh; padding: var(--gap); display: flex; gap: var(--gap); }

      .device { display: flex; flex-direction: column; gap: 12px; flex: none; width: var(--board-w); }
      .board { position: relative; width: 100%; aspect-ratio: 508 / 608; }
      .board svg { display: block; width: 100%; height: 100%; }
      .board svg * { pointer-events: none; }
      .board svg rect[data-key] { pointer-events: all; cursor: pointer; }
      .board svg rect[data-key]:hover { fill: var(--bezel); }
      .board svg rect[data-key].held { fill: #5B5470; stroke: var(--legend); }
      .board svg rect[data-key].down { fill: var(--key-edge); }
      #panel { position: absolute; image-rendering: pixelated; transition: filter 0.3s; }

      /* Inset to the key grid's outer edges in the drawing. */
      .hint { display: flex; align-items: center; gap: 16px; min-height: var(--hint); padding: 0 5.9%; }
      .hint p { flex: 1; margin: 0; font-size: 12px; line-height: 1.5; color: var(--dim); text-wrap: pretty; }

      .cap {
        font: 500 12px/1 var(--mono); color: var(--legend); background: var(--key);
        border: 1.5px solid var(--key-edge); border-radius: 5px; padding: 8px 14px; cursor: pointer;
        box-shadow: inset 0 -2px 0 var(--key-edge);
      }
      .cap:hover { background: var(--bezel); }
      .cap:active { box-shadow: none; transform: translateY(1px); }
      .cap:focus-visible { outline: 2px solid var(--board); outline-offset: 2px; }
      .cap[aria-pressed="true"] { background: var(--board); color: var(--key); }

      .bench {
        flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 16px;
        background: var(--key); border: 1px solid var(--bezel); border-radius: 12px; padding: 16px;
      }
      .views { display: flex; gap: 8px; }
      .stage { flex: 1; min-height: 0; container-type: size; display: grid; place-items: center; }
      #big {
        width: min(100cqw, 100cqh * 4 / 3); height: auto; aspect-ratio: 4 / 3;
        image-rendering: pixelated; transition: filter 0.3s;
        border: 8px solid var(--bezel); border-radius: 4px; box-sizing: border-box;
      }
      .log {
        flex: 1; min-height: 0; overflow-y: auto; margin: 0; padding: 12px 14px; list-style: none;
        background: #050506; border-radius: 6px; font-size: 12px; line-height: 1.6; color: #D8D3E0;
        white-space: pre-wrap; overflow-wrap: anywhere;
      }
      .log .tag { color: #9B6BE8; }
      .log:empty::before { content: "Nothing logged yet."; color: var(--dim); }
      .bench[data-view="screen"] .log { display: none; }
      .bench[data-view="log"] .stage { display: none; }
      .bench[data-view="both"] .stage { flex: 3; }
      .bench[data-view="both"] .log { flex: 2; }

      @media (max-width: 1100px) {
        #badge { height: auto; min-height: 100vh; justify-content: center; }
        .bench { display: none; }
      }
      @media (prefers-reduced-motion: reduce) {
        #panel, #big { transition: none; }
      }
    </style>
    """
  end
end
