# A gallery of every piece, as a Phoenix app in one file:
#
#     elixir examples/demo.exs
#
# then open http://localhost:4000 (set PORT to use another). The index shows
# frame 0 of all the pieces by category: text pieces through
# AsciiArt.Phoenix.Components.ascii/1, coloured ones drawn on a canvas. Each
# opens a page that plays it with AsciiArt.Phoenix.player/1, where you can
# try its options, paper (dark ink on a light page) and one ink. /dashboard
# shows the UI and data pieces as live widgets, fed this very BEAM's figures.
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
          :root { --bg: #111; --ink: #ddd; --dim: #888; --card: #181818; --line: #2a2a2a; }
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
          .page.paper { --bg: #f4f1ea; --ink: #222; --dim: #777; --card: #fff; --line: #ddd; background: var(--bg); color: var(--ink); }
          .stage { margin: 1.5rem 0; max-width: 1000px; }
          .stage pre { font-size: min(16px, calc(min(100vw - 4rem, 1000px) / (var(--cols) * 0.6))); }
          form { display: grid; gap: .75rem; max-width: 640px; }
          textarea { width: 100%; min-height: 8rem; font: inherit; background: var(--card); color: var(--ink); border: 1px solid var(--line); }
          button { justify-self: start; font: inherit; padding: .25rem 1rem; }
          .toggles { display: flex; flex-wrap: wrap; gap: .5rem 1.5rem; margin-bottom: 1.25rem; }
          .switch { display: inline-flex; align-items: center; gap: .6rem; background: none; border: 0; padding: 0; color: inherit; font: inherit; cursor: pointer; }
          .switch .track { position: relative; width: 2.2rem; height: 1.2rem; border-radius: 1rem; background: var(--line); transition: background .15s; }
          .switch .track::after { content: ""; position: absolute; top: .15rem; left: .15rem; width: .9rem; height: .9rem; border-radius: 50%; background: var(--ink); transition: transform .15s; }
          .switch[aria-checked="true"] .track { background: #5a9a78; }
          .switch[aria-checked="true"] .track::after { transform: translateX(1rem); }
          .error { color: #e66; }
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
        The UI and data pieces also take live data: see the <a href="/dashboard">dashboard</a>.
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

defmodule Demo.PieceLive do
  use Phoenix.LiveView

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case AsciiArt.meta(slug) do
      {:ok, meta} ->
        slugs = Demo.Gallery.slugs()
        i = Enum.find_index(slugs, &(&1 == slug))

        {:ok,
         assign(socket,
           slug: slug,
           meta: meta,
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

    {options, error} =
      case JSON.decode(text) do
        {:ok, options} when is_map(options) -> {options, nil}
        _ -> {%{}, "options must be a JSON object; playing with the defaults"}
      end

    # A new id for new settings, so the embedded player starts afresh.
    id = "player-#{:erlang.phash2({socket.assigns.slug, options, paper, mono})}"

    {:noreply,
     assign(socket,
       paper: paper,
       mono: mono,
       options: options,
       options_text: text,
       error: error,
       player_id: id,
       query: Map.take(params, ["paper", "mono", "options"])
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

  defp path(slug, query) when map_size(query) == 0, do: "/piece/#{slug}"
  defp path(slug, query), do: "/piece/#{slug}?" <> URI.encode_query(query)

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
    assigns = assign(assigns, colored?: assigns.meta.palette != nil)

    ~H"""
    <div class={["page", @paper && "paper"]}>
      <main>
        <nav>
          <a href="/" data-to-gallery>← gallery</a> ·
          <a href={path(@prev, Map.take(@query, ["paper", "mono"]))}>← {@prev}</a> ·
          <a href={path(@next, Map.take(@query, ["paper", "mono"]))}>{@next} →</a>
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
            label={@meta.name}
          />
        </div>
        <div class="toggles">
          <button type="button" class="switch" role="switch" aria-checked={to_string(@paper)} phx-click="toggle" phx-value-key="paper">
            <span class="track"></span> paper: dark ink on a light page
          </button>
          <button :if={@colored?} type="button" class="switch" role="switch" aria-checked={to_string(@mono)} phx-click="toggle" phx-value-key="mono">
            <span class="track"></span> one ink
          </button>
        </div>
        <form :if={@meta.options != %{}} method="get" action={"/piece/#{@slug}"}>
          <input :if={@paper} type="hidden" name="paper" value="1" />
          <input :if={@mono} type="hidden" name="mono" value="1" />
          <label>
            options (JSON; unknown keys and wrong kinds are refused)
            <textarea name="options">{@options_text}</textarea>
          </label>
          <button>play with these options</button>
        </form>
        <p :if={@error} class="error">{@error}</p>
        <p class="note">In a terminal: <code>mix ascii_art.play {@slug}</code></p>
      </main>
    </div>
    """
  end
end

defmodule Demo.DashboardLive do
  # The UI and data pieces as live widgets: this BEAM's schedulers, memory,
  # run queue and busiest processes, sampled every second. Each widget is
  # AsciiArt.Phoenix.live_player/1, given new options from the assigns; it
  # carries on from where it was (the gauge's needle swings, the sparkline
  # scrolls), and the browser is sent only the cells that change.
  use Phoenix.LiveView

  @mb 1_048_576
  @gb 1_073_741_824

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :erlang.system_flag(:scheduler_wall_time, true)
      :timer.send_interval(1000, :sample)
    end

    {:ok, assign(socket, stats: sample(nil))}
  end

  @impl true
  def handle_info(:sample, socket),
    do: {:noreply, assign(socket, stats: sample(socket.assigns.stats))}

  # Busy work for every scheduler, for three seconds, to watch the widgets move.
  @impl true
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

  defp sample(prev) do
    sched = :scheduler.sample()
    memory = :erlang.memory()
    total = memory[:total]
    run_queue = :erlang.statistics(:total_run_queue_lengths)

    cores =
      if prev,
        do:
          for(
            {:normal, _id, util, _} <- :scheduler.utilization(prev.sched, sched),
            do: util * 100
          ),
        else: List.duplicate(0, System.schedulers_online())

    # Run-queue averages over about 1, 5 and 15 seconds, as load averages are.
    load =
      for {avg, k} <- Enum.zip((prev && prev.load) || [0, 0, 0], [1, 5, 15]),
          do: avg + (run_queue - avg) / k

    reductions = Map.new(Process.list(), fn pid -> {pid, reductions(pid)} end)

    %{
      sched: sched,
      load: load,
      reductions: reductions,
      cores: cores,
      busy: if(cores == [], do: 0, else: Enum.sum(cores) / length(cores)),
      memory: total,
      parts: for(k <- [:processes, :binary, :ets, :code, :atom], do: memory[k] / total * 100),
      processes: length(Process.list()),
      run_queue: run_queue,
      uptime: div(elem(:erlang.statistics(:wall_clock), 0), 1000),
      top: top(prev && prev.reductions, reductions, total),
      history:
        Enum.take(
          ((prev && prev.history) || []) ++ [{total / @mb, length(Process.list()), run_queue}],
          -120
        )
    }
  end

  defp reductions(pid) do
    case Process.info(pid, :reductions) do
      {:reductions, n} -> n
      nil -> 0
    end
  end

  # The busiest processes since the last sample, by reductions.
  defp top(nil, _now, _total), do: []

  defp top(before, now, total) do
    deltas = for {pid, n} <- now, d = n - Map.get(before, pid, n), d > 0, do: {pid, d}
    sum = deltas |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> max(1)

    deltas
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(5)
    |> Enum.flat_map(fn {pid, d} ->
      case Process.info(pid, [
             :memory,
             :registered_name,
             :initial_call,
             :current_function,
             :status
           ]) do
        nil -> []
        info -> [process(pid, info, d / sum * 100, total)]
      end
    end)
  end

  defp process(pid, info, cpu, total) do
    [_, n, _] =
      pid
      |> :erlang.pid_to_list()
      |> to_string()
      |> String.trim("<")
      |> String.trim(">")
      |> String.split(".")

    # Its registered name, or the module it was started in (or, for a plain
    # spawn, the one it is running).
    module =
      case {info[:registered_name], info[:initial_call]} do
        {[], {:erlang, :apply, _}} -> elem(info[:current_function], 0)
        {[], {module, _, _}} -> module
        {name, _} -> name
      end

    name = module |> inspect() |> String.replace_prefix("Elixir.", "")

    app =
      case :application.get_application(pid) do
        {:ok, app} -> Atom.to_string(app)
        :undefined -> "-"
      end

    %{
      pid: String.to_integer(n),
      user: app,
      cpu: cpu,
      mem: info[:memory] / total * 100,
      res: info[:memory] / @gb,
      state: if(info[:status] == :running, do: "R", else: "S"),
      command: name
    }
  end

  @impl true
  def render(assigns) do
    s = assigns.stats

    assigns =
      assign(assigns,
        meters: %{
          cores: s.cores,
          memory: [s.memory / @gb, max(1, Float.ceil(s.memory / @gb * 4) / 2)],
          swap: [0, 1],
          load: s.load,
          tasks: s.processes,
          uptime: s.uptime,
          processes: s.top
        },
        series: [
          %{label: "memory", unit: " mb", digits: 1, values: Enum.map(s.history, &elem(&1, 0))},
          %{label: "processes", unit: "", values: Enum.map(s.history, &elem(&1, 1))},
          %{label: "run queue", unit: "", lo: 0, values: Enum.map(s.history, &elem(&1, 2))}
        ]
      )

    ~H"""
    <main>
      <nav><a href="/" data-to-gallery>← gallery</a></nav>
      <h1 style="margin-top: 1rem">dashboard</h1>
      <div class="note">
        This BEAM, sampled every second. Each widget is <code>AsciiArt.Phoenix.live_player/1</code>,
        given new options from this LiveView's assigns.
        <button type="button" phx-click="work">make work</button>
      </div>
      <div class="dash">
        <section class="widget" style="grid-column: 1 / -1">
          <h2>cpu-meters: schedulers, memory, run queue, busiest processes</h2>
          <AsciiArt.Phoenix.live_player id="meters" piece="cpu-meters" options={@meters} />
        </section>
        <section class="widget">
          <h2>gauge: scheduler use</h2>
          <AsciiArt.Phoenix.live_player
            id="busy"
            piece="gauge"
            options={%{label: "schedulers busy", unit: "%", value: @stats.busy}}
          />
        </section>
        <section class="widget">
          <h2>progress-bar: where the memory goes</h2>
          <AsciiArt.Phoenix.live_player
            id="memory"
            piece="progress-bar"
            options={%{values: @stats.parts, labels: ~w(processes binary ets code atom), style: 1}}
          />
        </section>
        <section class="widget" style="grid-column: 1 / -1">
          <h2>sparkline: the last two minutes</h2>
          <AsciiArt.Phoenix.live_player id="history" piece="sparkline" options={%{series: @series, rate: 1}} />
        </section>
      </div>
    </main>
    """
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
{:ok, _} = Supervisor.start_link([Demo.Stills, Demo.Endpoint], strategy: :one_for_one)
IO.puts("ascii_art gallery at http://localhost:#{port}")
Process.sleep(:infinity)
