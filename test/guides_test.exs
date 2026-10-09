defmodule Ascii.GuidesTest do
  # Runs the guides' examples, which define modules, start processes and
  # write to stdio. Each guide's ```elixir blocks run in order, sharing
  # variables and aliases, and a `#=> value` line asserts what the code above
  # it returned. Blocks that start with `# needs` need something a test does
  # not have (a Phoenix app, ExRatatui, Kino, a device) and are skipped.
  use ExUnit.Case

  import ExUnit.CaptureIO

  @guides Path.wildcard("guides/*.md")

  test "every guide is in the docs" do
    extras = Mix.Project.config()[:docs][:extras]
    for path <- @guides, do: assert(path in extras, "add #{path} to the docs' extras in mix.exs")
  end

  for path <- @guides do
    @external_resource path

    blocks =
      ~r/```elixir\n(.*?)```/s
      |> Regex.scan(File.read!(path), capture: :all_but_first)
      |> List.flatten()
      |> Enum.reject(&String.starts_with?(&1, "# needs"))

    if blocks != [] do
      test "#{path}'s examples return what they say" do
        stderr =
          capture_io(:stderr, fn -> capture_io(fn -> run(unquote(path), unquote(blocks)) end) end)

        refute stderr =~ "warning", stderr
      end
    end
  end

  defp run(path, blocks) do
    Enum.reduce(blocks, {[], Code.env_for_eval(file: path)}, fn block, acc ->
      block |> chunks() |> Enum.reduce(acc, &eval(path, &1, &2))
    end)
  end

  # The block's code, cut after each `#=>` line: [{code, expected | nil}].
  defp chunks(block) do
    block
    |> String.split("\n")
    |> Enum.chunk_while(
      [],
      fn
        "#=> " <> expected, lines ->
          {:cont, {lines |> Enum.reverse() |> Enum.join("\n"), expected}, []}

        line, lines ->
          {:cont, [line | lines]}
      end,
      fn lines -> {:cont, {lines |> Enum.reverse() |> Enum.join("\n"), nil}, []} end
    )
  end

  defp eval(path, {code, expected}, {binding, env}) do
    quoted = Code.string_to_quoted!(code, file: path)
    {value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)

    if expected do
      {want, _} = Code.eval_string(expected)
      assert value == want, "#{path}: expected #{expected}, got #{inspect(value)}\n\n#{code}"
    end

    {binding, env}
  end
end
