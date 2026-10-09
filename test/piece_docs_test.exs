defmodule Ascii.PieceDocsTest do
  # Every component's docs (the UI, data and type pieces) say how to make it
  # yours, in the same sections in the same order: its options, its colours
  # and parts, the keys and clicks it takes (or that it takes none), what it
  # tells a screen reader, and an example. So do the docs of every other
  # piece that takes options, less the keys and clicks: art takes none.
  # Every option and every part is named, and the examples run: a `#=> value`
  # line asserts what the code above it returned, as in the guides.
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @sections ["Options", "Colours", "Keys and clicks", "Screen readers", "Example"]
  @art_sections ["Options", "Colours", "Screen readers", "Example"]

  for category <- [:ui, :data, :type], slug <- Ascii.pieces(category: category) do
    describe "#{slug}" do
      # The module looked up as the test runs, so nothing is known of it
      # when this compiles.
      setup do
        {:ok, module} = Ascii.resolve(unquote(slug))
        {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(module)
        {:ok, module: module, sections: sections(doc)}
      end

      test "has its sections, in order", %{sections: sections} do
        assert Enum.map(sections, &elem(&1, 0)) == @sections
      end

      test "names every option", %{module: module, sections: sections} do
        options = section(sections, "Options")
        meta = module.meta()

        for key <- Map.keys(meta.options) do
          assert options =~ "`#{key}`", "#{unquote(slug)}: option #{key} is not in its Options"
        end

        if meta.options == %{}, do: assert(options =~ "no options")
      end

      test "names every part, and how to colour it", %{module: module, sections: sections} do
        colours = section(sections, "Colours")
        assert colours =~ "`:ink`"

        case module.meta().parts do
          [] ->
            assert colours =~ "no parts"

          parts ->
            assert colours =~ "`:parts`"

            for {name, _color} <- parts do
              family = name |> String.split(".") |> hd()

              assert colours =~ "`#{name}`" or colours =~ "`#{family}.<",
                     "#{unquote(slug)}: part #{name} is not in its Colours"
            end
        end
      end

      test "says which keys and clicks it takes, or that it takes none",
           %{module: module, sections: sections} do
        keys = section(sections, "Keys and clicks")

        if function_exported?(module, :handle_event, 2),
          do: assert(keys =~ "`Ascii.handle_event/2`" and keys =~ "interactive"),
          else: assert(keys =~ "takes none")
      end

      test "says what it tells a screen reader", %{sections: sections} do
        assert section(sections, "Screen readers") =~ "`Ascii.describe/1`"
      end

      test "has examples that run", %{sections: sections} do
        blocks = blocks(section(sections, "Example"))
        assert blocks != [], "#{unquote(slug)}: no ```elixir example"
        capture_io(fn -> run(unquote(slug), blocks) end)
      end
    end
  end

  for slug <- Ascii.pieces(),
      {:ok, module} = Ascii.resolve(slug),
      module.meta().category not in [:ui, :data, :type],
      module.meta().options != %{} do
    describe "#{slug}" do
      setup do
        {:ok, module} = Ascii.resolve(unquote(slug))
        {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(module)
        {:ok, module: module, sections: sections(doc)}
      end

      test "has its sections, in order", %{sections: sections} do
        assert Enum.map(sections, &elem(&1, 0)) == @art_sections
      end

      test "names every option", %{module: module, sections: sections} do
        options = section(sections, "Options")

        for key <- Map.keys(module.meta().options) do
          assert options =~ "`#{key}`", "#{unquote(slug)}: option #{key} is not in its Options"
        end
      end

      test "says how to colour it", %{module: module, sections: sections} do
        colours = section(sections, "Colours")
        assert colours =~ "`:ink`" and colours =~ "no parts"
        if module.meta().palette, do: assert(colours =~ "`color: false`")
      end

      test "says what it tells a screen reader", %{sections: sections} do
        assert section(sections, "Screen readers") =~ "`Ascii.describe/1`"
      end

      test "has examples that run", %{sections: sections} do
        blocks = blocks(section(sections, "Example"))
        assert blocks != [], "#{unquote(slug)}: no ```elixir example"
        capture_io(fn -> run(unquote(slug), blocks) end)
      end
    end
  end

  test "the components guide lists every component" do
    guide = File.read!("guides/components.md")

    for category <- [:ui, :data, :type], slug <- Ascii.pieces(category: category) do
      {:ok, module} = Ascii.resolve(slug)

      assert guide =~ "| `#{inspect(module)}` |",
             "guides/components.md: #{slug} is not in the table"
    end
  end

  # The doc's "## " sections, in order, with their text.
  defp sections(doc) do
    ~r/^## (.+)$/m
    |> Regex.split(doc, include_captures: true, trim: true)
    |> Enum.drop_while(&(not String.starts_with?(&1, "## ")))
    |> Enum.chunk_every(2)
    |> Enum.map(fn ["## " <> name, text] -> {String.trim(name), text} end)
  end

  defp section(sections, name), do: sections |> List.keyfind(name, 0, {name, ""}) |> elem(1)

  defp blocks(text) do
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
  end

  defp run(slug, blocks) do
    Enum.reduce(blocks, {[], Code.env_for_eval(file: slug)}, fn block, acc ->
      block |> chunks() |> Enum.reduce(acc, &eval(slug, &1, &2))
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

  defp eval(slug, {code, expected}, {binding, env}) do
    quoted = Code.string_to_quoted!(code, file: slug)
    {value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)

    if expected do
      {want, _} = Code.eval_string(expected)
      assert value == want, "#{slug}: expected #{expected}, got #{inspect(value)}\n\n#{code}"
    end

    {binding, env}
  end
end
