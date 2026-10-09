defmodule Ascii.Pieces.GlitchTest do
  use ExUnit.Case, async: true

  use Ascii.ContractCase,
    piece: Ascii.Pieces.Glitch,
    variants: [
      %{text: "no signal"},
      %{text: "a&b ~ é 42"},
      %{text: "much too long a word to fit the screen at all"},
      %{text: ""}
    ]

  use Ascii.GoldenCase, slug: "glitch", piece: Ascii.Pieces.Glitch

  alias Ascii.Frame
  alias Ascii.Pieces.Glitch

  # Each mark's part and character at `t`, by {x, y}.
  defp marks(options, t) do
    {frame, anim} = "glitch" |> Ascii.new!(options: options) |> Ascii.frame(t)

    marks =
      for {runs, y} <- frame |> Glitch.parts(anim.options) |> Enum.with_index(),
          {{name, ch}, x} <-
            runs
            |> Enum.flat_map(fn {name, text} ->
              Enum.map(String.codepoints(text), &{name, &1})
            end)
            |> Enum.with_index(),
          ch != " ",
          into: %{},
          do: {{x, y}, {name, ch}}

    {frame, marks}
  end

  defp columns(marks, name), do: for({{x, _y}, {^name, _ch}} <- marks, uniq: true, do: x)

  describe "parts" do
    test "a clean frame is its letters, each where it was set" do
      {_frame, marks} = marks(%{text: "no sig"}, 0.0)
      names = for {_at, {name, _ch}} <- marks, uniq: true, do: name
      assert Enum.sort(names) == ~w(letter.1 letter.2 letter.4 letter.5 letter.6)

      for {_at, {_name, ch}} <- marks, do: assert(ch == "█")

      assert Enum.max(columns(marks, "letter.1")) < Enum.min(columns(marks, "letter.2"))
      assert Enum.max(columns(marks, "letter.2")) < Enum.min(columns(marks, "letter.4"))
    end

    test "through a cycle every mark comes from somewhere: letters, their ghosts, noise, tears" do
      seen =
        for i <- 0..104, reduce: MapSet.new() do
          seen ->
            {_frame, marks} = marks(%{text: "no signal"}, i / 15)

            for {at, {name, ch}} <- marks, reduce: seen do
              seen ->
                assert name != nil, "#{inspect(ch)} at #{inspect(at)}, t=#{i / 15}, in no part"
                MapSet.put(seen, name |> String.split(".") |> hd())
            end
        end

      assert Enum.sort(seen) == ~w(ghost letter noise tear)
    end

    test "a ghost is a copy left where its letter was, in the clean picture" do
      {_frame, clean} = marks(%{}, 0.0)

      for i <- 0..104, {frame, marks} = marks(%{}, i / 15), {{x, y}, {"ghost", ch}} <- marks do
        assert ch == "▒"
        # Or a row off, where the whole picture jumped.
        assert Enum.any?([y, y - 1, y + 1], &match?({_letter, "█"}, clean[{x, &1}])),
               "ghost at #{inspect({x, y})}, t=#{frame.t}"
      end
    end

    test "with parts: true, noise red, ghosts cyan, tears grey, letters in the ink" do
      anim = Ascii.new!("glitch", parts: true)

      found =
        for i <- 0..104, reduce: %{} do
          found ->
            {frame, _} = Ascii.frame(anim, i / 15)
            {_, marks} = marks(%{}, i / 15)

            for {{x, y}, {name, _ch}} <- marks, reduce: found do
              found -> Map.put(found, hd(String.split(name, ".")), Frame.color_at(frame, x, y))
            end
        end

      assert found == %{
               "letter" => nil,
               "ghost" => "#39c5cf",
               "noise" => "#f85149",
               "tear" => "#8b949e"
             }
    end
  end

  test "it says the text" do
    assert Ascii.describe(Ascii.new!("glitch")) == "glitch: noise"
    assert Glitch.describe(%{text: " no\tsignal "}) == "glitch: no signal"
    assert Glitch.describe(%{text: ""}) == nil
  end
end
