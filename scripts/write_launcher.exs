#!/usr/bin/env elixir

root = File.cwd!()
launcher_path = Path.join([root, "app", "histlog"])

script = """
#!/bin/sh
set -eu

HISTLOG_LAUNCHER="$0"
while [ -L "$HISTLOG_LAUNCHER" ]; do
  HISTLOG_LAUNCHER_DIR=$(CDPATH= cd -- "$(dirname -- "$HISTLOG_LAUNCHER")" && pwd)
  HISTLOG_LAUNCHER_TARGET=$(readlink "$HISTLOG_LAUNCHER")
  case "$HISTLOG_LAUNCHER_TARGET" in
    /*) HISTLOG_LAUNCHER="$HISTLOG_LAUNCHER_TARGET" ;;
    *) HISTLOG_LAUNCHER="$HISTLOG_LAUNCHER_DIR/$HISTLOG_LAUNCHER_TARGET" ;;
  esac
done

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$HISTLOG_LAUNCHER")" && pwd)
if [ -d "$APP_DIR/lib/histlog/ebin" ]; then
  HISTLOG_LIB_DIR="$APP_DIR/lib"
else
  HISTLOG_LIB_DIR="$APP_DIR/_build/dev/lib"
fi
export ERL_LIBS="$HISTLOG_LIB_DIR${ERL_LIBS:+:$ERL_LIBS}"
exec elixir -e 'Histlog.CLI.main(System.argv())' -- "$@"
"""

File.write!(launcher_path, script)
File.chmod!(launcher_path, 0o755)
