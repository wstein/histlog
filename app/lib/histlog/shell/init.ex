defmodule Histlog.Shell.Init do
  @moduledoc """
  Generates shell-native histlog integration scripts.
  """

  @supported_shells ["zsh", "bash", "fish"]
  @future_shells ["nu", "powershell"]

  def supported_shells, do: @supported_shells
  def future_shells, do: @future_shells

  def detect(env \\ System.get_env()) do
    cond do
      shell = normalize_shell(env["HISTLOG_SHELL"]) ->
        {:ok, shell}

      shell = normalize_shell(env["SHELL"]) ->
        {:ok, shell}

      true ->
        {:error, :shell_not_detected}
    end
  end

  def script(shell, opts \\ []) do
    aliases? = Keyword.get(opts, :aliases, false)
    binary = Keyword.get(opts, :binary, "histlog")
    durability = Keyword.get(opts, :durability, "balanced")

    case shell do
      "zsh" -> {:ok, zsh_script(aliases?, binary, durability)}
      "bash" -> {:ok, bash_script(aliases?, binary, durability)}
      "fish" -> {:ok, fish_script(aliases?, binary, durability)}
      shell when shell in @future_shells -> {:error, {:unsupported_shell, shell}}
      shell -> {:error, {:unknown_shell, shell}}
    end
  end

  def completions("zsh"), do: {:ok, zsh_completions()}
  def completions("bash"), do: {:ok, bash_completions()}
  def completions("fish"), do: {:ok, fish_completions()}
  def completions(shell), do: {:error, {:unsupported_shell, shell}}

  def doctor(shell, env \\ System.get_env()) do
    checks = [
      %{
        "check" => "shell",
        "status" => if(shell in @supported_shells, do: "ok", else: "unsupported")
      },
      %{
        "check" => "histlog_active",
        "status" => if(env["HISTLOG_ACTIVE"], do: "active", else: "inactive")
      },
      %{
        "check" => "session_id",
        "status" => if(env["HISTLOG_SESSION_ID"], do: "present", else: "missing")
      }
    ]

    %{
      "shell" => shell,
      "supported_shells" => @supported_shells,
      "checks" => checks
    }
  end

  defp normalize_shell(nil), do: nil
  defp normalize_shell(""), do: nil

  defp normalize_shell(value) do
    value
    |> Path.basename()
    |> String.downcase()
    |> case do
      shell when shell in @supported_shells -> shell
      shell when shell in @future_shells -> shell
      _other -> nil
    end
  end

  defp zsh_script(aliases?, binary, durability) do
    """
    # histlog zsh integration
    if [ -n "${HISTLOG_ACTIVE:-}" ]; then
      return
    fi

    export HISTLOG_ACTIVE=1
    export HISTLOG_ROOT="${HISTLOG_ROOT:-$HOME/.local/share/histlog}"
    export HISTLOG_BIN="${HISTLOG_BIN:-#{shell_param_default(binary)}}"
    export HISTLOG_DURABILITY="${HISTLOG_DURABILITY:-#{shell_param_default(durability)}}"
    export HISTLOG_SESSION_ID="$("$HISTLOG_BIN" hook session-start --root "$HISTLOG_ROOT" --shell zsh --pid $$ --ppid ${PPID:-0} --cwd "$PWD" --durability "$HISTLOG_DURABILITY")"

    _histlog_now_ms() {
      if command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf "%.0f\\n", time() * 1000'
      else
        printf '%s000\\n' "$(date +%s)"
      fi
    }

    _histlog_preexec() {
      HISTLOG_CMD="$1"
      HISTLOG_STARTED_AT="$(_histlog_now_ms)"
      "$HISTLOG_BIN" hook preexec --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --command "$HISTLOG_CMD" --cwd "$PWD" --started-at "$HISTLOG_STARTED_AT" >/dev/null 2>&1
    }

    _histlog_precmd() {
      local histlog_status="$?"
      local ended_at
      ended_at="$(_histlog_now_ms)"
      if [ -n "${HISTLOG_CMD:-}" ]; then
        "$HISTLOG_BIN" hook precmd --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --exit-status "$histlog_status" --cwd "$PWD" --ended-at "$ended_at" >/dev/null 2>&1
        unset HISTLOG_CMD
        unset HISTLOG_STARTED_AT
      fi
    }

    _histlog_zshexit() {
      "$HISTLOG_BIN" hook session-end --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --cwd "$PWD" >/dev/null 2>&1
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _histlog_preexec
    add-zsh-hook precmd _histlog_precmd
    add-zsh-hook zshexit _histlog_zshexit

    #{zsh_completions()}
    #{posix_aliases(aliases?)}
    """
  end

  defp bash_script(aliases?, binary, durability) do
    """
    # histlog bash integration
    if [ -n "${HISTLOG_ACTIVE:-}" ]; then
      return
    fi

    export HISTLOG_ACTIVE=1
    export HISTLOG_ROOT="${HISTLOG_ROOT:-$HOME/.local/share/histlog}"
    export HISTLOG_BIN="${HISTLOG_BIN:-#{shell_param_default(binary)}}"
    export HISTLOG_DURABILITY="${HISTLOG_DURABILITY:-#{shell_param_default(durability)}}"
    export HISTLOG_SESSION_ID="$("$HISTLOG_BIN" hook session-start --root "$HISTLOG_ROOT" --shell bash --pid $$ --ppid ${PPID:-0} --cwd "$PWD" --durability "$HISTLOG_DURABILITY")"

    _histlog_now_ms() {
      if command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf "%.0f\\n", time() * 1000'
      else
        printf '%s000\\n' "$(date +%s)"
      fi
    }

    _histlog_preexec() {
      local cmd="${1:-$BASH_COMMAND}"
      case "$cmd" in
        _histlog_*|histlog\\ hook*|history\\ -a*|PROMPT_COMMAND*) return ;;
      esac
      HISTLOG_CMD="$cmd"
      HISTLOG_STARTED_AT="$(_histlog_now_ms)"
      "$HISTLOG_BIN" hook preexec --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --command "$cmd" --cwd "$PWD" --started-at "$HISTLOG_STARTED_AT" >/dev/null 2>&1
    }

    _histlog_precmd() {
      local status="$?"
      local ended_at
      ended_at="$(_histlog_now_ms)"
      if [ -n "${HISTLOG_CMD:-}" ]; then
        "$HISTLOG_BIN" hook precmd --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --exit-status "$status" --cwd "$PWD" --ended-at "$ended_at" >/dev/null 2>&1
        unset HISTLOG_CMD
        unset HISTLOG_STARTED_AT
      fi
    }

    trap '_histlog_preexec' DEBUG
    if [ -n "${PROMPT_COMMAND:-}" ]; then
      PROMPT_COMMAND="_histlog_precmd; $PROMPT_COMMAND"
    else
      PROMPT_COMMAND="_histlog_precmd"
    fi

    _histlog_exit() {
      "$HISTLOG_BIN" hook session-end --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --cwd "$PWD" >/dev/null 2>&1
    }

    trap '_histlog_exit' EXIT

    #{bash_completions()}
    #{posix_aliases(aliases?)}
    """
  end

  defp fish_script(aliases?, binary, durability) do
    """
    # histlog fish integration
    if set -q HISTLOG_ACTIVE
        exit
    end

    set -gx HISTLOG_ACTIVE 1
    if not set -q HISTLOG_ROOT
        set -gx HISTLOG_ROOT "$HOME/.local/share/histlog"
    end
    if not set -q HISTLOG_BIN
        set -gx HISTLOG_BIN #{shell_quote(binary)}
    end
    if not set -q HISTLOG_DURABILITY
        set -gx HISTLOG_DURABILITY #{shell_quote(durability)}
    end
    set -gx HISTLOG_SESSION_ID ("$HISTLOG_BIN" hook session-start --root "$HISTLOG_ROOT" --shell fish --pid %self --cwd "$PWD" --durability "$HISTLOG_DURABILITY")

    function __histlog_now_ms
        if command -q perl
            perl -MTime::HiRes=time -e 'printf "%.0f\\n", time() * 1000'
        else
            printf '%s000\\n' (date +%s)
        end
    end

    function __histlog_preexec --on-event fish_preexec
        set -gx HISTLOG_CMD "$argv[1]"
        set -gx HISTLOG_STARTED_AT (__histlog_now_ms)
        "$HISTLOG_BIN" hook preexec --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --command "$HISTLOG_CMD" --cwd "$PWD" --started-at "$HISTLOG_STARTED_AT" >/dev/null 2>&1
    end

    function __histlog_postexec --on-event fish_postexec
        set -l histlog_status $status
        set -l ended_at (__histlog_now_ms)
        if set -q HISTLOG_CMD
            "$HISTLOG_BIN" hook precmd --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --exit-status "$histlog_status" --cwd "$PWD" --ended-at "$ended_at" >/dev/null 2>&1
            set -e HISTLOG_CMD
            set -e HISTLOG_STARTED_AT
        end
    end

    function __histlog_exit --on-event fish_exit
        "$HISTLOG_BIN" hook session-end --root "$HISTLOG_ROOT" --session "$HISTLOG_SESSION_ID" --cwd "$PWD" >/dev/null 2>&1
    end

    #{fish_completions()}
    #{fish_aliases(aliases?)}
    """
  end

  defp zsh_completions do
    """
    _histlog() {
      local -a commands
      commands=(
        'init:print shell integration'
        'query:query history'
        'tail:tail live history'
        'import:import history'
        'consolidate:consolidate ended sessions'
        'doctor:diagnose setup'
        'hook:internal shell hook boundary'
        'completions:print shell completions'
      )
      _describe 'histlog command' commands
    }
    if whence -w compdef >/dev/null 2>&1; then
      compdef _histlog histlog
    fi
    """
  end

  defp bash_completions do
    """
    _histlog_completion() {
      COMPREPLY=($(compgen -W "init query tail import consolidate doctor hook completions" -- "${COMP_WORDS[COMP_CWORD]}"))
    }
    complete -F _histlog_completion histlog
    """
  end

  defp fish_completions do
    """
    complete -c histlog -f -a "init" -d "Print shell integration"
    complete -c histlog -f -a "query" -d "Query history"
    complete -c histlog -f -a "tail" -d "Tail live history"
    complete -c histlog -f -a "import" -d "Import history"
    complete -c histlog -f -a "consolidate" -d "Consolidate ended sessions"
    complete -c histlog -f -a "doctor" -d "Diagnose setup"
    complete -c histlog -f -a "completions" -d "Print shell completions"
    """
  end

  defp posix_aliases(false), do: ""

  defp posix_aliases(true) do
    """
    alias hl='histlog'
    alias hq='histlog query'
    alias ht='histlog tail'
    alias hc='histlog consolidate'
    """
  end

  defp fish_aliases(false), do: ""

  defp fish_aliases(true) do
    """
    alias hl='histlog'
    alias hq='histlog query'
    alias ht='histlog tail'
    alias hc='histlog consolidate'
    """
  end

  defp shell_quote(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end

  defp shell_param_default(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
    |> String.replace("`", "\\`")
  end
end
