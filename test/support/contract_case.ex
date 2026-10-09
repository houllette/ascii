defmodule AsciiArt.ContractCase do
  @moduledoc """
  Upstream's `scripts/check.ts`, for one piece.

      defmodule AsciiArt.Pieces.DonutTest do
        use ExUnit.Case, async: true
        use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Donut
      end

  Checks the meta against the contract, then plays fresh instances at
  check.ts's sample times, ink and paper, in colour and in one ink, and checks
  every frame's size, characters and colours, and that the same `t` gives the
  same frame. A property does the same at random times.

  A piece that labels its parts (`c:AsciiArt.Piece.parts/2`) has every
  frame of a cycle (or of half a minute) labelled, with its defaults and each
  variant, fresh and taken up while playing, and the runs checked to make up
  each row exactly, in parts its meta lists.

  `variants:` is a list of options to check the same way, each from a fresh
  start and taken up while playing (`AsciiArt.put_options/2`), against the
  size the piece gives for those options:

      use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Gauge, variants: [%{value: 40}]
  """

  use ExUnitProperties

  alias AsciiArt.{Env, Meta}

  @samples [0, 1, 2, 3, 4, 6]
  @ascii 0x20..0x7E
  @boxes 0x2500..0x259F

  defmacro __using__(opts) do
    piece = Keyword.fetch!(opts, :piece)
    variants = Keyword.get(opts, :variants, [])

    quote do
      use ExUnitProperties
      require AsciiArt.ContractCase

      @moduletag :contract

      test "meta follows the contract" do
        AsciiArt.ContractCase.assert_meta(unquote(piece))
      end

      test "frames have the exact size, allowed characters and valid colours" do
        AsciiArt.ContractCase.assert_frames(unquote(piece))
      end

      test "the same t gives the same frame" do
        AsciiArt.ContractCase.assert_deterministic(unquote(piece))
      end

      property "frames keep the contract at any time" do
        AsciiArt.ContractCase.check_random_times(unquote(piece))
      end

      if unquote(variants) != [] do
        test "frames keep the contract with other options, fresh and taken up while playing" do
          AsciiArt.ContractCase.assert_variants(unquote(piece), unquote(variants))
        end
      end

      if Code.ensure_loaded?(unquote(piece)) and function_exported?(unquote(piece), :parts, 2) do
        test "parts make up every frame, in parts the meta lists" do
          AsciiArt.ContractCase.assert_parts(unquote(piece), unquote(variants))
        end
      end

      if Code.ensure_loaded?(unquote(piece)) and
           function_exported?(unquote(piece), :describe, 1) do
        test "it tells what it shows in words, from its options" do
          AsciiArt.ContractCase.assert_describe(unquote(piece), unquote(variants))
        end
      end

      if Code.ensure_loaded?(unquote(piece)) and
           function_exported?(unquote(piece), :handle_event, 2) do
        test "every key and every cell clicked gives options it takes, drawn to the contract" do
          AsciiArt.ContractCase.assert_events(unquote(piece), unquote(variants))
        end

        property "any run of events keeps the contract" do
          AsciiArt.ContractCase.check_event_runs(unquote(piece), unquote(variants))
        end
      end
    end
  end

  @keys ~w(up down left right enter esc tab back_tab backspace delete home end page_up page_down) ++
          [" ", "a", "Z", "7", "-", "/"]

  @doc false
  # The words for the defaults and each variant: text, or nil for the
  # piece's name and note; the same for the same options; one line.
  def assert_describe(piece, variants) do
    m = piece.meta()

    for given <- [%{} | variants] do
      {:ok, options} = AsciiArt.Options.cast(m, given)
      told = piece.describe(options)
      at = "#{m.name} (#{inspect(given)})"

      ExUnit.Assertions.assert(
        told == nil or (is_binary(told) and told != "" and String.valid?(told)),
        "#{at}: describe/1 gave #{inspect(told)}"
      )

      if told do
        ExUnit.Assertions.assert(String.length(told) <= 500, "#{at}: over 500 characters")
        ExUnit.Assertions.refute(told =~ "\n", "#{at}: more than one line")
      end

      ExUnit.Assertions.assert(told == piece.describe(options), "#{at}: not the same twice")
    end
  end

  @doc false
  # Every key, and a click on every cell, from the defaults and each
  # variant: the piece ignores it, or gives options that its own checks
  # take as they are, and the animation, taking them up, draws frames to the
  # contract that its parts (if it knows them) make up.
  def assert_events(piece, variants) do
    m = piece.meta()

    for given <- [%{} | variants] do
      {frame, anim} = AsciiArt.frame(AsciiArt.new!(piece, options: given), 0.5)
      clicks = for y <- 0..(frame.rows - 1), x <- 0..(frame.cols - 1), do: {:click, x, y}

      for event <- Enum.map(@keys, &{:key, &1}) ++ clicks do
        assert_event(m, piece, anim, event, "#{m.name} (#{inspect(given)}) on #{inspect(event)}")
      end
    end
  end

  defp assert_event(m, piece, anim, event, at) do
    case piece.handle_event(event, anim.options) do
      :ignore ->
        anim

      {:ok, options} ->
        ExUnit.Assertions.assert(
          AsciiArt.Options.cast(m, options) == {:ok, options},
          "#{at}: options its own checks change: #{inspect(options)}"
        )

        {:ok, anim} = AsciiArt.handle_event(anim, event)
        assert_drawn(m, piece, anim, 1.0, at)

      other ->
        ExUnit.Assertions.flunk("#{at}: handle_event/2 gave #{inspect(other)}")
    end
  end

  defp assert_drawn(m, piece, anim, t, at) do
    {frame, anim} = AsciiArt.frame(anim, t)
    assert_frame(m, {anim.cols, anim.rows}, {t, frame.text, frame.colors, anim.color?}, at)

    if function_exported?(piece, :parts, 2) do
      rows = piece.parts(frame, anim.options)

      for {{runs, line}, y} <- rows |> Enum.zip(frame.lines) |> Enum.with_index() do
        ExUnit.Assertions.assert(
          Enum.map_join(runs, &elem(&1, 1)) == line,
          "#{at}: row #{y}'s parts do not make it up: #{inspect(runs)}"
        )
      end
    end

    anim
  end

  @doc false
  defmacro check_event_runs(piece, variants) do
    quote do
      variants = [%{} | unquote(variants)]

      check all(
              given <- member_of(variants),
              events <-
                list_of(
                  one_of([
                    map(member_of(unquote(@keys)), &{:key, &1}),
                    map({integer(0..90), integer(0..40)}, fn {x, y} -> {:click, x, y} end)
                  ]),
                  max_length: 40
                ),
              max_runs: 25
            ) do
        AsciiArt.ContractCase.assert_event_run(unquote(piece), given, events)
      end
    end
  end

  @doc false
  def assert_event_run(piece, given, events) do
    m = piece.meta()
    anim = AsciiArt.new!(piece, options: given)

    events
    |> Enum.with_index()
    |> Enum.reduce(anim, fn {event, i}, anim ->
      at = "#{m.name} (#{inspect(given)}) after #{inspect(Enum.take(events, i + 1))}"
      anim = assert_event(m, piece, anim, event, at)
      assert_drawn(m, piece, anim, i * 0.25, at)
    end)
  end

  @doc false
  def assert_meta(piece) do
    m = piece.meta()
    scene? = m.category == :scenes
    {max_cols, max_rows} = if scene?, do: {320, 120}, else: {80, 32}
    hex? = &(is_binary(&1) and &1 =~ ~r/^#[0-9a-f]{6}$/i)

    errors =
      [
        {is_binary(m.name) and m.name != "" and m.name == String.downcase(m.name),
         "name must be lowercase"},
        {m.category in Meta.categories(), "unknown category"},
        {is_binary(m.note) and String.length(m.note) in 1..72, "note must be 1-72 characters"},
        {m.note == String.downcase(m.note), "note must be lowercase"},
        {is_integer(m.cols) and m.cols in 1..max_cols, "cols must be 1-#{max_cols}"},
        {is_integer(m.rows) and m.rows in 1..max_rows, "rows must be 1-#{max_rows}"},
        {is_integer(m.fps) and m.fps in 0..60, "fps must be 0-60"},
        {is_map(m.options), "options must be a map"},
        {is_boolean(m.clock), "clock must be a boolean"},
        {m.palette == nil or (length(m.palette) in 2..64 and Enum.all?(m.palette, hex?)),
         "palette must be 2-64 #rrggbb colours"},
        {m.ground == nil or hex?.(m.ground), "ground must be #rrggbb"},
        {m.cell in [1, 2], "cell must be 1 or 2"},
        {not scene? or (m.palette != nil and m.ground != nil),
         "a scene needs a palette and a ground"},
        {Enum.all?(m.bounds, fn {k, b} ->
           Map.has_key?(m.options, k) and bound?(b, Map.get(m.shapes, k, m.options[k]))
         end), "bounds must name options, with ranges, or ranges by key the option's maps have"},
        {Enum.all?(Map.keys(m.shapes), &Map.has_key?(m.options, &1)), "shapes must name options"},
        {m.loop == nil or (is_number(m.loop) and m.loop > 0), "loop must be seconds"},
        {parts?(m.parts), "parts must be {name, nil or #rrggbb}, each name once"},
        {m.parts != [] == function_exported?(piece, :parts, 2),
         "a piece lists parts if and only if it labels them"},
        {m.parts == [] or m.palette == nil, "only a piece in one ink has parts"}
      ]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    ExUnit.Assertions.assert(errors == [], "#{m.name}: #{Enum.join(errors, "; ")}")
  end

  # A range; or ranges by key, each a key of the maps the option holds.
  defp bound?({lo, hi}, _shape), do: is_number(lo) and is_number(hi) and lo <= hi

  defp bound?(bounds, [first | _] = shape) when is_map(bounds) and is_map(first),
    do: bound?(bounds, Enum.reduce(shape, %{}, &Map.merge(&2, &1)))

  defp bound?(bounds, shape) when is_map(bounds) and is_map(shape),
    do: Enum.all?(bounds, fn {k, b} -> Map.has_key?(shape, k) and bound?(b, shape[k]) end)

  defp bound?(_bounds, _shape), do: false

  defp parts?(parts) do
    is_list(parts) and
      Enum.all?(parts, fn
        {name, color} ->
          is_binary(name) and name =~ ~r/^[a-z0-9_-]+(\.[a-z0-9_+-]+)*$/ and
            (color == nil or (is_binary(color) and color =~ ~r/^#[0-9a-f]{6}$/))

        _ ->
          false
      end) and parts |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == length(parts)
  end

  @doc false
  # Every frame of a cycle, or of half a minute, a tenth of a second apart,
  # labelled: the runs make up each row, and every part's first word is one
  # the meta lists. Each variant from a fresh start, and taken up a second
  # into playing the defaults, for the frames between one and the other.
  def assert_parts(piece, variants) do
    m = piece.meta()
    known = MapSet.new(m.parts, fn {name, _} -> name |> String.split(".") |> hd() end)
    span = m.loop || 30
    times = for i <- 0..round(span * 10), do: i / 10

    runs =
      for options <- [%{} | variants],
          paper <- [false, true],
          how <- [:fresh, :taken_up],
          options != %{} or how == :fresh do
        {anim, start} =
          case how do
            :fresh ->
              {AsciiArt.new!(piece, options: options, paper: paper), 0}

            :taken_up ->
              {_, playing} = AsciiArt.frame(AsciiArt.new!(piece, paper: paper), 1.0)
              {AsciiArt.put_options!(playing, options), 1}
          end

        {anim, start, "#{inspect(options)}, paper: #{paper}, #{how}"}
      end

    for {anim, start, run} <- runs do
      Enum.reduce(times, anim, fn t, anim ->
        {frame, anim} = AsciiArt.frame(anim, start + t)
        at = "#{m.name} at t=#{start + t} (#{run})"
        rows = piece.parts(frame, anim.options)

        ExUnit.Assertions.assert(
          length(rows) == frame.rows,
          "#{at}: #{length(rows)} rows of parts, rows is #{frame.rows}"
        )

        for {{runs, line}, y} <- rows |> Enum.zip(frame.lines) |> Enum.with_index() do
          ExUnit.Assertions.assert(
            Enum.map_join(runs, &elem(&1, 1)) == line,
            "#{at}: row #{y}'s parts do not make it up: #{inspect(runs)}"
          )

          for {name, _text} <- runs, name != nil do
            ExUnit.Assertions.assert(
              is_binary(name) and MapSet.member?(known, name |> String.split(".") |> hd()),
              "#{at}: row #{y} has a part the meta does not list: #{inspect(name)}"
            )
          end
        end

        anim
      end)
    end
  end

  @doc "Plays a fresh instance at each of `times`, returning `{text, colors}` for each."
  def play(piece, times, opts \\ []) do
    m = piece.meta()
    color? = Keyword.get(opts, :color?, true) and Meta.colored?(m)

    env = %Env{
      cols: m.cols,
      rows: m.rows,
      paper: Keyword.get(opts, :paper, false),
      color?: color?,
      now: ~U[2026-03-14 15:09:26.535Z]
    }

    {frames, _} =
      Enum.map_reduce(times, initial(piece), fn t, state ->
        {io, colors, state} = piece.frame(state, t * 1.0, env)
        {{t, IO.iodata_to_binary(io), colors, color?}, state}
      end)

    frames
  end

  # init/1 is a pure function of the options, and some pieces simulate for a
  # while in it; one run's worth is enough. assert_deterministic/1 checks
  # that two fresh inits agree.
  defp initial(piece),
    do: AsciiArt.TestCache.fetch({:init, piece}, fn -> piece.init(piece.meta().options) end)

  @doc false
  def assert_frames(piece) do
    m = piece.meta()

    for paper <- [false, true],
        color? <- [true, false],
        frame <- play(piece, @samples, paper: paper, color?: color?) do
      assert_frame(m, frame, "paper: #{paper}, colour: #{color?}")
    end
  end

  defp assert_frame(m, frame, run), do: assert_frame(m, {m.cols, m.rows}, frame, run)

  defp assert_frame(m, {cols, rows}, {t, text, colors, color?}, run) do
    at = "#{m.name} at t=#{t} (#{run})"
    lines = String.split(text, "\n")

    ExUnit.Assertions.assert(
      length(lines) == rows,
      "#{at}: #{length(lines)} lines, rows is #{rows}"
    )

    for {line, i} <- Enum.with_index(lines) do
      n = String.length(line)

      ExUnit.Assertions.assert(
        n == cols,
        "#{at}: line #{i} is #{n} characters, cols is #{cols}: #{inspect(line)}"
      )
    end

    bad = text |> String.to_charlist() |> Enum.find(&(&1 != ?\n and not allowed?(&1, m.category)))

    if bad,
      do:
        ExUnit.Assertions.flunk(
          "#{at}: character outside the allowed set: #{inspect(<<bad::utf8>>)}"
        )

    if color? do
      ExUnit.Assertions.assert(is_binary(colors), "#{at}: no colours")

      ExUnit.Assertions.assert(
        byte_size(colors) == cols * rows,
        "#{at}: #{byte_size(colors)} colours"
      )

      n = length(m.palette)
      past = colors |> :binary.bin_to_list() |> Enum.find(&(&1 >= n))

      ExUnit.Assertions.assert(
        past == nil,
        "#{at}: colour #{past} is past the #{n}-colour palette"
      )
    else
      ExUnit.Assertions.assert(colors == nil, "#{at}: colours without asking for them")
    end
  end

  defp allowed?(c, _category) when c in @ascii or c in @boxes or c in [0xB7, 0xB0], do: true
  defp allowed?(c, :scenes), do: c in [0x2022, 0x25CF]
  defp allowed?(_c, _category), do: false

  @doc false
  def assert_variants(piece, variants) do
    m = piece.meta()

    for options <- variants, paper <- [false, true], color <- [true, false] do
      opts = [paper: paper, color: color]
      run = "#{inspect(options)}, paper: #{paper}, colour: #{color}"
      fresh = AsciiArt.new!(piece, [options: options] ++ opts)
      {_, playing} = AsciiArt.frame(AsciiArt.new!(piece, opts), 1.0)
      updated = AsciiArt.put_options!(playing, options)

      for {anim, start, how} <- [{fresh, 0, "fresh"}, {updated, 1, "taken up"}] do
        Enum.reduce(@samples, anim, fn t, anim ->
          {f, anim} = AsciiArt.frame(anim, start + t)

          ExUnit.Assertions.assert(
            {f.cols, f.rows} == {anim.cols, anim.rows},
            "#{m.name} (#{run}, #{how}): the frame is not the animation's size"
          )

          assert_frame(
            m,
            {f.cols, f.rows},
            {start + t, f.text, f.colors, anim.color?},
            "#{run}, #{how}"
          )

          anim
        end)
      end
    end
  end

  @doc false
  def assert_deterministic(piece) do
    m = piece.meta()

    ExUnit.Assertions.assert(
      piece.init(m.options) == piece.init(m.options),
      "#{m.name}: init is not deterministic"
    )

    unless m.clock do
      for paper <- [false, true] do
        a = play(piece, @samples, paper: paper)
        b = play(piece, @samples, paper: paper)

        ExUnit.Assertions.assert(
          a == b,
          "#{piece.meta().name}: not deterministic (paper: #{paper})"
        )
      end
    end
  end

  @doc false
  defmacro check_random_times(piece) do
    quote do
      check all(
              times <- list_of(float(min: 0.0, max: 120.0), min_length: 1, max_length: 4),
              paper <- boolean(),
              color? <- boolean(),
              max_runs: 15
            ) do
        AsciiArt.ContractCase.assert_times(unquote(piece), times, paper, color?)
      end
    end
  end

  @doc false
  def assert_times(piece, times, paper, color?) do
    m = piece.meta()
    frames = play(piece, times, paper: paper, color?: color?)
    for frame <- frames, do: assert_frame(m, frame, "random times #{inspect(times)}")

    unless m.clock do
      ExUnit.Assertions.assert(
        frames == play(piece, times, paper: paper, color?: color?),
        "#{m.name}: not deterministic at #{inspect(times)}"
      )
    end
  end
end
