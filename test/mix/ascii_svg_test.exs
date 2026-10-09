defmodule Mix.Tasks.Ascii.SvgTest do
  # Reads Mix.shell and writes files: not async.
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Ascii.Svg

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  @tag :tmp_dir
  test "writes frame 0 as an SVG, labelled with what it shows", %{tmp_dir: dir} do
    path = Path.join(dir, "gauge.svg")
    Svg.run(["gauge", "--option", "value=72", "--parts", "--output", path])
    svg = File.read!(path)
    assert svg =~ ~s(<svg xmlns="http://www.w3.org/2000/svg")
    assert svg =~ "<title>load: 72%</title>"
    assert svg =~ ~s(fill="#d29922")
    assert_received {:mix_shell, :info, ["wrote " <> _]}
  end

  test "to standard output, at a time, with a background and font size" do
    out =
      capture_io(fn ->
        Svg.run([
          "spinners",
          "--t",
          "0.5",
          "--output",
          "-",
          "--background",
          "0d1117",
          "--font-size",
          "10"
        ])
      end)

    assert out =~ ~s(<rect width="100%" height="100%" fill="#0d1117"/>)
    assert out =~ ~s(font-size="10")
    assert out =~ "</svg>"
  end

  test "an unknown piece or a bad colour stops with a message" do
    assert_raise Mix.Error, ~r/unknown piece/, fn ->
      Svg.run(["no-such-piece", "--output", "-"])
    end

    assert_raise Mix.Error, ~r/--background/, fn ->
      capture_io(fn -> Svg.run(["donut", "--output", "-", "--background", "blue"]) end)
    end
  end
end
