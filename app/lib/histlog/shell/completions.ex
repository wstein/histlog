defmodule Histlog.Shell.Completions do
  @moduledoc false

  @commands [
    {"query", "Query history"},
    {"commands", "Summarize command usage"},
    {"statistics", "Show history statistics"},
    {"sessions", "List shell sessions"},
    {"paths", "Summarize filesystem paths"},
    {"export", "Export history rows"},
    {"import", "Import history"},
    {"consolidate", "Consolidate ended sessions"},
    {"info", "Show runtime information"},
    {"doctor", "Diagnose setup"},
    {"init", "Print shell integration"}
  ]

  @global ["--help", "-h"]

  @options %{
    "query" =>
      @global ++
        ~w(--root --date --regex --delete --force-delete --asc --desc --session --fuzzy --command --dir --failed --success --exit --time --since --before --today --yesterday --week --has-paths --path --long --duration --quick --fast --instant --slow --background --rare --frequent --unique --shell --tty --with-args --no-args --arg-count --private --no-private --imported --no-imported --assisted --no-assisted --json --yaml --plain --format --limit --no-session --no-start-time --no-exit-code --no-duration),
    "commands" =>
      @global ++
        ~w(--root --date --time --since --before --today --yesterday --week --regex --fuzzy --session --dir --sort-by --context --asc --desc --limit --json --plain),
    "statistics" =>
      @global ++
        ~w(--root --date --time --since --before --today --yesterday --week --top --json --plain),
    "sessions" =>
      @global ++
        ~w(--root --date --time --since --before --today --yesterday --week --limit --details --json),
    "paths" =>
      @global ++
        ~w(--root --date --time --since --before --today --yesterday --week --limit --json --plain),
    "export" =>
      @global ++ ~w(--root --date --time --since --before --today --yesterday --week --format),
    "import" => @global ++ ~w(--root --date --source --session-id --import-batch-id),
    "consolidate" => @global ++ ~w(--root --date --rebuild --json),
    "info" => @global ++ ~w(--root --json --plain),
    "doctor" => @global ++ ~w(--root --date --json --plain),
    "init" => @global ++ ~w(--aliases --binary --durability)
  }

  def commands, do: @commands

  def options(command), do: Map.get(@options, command, @global)
end
