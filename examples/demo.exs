# A gallery of every piece, as a Phoenix app in one file:
#
#     elixir examples/demo.exs
#
# then open http://localhost:4000 (set PORT to use another). The index shows
# frame 0 of all the pieces by category: text pieces through
# AsciiArt.Phoenix.Components.ascii/1, coloured ones drawn on a canvas. Each
# opens a page that plays it with AsciiArt.Phoenix.player/1, where you can
# try its options, paper (dark ink on a light page), one ink, the colour of
# that ink (one, or several in a gradient: AsciiArt.Ink) and, for pieces that
# know their parts, a colour for each part (AsciiArt.Parts), and for pieces
# that can be used, keys and clicks. /dashboard shows the UI and data pieces
# as live widgets, fed this very BEAM's figures (AsciiArt.BEAM) and its
# LiveViews' telemetry (AsciiArt.Telemetry); /widgets, the ones you can use;
# /piece/<slug>/svg, a piece as an SVG.
Mix.install([
  {:ascii_art, path: Path.expand("..", __DIR__)},
  {:phoenix_live_view, "~> 1.1"},
  {:bandit, "~> 1.5"}
])

port = String.to_integer(System.get_env("PORT", "4000"))

Application.put_env(:phoenix, :json_library, JSON)

Application.put_env(:demo, Demo.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: port],
  server: true,
  secret_key_base: String.duplicate("ascii_art_demo", 5),
  live_view: [signing_salt: "ascii_art_demo"]
)

defmodule Demo.Layout do
  use Phoenix.Component

  def render("root.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>ascii_art gallery</title>
        <style>
          :root { --bg: #111; --ink: #ddd; --dim: #888; --card: #181818; --line: #2a2a2a; --accent: #7fdbca; }
          body { margin: 0; background: var(--bg); color: var(--ink); font: 14px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
          a { color: inherit; }
          main { padding: 1.5rem 2rem 4rem; }
          h1 { font-size: 20px; margin: 0 0 .25rem; } h2 { font-size: 15px; margin: 2.5rem 0 1rem; }
          h2 small, .note, .facts { color: var(--dim); }
          nav.cats { display: flex; flex-wrap: wrap; gap: .25rem 1rem; margin-top: .75rem; }
          .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem; }
          .card { display: block; text-decoration: none; background: var(--card); border: 1px solid var(--line); border-radius: 6px; padding: 10px; }
          .card:hover { border-color: #555; }
          .art { height: 180px; display: flex; align-items: center; justify-content: center; overflow: hidden; }
          .art pre { font-size: min(9px, calc(280px / (var(--cols) * 0.6))); }
          .art canvas { display: block; max-width: 100%; max-height: 180px; }
          .name { margin-top: 8px; } .note { font-size: 12px; }
          .page { min-height: 100vh; }
          .page.paper { --bg: #f4f1ea; --ink: #222; --dim: #777; --card: #fff; --line: #ddd; --accent: #1b7c83; background: var(--bg); color: var(--ink); }
          .stage { margin: 1.5rem 0; max-width: 1000px; }
          .stage pre { font-size: min(16px, calc(min(100vw - 4rem, 1000px) / (var(--cols) * 0.6))); }
          form { display: grid; gap: .75rem; max-width: 640px; }
          label { display: grid; gap: .25rem; }
          .hint { color: var(--dim); font-size: 12px; }
          textarea { width: 100%; min-height: 8rem; font: inherit; background: var(--card); color: var(--ink); border: 1px solid var(--line); }
          input[type=text], select { font: inherit; background: var(--card); color: var(--ink); border: 1px solid var(--line); padding: .2rem .4rem; }
          .ink { display: grid; grid-template-columns: 1fr auto; gap: .75rem; align-items: end; }
          .presets { display: flex; flex-wrap: wrap; gap: .25rem 1rem; font-size: 12px; }
          fieldset.parts { border: 1px solid var(--line); border-radius: 6px; padding: .5rem .75rem .75rem; }
          fieldset.parts legend { padding: 0 .25rem; }
          .part-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); gap: .5rem .75rem; margin-top: .5rem; }
          .part-list input { width: 100%; box-sizing: border-box; }
          .swatch { display: inline-block; width: .8em; height: .8em; border-radius: 2px; vertical-align: -.05em; margin-right: .3em; border: 1px solid var(--line); }
          button { justify-self: start; font: inherit; padding: .25rem 1rem; }
          .toggles { display: flex; flex-wrap: wrap; gap: .5rem 1.5rem; margin-bottom: 1.25rem; }
          .switch { display: inline-flex; align-items: center; gap: .6rem; background: none; border: 0; padding: 0; color: inherit; font: inherit; cursor: pointer; }
          .switch .track { position: relative; width: 2.2rem; height: 1.2rem; border-radius: 1rem; background: var(--line); transition: background .15s; }
          .switch .track::after { content: ""; position: absolute; top: .15rem; left: .15rem; width: .9rem; height: .9rem; border-radius: 50%; background: var(--ink); transition: transform .15s; }
          .switch[aria-checked="true"] .track { background: #5a9a78; }
          .switch[aria-checked="true"] .track::after { transform: translateX(1rem); }
          .error, [role=alert] { color: #e66; }
          .dash { display: grid; grid-template-columns: repeat(auto-fill, minmax(520px, 1fr)); gap: 1.5rem; margin-top: 1.5rem; }
          .widget { background: var(--card); border: 1px solid var(--line); border-radius: 6px; padding: 12px; }
          .widget h2 { margin: 0 0 .5rem; font-size: 13px; color: var(--dim); }
          .widget pre { font-size: 11.5px; }
        </style>
        <script src="/phoenix/phoenix.min.js"></script>
        <script src="/phoenix_live_view/phoenix_live_view.min.js"></script>
        <script type="module">
          import {AsciiArt} from "/ascii_art/ascii_art_hook.js";
          const csrf = document.querySelector("meta[name='csrf-token']").content;
          const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
            hooks: {AsciiArt},
            params: {_csrf_token: csrf},
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;

          // Back to where you were in the gallery: its scroll position is kept
          // for this tab as you leave it, and put back when you return, by the
          // browser's back button or by a "← gallery" link (a new visit to /,
          // which a browser would otherwise show from the top).
          const KEY = "ascii_art_gallery_scroll";
          if (document.querySelector("[data-gallery]")) {
            history.scrollRestoration = "manual";
            const nav = performance.getEntriesByType("navigation")[0];
            const returning = nav && ["back_forward", "reload"].includes(nav.type);
            const saved = sessionStorage.getItem(KEY);
            if (saved !== null && (returning || sessionStorage.getItem(KEY + "_return"))) {
              const restore = () => window.scrollTo(0, +saved);
              restore();
              // Again once loaded, in case a #category in the URL scrolled it since.
              addEventListener("load", restore, {once: true});
            }
            sessionStorage.removeItem(KEY + "_return");
            addEventListener("pagehide", () => sessionStorage.setItem(KEY, String(window.scrollY)));
          }
          document.addEventListener("click", (e) => {
            if (e.target.closest("a[data-to-gallery]")) sessionStorage.setItem(KEY + "_return", "1");
          });

          // The index's coloured stills: one frame each, drawn as the hook draws.
          const FONT = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace";
          for (const el of document.querySelectorAll("canvas[data-still]")) {
            const d = el.dataset, cols = +d.cols, rows = +d.rows, cell = +d.cell || 2;
            const palette = JSON.parse(d.palette);
            const colors = Uint8Array.from(atob(d.colors), (c) => c.charCodeAt(0));
            const fit = Math.min(280 / cols, 180 / (rows * cell));
            const dpr = window.devicePixelRatio || 1;
            el.style.width = `${fit * cols}px`;
            el.width = Math.round(fit * cols * dpr);
            el.height = Math.round(fit * cell * rows * dpr);
            const ctx = el.getContext("2d"), cw = el.width / cols, ch = el.height / rows;
            if (d.ground) { ctx.fillStyle = d.ground; ctx.fillRect(0, 0, el.width, el.height); }
            ctx.font = `${cw / 0.6}px ${FONT}`;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            let x = 0, y = 0;
            for (const c of d.text) {
              if (c === "\n") { x = 0; y++; continue; }
              if (c !== " ") {
                ctx.fillStyle = palette[colors[y * cols + x]] || palette[0];
                ctx.fillText(c, (x + 0.5) * cw, (y + 0.5) * ch);
              }
              x++;
            }
          }
        </script>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end

defmodule Demo.Gallery do
  # The order of the index: by category, upstream's order of categories,
  # then by slug. Pieces' prev and next links follow it too.
  def slugs,
    do:
      for(
        category <- AsciiArt.Meta.categories(),
        slug <- AsciiArt.pieces(category: category),
        do: slug
      )
end

defmodule Demo.Stills do
  # Frame 0 of every piece, worked out once at boot, in parallel (a scene
  # takes up to a second or so to set up), and kept for the index.
  use Agent
  use Phoenix.Component

  def start_link(_), do: Agent.start_link(&build/0, name: __MODULE__)

  def all, do: Agent.get(__MODULE__, & &1)

  defp build do
    Demo.Gallery.slugs()
    |> Task.async_stream(&still/1, timeout: :infinity)
    |> Enum.map(fn {:ok, still} -> still end)
  end

  defp still(slug) do
    meta = AsciiArt.meta!(slug)
    Map.merge(%{slug: slug, meta: meta}, picture(slug, meta))
  end

  # Coloured pieces as data for a canvas; text pieces as the component draws them.
  defp picture(slug, %{palette: palette} = meta) when palette != nil do
    {frame, _anim} = slug |> AsciiArt.new!() |> AsciiArt.frame(0.0)

    %{
      kind: :canvas,
      text: frame.text,
      colors: Base.encode64(frame.colors),
      palette: JSON.encode!(frame.palette),
      ground: frame.ground,
      cell: meta.cell
    }
  end

  defp picture(slug, _meta) do
    assigns = %{slug: slug}

    html =
      ~H"""
      <AsciiArt.Phoenix.Components.ascii piece={@slug} />
      """
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    %{kind: :text, html: html}
  end
end

defmodule Demo.GalleryHTML do
  use Phoenix.Component

  def index(assigns) do
    # The stills are in gallery order, so already grouped by category.
    groups =
      assigns.stills
      |> Enum.chunk_by(& &1.meta.category)
      |> Enum.map(&{hd(&1).meta.category, &1})

    # From a controller, assigns is a plain map.
    assigns = Map.put(assigns, :groups, groups)

    ~H"""
    <main data-gallery>
      <h1>ascii_art</h1>
      <div class="note">
        {length(@stills)} pieces from <a href="https://ascii.rest">ascii.rest</a>
        by <a href="https://github.com/bas3line">@bas3line</a>, drawn by Elixir. Each opens to play.
        The UI and data pieces also take live data: see the <a href="/dashboard">dashboard</a>,
        and some can be used: see the <a href="/widgets">widgets</a>.
      </div>
      <nav class="cats">
        <a :for={{category, stills} <- @groups} href={"##{category}"}>{category} ({length(stills)})</a>
      </nav>
      <section :for={{category, stills} <- @groups} id={category}>
        <h2>{category} <small>{length(stills)}</small></h2>
        <div class="grid">
          <a :for={s <- stills} class="card" href={"/piece/#{s.slug}"}>
            <div class="art" style={"--cols: #{s.meta.cols}"}>
              <canvas
                :if={s.kind == :canvas}
                data-still
                data-cols={s.meta.cols}
                data-rows={s.meta.rows}
                data-cell={s.cell}
                data-palette={s.palette}
                data-ground={s.ground}
                data-text={s.text}
                data-colors={s.colors}
                role="img"
                aria-label={s.meta.name}
              ></canvas>
              {if s.kind == :text, do: Phoenix.HTML.raw(s.html)}
            </div>
            <div class="name">{s.meta.name}</div>
            <div class="note">{s.meta.note}</div>
          </a>
        </div>
      </section>
    </main>
    """
  end
end

defmodule Demo.GalleryController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    conn |> put_view(html: Demo.GalleryHTML) |> render(:index, stills: Demo.Stills.all())
  end
end

defmodule Demo.SVGController do
  # A frame of a piece as an SVG (AsciiArt.Render.SVG), drawn as its page
  # shows it: the same options, paper, one ink and parts, from the query.
  use Phoenix.Controller, formats: []

  def show(conn, %{"slug" => slug} = params) do
    paper = params["paper"] == "1"

    opts = [
      options: decode(params["options"]),
      paper: paper,
      color: params["mono"] != "1",
      ink: blank_nil(params["ink"]),
      gradient: blank_nil(params["gradient"]),
      parts: for({k, v} <- params["parts"] || %{}, is_binary(v) and v != "", into: %{}, do: {k, v})
    ]

    case AsciiArt.new(slug, opts) do
      {:ok, anim} ->
        {frame, _} = AsciiArt.frame(anim, 0.0)

        svg =
          AsciiArt.Render.SVG.render(frame,
            title: AsciiArt.describe(anim),
            background: frame.ground || if(paper, do: "#f4f1ea", else: "#111111"),
            foreground: if(paper, do: "#222222", else: "#dddddd")
          )

        conn |> put_resp_content_type("image/svg+xml") |> send_resp(200, svg)

      {:error, reason} ->
        send_resp(conn, 400, inspect(reason))
    end
  end

  defp decode(nil), do: %{}

  defp decode(text) do
    case JSON.decode(text) do
      {:ok, options} when is_map(options) -> options
      _ -> %{}
    end
  end

  defp blank_nil(value) when value in [nil, ""], do: nil
  defp blank_nil(value), do: value
end

defmodule Demo.PieceLive do
  use Phoenix.LiveView

  @gradients %{"horizontal" => :horizontal, "vertical" => :vertical, "diagonal" => :diagonal}

  # Inks to try at a click: {name, colours, gradient}.
  @presets [
    {"amber", "#ffb000", nil},
    {"mint", "#7fdbca", nil},
    {"sunset", "#ff5f6d,#ffc371", nil},
    {"ocean", "#36d1dc,#5b86e5", "vertical"},
    {"rainbow", "#ff3b30,#ff9500,#ffcc00,#34c759,#5ac8fa,#af52de", "diagonal"},
    {"the page's --accent", "var(--accent, #7fdbca)", nil}
  ]

  # What the URL keeps from page to page: prev and next carry all but options.
  @carried ["paper", "mono", "ink", "gradient"]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case AsciiArt.meta(slug) do
      {:ok, meta} ->
        slugs = Demo.Gallery.slugs()
        i = Enum.find_index(slugs, &(&1 == slug))

        {:ok, module} = AsciiArt.resolve(slug)

        {:ok,
         assign(socket,
           slug: slug,
           meta: meta,
           # A piece that can be used takes keys and clicks here.
           usable?: function_exported?(module, :handle_event, 2),
           told: nil,
           prev: Enum.at(slugs, i - 1),
           next: Enum.at(slugs, rem(i + 1, length(slugs)))
         )}

      {:error, :unknown_piece} ->
        {:ok, assign(socket, slug: slug, meta: nil)}
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{meta: nil}} = socket), do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    meta = socket.assigns.meta
    paper = params["paper"] == "1"
    mono = params["mono"] == "1"
    text = params["options"] || JSON.encode!(meta.options)
    ink_text = String.trim(params["ink"] || "")
    gradient = Map.get(@gradients, params["gradient"], :horizontal)

    {options, options_error} =
      case JSON.decode(text) do
        {:ok, options} when is_map(options) -> {options, nil}
        _ -> {%{}, "options must be a JSON object; playing with the defaults"}
      end

    # Parts with a colour typed in: the form sends every part, most empty.
    given =
      for {name, color} <- (is_map(params["parts"]) && params["parts"]) || %{},
          is_binary(color) and String.trim(color) != "",
          into: %{},
          do: {name, String.trim(color)}

    {parts, parts_error} =
      case AsciiArt.Parts.cast(given, meta) do
        {:ok, _} ->
          {given, nil}

        {:error, _} ->
          {%{}, "parts take colours like #58a6ff, one a part; playing without"}
      end

    {ink, ink_error} =
      case AsciiArt.Ink.cast(ink_text) do
        {:ok, nil} ->
          {nil, nil}

        {:ok, _ink} ->
          {ink_text, nil}

        {:error, _} ->
          {nil, "ink takes up to 16 colours like #ff5f6d, comma-separated; playing without"}
      end

    # A new id for new settings, so the embedded player starts afresh.
    id =
      "player-#{:erlang.phash2({socket.assigns.slug, options, paper, mono, ink, gradient, parts})}"

    {:noreply,
     assign(socket,
       paper: paper,
       mono: mono,
       options: options,
       options_text: text,
       ink: ink,
       ink_text: ink_text,
       gradient: gradient,
       parts: parts,
       given: Map.new(meta.parts, fn {name, _} -> {name, Map.get(given, name, "")} end),
       errors: Enum.reject([options_error, ink_error, parts_error], &is_nil/1),
       player_id: id,
       # Parts are the piece's own, so prev and next do not carry them.
       query: Map.take(params, ["options", "parts" | @carried])
     )}
  end

  # A switch flips its setting in the URL, so the page and the player follow
  # at once, and a reload or a shared link keeps it.
  @impl true
  def handle_event("toggle", %{"key" => key}, socket) when key in ["paper", "mono"] do
    query = socket.assigns.query
    query = if query[key] == "1", do: Map.delete(query, key), else: Map.put(query, key, "1")
    {:noreply, push_patch(socket, to: path(socket.assigns.slug, query))}
  end

  # What a piece that can be used tells of its keys and clicks (notify).
  @impl true
  def handle_info({:ascii_art, _id, info}, socket),
    do: {:noreply, assign(socket, told: info)}

  defp path(slug, query) when map_size(query) == 0, do: "/piece/#{slug}"
  defp path(slug, query), do: "/piece/#{slug}?" <> Plug.Conn.Query.encode(query)

  # The colours the piece suggests for its parts, for the page it is on.
  defp suggested(meta, paper), do: AsciiArt.Parts.suggested(meta, paper: paper)

  defp preset(query, ink, nil), do: query |> Map.put("ink", ink) |> Map.delete("gradient")
  defp preset(query, ink, gradient), do: Map.merge(query, %{"ink" => ink, "gradient" => gradient})

  @impl true
  def render(%{meta: nil} = assigns) do
    ~H"""
    <main>
      <a href="/" data-to-gallery>← gallery</a>
      <h1>no piece called {inspect(@slug)}</h1>
    </main>
    """
  end

  def render(assigns) do
    colored? = assigns.meta.palette != nil

    assigns =
      assign(assigns,
        colored?: colored?,
        # A coloured piece keeps its palette; in one ink, it takes the ink too.
        inkable?: not colored? or assigns.mono,
        presets: @presets,
        gradients: ~w(horizontal vertical diagonal),
        carried: Map.take(assigns.query, @carried)
      )

    ~H"""
    <div class={["page", @paper && "paper"]}>
      <main>
        <nav>
          <a href="/" data-to-gallery>← gallery</a> ·
          <a href={path(@prev, @carried)}>← {@prev}</a> ·
          <a href={path(@next, @carried)}>{@next} →</a>
        </nav>
        <h1 style="margin-top: 1rem">{@meta.name}</h1>
        <div class="note">{@meta.note}</div>
        <div class="facts">
          {@meta.category} · {@meta.cols}×{@meta.rows} · {@meta.fps} fps{if @meta.loop, do: " · a #{@meta.loop} s loop"} · <code>{@slug}</code>
        </div>
        <div class="stage" style={"--cols: #{@meta.cols}"}>
          <AsciiArt.Phoenix.player
            socket={@socket}
            id={@player_id}
            piece={@slug}
            options={@options}
            paper={@paper}
            mono={@mono}
            ink={@ink}
            gradient={@gradient}
            parts={@parts}
            interactive={@usable?}
            notify={@usable?}
          />
        </div>
        <p :if={@usable?} class="note">
          This one can be used: click it or tab to it, then the arrows, space, enter and typing. Its options say
          what it takes (a file tree with <code>"walk": false</code>, a form with <code>"fields"</code>, a calendar
          with a <code>"date"</code>).
          <span :if={@told}>
            Last: <code>{inspect(@told.event)}</code><span :if={@told.part}> on <code>{@told.part}</code> <code>{inspect(@told.text)}</code></span>.
          </span>
        </p>
        <div class="toggles">
          <button type="button" class="switch" role="switch" aria-checked={to_string(@paper)} phx-click="toggle" phx-value-key="paper">
            <span class="track"></span> paper: dark ink on a light page
          </button>
          <button :if={@colored?} type="button" class="switch" role="switch" aria-checked={to_string(@mono)} phx-click="toggle" phx-value-key="mono">
            <span class="track"></span> one ink
          </button>
        </div>
        <form :if={@meta.options != %{} or @inkable?} method="get" action={"/piece/#{@slug}"}>
          <input :if={@paper} type="hidden" name="paper" value="1" />
          <input :if={@mono} type="hidden" name="mono" value="1" />
          <label :if={@meta.options != %{}}>
            options
            <span class="hint">
              a JSON object of the piece's own options, each value of the same kind as its default
            </span>
            <textarea name="options">{@options_text}</textarea>
          </label>
          <div :if={@inkable?} class="ink">
            <label>
              ink
              <span class="hint">
                one colour, or several (comma-separated) for a gradient, or a CSS variable,
                var(--accent, #7fdbca); empty for the page's own
              </span>
              <input type="text" name="ink" value={@ink_text} placeholder="#ff5f6d, #ffc371" />
            </label>
            <label>
              gradient
              <select name="gradient">
                <option :for={g <- @gradients} value={g} selected={Atom.to_string(@gradient) == g}>{g}</option>
              </select>
            </label>
          </div>
          <div :if={@inkable?} class="presets">
            try:
            <.link :for={{name, ink, gradient} <- @presets} patch={path(@slug, preset(@query, ink, gradient))}>{name}</.link>
            <.link patch={path(@slug, Map.drop(@query, ["ink", "gradient"]))}>no ink</.link>
          </div>
          <fieldset :if={@meta.parts != []} class="parts">
            <legend>parts</legend>
            <span class="hint">
              a colour for any of the piece's parts, over the ink; a part left empty takes the ink.
              A name covers the ones under it: file colours every file.ts and file.md unless they have their own.
            </span>
            <div class="presets" style="margin-top: .5rem">
              <.link patch={path(@slug, Map.put(@query, "parts", suggested(@meta, @paper)))}>the piece's suggested colours</.link>
              <.link patch={path(@slug, Map.delete(@query, "parts"))}>no parts</.link>
            </div>
            <div class="part-list">
              <label :for={{name, suggestion} <- @meta.parts}>
                <span><span :if={@parts[name]} class="swatch" style={"background: #{@parts[name]}"}></span>{name}</span>
                <input type="text" name={"parts[#{name}]"} value={@given[name]} placeholder={suggestion || "the ink"} />
              </label>
            </div>
          </fieldset>
          <%!-- A coloured piece in colour ignores an ink, but keeps it for one ink. --%>
          <input :if={not @inkable? and @ink_text != ""} type="hidden" name="ink" value={@ink_text} />
          <input :if={not @inkable? and @query["gradient"]} type="hidden" name="gradient" value={@query["gradient"]} />
          <button>play</button>
        </form>
        <p :for={error <- @errors} class="error">{error}</p>
        <p class="note">
          In a terminal: <code>mix ascii_art.play {@slug}</code> ·
          as a picture: <a href={"/piece/#{@slug}/svg" <> if(@query == %{}, do: "", else: "?" <> Plug.Conn.Query.encode(@query))}>svg</a>
          (<code>mix ascii_art.svg {@slug}</code>)
        </p>
      </main>
    </div>
    """
  end
end

defmodule Demo.DashboardLive do
  # The UI and data pieces as live widgets: this BEAM's schedulers, memory,
  # run queue and busiest processes, sampled every second by AsciiArt.BEAM,
  # and the LiveViews' own telemetry through AsciiArt.Telemetry. Each widget
  # is AsciiArt.Phoenix.live_player/1, given new options from the assigns;
  # it carries on from where it was (the gauge's needle swings, the
  # sparkline scrolls), and the browser is sent only the cells that change.
  use Phoenix.LiveView

  alias AsciiArt.BEAM

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(1000, :sample)
      AsciiArt.Telemetry.subscribe(Demo.Readings)
    end

    {:ok, assign(socket, stats: BEAM.sample(), parts: true, readings: [])}
  end

  @impl true
  def handle_info(:sample, socket),
    do: {:noreply, assign(socket, stats: BEAM.sample(socket.assigns.stats))}

  def handle_info({:ascii_art_telemetry, _feed, readings}, socket),
    do: {:noreply, assign(socket, readings: readings)}

  # The widgets' parts in the colours they suggest (AsciiArt.Parts), or not.
  @impl true
  def handle_event("parts", _params, socket),
    do: {:noreply, assign(socket, parts: not socket.assigns.parts)}

  # Busy work for every scheduler, for three seconds, to watch the widgets move.
  def handle_event("work", _params, socket) do
    for _ <- 1..System.schedulers_online() do
      spawn(fn -> spin(System.monotonic_time(:millisecond) + 3000) end)
    end

    {:noreply, socket}
  end

  defp spin(until) do
    if System.monotonic_time(:millisecond) < until do
      Enum.sum(1..1000)
      spin(until)
    end
  end

  @impl true
  def render(assigns) do
    s = assigns.stats

    assigns =
      assign(assigns,
        meters: BEAM.cpu_meters(s),
        series: BEAM.sparkline(s),
        busy: BEAM.gauge(s),
        memory: Map.put(BEAM.progress_bar(s), :style, 1),
        telemetry: AsciiArt.Telemetry.sparkline(assigns.readings)
      )

    ~H"""
    <main>
      <nav><a href="/" data-to-gallery>← gallery</a> · <a href="/widgets">widgets you can use</a></nav>
      <h1 style="margin-top: 1rem">dashboard</h1>
      <div class="note">
        This BEAM, sampled every second by <code>AsciiArt.BEAM</code>, and its LiveViews' telemetry by
        <code>AsciiArt.Telemetry</code>. Each widget is <code>AsciiArt.Phoenix.live_player/1</code>,
        given new options from this LiveView's assigns, and labelled for screen readers with what it shows.
        In a terminal, the same: <code>mix ascii_art.top</code>.
        <button type="button" phx-click="work">make work</button>
      </div>
      <div class="toggles" style="margin-top: 1rem">
        <button type="button" class="switch" role="switch" aria-checked={to_string(@parts)} phx-click="parts">
          <span class="track"></span> parts in colour: <code>parts</code>, each widget's suggested colours
        </button>
      </div>
      <div class="dash">
        <section class="widget" style="grid-column: 1 / -1">
          <h2>cpu-meters: schedulers, memory, run queue, busiest processes</h2>
          <AsciiArt.Phoenix.live_player id="meters" piece="cpu-meters" options={@meters} parts={@parts} />
        </section>
        <section class="widget">
          <h2>gauge: scheduler use</h2>
          <AsciiArt.Phoenix.live_player id="busy" piece="gauge" options={@busy} parts={@parts} />
        </section>
        <section class="widget">
          <h2>progress-bar: where the memory goes</h2>
          <AsciiArt.Phoenix.live_player id="memory" piece="progress-bar" options={@memory} parts={@parts} />
        </section>
        <section class="widget" style="grid-column: 1 / -1">
          <h2>sparkline: the last two minutes</h2>
          <AsciiArt.Phoenix.live_player id="history" piece="sparkline" options={@series} parts={@parts} />
        </section>
        <section :if={@readings != []} class="widget" style="grid-column: 1 / -1">
          <h2>sparkline from telemetry: the LiveViews' renders and component updates a second, and a render's time</h2>
          <AsciiArt.Phoenix.live_player id="telemetry" piece="sparkline" options={@telemetry} parts={@parts} />
        </section>
      </div>
    </main>
    """
  end
end

defmodule Demo.WidgetsLive do
  # Components you can use: keys and clicks go to the piece (interactive),
  # and this LiveView is told of each one (notify), to show what was chosen.
  # Click a picture, or tab to it, then use the arrows, space, enter and
  # typing.
  use Phoenix.LiveView

  @root Path.expand("..", __DIR__)

  @fields [
    %{type: "text", label: "name", text: "ada"},
    %{type: "select", label: "plan", choices: ["hobby", "team", "enterprise"], choice: 1},
    %{type: "radio", label: "theme", choices: ["light", "dark", "system"], choice: 2},
    %{type: "checkbox", label: "notify", choices: ["email", "sms"], checked: [true, false]},
    %{type: "switch", label: "sync", on: true},
    %{type: "slider", label: "volume", value: 40, min: 0, max: 100, step: 5, unit: "%"}
  ]

  @deploy [
    {"fetched the release", "ok"},
    {"built assets", "ok"},
    {"ran the migrations", "ok"},
    {"cache warm-up was slow", "warn"},
    {"rolled out to 3 nodes", "ok"},
    {"health check on node 3", "fail"},
    {"rolled back node 3", "ok"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    paths =
      Path.wildcard(Path.join(@root, "lib/**/*.ex"))
      |> Enum.map(&Path.relative_to(&1, @root))
      |> Enum.reject(&String.contains?(&1, "/pieces/"))
      |> Enum.sort()

    {:ok,
     assign(socket,
       paths: paths,
       file: nil,
       # What the form and calendar start with, given them once; what they
       # tell of their keys is shown, never given back, as they have it
       # already, and a key typed meanwhile would be undone.
       fields: @fields,
       today: Date.utc_today() |> Date.to_iso8601(),
       date: Date.utc_today() |> Date.to_iso8601(),
       steps: [],
       told: nil
     )}
  end

  # What the players tell us: the file opened, the form's values, the date.
  @impl true
  def handle_info({:ascii_art, id, info} = told, socket) do
    socket = assign(socket, told: inspect(Map.delete(info, :options), limit: 6))
    {:noreply, take(socket, id, told)}
  end

  def handle_info({:deploy, [{text, status} | rest]}, socket) do
    steps = List.update_at(socket.assigns.steps, -1, &%{&1 | status: status, text: text})
    steps = if rest == [], do: steps, else: steps ++ [%{text: next_text(rest), status: "busy"}]
    if rest != [], do: Process.send_after(self(), {:deploy, rest}, 900)
    {:noreply, assign(socket, steps: steps)}
  end

  defp next_text([{text, _} | _]), do: text

  defp take(socket, "files", {_, _, %{event: {:key, "enter"}, options: %{cursor: path}}}),
    do: open(socket, path)

  defp take(socket, "files", {_, _, %{event: {:click, _, _}, part: "file" <> _, options: options}}),
    do: open(socket, options.cursor)

  defp take(socket, "form", {_, _, %{options: options}}), do: assign(socket, fields: options.fields)
  defp take(socket, "calendar", {_, _, %{options: options}}), do: assign(socket, date: options.date)
  defp take(socket, _id, _told), do: socket

  defp open(socket, path) do
    full = Path.join(@root, path)

    if File.regular?(full) do
      lines = full |> File.stream!() |> Enum.take(12) |> Enum.map(&String.trim_trailing/1)
      assign(socket, file: %{command: "head -n 12 " <> path, output: lines})
    else
      socket
    end
  end

  @impl true
  def handle_event("deploy", _params, socket) do
    [{text, _} | _] = @deploy
    Process.send_after(self(), {:deploy, @deploy}, 900)
    {:noreply, assign(socket, steps: [%{text: text, status: "busy"}])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <nav><a href="/" data-to-gallery>← gallery</a> · <a href="/dashboard">dashboard</a></nav>
      <h1 style="margin-top: 1rem">widgets you can use</h1>
      <div class="note">
        Each is <code>live_player/1</code> with <code>interactive</code> and <code>notify</code>: click it or tab to it,
        then use the arrows, space, enter and typing. The piece takes the keys (<code>AsciiArt.handle_event/2</code>),
        and this LiveView is told of each, with the part clicked.
      </div>
      <p class="note">last told: <code>{@told || "nothing yet"}</code></p>
      <div class="dash">
        <section class="widget">
          <h2>file-tree: this library's lib/ (enter or click a file to open it)</h2>
          <AsciiArt.Phoenix.live_player
            id="files"
            piece="file-tree"
            options={%{walk: false, paths: @paths, root: "ascii_art", cols: 56, rows: 24}}
            parts
            interactive
            notify
          />
        </section>
        <section class="widget">
          <h2>terminal: the file opened</h2>
          <AsciiArt.Phoenix.live_player
            id="file"
            piece="terminal"
            options={%{prompt: "$", title: "ascii_art", history: [@file || %{output: ["enter or click a file in the tree to open it here"]}], typing: true, cols: 66, rows: 18}}
            parts
          />
        </section>
        <section class="widget">
          <h2>form-controls: a form you describe</h2>
          <AsciiArt.Phoenix.live_player id="form" piece="form-controls" options={%{fields: fields(), title: "settings"}} parts interactive notify />
          <p class="note">values: <code>{inspect(Enum.map(@fields, &Map.take(&1, [:text, :choice, :checked, :on, :value])))}</code></p>
        </section>
        <section class="widget">
          <h2>calendar: a date picker, the 1st and 15th marked</h2>
          <AsciiArt.Phoenix.live_player
            id="calendar"
            piece="calendar"
            options={%{date: @today, time: false, marks: marks(@today)}}
            parts
            interactive
            notify
          />
          <p class="note">picked: <code>{@date}</code></p>
        </section>
        <section class="widget">
          <h2>boot-log: a deploy, step by step <button type="button" phx-click="deploy">deploy</button></h2>
          <AsciiArt.Phoenix.live_player id="deploy" piece="boot-log" options={%{title: "deploy web", steps: @steps}} parts />
        </section>
        <section class="widget">
          <h2>digital-clock: a countdown</h2>
          <AsciiArt.Phoenix.live_player id="tea" piece="digital-clock" options={%{timer: "down", from: 300, label: "tea"}} parts />
        </section>
        <section class="widget">
          <h2>big-text: a heading in your palette, a letter at a time</h2>
          <AsciiArt.Phoenix.live_player
            id="heading"
            piece="big-text"
            options={%{text: "elixir"}}
            parts={%{"letter.1" => "#ff5f6d", "letter.2" => "#ff9f43", "letter.3" => "#ffd32a", "letter.4" => "#3fb950", "letter.5" => "#58a6ff", "letter.6" => "#a371f7", "shadow" => "#555555"}}
          />
        </section>
        <section class="widget">
          <h2>radar: your contacts</h2>
          <AsciiArt.Phoenix.live_player
            id="radar"
            piece="radar"
            options={%{contacts: [%{bearing: 40, range: 9}, %{bearing: 130, range: 18, size: 2}, %{bearing: 300, range: 14}], land: false}}
            parts
          />
        </section>
      </div>
    </main>
    """
  end

  defp fields, do: @fields

  defp marks(date) do
    {:ok, d} = Date.from_iso8601(date)
    for day <- [1, 15], do: Date.to_iso8601(%{d | day: day})
  end
end

defmodule Demo.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {Demo.Layout, :root})
  end

  scope "/" do
    pipe_through(:browser)
    get("/", Demo.GalleryController, :index)
    live("/piece/:slug", Demo.PieceLive)
    live("/dashboard", Demo.DashboardLive)
    live("/widgets", Demo.WidgetsLive)
    get("/piece/:slug/svg", Demo.SVGController, :show)
  end
end

defmodule Demo.Endpoint do
  use Phoenix.Endpoint, otp_app: :demo

  @session [store: :cookie, key: "_demo", signing_salt: "ascii_art_demo"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])

  plug(Plug.Static, at: "/phoenix", from: {:phoenix, "priv/static"})
  plug(Plug.Static, at: "/phoenix_live_view", from: {:phoenix_live_view, "priv/static"})
  plug(Plug.Static, at: "/ascii_art", from: {:ascii_art, "priv/static"})
  plug(Plug.Session, @session)
  plug(Demo.Router)
end

IO.puts("ascii_art gallery: drawing frame 0 of every piece...")
# The LiveViews' own telemetry, a reading a second, for the dashboard.
readings =
  {AsciiArt.Telemetry,
   name: Demo.Readings,
   metrics: [
     %{name: "renders", event: [:phoenix, :live_view, :render, :stop], measurement: :duration, kind: :counter},
     %{name: "updates", event: [:phoenix, :live_component, :update, :stop], measurement: :duration, kind: :counter},
     %{
       name: "render us",
       event: [:phoenix, :live_view, :render, :stop],
       measurement: &System.convert_time_unit(&1.duration, :native, :microsecond),
       kind: :summary,
       unit: "us"
     }
   ]}

{:ok, _} = Supervisor.start_link([Demo.Stills, readings, Demo.Endpoint], strategy: :one_for_one)
IO.puts("ascii_art gallery at http://localhost:#{port}")
Process.sleep(:infinity)
