defmodule AsciiArt.Pieces.CpuMetersTest do
  use ExUnit.Case, async: true

  alias AsciiArt.Pieces.CpuMeters

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

  # Readings wider than their columns, every one of them.
  @too_wide [
    %{
      pid: 1_000_000,
      user: "postgres",
      cpu: 1234.5,
      mem: 100,
      virt: 2000,
      res: 150.5,
      time: 1.0e6,
      state: "R",
      command: "thirteenchars"
    },
    %{
      pid: 4_294_967_295,
      user: "nobody-at-all",
      cpu: 1.0e7,
      mem: 1_000_000,
      virt: 1.0e9,
      res: 5.0e6,
      time: 1.0e9,
      command: "biggest"
    }
  ]

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.CpuMeters,
    variants: [
      @live,
      %{cores: Enum.to_list(1..32)},
      %{cores: [150, -3]},
      %{memory: [1, 0], swap: [5]},
      %{processes: [%{command: "a very long command name indeed"}]},
      %{commands: ["two words", "", "x"]},
      %{cores: Enum.to_list(1..11), load: [1.0e5, 1.0e5]},
      %{
        cores: [12, 87.5],
        processes: [
          %{pid: 1_000_000, user: "a b", cpu: 1234.5, virt: 2000, state: "D", command: "x"},
          %{state: "", cpu: 1, command: "no state"}
        ]
      },
      %{processes: @too_wide}
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

  test "readings too wide for their columns are written to fit, every row 66 wide" do
    frame = draw(%{processes: @too_wide})
    assert Enum.all?(frame.lines, &(String.length(&1) == 66))

    # A long pid takes room from the user's name; sizes go to terabytes,
    # and percentages lose their decimals, then go to thousands.
    assert " 1000000 postgr 1.95T  151G R  1235  100 277h46:40  thirteenchars " in frame.lines
    assert " 4294967295 nob  954P 4883T R   10M  100 11574d01h  biggest       " in frame.lines

    # Cut by character, not byte.
    frame = draw(%{processes: [%{pid: 1_000_000, user: "négatif", command: "café"}]})
    assert Enum.all?(frame.lines, &(String.length(&1) == 66))
    assert Enum.any?(frame.lines, &String.starts_with?(&1, " 1000000 négati "))
  end

  test "readings past a million are as given, and below zero are zero" do
    frame =
      draw(%{
        processes: [
          %{pid: 4_194_304, cpu: 40, time: 2_000_000, command: "beam.smp"},
          %{pid: -5, cpu: -3, mem: -1, virt: -2, res: -2, time: -60, command: "neg"}
        ]
      })

    assert Enum.any?(frame.lines, &(&1 =~ ~r/^ 4194304 .* 555h33:20  beam\.smp/))

    assert ("     0             0M    0M S   0.0  0.0   0:00.00  neg" <> String.duplicate(" ", 11)) in frame.lines
  end

  test "readings that fit are as ever, decimals and all" do
    frame =
      draw(%{
        processes: [
          %{
            pid: 99_999,
            user: "eightchr",
            cpu: 999.9,
            mem: 99.9,
            virt: 99.9,
            res: 9.99,
            time: 999_999,
            command: "x"
          }
        ]
      })

    assert (" 99999 eightchr 99.9G 9.99G R 999.9 99.9 277h46:39  x" <> String.duplicate(" ", 13)) in frame.lines
  end

  test "a process past a thousand hours of CPU time shows days and hours" do
    # Ten days of play away: put it there.
    state = CpuMeters.init(AsciiArt.meta!("cpu-meters").options)
    state = update_in(state.sim.procs, fn procs -> Enum.map(procs, &%{&1 | time: 4.0e6}) end)
    {io, nil, _} = CpuMeters.frame(state, 0.0, %AsciiArt.Env{})
    lines = io |> IO.iodata_to_binary() |> String.split("\n")

    assert Enum.all?(lines, &(String.length(&1) == 66))
    assert Enum.count(lines, &(&1 =~ ~r/ +46d07h  \S/)) == 5
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

  describe "in words" do
    defp told(options),
      do: "cpu-meters" |> AsciiArt.new!(options: options) |> AsciiArt.describe()

    test "the readings given, the simulation's left out" do
      assert told(%{
               cores: [10, 50, 150],
               memory: [5.25, 15.5],
               swap: [0.5],
               load: [0.5, 0.25, 0.125, 9],
               tasks: 142,
               uptime: 90_061,
               processes: [%{command: "beam.smp", cpu: 12.5}, %{pid: 7, cpu: 40}]
             }) ==
               "cpu meters: 3 cores 53% busy on average, memory 5.3 of 15.5 gb, " <>
                 "swap 0.5 gb used, load 0.50 0.25 0.13, 142 tasks, up 1 day, 01:01:01, " <>
                 "busiest pid 7 40.0%"

      assert told(%{tasks: 3}) == "cpu meters: 3 tasks"
    end

    test "without readings, what the piece is" do
      assert told(%{commands: ["x"]}) =~ "cpu meters: htop-style"
    end
  end

  describe "parts" do
    alias AsciiArt.Frame
    alias AsciiArt.Kit.Text

    defp parts(options, t \\ 0.0) do
      {frame, anim} = "cpu-meters" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
      {frame, CpuMeters.parts(frame, anim.options)}
    end

    # The part of row y's cell at column x.
    defp part_at(rows, x, y) do
      rows
      |> Enum.at(y)
      |> Enum.flat_map(fn {name, text} -> List.duplicate(name, Text.length(text)) end)
      |> Enum.at(x)
    end

    test "a core's meter: its number, brackets, user and system time, and its use" do
      {frame, rows} = parts(%{})

      assert Enum.at(frame.lines, 1) ==
               "   0[|||||||||||||||||||||98.0%]    4[|||||||||||||||####  73.5%] "

      assert Enum.at(rows, 1) == [
               {nil, "   "},
               {"label", "0"},
               {"frame", "["},
               {"bar.user", String.duplicate("|", 21)},
               {"value", "98.0%"},
               {"frame", "]"},
               {nil, "    "},
               {"label", "4"},
               {"frame", "["},
               {"bar.user", String.duplicate("|", 15)},
               {"bar.system", "####"},
               {"track", "  "},
               {"value", "73.5%"},
               {"frame", "]"},
               {nil, " "}
             ]
    end

    test "memory's used, buffers and cache, swap's used, and the stats beside them" do
      {frame, rows} = parts(%{}, 7.3)

      assert Enum.at(frame.lines, 5) ==
               " Mem[|||||||||#*****5.59G/15.5G]  Tasks: 141, 418 thr; 1 running  "

      assert Enum.at(rows, 5) == [
               {nil, " "},
               {"label", "Mem"},
               {"frame", "["},
               {"bar.used", "|||||||||"},
               {"bar.buffers", "#"},
               {"bar.cache", "*****"},
               {"value", "5.59G/15.5G"},
               {"frame", "]"},
               {nil, "  "},
               {"label", "Tasks:"},
               {nil, " "},
               {"value", "141"},
               {nil, ", "},
               {"value", "418"},
               {nil, " thr; "},
               {"value", "1"},
               {nil, " running  "}
             ]

      assert [
               {nil, " "},
               {"label", "Swp"},
               {"frame", "["},
               {"bar.used", "||"},
               {"track", "              "},
               {"value", "139M/2.00G"},
               {"frame", "]"},
               {nil, "  "},
               {"label", "Load average:"},
               {nil, " "},
               {"value", "3.38"},
               {nil, " "},
               {"value", "1.76"},
               {nil, " "},
               {"value", "1.11"},
               {nil, _}
             ] = Enum.at(rows, 6)

      assert [
               {nil, _},
               {"label", "Uptime:"},
               {nil, " "},
               {"value", "4"},
               {nil, " days, "},
               {"value", "03:12:52"},
               {nil, _}
             ] = Enum.at(rows, 7)
    end

    test "the table's header, and each process's columns and state" do
      {frame, rows} = parts(%{})
      assert Enum.at(frame.lines, 10) =~ "20379 app      1.19G  350M R 497.8"

      assert Enum.at(rows, 9) == [
               {nil, "   "},
               {"header", "PID USER      VIRT   RES S  CPU% MEM%     TIME+  Command"},
               {nil, "       "}
             ]

      assert Enum.at(rows, 10) == [
               {nil, " "},
               {"pid", "20379"},
               {nil, " "},
               {"user", "app"},
               {nil, "      "},
               {"value.virt", "1.19G"},
               {nil, "  "},
               {"value.res", "350M"},
               {nil, " "},
               {"status.running", "R"},
               {nil, " "},
               {"value.cpu", "497.8"},
               {nil, "  "},
               {"value.mem", "2.2"},
               {nil, "  "},
               {"value.time", "25:38.59"},
               {nil, "  "},
               {"command", "indexer"},
               {nil, "       "}
             ]

      assert part_at(rows, 28, 11) == "status.sleeping"
      assert part_at(rows, 7, 11) == "user"
    end

    test "readings given: whole use, columns left out or too wide, any state" do
      processes = [
        %{
          pid: 4242,
          user: "deploy",
          cpu: 87.5,
          mem: 3.1,
          virt: 1.2,
          res: 0.4,
          command: "beam.smp"
        },
        %{pid: 1_000_000, user: "a b", cpu: 1234.5, virt: 2000, state: "D", command: "x"},
        %{state: "", cpu: 1, command: "no state"}
      ]

      {frame, rows} = parts(%{cores: [12, 87.5], memory: [6.2, 32], processes: processes}, 1.0)
      assert Enum.at(frame.lines, 1) =~ "0[|||                  12.0%]"

      assert [_, _, _, {"bar.user", "|||"}, {"track", _}, {"value", "12.0%"} | _] =
               Enum.at(rows, 1)

      assert [_, _, _, {"bar.used", "|||||"}, {"track", _}, {"value", "6.20G/32.0G"} | _] =
               Enum.at(rows, 2)

      # Two cores take one row of meters, so the table starts two rows up.
      assert Enum.at(frame.lines, 7) =~ " 1000000 a b    1.95T       D  1235  0.0"

      assert Enum.at(rows, 7) == [
               {nil, " "},
               {"pid", "1000000"},
               {nil, " "},
               {"user", "a b"},
               {nil, "    "},
               {"value.virt", "1.95T"},
               {nil, "       "},
               {"status.waiting", "D"},
               {nil, "  "},
               {"value.cpu", "1235"},
               {nil, "  "},
               {"value.mem", "0.0"},
               {nil, String.duplicate(" ", 12)},
               {"command", "x"},
               {nil, String.duplicate(" ", 13)}
             ]

      assert [
               {nil, _},
               {"value.cpu", "1.0"},
               {nil, "  "},
               {"value.mem", "0.0"},
               {nil, _},
               {"command", "no state"},
               {nil, _}
             ] = Enum.at(rows, 9)
    end

    test "rows move down with more cores, and readings cut at the column keep their parts" do
      {frame, rows} = parts(%{cores: Enum.to_list(1..11), load: [1.0e5, 1.0e5]}, 1.0)
      assert Enum.at(frame.lines, 7) =~ "Load average: 100000.00 100000. "

      assert [_, _, _, _, _, _, _, {nil, "   "}, {"label", "10"}, {"frame", "["} | _] =
               Enum.at(rows, 5)

      load = Enum.drop_while(Enum.at(rows, 7), &(&1 != {"label", "Load average:"}))

      assert load == [
               {"label", "Load average:"},
               {nil, " "},
               {"value", "100000.00"},
               {nil, " "},
               {"value", "100000."},
               {nil, " "}
             ]

      assert [{nil, "   "}, {"header", "PID" <> _}, _] = Enum.at(rows, 11)
      assert [{nil, " "}, {"pid", _} | _] = Enum.at(rows, 12)
    end

    test "with parts: true, labels cyan, user time green, kernel time red, R green" do
      {frame, _} = "cpu-meters" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)

      assert Frame.color_at(frame, 3, 1) == "#39c5cf"
      assert Frame.color_at(frame, 4, 1) == "#8b949e"
      assert Frame.color_at(frame, 5, 1) == "#3fb950"
      assert Frame.color_at(frame, 53, 1) == "#f85149"
      assert Frame.color_at(frame, 28, 10) == "#3fb950"
      assert Frame.color_at(frame, 1, 10) == nil
    end
  end
end
