defmodule Histlog.Shell.Init do
  @moduledoc """
  Generates shell-native histlog integration scripts.
  """

  @supported_shells ["zsh", "bash", "fish"]
  @future_shells ["nu", "powershell"]

  def supported_shells, do: @supported_shells
  def future_shells, do: @future_shells

  def detect(env \\ System.get_env(), parent_shell_fun \\ &parent_process_shell/0) do
    cond do
      shell = normalize_shell(env["HISTLOG_SHELL"]) ->
        {:ok, shell}

      shell = normalize_shell(parent_shell_fun.()) ->
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
    pinned_binary? = Keyword.has_key?(opts, :binary)

    with :ok <- validate_binary(binary, pinned_binary?),
         {:ok, durability} <- Histlog.Durability.normalize(Keyword.get(opts, :durability)) do
      case shell do
        "zsh" -> {:ok, zsh_script(aliases?, binary, pinned_binary?, durability)}
        "bash" -> {:ok, bash_script(aliases?, binary, pinned_binary?, durability)}
        "fish" -> {:ok, fish_script(aliases?, binary, pinned_binary?, durability)}
        shell when shell in @future_shells -> {:error, {:unsupported_shell, shell}}
        shell -> {:error, {:unknown_shell, shell}}
      end
    end
  end

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

  defp parent_process_shell do
    with pid when is_binary(pid) <- System.pid(),
         {ppid, 0} <- System.cmd("ps", ["-p", pid, "-o", "ppid="], stderr_to_stdout: true),
         ppid <- String.trim(ppid),
         true <- ppid != "",
         {command, 0} <- System.cmd("ps", ["-p", ppid, "-o", "comm="], stderr_to_stdout: true) do
      command
      |> String.trim()
      |> Path.basename()
    else
      _ -> nil
    end
  end

  defp validate_binary(_binary, false), do: :ok

  defp validate_binary(binary, true) do
    if Path.type(binary) == :absolute do
      :ok
    else
      {:error, "init --binary requires an absolute path"}
    end
  end

  defp zsh_script(aliases?, binary, pinned_binary?, durability) do
    """
    # histlog zsh integration
    if [ -n "${HISTLOG_ACTIVE:-}" ]; then
      return
    fi

    export HISTLOG_ACTIVE=1
    export HISTLOG_SHELL="zsh"
    export HISTLOG_ROOT="${HISTLOG_ROOT:-$HOME/.local/share/histlog}"
    #{posix_binary_assignment(binary, pinned_binary?)}
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

  defp bash_script(aliases?, binary, pinned_binary?, durability) do
    """
    # histlog bash integration
    if [ -n "${HISTLOG_ACTIVE:-}" ]; then
      return
    fi

    export HISTLOG_ACTIVE=1
    export HISTLOG_SHELL="bash"
    export HISTLOG_ROOT="${HISTLOG_ROOT:-$HOME/.local/share/histlog}"
    #{posix_binary_assignment(binary, pinned_binary?)}
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

  defp fish_script(aliases?, binary, pinned_binary?, durability) do
    """
    # histlog fish integration
    if set -q HISTLOG_ACTIVE
        exit
    end

    set -gx HISTLOG_ACTIVE 1
    set -gx HISTLOG_SHELL fish
    if not set -q HISTLOG_ROOT
        set -gx HISTLOG_ROOT "$HOME/.local/share/histlog"
    end
    #{fish_binary_assignment(binary, pinned_binary?)}
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
    command_entries =
      Histlog.Shell.Completions.commands()
      |> Enum.map_join("\n", fn {command, description} ->
        "    '#{command}:#{String.downcase(description)}'"
      end)

    option_cases =
      Histlog.Shell.Completions.commands()
      |> Enum.map_join("\n", fn {command, _description} ->
        options = Histlog.Shell.Completions.options(command) |> Enum.join(" ")

        """
          #{command})
            _arguments '*::histlog #{command} option:((#{options}))'
            ;;
        """
      end)

    """
    _histlog() {
      local -a commands
      commands=(
    #{command_entries}
      )

      if (( CURRENT == 2 )); then
        _describe 'histlog command' commands
        return
      fi

      case "${words[2]}" in
    #{option_cases}
        *)
          _describe 'histlog command' commands
          ;;
      esac
    }
    if whence -w compdef >/dev/null 2>&1; then
      compdef _histlog histlog
    fi
    """
  end

  defp bash_completions do
    commands =
      Histlog.Shell.Completions.commands()
      |> Enum.map_join(" ", fn {command, _description} -> command end)

    cases =
      Histlog.Shell.Completions.commands()
      |> Enum.map_join("\n", fn {command, _description} ->
        options = Histlog.Shell.Completions.options(command) |> Enum.join(" ")
        "        #{command}) words=\"#{options}\" ;;"
      end)

    """
    _histlog_completion() {
      local current command words
      current="${COMP_WORDS[COMP_CWORD]}"
      command="${COMP_WORDS[1]:-}"

      if [ "$COMP_CWORD" -le 1 ]; then
        words="#{commands}"
      else
        case "$command" in
    #{cases}
          *) words="#{commands}" ;;
        esac
      fi

      COMPREPLY=($(compgen -W "$words" -- "$current"))
    }
    complete -F _histlog_completion histlog
    """
  end

  defp fish_completions do
    command_lines =
      Histlog.Shell.Completions.commands()
      |> Enum.map_join("\n", fn {command, description} ->
        ~s(complete -c histlog -f -n "__fish_use_subcommand" -a "#{command}" -d "#{description}")
      end)

    option_lines =
      Histlog.Shell.Completions.commands()
      |> Enum.flat_map(fn {command, _description} ->
        Enum.map(Histlog.Shell.Completions.options(command), fn option ->
          name = String.trim_leading(option, "-")
          ~s(complete -c histlog -f -n "__fish_seen_subcommand_from #{command}" -l "#{name}")
        end)
      end)
      |> Enum.join("\n")

    """
    #{command_lines}
    #{option_lines}
    """
  end

  defp posix_aliases(false), do: ""

  defp posix_aliases(true) do
    """
    alias hl='histlog'
    alias hq='histlog query'
    alias hs='histlog sync'
    alias hr='histlog rebuild'
    """
  end

  defp fish_aliases(false), do: ""

  defp fish_aliases(true) do
    """
    alias hl='histlog'
    alias hq='histlog query'
    alias hs='histlog sync'
    alias hr='histlog rebuild'
    """
  end

  defp posix_binary_assignment(binary, true),
    do: ~s(export HISTLOG_BIN="#{shell_param_default(binary)}")

  defp posix_binary_assignment(binary, false),
    do: ~s(export HISTLOG_BIN="${HISTLOG_BIN:-#{shell_param_default(binary)}}")

  defp fish_binary_assignment(binary, true), do: "set -gx HISTLOG_BIN #{shell_quote(binary)}"

  defp fish_binary_assignment(binary, false) do
    """
    if not set -q HISTLOG_BIN
        set -gx HISTLOG_BIN #{shell_quote(binary)}
    end
    """
    |> String.trim_trailing()
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
