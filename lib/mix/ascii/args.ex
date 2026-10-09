defmodule Mix.Ascii.Args do
  @moduledoc false
  # What the tasks that draw a piece take from their command lines: the
  # piece, its options, and how it is drawn.

  @doc false
  # The switches every such task takes, for OptionParser.
  @spec switches() :: keyword()
  def switches do
    [
      mono: :boolean,
      ink: :string,
      gradient: :string,
      parts: :boolean,
      part: :keep,
      paper: :boolean,
      option: :keep
    ]
  end

  @doc false
  # The piece named, and the options of Ascii.new/2 the switches give,
  # checked, or the task stops with what is wrong.
  @spec piece!(name :: String.t(), opts :: keyword()) :: {Ascii.piece(), keyword()}
  def piece!(name, opts) do
    piece = piece(name)

    new_opts =
      [
        options: Map.new(Keyword.get_values(opts, :option), &option/1),
        paper: Keyword.get(opts, :paper, false),
        color: not Keyword.get(opts, :mono, false),
        parts: parts(piece, opts)
      ] ++ Keyword.take(opts, [:fps, :ink, :gradient])

    piece |> Ascii.prepare(new_opts) |> check()
    {piece, new_opts}
  end

  # A slug, or a module of a loaded application named by the argument. The
  # name is compared with the modules that exist, so no atom is made from it.
  defp piece(name) do
    case Ascii.resolve(name) do
      {:ok, _} -> name
      {:error, :unknown_piece} -> find_module(name) || name
    end
  end

  defp find_module(name) do
    full = if String.starts_with?(name, "Elixir."), do: name, else: "Elixir." <> name

    Enum.find_value(Application.loaded_applications(), fn {app, _, _} ->
      app |> Application.spec(:modules) |> List.wrap() |> Enum.find(&(Atom.to_string(&1) == full))
    end)
  end

  defp option(pair, flag \\ "--option") do
    case String.split(pair, "=", parts: 2) do
      [key, value] -> {key, value}
      _ -> Mix.raise("#{flag} takes key=value, got #{inspect(pair)}")
    end
  end

  # --part colours over the piece's own suggestions (for a light terminal
  # with --paper), if --parts asks for them.
  defp parts(piece, opts) do
    given = Map.new(Keyword.get_values(opts, :part), &option(&1, "--part"))

    with true <- Keyword.get(opts, :parts, false),
         {:ok, meta} <- Ascii.meta(piece) do
      meta
      |> Ascii.Parts.suggested(paper: Keyword.get(opts, :paper, false))
      |> Map.merge(given)
    else
      _ -> given
    end
  end

  defp check({:ok, anim}), do: {:ok, anim}

  defp check({:error, :unknown_piece}),
    do:
      Mix.raise(
        "unknown piece: give a slug (see Ascii.pieces/0) or a module implementing Ascii.Piece"
      )

  defp check({:error, {:invalid_option, :fps}}), do: Mix.raise("invalid --fps")

  defp check({:error, {:invalid_option, :ink}}),
    do:
      Mix.raise(
        "invalid --ink: give rrggbb, or several comma-separated, up to 16, " <>
          "or one CSS variable, var(--name, #rrggbb)"
      )

  defp check({:error, {:invalid_option, :gradient}}),
    do: Mix.raise("--gradient must be horizontal, vertical or diagonal")

  defp check({:error, {:invalid_option, {:parts, part}}}),
    do:
      Mix.raise(
        "invalid --part #{inspect(part)}: name one of the piece's parts (see its docs), " <>
          "and give a colour as rrggbb"
      )

  defp check({:error, {:invalid_option, key}}),
    do:
      Mix.raise(
        "invalid option #{inspect(key)}: options must be the piece's own, with values of the same kind"
      )
end
