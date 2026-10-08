# Nerves

AsciiArt is pure Elixir with no required dependencies and no NIFs, so it
cross-compiles to every [Nerves](https://nerves-project.org) target as it is.
A device can show pieces on its console, to anyone who connects over SSH, or
on a display.

```elixir
# needs: a Nerves project's mix.exs
def deps do
  [
    {:ascii_art, github: "houllette/ascii_art"},
    # ...
  ]
end
```

Leave `phoenix_live_view` out unless the device serves a web page.

## On the console

IEx on the device, over the serial console, HDMI or
[nerves_ssh](https://hexdocs.pm/nerves_ssh) (`ssh nerves.local`), is a
terminal like any other, so everything in the
[terminal guide](terminal.md) works there:

```elixir
alias AsciiArt.{Player, Render.ANSI}

IO.write([ANSI.hide_cursor(), ANSI.clear()])
{:ok, player} = Player.start_link(piece: "spinners", callback: &IO.write([ANSI.home(), ANSI.render(&1)]))
Process.sleep(200)
Player.stop(player)
IO.write([ANSI.reset(), ANSI.show_cursor()])
```

The callback runs in the player's process, which writes to the group leader
it was started with: start it from an SSH session and it draws in that
session. Serial terminals vary; `mode: :ansi256` or `mode: :mono` is the safe
choice there, and text pieces read well in one ink.

A serial line is slow, so after the first frame write only what changed
(`ANSI.changes/3`, see the [terminal guide](terminal.md#writing-only-what-changed)):
a drawer that keeps the frame before.

```elixir
alias AsciiArt.{Player, Render.ANSI}

draw = fn draw, prev ->
  receive do
    {:ascii_art_frame, _ref, frame} ->
      IO.write(ANSI.changes(prev, frame, mode: :ansi256))
      draw.(draw, frame)

    :stop ->
      :ok
  end
end

IO.write([ANSI.hide_cursor(), ANSI.clear()])
drawer = spawn(fn -> draw.(draw, nil) end)
{:ok, player} = Player.start_link(piece: "spinners", to: drawer)
Process.sleep(200)
Player.stop(player)
send(drawer, :stop)
IO.write([ANSI.reset(), ANSI.show_cursor()])
```

## A TUI over SSH

[ExRatatui](ex_ratatui.md) runs on Nerves (its NIF is precompiled for the
ARM and RISC-V Linux targets) and serves an app over SSH. With it as a
dependency, `AsciiArt.ExRatatui.Viewer` is such an app: add it to your
supervision tree and every visitor gets a full-screen piece with its own
animation, and ← and → to step through the rest. The host key lives on the
writable `/data` partition:

```elixir
# needs: ex_ratatui, and an SSH host key in /data/ssh
children = [
  {AsciiArt.ExRatatui.Viewer,
   transport: :ssh, port: 2222, system_dir: "/data/ssh", app_opts: [piece: "matrix-rain"]}
]
```

## Under a supervisor

Started by a supervisor, `AsciiArt.Player` has no owner to send frames to.
Give it a `:callback` to draw each frame, or let processes `subscribe/1` to
it (see the [terminal guide](terminal.md#sharing-a-player)):

```elixir
# needs: a supervision tree
children = [
  {AsciiArt.Player, piece: "analog-clock", fps: 1, callback: &MyDevice.Screen.draw/1}
]
```

`start_link/1` returns as soon as the player is running, and the player sets
its piece up in its own process. Text pieces take microseconds, but scenes
take a second or more on a small board (they precompute their sky and
terrain), and the rest of the tree starts meanwhile.

The data pieces show readings (see
[Live data](getting-started.md#live-data)), so a supervised player can show
a sensor: name it, and give it each reading with `set_options/2`.

```elixir
# needs: a supervision tree and a sensor
children = [
  {AsciiArt.Player,
   piece: "gauge",
   name: MyDevice.TempGauge,
   options: %{label: "cpu", unit: "°c", min: 20, max: 90, value: 40},
   callback: &MyDevice.Screen.draw/1}
]

# wherever the sensor is read
AsciiArt.Player.set_options(MyDevice.TempGauge, value: MyDevice.Sensor.celsius())
```

A piece that closes a loop is drawn once a frame of its cycle and then
replayed (up to a megabyte of frames), which on a small board is most of
its cost saved; `cache: false` turns that off.

## On a display

A frame is plain data: `lines` of characters and, for a coloured piece,
`colors`, a palette index for every cell. A display needs pixels, and the
quickest picture is one block of colour a cell. That suits scenes (their
cells are square, `frame.cell == 1`) and logos; text pieces need a font to be
drawn, so on a pixel display use [Scenic](https://hexdocs.pm/scenic)'s text
in a monospaced font, or your own glyphs.

This turns a frame into rows of pixels, `scale` pixels a cell across and
`scale * frame.cell` down, in 16-bit RGB565 or 32-bit XRGB8888. Blank cells
show the scene's ground (or black), as they do on a canvas:

```elixir
defmodule MyDevice.Pixels do
  alias AsciiArt.Frame

  @doc "The frame as a list of pixel rows."
  def rows(%Frame{colors: colors} = frame, bits, scale \\ 1) when is_binary(colors) do
    palette = frame.palette |> Enum.map(&pixel(&1, bits)) |> List.to_tuple()
    blank = pixel(frame.ground || "#000000", bits)

    for {line, y} <- Enum.with_index(frame.lines),
        row = draw_row(line, y, frame.cols, colors, palette, blank, scale),
        _ <- 1..(scale * frame.cell) do
      row
    end
  end

  defp draw_row(line, y, cols, colors, palette, blank, scale) do
    for {char, x} <- Enum.with_index(String.codepoints(line)), into: <<>> do
      pixel = if char == " ", do: blank, else: elem(palette, :binary.at(colors, y * cols + x))
      :binary.copy(pixel, scale)
    end
  end

  # Framebuffers hold pixels in the CPU's byte order: little-endian on ARM.
  defp pixel(<<"#", hex::binary-size(6)>>, 16) do
    <<r, g, b>> = Base.decode16!(hex, case: :mixed)
    <<div(r, 8) * 2048 + div(g, 4) * 32 + div(b, 8)::16-little>>
  end

  defp pixel(<<"#", hex::binary-size(6)>>, 32) do
    <<r, g, b>> = Base.decode16!(hex, case: :mixed)
    <<b, g, r, 0>>
  end
end

{frame, _} = AsciiArt.new!("debian") |> AsciiArt.frame(0.0)
rows = MyDevice.Pixels.rows(frame, 16, 2)
{length(rows), byte_size(hd(rows))} == {frame.rows * frame.cell * 2, frame.cols * 2 * 2}
#=> true
```

Many SPI panels driven directly (over `circuits_spi`) take RGB565 big-endian
instead: write `::16-big`.

On Linux, a display with a framebuffer driver is `/dev/fb0`, whose pixel
format is in `/sys/class/graphics/fb0/bits_per_pixel` and row length in
bytes in `/sys/class/graphics/fb0/stride`. A small GenServer can play a piece
onto it:

```elixir
# needs: a device with a framebuffer
defmodule MyDevice.Screen do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    {:ok, fb} = :file.open(~c"/dev/fb0", [:read, :write, :raw, :binary])
    {:ok, _player} = AsciiArt.Player.start_link(piece: Keyword.get(opts, :piece, "kyoto-dusk"), fps: 10)
    {:ok, %{fb: fb, bits: sysfs("bits_per_pixel"), stride: sysfs("stride"), scale: Keyword.get(opts, :scale, 2)}}
  end

  @impl true
  def handle_info({:ascii_art_frame, _ref, frame}, state) do
    frame
    |> MyDevice.Pixels.rows(state.bits, state.scale)
    |> Enum.with_index()
    |> Enum.each(fn {row, y} -> :ok = :file.pwrite(state.fb, y * state.stride, row) end)

    {:noreply, state}
  end

  defp sysfs(name) do
    ("/sys/class/graphics/fb0/" <> name) |> File.read!() |> String.trim() |> String.to_integer()
  end
end
```

The player is started in `init/1`, so it sends its frames to the screen
process and stops with it. If the kernel console also draws on `fb0`, move it
to the serial port in your `cmdline.txt` (or equivalent), or it will write
over the picture.

## Choosing pieces for a small board

A Raspberry Pi Zero is many times slower than a laptop. Text pieces, logos
and distros cost well under a millisecond a frame on a laptop and are fine
anywhere; scenes cost 2 to 14 ms a frame there, so on a small board give
them a low `fps` (5 to 10) and measure. In IEx on the device:

```elixir
anim = AsciiArt.new!("night-coast")
{_frame, anim} = AsciiArt.frame(anim, 0.0)
{micros, _} = :timer.tc(fn -> AsciiArt.frame(anim, 1.0) end)
micros > 0
#=> true
```

A piece that closes a loop (`meta.loop`, sixty of them) costs nothing after
its first cycle if you keep it: draw it once with `AsciiArt.loop/1` and
show the frames in turn. A logo's cycle is 150 frames of a few kilobytes.

## Clocks

Pieces that read the clock (`analog-clock`, `digital-clock`, `calendar`,
`sundial`, `landscape`) show the system's local time, so they are only as
right as the device's clock: most boards have no battery-backed clock and
take the time from the network ([nerves_time](https://hexdocs.pm/nerves_time)
does this in the default Nerves setup). The local time zone is UTC unless you
set one, with [nerves_time_zones](https://hexdocs.pm/nerves_time_zones) for
example. To draw a particular moment instead, pass a `DateTime` as `now:` to
`AsciiArt.frame/3` or the components; its offset sets the local time.
