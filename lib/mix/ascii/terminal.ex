defmodule Mix.Ascii.Terminal do
  @moduledoc false
  # Keys from the terminal a task plays in: raw, a key at a time, by
  # ExRatatui's names for them (see `t:Ascii.event/0`).

  @doc false
  # Waits `seconds`, or (nil) for q, Ctrl-C or the end of input; with
  # `on_key`, every key but Ctrl-C goes to it by name instead, q included.
  @spec wait(seconds :: number() | nil, on_key :: (String.t() -> term()) | nil) :: :ok
  def wait(seconds, _on_key) when is_number(seconds), do: Process.sleep(round(seconds * 1000))

  # Keys one at a time, if this is a terminal. Raw mode alone leaves Ctrl-C
  # to the emulator's break menu, so the terminal's signal keys are turned
  # off while it plays, and Ctrl-C arrives as a key like any other.
  def wait(nil, on_key) do
    case :shell.start_interactive({:noshell, :raw}) do
      :ok ->
        tty = tty()
        saved = tty && stty(tty, ["-g"])

        try do
          if saved, do: stty(tty, ["-isig"])
          read_keys(on_key, "")
        after
          if saved, do: stty(tty, [String.trim(saved)])
        end

      {:error, _} ->
        IO.read(:eof)
        :ok
    end
  end

  # The VM's terminal, by device: programs it starts have no controlling
  # terminal, so /dev/tty is not theirs to open.
  defp tty do
    with {name, 0} <- System.cmd("ps", ["-o", "tty=", "-p", System.pid()], stderr_to_stdout: true),
         name = String.trim(name),
         true <- name =~ ~r{^[A-Za-z0-9/]+$} and name not in ["?", "??"] do
      "/dev/" <> name
    else
      _ -> nil
    end
  rescue
    ErlangError -> nil
  end

  # stty on that device, given as an argument rather than spliced into the command.
  defp stty(tty, args) do
    case System.cmd("sh", ["-c", ~s(stty "$@" < "$0"), tty | args], stderr_to_stdout: true) do
      {out, 0} -> out
      _ -> nil
    end
  end

  defp read_keys(nil, _buffer) do
    case IO.getn("", 1) do
      key when key in ["q", "Q", <<3>>, <<4>>] -> :ok
      :eof -> :ok
      {:error, _} -> :ok
      _ -> read_keys(nil, "")
    end
  end

  # For a piece: keys by their names, read a byte at a time until each is
  # whole (an arrow is three bytes, an escape sequence). A lone esc shows
  # with the key after it.
  defp read_keys(on_key, buffer) do
    case IO.getn("", 1) do
      byte when is_binary(byte) ->
        case next_key(buffer <> byte) do
          :more ->
            read_keys(on_key, buffer <> byte)

          {:quit, _rest} ->
            :ok

          {key, rest} ->
            if key, do: on_key.(key)
            read_keys(on_key, rest)
        end

      _eof_or_error ->
        :ok
    end
  end

  @doc false
  # The keys in raw terminal input, by ExRatatui's names, :quit for Ctrl-C
  # or Ctrl-D.
  @spec keys(input :: binary()) :: [String.t() | :quit]
  def keys(input) do
    case next_key(input) do
      :more when input == <<27>> -> ["esc"]
      :more -> []
      {nil, rest} -> keys(rest)
      {key, rest} -> [key | keys(rest)]
    end
  end

  @csi %{
    "A" => "up",
    "B" => "down",
    "C" => "right",
    "D" => "left",
    "H" => "home",
    "F" => "end",
    "Z" => "back_tab",
    "1~" => "home",
    "7~" => "home",
    "4~" => "end",
    "8~" => "end",
    "3~" => "delete",
    "5~" => "page_up",
    "6~" => "page_down"
  }

  @sequence ~r/^([0-9;]*)([~A-Za-z])/
  @unfinished ~r/^[0-9;]*$/

  # The first key in `input` and what follows it ({nil, rest} for bytes
  # that are no key), or :more until it is whole.
  defp next_key(<<>>), do: :more
  defp next_key(<<c, rest::binary>>) when c in [3, 4], do: {:quit, rest}
  defp next_key(<<27>>), do: :more
  defp next_key(<<27, b>>) when b in [?[, ?O], do: :more

  # A letter names the key, its numbers being modifiers; before ~, the
  # number up to any modifiers does.
  defp next_key(<<27, b, rest::binary>>) when b in [?[, ?O] do
    case Regex.run(@sequence, rest) do
      [whole, params, "~"] ->
        [n | _] = String.split(params, ";")
        {Map.get(@csi, n <> "~"), binary_slice(rest, byte_size(whole)..-1//1)}

      [whole, _params, final] ->
        {Map.get(@csi, final), binary_slice(rest, byte_size(whole)..-1//1)}

      nil ->
        if rest =~ @unfinished, do: :more, else: {"esc", <<b, rest::binary>>}
    end
  end

  defp next_key(<<27, rest::binary>>), do: {"esc", rest}
  defp next_key(<<c, rest::binary>>) when c in [?\r, ?\n], do: {"enter", rest}
  defp next_key(<<?\t, rest::binary>>), do: {"tab", rest}
  defp next_key(<<c, rest::binary>>) when c in [8, 127], do: {"backspace", rest}
  defp next_key(<<c::utf8, rest::binary>>) when c >= 32, do: {<<c::utf8>>, rest}

  # Part of a character of more than one byte: wait for the rest of it.
  defp next_key(<<c, _::binary>> = input) when c >= 0x80 do
    if byte_size(input) >= 4, do: {nil, binary_slice(input, 1..-1//1)}, else: :more
  end

  defp next_key(<<_c, rest::binary>>), do: {nil, rest}
end
