defmodule AsciiArt.Pieces.SpinnersTest do
  use ExUnit.Case, async: true

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Spinners,
    variants: [
      %{names: ["dots"]},
      %{names: ["line", "arc", "dots", "pipe", "bars", "clock", "orbit"], labels: false},
      %{names: ["nope"]},
      %{speed: -2},
      %{speed: 0}
    ]

  test "names pick spinners and the frame shrinks to fit them" do
    {frame, _} = "spinners" |> AsciiArt.new!(options: %{names: ["dots"]}) |> AsciiArt.frame(0.5)
    assert {frame.cols, frame.rows} == {11, 7}
    assert frame.text =~ "dots"

    {frame, _} = "spinners" |> AsciiArt.new!(options: %{names: ["nope"]}) |> AsciiArt.frame(0.5)
    assert {frame.cols, frame.rows} == {66, 13}
  end

  test "a negative speed runs the steps backwards" do
    # "line" takes two frames a step: at speed -1 its steps go 0, -1, -2,
    # -3, as forwards they go 0, 3, 2, 1 of its four.
    text = fn anim, t -> anim |> AsciiArt.frame(t) |> elem(0) |> Map.get(:text) end
    back = AsciiArt.new!("spinners", options: %{names: ["line"], speed: -1})
    forward = AsciiArt.new!("spinners", options: %{names: ["line"]})
    backwards = for k <- 1..3, do: text.(back, k * 2 / 12)
    forwards = for k <- [3, 2, 1], do: text.(forward, k * 2 / 12)
    assert backwards == forwards
    assert length(Enum.uniq(backwards)) == 3
  end

  use AsciiArt.GoldenCase, slug: "spinners", piece: AsciiArt.Pieces.Spinners
end
