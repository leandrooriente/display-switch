BASE="$HOME/Library/Application Support/Display Switch"
CONFIG="$BASE/config.json"
if [[ ! -x "$BASE/display-switch" ]]; then
  printf 'Run the monitor follow installer on this Mac first.\n' >&2
  exit 1
fi
