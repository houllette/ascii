defmodule Mix.Tasks.Ascii.Golden do
  @shortdoc "Regenerates the golden fixtures from upstream (needs Node)"
  @moduledoc """
  Regenerates `test/fixtures/golden/*.json` and `test/fixtures/js_math.json`
  from an upstream checkout, by running `tools/gen_golden.mjs` and
  `tools/gen_js_math.mjs` under Node.

      mix ascii.golden                 # every piece
      mix ascii.golden donut cube      # some pieces

  ## Options

    * `--upstream DIR` - the upstream checkout (default `tmp/upstream`)
    * `--node PATH` - the Node to run (default `$NODE`, then `node`). It must
      be an x64 build of Node 22.18 or later; see `PORTING.md`.

  This is a development tool: `mix test` reads the committed fixtures and
  never needs Node.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, slugs} = OptionParser.parse!(args, strict: [upstream: :string, node: :string])
    upstream = Keyword.get(opts, :upstream, "tmp/upstream")
    node = Keyword.get(opts, :node) || System.get_env("NODE") || "node"

    unless File.dir?(Path.join(upstream, "src/pieces")) do
      Mix.raise("no upstream checkout at #{upstream}; see UPSTREAM.md")
    end

    if slugs == [], do: node!(node, ["tools/gen_js_math.mjs", "test/fixtures/js_math.json"])
    node!(node, ["tools/gen_golden.mjs", upstream, "test/fixtures/golden" | slugs])
  end

  defp node!(node, args) do
    {_, status} =
      System.cmd(node, args, into: IO.stream(), stderr_to_stdout: true, env: [{"TZ", "UTC"}])

    if status != 0, do: Mix.raise("#{node} #{Enum.join(args, " ")} exited with #{status}")
  end
end
