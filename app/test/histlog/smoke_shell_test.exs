defmodule Histlog.SmokeShellTest do
  use ExUnit.Case, async: false

  @moduletag :smoke_shell

  alias Histlog.Schema
  alias Histlog.Storage

  setup do
    root =
      Path.join(System.tmp_dir!(), "histlog-smoke-shell-#{System.unique_integer([:positive])}")

    wrapper_dir = Path.join(root, "bin")
    File.mkdir_p!(wrapper_dir)
    write_histlog_wrapper!(wrapper_dir)

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root, wrapper_dir: wrapper_dir}
  end

  test "zsh init can be sourced and records through hook functions", %{
    root: root,
    wrapper_dir: wrapper_dir
  } do
    if zsh = System.find_executable("zsh") do
      script = """
      eval "$(histlog init zsh)"
      _histlog_preexec "echo smoke-zsh"
      echo smoke-zsh >/dev/null
      _histlog_precmd
      _histlog_zshexit
      """

      assert_shell_smoke!(zsh, ["-f", "-c", script], root, wrapper_dir, "echo smoke-zsh")
    end
  end

  test "bash init can be sourced and records through DEBUG/PROMPT hooks", %{
    root: root,
    wrapper_dir: wrapper_dir
  } do
    if bash = System.find_executable("bash") do
      script = """
      eval "$(histlog init bash)"
      echo smoke-bash >/dev/null
      _histlog_precmd
      _histlog_exit
      """

      assert_shell_smoke!(
        bash,
        ["--noprofile", "--norc", "-c", script],
        root,
        wrapper_dir,
        "echo smoke-bash > /dev/null"
      )
    end
  end

  test "fish init can be sourced and records through event functions", %{
    root: root,
    wrapper_dir: wrapper_dir
  } do
    if fish = System.find_executable("fish") do
      script = """
      histlog init fish | source
      __histlog_preexec "echo smoke-fish"
      echo smoke-fish >/dev/null
      __histlog_postexec
      __histlog_exit
      """

      assert_shell_smoke!(
        fish,
        ["--no-config", "-c", script],
        root,
        wrapper_dir,
        "echo smoke-fish"
      )
    end
  end

  defp assert_shell_smoke!(executable, args, root, wrapper_dir, expected_command) do
    {output, status} =
      System.cmd(executable, args,
        env: [
          {"HISTLOG_ROOT", root},
          {"HISTLOG_ACTIVE", nil},
          {"HISTLOG_SESSION_ID", nil},
          {"HISTLOG_BIN", nil},
          {"PATH", wrapper_dir <> ":" <> System.get_env("PATH", "")}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    events = closed_session_events!(root)
    assert :ok = Schema.validate_session(events)

    commands =
      events
      |> Enum.filter(&(&1["event"] == "command_defined"))
      |> Enum.map(& &1["command"])

    assert expected_command in commands
  end

  defp closed_session_events!(root) do
    paths =
      root
      |> Path.join("sessions/closed/session-*.ndjson")
      |> Path.wildcard()

    assert [path] = paths
    assert {:ok, events} = Storage.read_events(path)
    events
  end

  defp write_histlog_wrapper!(wrapper_dir) do
    app_dir = Path.expand("../..", __DIR__)
    ebin_dir = Path.join(app_dir, "_build/test/lib/histlog/ebin")
    elixir = System.find_executable("elixir") || "elixir"

    path = Path.join(wrapper_dir, "histlog")

    File.write!(path, """
    #!/bin/sh
    exec "#{elixir}" -pa "#{ebin_dir}" -e 'Histlog.CLI.main(System.argv())' -- "$@"
    """)

    File.chmod!(path, 0o755)
  end
end
