defmodule AsciiArt.Pieces.CpuMetersTest do
  use ExUnit.Case, async: true

  @live %{
    cores: [12, 87.5, 40, 3, 100, 55],
    memory: [6.2, 32],
    swap: [0.1, 4],
    load: [0.52, 0.61, 0.58],
    tasks: 212,
    uptime: 93_784,
    processes: [
      %{
        pid: 4242,
        user: "deploy",
        cpu: 87.5,
        mem: 3.1,
        virt: 1.2,
        res: 0.4,
        time: 812.5,
        command: "beam.smp"
      },
      %{pid: 88, user: "root", cpu: 4.0, command: "sshd"}
    ]
  }

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.CpuMeters,
    variants: [
      @live,
      %{cores: Enum.to_list(1..32)},
      %{cores: [150, -3]},
      %{memory: [1, 0], swap: [5]},
      %{processes: [%{command: "a very long command name indeed"}]}
    ]

  use AsciiArt.GoldenCase, slug: "cpu-meters", piece: AsciiArt.Pieces.CpuMeters

  defp draw(options, t \\ 1.0) do
    {frame, _} = "cpu-meters" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    frame
  end

  test "readings given replace the simulation's" do
    frame = draw(@live)
    assert Enum.at(frame.lines, 2) =~ "1[|||||||||||||||||||||87.5%]"
    assert frame.text =~ "6.20G/32.0G"
    assert frame.text =~ "Load average: 0.52 0.61 0.58"
    assert frame.text =~ "Tasks: 212"
    assert frame.text =~ "Uptime: 1 days, 02:03:05"
    assert frame.text =~ "4242 deploy   1.20G  410M R  87.5  3.1  13:32.50  beam.smp"
  end

  test "more than eight cores make the frame taller" do
    assert draw(%{cores: Enum.to_list(1..32)}).rows == 28
    assert draw(%{cores: [1, 2]}).rows == 16
  end

  test "what is not given plays on as upstream's" do
    frame = draw(%{tasks: 5})
    assert frame.text =~ "Tasks: 5,"
    assert frame.text =~ "Mem["
    refute draw(%{tasks: 5}, 1.0).text == draw(%{tasks: 5}, 9.0).text
  end

  test "new readings taken up while playing keep the simulation going" do
    anim = AsciiArt.new!("cpu-meters")
    {_, anim} = AsciiArt.frame(anim, 5.0)
    sim = anim.state.sim
    anim = AsciiArt.put_options!(anim, cores: [50])
    assert anim.state.sim == sim
  end
end
