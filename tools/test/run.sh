#!/usr/bin/env bash
# Every check, in one go: bash tools/test/run.sh   (quick: bash tools/test/run.sh quick - one load test only)
# Installs what it needs (luaparse, lupa) the first time. Prints a summary at the end; exit 1 if anything failed.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d)
npm ls --prefix "$T/n" luaparse >/dev/null 2>&1 || npm i --silent --prefix "$T/n" luaparse >/dev/null 2>&1
export NODE_PATH="$T/n/node_modules"
python3 -c "import lupa" 2>/dev/null || pip install -q lupa --break-system-packages >/dev/null 2>&1
gunzip -c tools/test/feeds/hourly.lua.gz > "$T/hourly.lua"
gunzip -c tools/test/feeds/base.lua.gz > "$T/base.lua"
fail=0
line() { printf '%-28s %s\n' "$1" "$2"; }
node tools/test/luacheck.js . >"$T/lc.txt" 2>&1 && line "lua syntax" ok || { line "lua syntax" FAIL; cat "$T/lc.txt"; fail=1; }
node tools/test/audit.js . >"$T/au.txt" 2>&1 && line "audit" ok || { line "audit" FAIL; tail -5 "$T/au.txt"; fail=1; }
node --test tools/feed/build.test.mjs >"$T/fd.txt" 2>&1 && line "price robot" ok || { line "price robot" FAIL; grep -E "not ok|error:" "$T/fd.txt"; fail=1; }
# every item that trades has a source (tools/sources/build.py writes the list of the ones it can't place)
g=$(head -1 tools/sources/gaps.txt 2>/dev/null | grep -oE "[0-9]+$")
if [[ "$g" == "0" ]]; then line "item sources: no gaps" ok; else line "item sources: no gaps" FAIL; sed -n 2,20p tools/sources/gaps.txt; fail=1; fi
load() { # look text feed label
  WOLF_LOOK=$1 WOLF_TEXT=$2 python3 tools/test/loadtest.py . "$3" >"$T/lt.txt" 2>&1
  local e l
  e=$(grep -E "errors, " "$T/lt.txt" | tail -1); l=$(grep -E "^layout:" "$T/lt.txt" | tail -1)
  if [[ "$e" == "0 errors, 0 distinct" && "$l" == *"0 overlapping text pairs, 0 texts cut short"* ]]; then line "$4" ok
  else line "$4" FAIL; grep -E "^ERROR|^(OVERLAP|CUT|SPILL|OUT|LOOSE)|MS OVER" "$T/lt.txt" | sort | uniq -c | head -20; fail=1; fi
}
if [[ "$1" == "quick" ]]; then
  load classic 0 "$T/hourly.lua" "load test"
else
  for look in classic dark; do for t in 0 2; do load $look $t "$T/hourly.lua" "load test $look, text $t"; done; done
  load classic 0 "$T/base.lua" "load test, no hourly feed"
fi
rm -rf "$T"
[[ $fail == 0 ]] && echo "ALL GOOD" || echo "SOMETHING FAILED"
exit $fail
