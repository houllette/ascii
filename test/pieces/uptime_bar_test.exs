defmodule AsciiArt.Pieces.UptimeBarTest do
  use ExUnit.Case, async: true

  @api Enum.map(1..90, fn d ->
         if rem(d, 13) == 0, do: 91.0, else: if(rem(d, 7) == 0, do: 99.5, else: 100)
       end)

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.UptimeBar,
    variants: [
      %{history: [@api]},
      %{history: [@api, [100, 98.0], [50]], days: 20},
      %{history: [[], [99.99]], days: 196},
      %{services: ["just one"], history: [[100]]}
    ]

  use AsciiArt.GoldenCase, slug: "uptime-bar", piece: AsciiArt.Pieces.UptimeBar

  defp draw(options, t \\ 2.0) do
    {frame, _} = "uptime-bar" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    frame
  end

  test "a history draws each day as given: up, degraded, out; blank before it began" do
    frame = draw(%{services: ["db"], history: [[100, 99.5, 50.0]], days: 20})
    assert frame.cols == 24
    assert Enum.join(frame.lines, "\n") =~ String.duplicate(" ", 17) <> "▌▖▁"
    assert frame.text =~ "partial outage"
    assert frame.text =~ "83.17%"
  end

  test "a history stands still; upstream's slides on" do
    assert draw(%{history: [@api, @api, @api]}, 1.0).text ==
             draw(%{history: [@api, @api, @api]}, 9.0).text

    refute draw(%{}, 1.0).text == draw(%{}, 9.0).text
  end
end
