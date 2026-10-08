defmodule AsciiArt.LoopsTest do
  use ExUnit.Case, async: true

  alias AsciiArt.TestPieces.Waltz

  defp pictures(frames), do: Enum.map(frames, &{&1.text, &1.colors})

  test "a looping piece's loop is its first cycle" do
    {:ok, frames, 30} = AsciiArt.new!("elixir") |> AsciiArt.loop()
    assert pictures(frames) == "elixir" |> AsciiArt.stream!() |> Enum.take(150) |> pictures()
  end

  test "a piece that does not loop, or a still, has no loop" do
    assert AsciiArt.new!("donut") |> AsciiArt.loop() == :error
    assert AsciiArt.new!("box-frames") |> AsciiArt.loop() == :error
  end

  test "options that change the period break the loop; ones that keep it do not" do
    # Logos shine every `shine` seconds: 5 by default, the measured period.
    assert AsciiArt.new!("elixir", options: %{shine: 3}) |> AsciiArt.loop() == :error
    assert {:ok, frames, 30} = AsciiArt.new!("elixir", options: %{shine: 2.5}) |> AsciiArt.loop()
    assert length(frames) == 150
  end

  test "at another frame rate, the period is as many frames as fit" do
    assert {:ok, frames, 7} = AsciiArt.new!("elixir", fps: 7) |> AsciiArt.loop()
    assert length(frames) == 35
  end

  test "a period that is not a whole number of frames is spread over the nearest" do
    # 0.75 s at 10 fps is 7.5 frames: 8, shown a little faster.
    assert {:ok, frames, fps} = AsciiArt.new!(Waltz) |> AsciiArt.loop()
    assert length(frames) == 8
    assert_in_delta fps, 32 / 3, 1.0e-9
    assert Enum.map(frames, & &1.text) == ~w(1 1 1 2 2 2 3 3)
  end
end

# Every period in a meta, from tools/loops.exs (which checks every frame of
# two cycles), still holds. Every looping piece keeps no state between frames,
# so a frame can be drawn at any t on its own: 120 frames through a cycle are
# drawn and compared with the same frames a cycle on, in colour and on paper
# in one ink. A module a piece, so they run at once.
for {slug, mod} <- AsciiArt.Registry.all(), seconds = mod.meta().loop do
  defmodule Module.concat(AsciiArt.LoopsTest, mod |> Module.split() |> List.last()) do
    use ExUnit.Case, async: true

    test "#{slug} comes round every #{seconds} s" do
      for opts <- [[], [paper: true, color: false]] do
        anim = AsciiArt.new!(unquote(slug), opts)
        n = round(unquote(seconds) * anim.fps)

        for i <- 0..(n - 1)//max(div(n, 120), 1) do
          {now, same} = AsciiArt.frame(anim, i / anim.fps)
          {later, still} = AsciiArt.frame(anim, (i + n) / anim.fps)
          assert same.state == anim.state and still.state == anim.state, "keeps state"
          assert {now.text, now.colors} == {later.text, later.colors}, "differs at frame #{i}"
        end
      end
    end
  end
end
