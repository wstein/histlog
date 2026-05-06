defmodule Histlog.ShellInitTest do
  use ExUnit.Case, async: true

  alias Histlog.Shell.Init

  test "detects shell from HISTLOG_SHELL before SHELL" do
    assert {:ok, "fish"} = Init.detect(%{"HISTLOG_SHELL" => "fish", "SHELL" => "/bin/zsh"})
  end

  test "detects shell from SHELL path" do
    assert {:ok, "zsh"} = Init.detect(%{"SHELL" => "/bin/zsh"})
  end

  test "zsh init prints hooks, completions, and no aliases by default" do
    assert {:ok, script} = Init.script("zsh")
    assert script =~ "add-zsh-hook preexec _histlog_preexec"
    assert script =~ "histlog hook session-start --shell zsh"
    assert script =~ "compdef _histlog histlog"
    refute script =~ "alias hl="
  end

  test "bash init filters recursive hook capture" do
    assert {:ok, script} = Init.script("bash")
    assert script =~ "trap '_histlog_preexec' DEBUG"
    assert script =~ "histlog\\ hook*"
  end

  test "fish init uses fish events" do
    assert {:ok, script} = Init.script("fish", aliases: true)
    assert script =~ "function __histlog_preexec --on-event fish_preexec"
    assert script =~ "function __histlog_postexec --on-event fish_postexec"
    assert script =~ "alias hl='histlog'"
  end

  test "completions can be printed separately" do
    assert {:ok, completions} = Init.completions("bash")
    assert completions =~ "complete -F _histlog_completion histlog"
  end

  test "future shells are explicit unsupported targets" do
    assert {:error, {:unsupported_shell, "nu"}} = Init.script("nu")
    assert {:error, {:unsupported_shell, "powershell"}} = Init.script("powershell")
  end
end
