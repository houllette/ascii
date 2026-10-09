defmodule Ascii.GoldenCase do
  @moduledoc """
  Checks a piece frame for frame against upstream.

      defmodule Ascii.Pieces.DonutTest do
        use ExUnit.Case, async: true
        use Ascii.GoldenCase, slug: "donut", piece: Ascii.Pieces.Donut
      end

  Loads `test/fixtures/golden/<slug>.json` (made by `mix ascii.golden`
  from the upstream source) and defines three tests:

    * the piece's meta is upstream's meta (options this port adds aside);
    * each recorded run, a fresh instance played at the fixture's
      `call_order`, threading state, gives the same text and colours;
    * check.ts's playback, every `1/fps` from 0 to 6 s, gives the same frames
      at the sampled times.

  A failure prints both frames side by side with the differing cells marked.
  A piece may differ in up to the number of cells
  `test/fixtures/tolerances.exs` allows, which is for libm differences only.
  """

  alias Ascii.Env

  @golden_dir "test/fixtures/golden"

  defmacro __using__(opts) do
    slug = Keyword.fetch!(opts, :slug)
    piece = Keyword.fetch!(opts, :piece)

    quote do
      @moduletag :golden

      test "meta is upstream's" do
        Ascii.GoldenCase.assert_meta(unquote(piece), unquote(slug))
      end

      test "frames match upstream at the fixture's times" do
        Ascii.GoldenCase.assert_runs(unquote(piece), unquote(slug))
      end

      test "frames match upstream played at the frame rate" do
        Ascii.GoldenCase.assert_play(unquote(piece), unquote(slug))
      end
    end
  end

  @doc "The decoded fixture for a slug."
  @spec fixture(String.t()) :: map()
  def fixture(slug) do
    Ascii.TestCache.fetch({:fixture, slug}, fn ->
      Path.join(@golden_dir, slug <> ".json") |> File.read!() |> JSON.decode!()
    end)
  end

  @doc "Slugs with a fixture."
  @spec fixture_slugs() :: [String.t()]
  def fixture_slugs do
    @golden_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(&Path.rootname/1)
    |> Enum.sort()
  end

  @doc "Upstream's meta, as an `Ascii.Meta` would hold it."
  @spec upstream_meta(map()) :: map()
  def upstream_meta(%{"meta" => m}) do
    %{
      name: m["name"],
      category: m["category"],
      note: m["note"],
      cols: m["cols"],
      rows: m["rows"],
      fps: m["fps"],
      options: m["options"] || %{},
      clock: m["clock"] || false,
      palette: m["palette"],
      ground: m["ground"],
      cell: m["cell"] || 2
    }
  end

  @doc false
  def assert_meta(piece, slug) do
    want = upstream_meta(fixture(slug))
    meta = piece.meta()
    # Options this port adds (a reading, a width) are its own; every one of
    # upstream's must be there with upstream's default.
    options = jsonable(meta.options) |> Map.take(Map.keys(want.options))

    got = %{
      name: meta.name,
      category: Atom.to_string(meta.category),
      note: meta.note,
      cols: meta.cols,
      rows: meta.rows,
      fps: meta.fps,
      options: options,
      clock: meta.clock,
      palette: meta.palette,
      ground: meta.ground,
      cell: meta.cell
    }

    ExUnit.Assertions.assert(got == want, """
    #{slug}: meta differs from upstream
    upstream: #{inspect(want, pretty: true, limit: :infinity)}
    port:     #{inspect(got, pretty: true, limit: :infinity)}
    """)
  end

  # Atom keys to strings, as the options came through JSON.
  defp jsonable(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), jsonable(v)} end)

  defp jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  defp jsonable(value), do: value

  @doc false
  def assert_runs(piece, slug) do
    fx = fixture(slug)
    tolerance = tolerance(slug)

    failures =
      fx["frames"]
      |> Enum.chunk_by(&{&1["paper"], &1["mono"]})
      |> Enum.flat_map(fn [first | _] = run ->
        {_, failures} =
          Enum.reduce(run, {initial(piece), []}, fn want, {state, failures} ->
            {got, state} = draw(piece, state, want)
            {state, failures ++ compare(slug, run_name(first), want, got, tolerance)}
          end)

        failures
      end)

    report(failures)
  end

  @doc false
  def assert_play(piece, slug) do
    fx = fixture(slug)
    play = fx["play"]
    tolerance = tolerance(slug)
    meta = piece.meta()
    step = if meta.fps > 0, do: 1 / meta.fps, else: 0.5
    wanted = Map.new(play["frames"], &{&1["t"] * 1.0, &1})
    last = play["frames"] |> Enum.map(& &1["t"]) |> Enum.max()

    {_, failures} =
      Stream.iterate(0, &(&1 + 1))
      |> Stream.map(&(Ascii.JSMath.round(&1 * step * 1.0e6) / 1.0e6))
      |> Stream.take_while(&(&1 <= last + 1.0e-9))
      |> Enum.reduce({initial(piece), []}, fn t, {state, failures} ->
        mono? = not Ascii.Meta.colored?(meta)
        clock = if meta.clock, do: fx["clock"]["start"] + Ascii.JSMath.round(t * 1000)
        frame = %{"t" => t, "paper" => false, "mono" => mono?, "now" => clock}
        {got, state} = draw(piece, state, frame)

        case Map.fetch(wanted, t) do
          {:ok, want} ->
            {state,
             failures ++ compare(slug, "played to #{want["sample"]} s", want, got, tolerance)}

          :error ->
            {state, failures}
        end
      end)

    report(failures)
  end

  # A fresh instance: init/1 is pure, so one computed state serves every run.
  defp initial(piece),
    do: Ascii.TestCache.fetch({:init, piece}, fn -> piece.init(piece.meta().options) end)

  defp draw(piece, state, want) do
    meta = piece.meta()

    env = %Env{
      cols: meta.cols,
      rows: meta.rows,
      paper: want["paper"],
      color?: not want["mono"],
      now: if(want["now"], do: DateTime.from_unix!(want["now"], :millisecond))
    }

    {io, colors, state} = piece.frame(state, want["t"] * 1.0, env)
    {%{text: IO.iodata_to_binary(io), colors: colors}, state}
  end

  defp run_name(%{"paper" => paper, "mono" => mono}) do
    Enum.join(
      [if(paper, do: "paper", else: "ink")] ++ if(mono, do: [], else: ["in colour"]),
      ", "
    )
  end

  defp tolerance(slug) do
    {tolerances, _} = Code.eval_file("test/fixtures/tolerances.exs")

    case Map.get(tolerances, slug) do
      {cells, _why} -> cells
      nil -> 0
    end
  end

  defp compare(slug, run, want, got, tolerance) do
    want_text = want["text"]
    want_colors = if want["color"], do: Base.decode64!(want["color"])
    text_cells = diff_cells(want_text, got.text)
    color_cells = diff_colors(want_colors, got.colors)

    if length(text_cells) + length(color_cells) <= tolerance and
         line_shape(want_text) == line_shape(got.text) do
      []
    else
      [
        describe(
          slug,
          run,
          want["t"],
          want_text,
          got.text,
          text_cells,
          want_colors,
          got.colors,
          color_cells
        )
      ]
    end
  end

  defp line_shape(text), do: text |> String.split("\n") |> Enum.map(&String.length/1)

  defp diff_cells(want, got) do
    want_lines = String.split(want, "\n")
    got_lines = String.split(got, "\n")

    if length(want_lines) != length(got_lines) do
      [:shape]
    else
      for {{w, g}, y} <- Enum.with_index(Enum.zip(want_lines, got_lines)),
          w != g,
          {{a, b}, x} <- Enum.with_index(zip_padded(String.graphemes(w), String.graphemes(g))),
          a != b,
          do: {x, y}
    end
  end

  defp zip_padded(a, b) do
    n = max(length(a), length(b))
    Enum.zip(a ++ List.duplicate(nil, n - length(a)), b ++ List.duplicate(nil, n - length(b)))
  end

  defp diff_colors(nil, nil), do: []
  defp diff_colors(nil, _got), do: [:unexpected]
  defp diff_colors(_want, nil), do: [:missing]
  defp diff_colors(want, got) when byte_size(want) != byte_size(got), do: [:size]

  defp diff_colors(want, got) do
    for {{a, b}, i} <-
          Enum.with_index(Enum.zip(:binary.bin_to_list(want), :binary.bin_to_list(got))),
        a != b,
        do: {i, a, b}
  end

  defp describe(slug, run, t, want, got, text_cells, want_colors, got_colors, color_cells) do
    header =
      "#{slug} at t=#{t} (#{run}): #{length(text_cells)} cells and #{length(color_cells)} colours differ"

    [header, side_by_side(want, got, text_cells), colors(want_colors, got_colors, color_cells)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp side_by_side(_want, _got, []), do: ""

  defp side_by_side(want, got, cells) do
    want_lines = String.split(want, "\n")
    got_lines = String.split(got, "\n")
    width = want_lines |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
    rows = cells |> Enum.reject(&(&1 == :shape)) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    rows =
      if rows == [],
        do: Enum.to_list(0..(max(length(want_lines), length(got_lines)) - 1)),
        else: rows

    body =
      for y <- rows do
        w = Enum.at(want_lines, y, "")
        g = Enum.at(got_lines, y, "")

        mark =
          for x <- 0..(max(String.length(w), String.length(g)) - 1)//1,
              into: "",
              do: if({x, y} in cells, do: "^", else: " ")

        "#{pad(y)} |#{String.pad_trailing(w, width)}| |#{g}|\n     #{String.pad_trailing("", width + 1)}   #{mark}"
      end

    ["      " <> String.pad_trailing("upstream", width + 3) <> "port" | Enum.take(body, 12)]
    |> Enum.join("\n")
  end

  defp colors(_want, _got, []), do: ""
  defp colors(_want, _got, [reason]) when is_atom(reason), do: "colours: #{reason}"

  defp colors(_want, _got, cells) do
    listed = cells |> Enum.take(12) |> Enum.map_join(", ", fn {i, a, b} -> "##{i} #{a}→#{b}" end)
    "colours (cell upstream→port): " <> listed
  end

  defp pad(y), do: String.pad_leading(Integer.to_string(y), 4)

  defp report([]), do: :ok
  defp report(failures), do: ExUnit.Assertions.flunk(Enum.join(Enum.take(failures, 4), "\n\n"))
end
