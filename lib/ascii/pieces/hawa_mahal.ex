defmodule Ascii.Pieces.HawaMahal do
  @moduledoc """
  Jaipur's palace of winds at night, lamps behind the jali.

  The palace of winds in Jaipur at night. Five storeys of narrow and wide
  bays step up to a domed crown, with kiosks on every terrace. The windows
  are jali screens, and lamps behind them come and go.

  Ported from `src/pieces/hawa-mahal.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Hash, Rand}

  @meta %Ascii.Meta{
    name: "hawa mahal",
    category: :objects,
    note: "jaipur's palace of winds at night, lamps behind the jali",
    cols: 61,
    rows: 24,
    fps: 10
  }

  @cols 61
  @rows 24

  # Every "+" is a lattice cell. The top three storeys wear pointed hoods,
  # the fourth sits under a balcony with rounded ones, and the first has tall
  # arched windows on a plinth.
  @facade ~S"""
                          '
                         .^.
                   '   .-' '-.   '
                  .^.  (+++++)  .^.
                __|_|__|+++++|__|_|__
                .-^-..^..-^-..^..-^-.
            '   (+++)(+)(+++)(+)(+++)   '
           .^.  |+++||+||+++||+||+++|  .^.
          _|_|__|___________________|__|_|_
          .^..^..-^-..^..-^-..^..-^-..^..^.
     '    (+)(+)(+++)(+)(+++)(+)(+++)(+)(+)    '
    .^.   |+||+||+++||+||+++||+||+++||+||+|   .^.
  __|_|___|_______________________________|___|_|__
  .^..-^-..^..^..-^-..^..-^-..^..-^-..^..^..-^-..^.
  (+)(+++)(+)(+)(+++)(+)(+++)(+)(+++)(+)(+)(+++)(+)
  |+||+++||+||+||+++||+||+++||+||+++||+||+||+++||+|
  =================================================
  .-..---..-..-..---..-..---..-..---..-..-..---..-.
  (+)(+++)(+)(+)(+++)(+)(+++)(+)(+++)(+)(+)(+++)(+)
  |+||+++||+||+||+++||+||+++||+||+++||+||+||+++||+|
  /^\/'^'\/^\/^\/'^'\/^\/'^'\/^\/'^'\/^\/^\/'^'\/^\
  |+||+++||+||+||+++||+||+++||+||+++||+||+||+++||+|
  |+||+++||+||+||+++||+||+++||+||+++||+||+||+++||+|
  |_||___||_||_||___||_||___||_||___||_||_||___||_|
  """

  # Stars in the open sky either side of the steps: row, col, twinkle rate, phase.
  @stars [
    {0, 4, 0.9, 0},
    {1, 15, 1.3, 2},
    {3, 8, 0.7, 4},
    {6, 2, 1.1, 1},
    {0, 53, 1.2, 3},
    {2, 45, 0.8, 5},
    {4, 57, 1.0, 0.5},
    {7, 52, 1.4, 2.5}
  ]
  # The share of lamps lit, which the night drifts back toward; seconds for a
  # lamp to come up, and for one to go out.
  @share 0.3
  @rise 0.3
  @fade 1.8
  # A screen by brightness, dark to lit, as a checker of two glyphs.
  @jali {{"·", ":"}, {":", "+"}, {"+", "#"}}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    facade = @facade |> String.replace_suffix("\n", "") |> String.split("\n")
    left = div(@cols - 49, 2)
    rand = Rand.seed(8)

    # The still picture: the facade on a ground line, the balcony running a
    # column past each side.
    band = Enum.find_index(facade, &String.starts_with?(&1, "="))

    base =
      for {line, r} <- Enum.with_index(facade) do
        line = String.pad_trailing(String.duplicate(" ", left) <> line, @cols)
        line = if r == @rows - 1, do: String.replace(line, " ", "_"), else: line
        chars = String.codepoints(line)

        if r == band,
          do: chars |> List.replace_at(left - 1, "=") |> List.replace_at(left + 49, "="),
          else: chars
      end
      |> Enum.map(&List.to_tuple/1)
      |> List.to_tuple()

    {cells, count} = jharokhas(facade, left)

    # Each lamp keeps whether it is lit and when that last changed. The night
    # opens with the share lit and a few lamps still going out.
    {lit, rand} =
      light_up(
        List.to_tuple(List.duplicate(false, count)),
        JSMath.round(@share * count),
        count,
        rand
      )

    {since, rand} = going_out(lit, List.to_tuple(List.duplicate(-99, count)), 3, count, rand)

    %{
      base: base,
      cells: cells,
      count: count,
      lit: lit,
      since: since,
      rand: rand,
      next: 0.2,
      clock: 0
    }
  end

  # A jharokha is a run of "+" and the run straight below it.
  defp jharokhas(facade, left) do
    {cells, _at, count} =
      facade
      |> Enum.with_index()
      |> Enum.reduce({[], %{}, 0}, fn {line, y}, acc ->
        ~r/\++/
        |> Regex.scan(line, return: :index)
        |> Enum.reduce(acc, fn [{i, len}], {cells, at, count} ->
          {w, count} =
            case Map.fetch(at, {y - 1, i}) do
              {:ok, w} -> {w, count}
              :error -> {count, count + 1}
            end

          new = for j <- 0..(len - 1), do: {y, left + i + j, w, Bitwise.band(i + j + y, 1)}
          {Enum.reverse(new, cells), Map.put(at, {y, i}, w), count}
        end)
      end)

    {Enum.reverse(cells), count}
  end

  defp light_up(lit, 0, _count, rand), do: {lit, rand}

  defp light_up(lit, n, count, rand) do
    {x, rand} = Rand.next(rand)
    w = trunc(x * count)

    if elem(lit, w),
      do: light_up(lit, n, count, rand),
      else: light_up(put_elem(lit, w, true), n - 1, count, rand)
  end

  defp going_out(_lit, since, 0, _count, rand), do: {since, rand}

  defp going_out(lit, since, n, count, rand) do
    {x, rand} = Rand.next(rand)
    w = trunc(x * count)

    if not elem(lit, w) and elem(since, w) < -9 do
      {y, rand} = Rand.next(rand)
      going_out(lit, put_elem(since, w, -@fade * (0.3 + 0.5 * y)), n - 1, count, rand)
    else
      going_out(lit, since, n, count, rand)
    end
  end

  # One lamp changes at a time, a fraction of a second apart. Below the
  # share, lighting one is likelier than putting one out.
  defp advance(%{next: next} = state, t) when next > t, do: state

  defp advance(%{count: count, lit: lit, rand: rand, next: next} = state, t) do
    share = Enum.count(Tuple.to_list(lit), & &1) / count
    {x, rand} = Rand.next(rand)
    light = x < 0.5 + (@share - share) * 3
    pool = for w <- 0..(count - 1), elem(lit, w) != light, do: w
    {y, rand} = Rand.next(rand)

    state =
      case Enum.at(pool, trunc(y * length(pool))) do
        nil -> state
        w -> %{state | lit: put_elem(lit, w, light), since: put_elem(state.since, w, next)}
      end

    {z, rand} = Rand.next(rand)
    advance(%{state | rand: rand, next: next + (0.3 + z * 0.5)}, t)
  end

  # A lamp comes up through a glow and goes out through one, and a lit lamp
  # now and then gutters for a moment.
  defp level(%{lit: lit, since: since, clock: clock}, w) do
    age = clock - elem(since, w)

    cond do
      not elem(lit, w) -> if age < 0.2, do: 2, else: if(age < @fade, do: 1, else: 0)
      age < @rise -> 1
      Hash.short(w + 1, JSMath.floor(clock * 10 + 1.0e-6) + 1) < 0.03 -> 1
      true -> 2
    end
  end

  @impl true
  def frame(state, t, _env) do
    clock = state.clock + min(max(t - state.clock, 0), 1)
    state = advance(%{state | clock: clock}, clock)
    levels = List.to_tuple(for w <- 0..(state.count - 1)//1, do: level(state, w))

    over =
      Map.new(state.cells, fn {y, x, w, k} ->
        {y * @cols + x, @jali |> elem(elem(levels, w)) |> elem(k)}
      end)

    over =
      Enum.reduce(@stars, over, fn {r, c, f, p}, over ->
        b = :math.sin(f * clock + p)

        Map.put(
          over,
          r * @cols + c,
          cond do
            b > 0.85 -> "*"
            b > -0.3 -> "·"
            true -> "."
          end
        )
      end)

    lines =
      for r <- 0..(@rows - 1) do
        row = elem(state.base, r)
        for c <- 0..(@cols - 1), do: Map.get(over, r * @cols + c, elem(row, c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
