#!/usr/bin/env elixir

root = File.cwd!()
launcher_path = Path.join([root, "app", "histlog"])

script = """
#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export ERL_LIBS="$APP_DIR/_build/dev/lib${ERL_LIBS:+:$ERL_LIBS}"
exec elixir -e 'Histlog.CLI.main(System.argv())' -- "$@"
"""

File.write!(launcher_path, script)
File.chmod!(launcher_path, 0o755)
