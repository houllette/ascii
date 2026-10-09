defmodule AsciiArt.Pieces.RadarTest do
  use ExUnit.Case, async: true

  alias AsciiArt.Pieces.Radar

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Radar,
    variants: [
      %{contacts: [%{bearing: 90, range: 12}, %{bearing: 225, range: 22, size: 2}]},
      %{
        contacts: [%{bearing: 10, range: 30}, %{bearing: -45, range: 24}, %{bearing: 0, range: 0}]
      },
      %{contacts: [%{bearing: 400.5, range: 3.2, size: 2}, %{bearing: 7}], range: 5, unit: "km"},
      %{contacts: [%{bearing: 90, range: 1}], range: 0},
      %{land: false},
      %{land: false, contacts: [%{bearing: 200, range: 20}], unit: ""}
    ]

  use AsciiArt.GoldenCase, slug: "radar", piece: AsciiArt.Pieces.Radar

  defp draw(options, t) do
    anim = AsciiArt.new!("radar", options: options)
    {frame, anim} = AsciiArt.frame(anim, t)
    {frame, Radar.parts(frame, anim.options)}
  end

  # The character at column x, row y, and its part.
  defp at({frame, rows}, x, y) do
    part =
      rows
      |> Enum.at(y)
      |> Enum.flat_map(fn {name, text} -> List.duplicate(name, String.length(text)) end)
      |> Enum.at(x)

    {frame.lines |> Enum.at(y) |> String.at(x), part}
  end

  describe "contacts" do
    # Due east at half range: the beam crosses it a second into each turn.
    @east [%{bearing: 90, range: 12}]

    test "light as the beam crosses them, and fade until it comes round" do
      assert at(draw(%{contacts: @east}, 0.95), 36, 12) == {"▒", "contact"}
      assert at(draw(%{contacts: @east}, 1.05), 36, 12) == {"█", "contact"}
      assert at(draw(%{contacts: @east}, 2.0), 36, 12) == {"▓", "contact"}
      assert at(draw(%{contacts: @east}, 4.95), 36, 12) == {"▒", "contact"}
    end

    test "stand where they are given, two cells wide if asked, and are counted" do
      {frame, _} = p = draw(%{contacts: [%{bearing: 0, range: 12, size: 2}]}, 0.05)
      # Due north at half range: up the scope from the centre, at (26, 12).
      assert at(p, 26, 7) == {"█", "contact"}
      assert at(p, 27, 7) == {"█", "contact"}
      assert Enum.at(frame.lines, 23) =~ " contacts 1 "
    end

    test "over the land too; beyond the range, not at all" do
      contacts = [%{bearing: 225, range: 22}, %{bearing: 10, range: 30}]
      # South-west, over the coast: the beam is there two and a half seconds in.
      {frame, _} = p = draw(%{contacts: contacts}, 2.55)
      assert at(p, 14, 18) == {"█", "contact"}
      assert Enum.at(frame.lines, 23) =~ " contacts 1 "
    end

    test "at the edge of the range, just inside the bezel" do
      p = draw(%{contacts: [%{bearing: 90, range: 24}]}, 1.05)
      assert at(p, 44, 12) == {"█", "contact"}
      assert at(p, 46, 12) == {"█", "bezel"}
    end

    test "new ones taken up while playing are drawn at once" do
      anim = AsciiArt.new!("radar", options: %{contacts: @east})
      {_, anim} = AsciiArt.frame(anim, 1.05)
      anim = AsciiArt.put_options!(anim, contacts: [%{bearing: 0, range: 12}])
      {frame, _} = AsciiArt.frame(anim, 1.1)
      assert String.at(Enum.at(frame.lines, 12), 36) != "█"
      assert String.at(Enum.at(frame.lines, 7), 26) == "▓"
    end

    test "without any, upstream's tracks" do
      {a, _} = draw(%{}, 3.0)
      {b, _} = draw(%{contacts: []}, 3.0)
      assert a.text == b.text
      refute a.text == elem(draw(%{contacts: @east}, 3.0), 0).text
    end
  end

  test "land: false leaves the coast out" do
    {with_land, _} = draw(%{}, 1.0)
    {without, _} = p = draw(%{land: false}, 1.0)
    assert at(draw(%{}, 1.0), 8, 12) == {"░", "land"}
    assert at(p, 8, 12) == {" ", nil}
    assert count(without.text, "░") < count(with_land.text, "░")
  end

  defp count(text, s), do: length(String.split(text, s)) - 1

  describe "parts" do
    test "the bezel, rings, scale, readouts, land, and the sweep with its beam" do
      p = draw(%{}, 1.05)
      assert at(p, 6, 12) == {"█", "bezel"}
      assert at(p, 26, 12) == {"+", "ring"}
      assert at(p, 20, 12) == {"·", "ring"}
      assert at(p, 1, 12) == {"2", "scale"}
      assert at(p, 25, 1) == {"0", "scale"}
      assert at(p, 1, 1) == {"b", "readout"}
      assert at(p, 51, 1) == {"m", "readout"}
      assert at(p, 1, 23) == {"c", "readout"}
      assert at(p, 9, 12) == {"░", "land"}
      assert at(p, 14, 12) == {"░", "land.coast"}
      assert at(p, 30, 12) == {"▓", "sweep.beam"}
      assert at(p, 40, 11) == {"▒", "sweep"}
      assert at(p, 32, 10) == {"░", "sweep"}
      assert at(p, 0, 0) == {" ", nil}
    end

    test "every cell drawn is in a part, through a whole turn" do
      for options <- [%{}, %{contacts: [%{bearing: 90, range: 12, size: 2}], land: false}],
          step <- 0..80 do
        {frame, rows} = draw(options, step / 20)

        for {line, runs} <- Enum.zip(frame.lines, rows),
            {name, text} <- runs,
            name == nil do
          assert String.trim(text) == "", "#{inspect(text)} in no part in #{inspect(line)}"
        end
      end
    end

    test "coloured through the animation" do
      anim = AsciiArt.new!("radar", options: %{contacts: @east}, parts: true)
      {frame, _} = AsciiArt.frame(anim, 1.05)
      assert AsciiArt.Frame.color_at(frame, 36, 12) == "#3fb950"
      assert AsciiArt.Frame.color_at(frame, 6, 12) == "#8b949e"
      assert AsciiArt.Frame.color_at(frame, 9, 12) == "#db6d28"
    end
  end

  test "describe/1 counts the contacts within range" do
    options = AsciiArt.meta!("radar").options
    assert Radar.describe(options) == nil

    assert Radar.describe(%{
             options
             | contacts: [%{bearing: 1, range: 2}, %{bearing: 3, range: 4}]
           }) ==
             "radar: 2 contacts within 24 nm"

    assert Radar.describe(%{
             options
             | contacts: [%{bearing: 1, range: 2}, %{bearing: 1, range: 99}]
           }) ==
             "radar: 1 contact within 24 nm"

    assert Radar.describe(%{options | contacts: [%{bearing: 1, range: 99}], range: 5.5, unit: ""}) ==
             "radar: no contacts within 5.5"
  end
end
