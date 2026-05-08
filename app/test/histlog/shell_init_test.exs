defmodule Histlog.ShellInitTest do
  use ExUnit.Case, async: true

  alias Histlog.Shell.Init

  test "detects shell from HISTLOG_SHELL before SHELL" do
    assert {:ok, "fish"} = Init.detect(%{"HISTLOG_SHELL" => "fish", "SHELL" => "/bin/zsh"})
  end

  test "detects shell from parent process before SHELL" do
    assert {:ok, "fish"} = Init.detect(%{"SHELL" => "/bin/zsh"}, fn -> "fish" end)
  end

  test "detects shell from SHELL path" do
    assert {:ok, "zsh"} = Init.detect(%{"SHELL" => "/bin/zsh"}, fn -> nil end)
  end

  test "zsh init prints hooks, completions, and guarded hl alias by default" do
    assert {:ok, script} = Init.script("zsh")
    assert script =~ "add-zsh-hook preexec _histlog_preexec"
    assert script =~ "_histlog_now_ms"
    assert script =~ "export HISTLOG_SHELL=\"zsh\""
    assert script =~ "\"$HISTLOG_BIN\" hook session-start --root \"$HISTLOG_ROOT\" --shell zsh"
    assert script =~ "--durability \"$HISTLOG_DURABILITY\""
    assert script =~ "compdef _histlog histlog"
    assert script =~ "query)"
    assert script =~ "--today"
    assert script =~ "--no-private"
    assert script =~ "if ! command -v hl >/dev/null 2>&1; then"
    assert script =~ ~s(alias hl="$HISTLOG_BIN")
    refute script =~ "alias hq="
  end

  test "bash init filters recursive hook capture" do
    assert {:ok, script} = Init.script("bash")
    assert script =~ "trap '_histlog_preexec' DEBUG"
    assert script =~ "export HISTLOG_SHELL=\"bash\""
    assert script =~ "local cmd=\"${1:-$BASH_COMMAND}\""
    assert script =~ "histlog\\ hook*"
    assert script =~ "query) words="
    assert script =~ "--today"
    assert script =~ "--no-private"
  end

  test "fish init uses fish events" do
    assert {:ok, script} = Init.script("fish", aliases: true)
    assert script =~ "function __histlog_preexec --on-event fish_preexec"
    assert script =~ "function __histlog_postexec --on-event fish_postexec"
    assert script =~ "set -gx HISTLOG_SHELL fish"
    assert script =~ "__fish_seen_subcommand_from query"
    assert script =~ ~s(-l "today")
    assert script =~ ~s(-l "no-private")
    assert script =~ "__fish_seen_subcommand_from init"
    assert script =~ ~s(-l "binary")
    assert script =~ "if not type -q hl"
    assert script =~ ~s(alias hl "$HISTLOG_BIN")
    assert script =~ ~s(alias hq "$HISTLOG_BIN query")
  end

  test "init can pin an explicit histlog binary path" do
    assert {:ok, script} = Init.script("zsh", binary: "/opt/histlog/bin/histlog")
    assert script =~ "HISTLOG_BIN=\"/opt/histlog/bin/histlog\""
    refute script =~ "HISTLOG_BIN:-/opt/histlog/bin/histlog"

    assert {:ok, fish_script} = Init.script("fish", binary: "/opt/histlog/bin/histlog")
    assert fish_script =~ "set -gx HISTLOG_BIN '/opt/histlog/bin/histlog'"
    refute fish_script =~ "if not set -q HISTLOG_BIN"
  end

  test "init can set default durability mode" do
    assert {:ok, script} = Init.script("bash", durability: "safe")
    assert script =~ "HISTLOG_DURABILITY=\"${HISTLOG_DURABILITY:-safe}\""
  end

  test "init rejects relative binary paths and invalid durability" do
    assert {:error, "init --binary requires an absolute path"} =
             Init.script("zsh", binary: "histlog")

    assert {:error, reason} = Init.script("zsh", durability: "reckless")
    assert reason =~ "invalid durability"
  end

  test "future shells are explicit unsupported targets" do
    assert {:error, {:unsupported_shell, "nu"}} = Init.script("nu")
    assert {:error, {:unsupported_shell, "powershell"}} = Init.script("powershell")
  end
end
