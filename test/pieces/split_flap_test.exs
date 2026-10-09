defmodule Ascii.Pieces.SplitFlapTest do
  use ExUnit.Case, async: true

  use Ascii.ContractCase,
    piece: Ascii.Pieces.SplitFlap,
    variants: [
      %{
        title: "late arrivals & co",
        start: "23:50",
        flights: [
          ["23:55", "  porto", "a1", "Gate closed!"],
          ["00:10", "bergen", "b2"],
          ["00:20", "rome", "c3", ""],
          ["bad", "nowhere", "x", "lost"]
        ]
      },
      %{title: "", flights: [["12:00", "ÿ-town", "z9", "délayé"]]},
      %{flights: []}
    ]

  use Ascii.GoldenCase, slug: "split-flap", piece: Ascii.Pieces.SplitFlap

  alias Ascii.Frame
  alias Ascii.Pieces.SplitFlap

  # A frame at `t` with `options`, and the part of each of its cells.
  defp parts_at(t, options \\ %{}) do
    anim = Ascii.new!("split-flap", options: options)
    {frame, _} = Ascii.frame(anim, t)

    names =
      for runs <- SplitFlap.parts(frame, anim.options) do
        Enum.flat_map(runs, fn {name, text} -> List.duplicate(name, String.length(text)) end)
      end

    {frame, names}
  end

  defp char_at(%Frame{lines: lines}, x, y), do: lines |> Enum.at(y) |> String.at(x)
  defp name_at(names, x, y), do: names |> Enum.at(y) |> Enum.at(x)
  defp cell(frame, names, x, y), do: {char_at(frame, x, y), name_at(names, x, y)}

  describe "parts" do
    test "a settled board: frame, title, clock, column labels and flaps" do
      {frame, names} = parts_at(0.0)

      for {x, y} <- [{0, 0}, {30, 0}, {0, 3}, {60, 3}, {0, 5}, {60, 9}, {30, 17}],
          do: assert(name_at(names, x, y) == "frame")

      assert cell(frame, names, 2, 1) == {"D", "title"}
      assert cell(frame, names, 3, 1) == {" ", "title"}
      assert cell(frame, names, 20, 1) == {"S", "title"}
      assert name_at(names, 21, 1) == nil
      assert name_at(names, 1, 1) == nil

      assert cell(frame, names, 50, 1) == {"1", "clock"}
      assert cell(frame, names, 54, 1) == {":", "clock"}
      assert cell(frame, names, 58, 1) == {"3", "clock"}
      assert cell(frame, names, 50, 2) == {"▔", "flap"}
      assert name_at(names, 49, 2) == nil

      assert cell(frame, names, 2, 4) == {"t", "label"}
      assert cell(frame, names, 14, 4) == {"d", "label"}
      assert cell(frame, names, 34, 4) == {"g", "label"}
      assert cell(frame, names, 42, 4) == {"r", "label"}
      assert name_at(names, 6, 4) == nil

      assert cell(frame, names, 2, 6) == {"▔", "flap"}
      assert cell(frame, names, 58, 16) == {"▔", "flap"}
      assert name_at(names, 3, 6) == nil
    end

    test "a flight's time, destination, gate and remark, by column" do
      {frame, names} = parts_at(0.0)

      assert cell(frame, names, 2, 5) == {"1", "time"}
      assert cell(frame, names, 6, 5) == {":", "time"}
      assert cell(frame, names, 10, 5) == {"5", "time"}
      assert cell(frame, names, 14, 5) == {"L", "destination"}
      assert cell(frame, names, 24, 5) == {"N", "destination"}
      assert name_at(names, 26, 5) == nil
      assert cell(frame, names, 34, 5) == {"A", "gate"}
      assert cell(frame, names, 36, 5) == {"4", "gate"}
      assert name_at(names, 38, 5) == nil
    end

    test "a remark is named by what it says" do
      {frame, names} = parts_at(0.0)

      assert cell(frame, names, 42, 5) == {"L", "remark.last_call"}
      assert cell(frame, names, 50, 5) == {" ", "remark.last_call"}
      assert cell(frame, names, 58, 5) == {"L", "remark.last_call"}
      assert cell(frame, names, 42, 7) == {"B", "remark.boarding"}
      assert cell(frame, names, 42, 9) == {"D", "remark.delayed"}
      assert cell(frame, names, 42, 11) == {"O", "remark.on_time"}

      {frame, names} = parts_at(3.0)
      assert cell(frame, names, 42, 15) == {"C", "remark.cancelled"}
    end

    test "a remark of the options' is named by its whole text, cut short on the board or not" do
      flights = [["14:05", "porto", "a1", "Gate closed!"], ["14:30", "rome", "b2", "diverted"]]
      {frame, names} = parts_at(0.0, %{start: "14:00", flights: flights})

      assert Enum.at(frame.lines, 5) =~ "G A T E   C L O S"
      assert cell(frame, names, 42, 5) == {"G", "remark.gate_closed"}
      assert cell(frame, names, 42, 7) == {"D", "remark.diverted"}

      # Two remarks the board shows alike: which it is cannot be told.
      flights = [["14:05", "porto", "a1", "gate closed"], ["14:30", "rome", "b2", "gate closing"]]
      {frame, names} = parts_at(0.0, %{start: "14:00", flights: flights})
      assert cell(frame, names, 42, 5) == {"G", "remark"}
      assert cell(frame, names, 42, 7) == {"G", "remark"}
    end

    test "flaps mid-riffle are flipping, the rest keep their column's part" do
      {frame, names} = parts_at(1.05)

      # The first row's destination riffles from LISBON to OSLO.
      assert cell(frame, names, 14, 6) == {"▀", "flipping"}
      assert name_at(names, 14, 5) == "flipping"
      assert name_at(names, 15, 5) == "destination"
      assert cell(frame, names, 26, 6) == {"▔", "flap"}
      # Its remark has yet to start, and still says last call.
      assert cell(frame, names, 42, 5) == {"L", "remark.last_call"}

      # The second row: its first flap turns, the next has yet to.
      assert name_at(names, 14, 7) == "flipping"
      assert cell(frame, names, 16, 7) == {"S", "destination"}

      # A remark part way through its riffle says nothing yet.
      {frame, names} = parts_at(1.5)
      assert cell(frame, names, 42, 10) == {"▀", "flipping"}
      assert name_at(names, 42, 9) == "flipping"
      assert cell(frame, names, 52, 9) == {"M", "remark"}
      assert cell(frame, names, 52, 10) == {"▔", "flap"}
    end

    test "rows with no flight are blank but for their flaps" do
      flights = [["14:05", "porto", "a1", "delayed"]]
      {frame, names} = parts_at(0.0, %{flights: flights})

      assert Enum.at(names, 7) |> Enum.slice(1..59) |> Enum.all?(&is_nil/1)
      assert cell(frame, names, 2, 8) == {"▔", "flap"}
      assert cell(frame, names, 42, 5) == {"D", "remark.delayed"}
    end

    test "with parts: true, remarks take the colours the piece suggests" do
      {frame, _} = "split-flap" |> Ascii.new!(parts: true) |> Ascii.frame(3.0)
      assert Frame.color_at(frame, 42, 9) == "#3fb950"
      assert Frame.color_at(frame, 42, 15) == "#f85149"
      assert Frame.color_at(frame, 42, 5) == "#39c5cf"
      assert Frame.color_at(frame, 14, 5) == nil
      assert Frame.color_at(frame, 0, 0) == "#8b949e"
    end
  end

  test "it says the board, its clock and its first flights" do
    assert Ascii.describe(Ascii.new!("split-flap")) ==
             "departures at 14:03: 14:05 lisbon, gate a4, on time; " <>
               "14:15 oslo, gate b12, on time; 14:20 nairobi, gate c7, delayed; and 9 more"

    describe = &SplitFlap.describe/1

    assert describe.(%{
             title: "",
             start: "",
             flights: [["09:00", " porto"], [], ["", "", "", "late"]]
           }) ==
             "split-flap: 09:00 porto; late"

    assert describe.(%{title: "arrivals", start: "", flights: []}) == "arrivals: no flights"
  end
end
