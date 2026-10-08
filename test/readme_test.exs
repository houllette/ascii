defmodule AsciiArt.ReadmeTest do
  # Runs the README's examples, which start processes and write to stdio.
  use ExUnit.Case

  import ExUnit.CaptureIO

  @readme File.read!("README.md")

  # Every ```elixir block but the mix.exs snippet, which is not a script.
  @examples ~r/```elixir\n(.*?)```/s
            |> Regex.scan(@readme, capture: :all_but_first)
            |> List.flatten()
            |> Enum.reject(&String.starts_with?(&1, "# in mix.exs"))

  test "the README has examples to run" do
    assert length(@examples) >= 4
  end

  for {code, i} <- Enum.with_index(@examples) do
    test "README example #{i + 1} runs" do
      capture_io(fn -> Code.eval_string(unquote(code)) end)
    end
  end

  test "the README's table lists every piece, by category" do
    [table] =
      Regex.run(~r/<!-- pieces -->\n(.*?)\n<!-- \/pieces -->/s, @readme, capture: :all_but_first)

    listed =
      ~r/`([a-z0-9-]+)`/
      |> Regex.scan(table, capture: :all_but_first)
      |> List.flatten()
      |> Enum.sort()

    assert listed == AsciiArt.pieces(), "run: mix run tools/readme_pieces.exs"

    for {slug, mod} <- AsciiArt.Registry.all() do
      [row] = for line <- String.split(table, "\n"), line =~ "`#{slug}`", do: line
      assert row =~ "| #{mod.meta().category} |"
    end
  end
end
