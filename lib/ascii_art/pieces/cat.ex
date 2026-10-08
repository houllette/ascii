defmodule AsciiArt.Pieces.Cat do
  @moduledoc """
  A tabby asleep on its paws, breathing slowly.

  A tabby asleep on its side, head down on its front paws. Its back rises
  and falls with each breath, the tail tip lifts now and then, an ear
  twitches, and a z drifts up.

  Ported from `src/pieces/cat.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Text

  @meta %AsciiArt.Meta{
    name: "cat",
    category: :creatures,
    note: "a tabby asleep on its paws, breathing slowly",
    cols: 56,
    rows: 15,
    fps: 15
  }

  @cols 56
  @rows 15

  # Everything that keeps still: the head on its paws, the haunch, the belly
  # and hind foot, and the root of the tail. The back and the tail tip are
  # drawn over it.
  @cat [
    "",
    "",
    "",
    "                                    /\\      /\\",
    "                                   /  `----'  \\",
    "                                  /            \\",
    "                                 |  `-'    `-'  |",
    "                                 |       v      |",
    "                                  \\    `-'-'   /",
    "       |          _.--._           `-._____.-'",
    "        \\       .'      `.         _(__)  (__)_",
    "         `.   /          \\_______.'            `.",
    "      `-._ `-(______.---.___________________________)",
    "          `---'"
  ]

  # The back and its stripes from row 3, breathed out, half in and all the
  # way in: the top lifts half a row, then the whole back a row, stripes and
  # all.
  @back [
    [
      "",
      "               _..-------.._",
      "           _.-'   )   )   ) `-.",
      "         .'     )   )   )   )  `-",
      "        /      )   )   )   )",
      "       |"
    ],
    [
      "               ____________",
      "            _.-'            `-._",
      "          .'      )   )   )     `-",
      "         /      )   )   )   )",
      "        |      )   )   )   )",
      "       |"
    ],
    [
      "              _..--------.._",
      "          _.-'    )   )   ) `-._",
      "        .'      )   )   )   )   `-",
      "       /       )   )   )   )",
      "       |",
      "       |"
    ]
  ]

  # The tail tip resting, half raised and raised, as {row, column, text}.
  @tip [
    [{10, 3, "_"}, {11, 2, "( `."}, {12, 3, "`."}, {13, 5, "`-.__"}],
    [{9, 2, ".-."}, {10, 1, "( ,'"}, {11, 2, "\\ `."}, {12, 3, "`."}, {13, 5, "`-.__"}],
    [
      {7, 2, ".-."},
      {8, 1, "/ ,'"},
      {9, 1, "| |"},
      {10, 1, "\\ \\"},
      {11, 2, "\\ `."},
      {12, 3, "`."},
      {13, 5, "`-.__"}
    ]
  ]

  # The right ear laid flat.
  @ear_back [{3, 44, "  _"}, {4, 43, ".-' \\"}]
  # Seconds.
  @loop 16
  # Seconds a breath, four to a loop.
  @breath 4
  @flick [{1.9, 3.4}, {10.4, 11.6}]
  @twitch [{4.5, 4.8}, {4.95, 5.3}, {12.8, 13.1}]
  @z_every 1.6
  @z_life 3.2

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    art =
      for r <- 0..(@rows - 1) do
        @cat |> Enum.at(r, "") |> Text.pad_end(@cols) |> Text.chars() |> List.to_tuple()
      end

    # Marks that skip spaces and stop at the right edge, as {index, char}.
    marks = fn {r, c, s} ->
      for {ch, i} <- Enum.with_index(Text.chars(s)),
          ch != " " and c + i < @cols,
          do: {r * @cols + c + i, ch}
    end

    back =
      for lines <- @back do
        lines |> Enum.with_index(3) |> Enum.flat_map(fn {s, r} -> marks.({r, 0, s}) end)
      end

    %{
      art: List.to_tuple(art),
      back: List.to_tuple(back),
      tip: @tip |> Enum.map(&Enum.flat_map(&1, marks)) |> List.to_tuple(),
      ear:
        Enum.flat_map(@ear_back, fn {r, c, s} ->
          for {ch, i} <- Enum.with_index(Text.chars(s)), do: {r * @cols + c + i, ch}
        end),
      # k runs from -2 while k <= LOOP / Z_EVERY.
      zs: Enum.take_while(-2..100, &(&1 <= @loop / @z_every))
    }
  end

  defp within?(u, spans), do: Enum.any?(spans, fn {a, b} -> u >= a and u < b end)

  defp put(g, marks), do: Enum.reduce(marks, g, fn {i, ch}, g -> Map.put(g, i, ch) end)

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)

    # A breath: in, out a little slower, then a pause before the next.
    p = JSMath.mod(u + 0.4, @breath) / @breath
    back = elem(state.back, back(rise(p)))

    # The tail tip lifts and settles; now and then an ear lies back.
    up =
      case Enum.find(@flick, fn {a, b} -> u >= a and u < b end) do
        {a, b} -> :math.sin(:math.pi() * (u - a) / (b - a))
        nil -> 0
      end

    g =
      %{}
      |> put(back)
      |> put(elem(state.tip, tip(up)))
      |> put(if within?(u, @twitch), do: state.ear, else: [])
      |> zs(state, u)

    lines =
      for r <- 0..(@rows - 1) do
        row = elem(state.art, r)
        base = r * @cols
        for c <- 0..(@cols - 1), do: Map.get(g, base + c, elem(row, c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp rise(p) when p < 0.35 do
    s = :math.sin(:math.pi() / 2 * (p / 0.35))
    s * s
  end

  defp rise(p) when p < 0.8 do
    c = :math.cos(:math.pi() / 2 * ((p - 0.35) / 0.45))
    c * c
  end

  defp rise(_p), do: 0

  defp back(rise) when rise < 0.3, do: 0
  defp back(rise) when rise < 0.75, do: 1
  defp back(_rise), do: 2

  defp tip(up) when up > 0.7, do: 2
  defp tip(up) when up > 0.25, do: 1
  defp tip(_up), do: 0

  # Zs drift up from over the head, swaying and growing as they go.
  defp zs(g, state, u) do
    Enum.reduce(state.zs, g, fn k, g ->
      age = u - k * @z_every
      born = JSMath.mod(JSMath.mod(k * @z_every, @loop) + @loop, @loop)

      if age < 0 or age >= @z_life or within?(born, @twitch) do
        g
      else
        f = age / @z_life
        c = JSMath.floor(48.5 + f * 4 + :math.sin(age * 2.6 + k) * 0.7)
        r = JSMath.floor(3.7 - f * 3.7)
        i = r * @cols + c

        if r >= 0 and c < @cols and Map.get(g, i, elem(elem(state.art, r), c)) == " ",
          do: Map.put(g, i, if(f < 0.5, do: "z", else: "Z")),
          else: g
      end
    end)
  end
end
