# mix run tools/loops.exs [slug ...]
#
# Plays every piece (or the ones named) at its own frame rate with its
# default options, finds the shortest period after which its frames come
# round again exactly, and writes it into the piece's @meta as `loop:`, in
# seconds; a piece that does not repeat loses the field. A period counts only
# if the frames repeat twice over in the time played: 320 seconds, enough for
# upstream's longest loop (pendulum-wave's 150), or 60 for scenes, which are
# slow to draw and do not loop. Pieces that read the clock, and stills, never
# loop. test/ascii_art/loops_test.exs holds every period written here.
alias AsciiArt.Registry

slugs =
  case System.argv() do
    [] -> AsciiArt.pieces()
    named -> named
  end

period = fn slug ->
  meta = AsciiArt.meta!(slug)
  horizon = if meta.category == :scenes, do: 60, else: 320

  if meta.clock or meta.fps == 0 do
    nil
  else
    n = horizon * meta.fps
    anim = AsciiArt.new!(slug)

    {hashes, _} =
      Enum.map_reduce(0..(n - 1), anim, fn i, anim ->
        {frame, anim} = AsciiArt.frame(anim, i / meta.fps)
        {:erlang.phash2({frame.text, frame.colors}), anim}
      end)

    hashes = List.to_tuple(hashes)

    frames =
      Enum.find(1..div(n, 2), fn p ->
        Enum.all?(0..(n - 1 - p), &(elem(hashes, &1) == elem(hashes, &1 + p)))
      end)

    frames && frames / meta.fps
  end
end

seconds = fn x -> if x == trunc(x), do: Integer.to_string(trunc(x)), else: :erlang.float_to_binary(x, [:short]) end

found =
  slugs
  |> Task.async_stream(&{&1, period.(&1)}, timeout: :infinity, ordered: false)
  |> Enum.map(fn {:ok, result} -> result end)

for {slug, loop} <- Enum.sort(found) do
  {:ok, mod} = Registry.fetch(slug)
  path = mod.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd()
  source = File.read!(path)

  [block] = Regex.run(~r/  @meta %AsciiArt\.Meta\{\n.*?\n  \}\n/s, source)

  fields =
    block
    |> String.split("\n")
    |> Enum.reject(&String.match?(&1, ~r/^\s+loop: /))
    |> Enum.join("\n")
    |> String.replace(~r/,?\n  \}\n\z/, "")

  fields = if loop, do: fields <> ",\n    loop: #{seconds.(loop)}", else: fields
  File.write!(path, String.replace(source, block, fields <> "\n  }\n"))
  if loop, do: IO.puts("#{slug}: #{seconds.(loop)} s")
end

IO.puts("#{Enum.count(found, &elem(&1, 1))} of #{length(found)} pieces loop")
