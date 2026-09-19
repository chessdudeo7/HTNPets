#!/usr/bin/env bash
# Badge sandbox lint. Catches the class of bug that looks fine locally and
# hard-errors on the badge, where there is no pcall to recover with.
# Usage: ./lint.sh apps/*.lua

status=0
LOCALAPPDATA_LUAC="$HOME/AppData/Local/Programs/Lua/bin/luac.exe"

# Identifiers the badge Lua sandbox does not provide.
BANNED='pcall|xpcall|loadfile|dofile|setmetatable|getmetatable|\bload\s*\(|\bos\.|\bio\.|coroutine\.|package\.|debug\.'
# Factories that exist only under api=1.
LEGACY='badge\.label\s*\(|badge\.box\s*\('

for f in "$@"; do
  echo "== $f"

  if ! head -1 "$f" | grep -q '^--\[==\[badge-app$'; then
    echo "  FAIL missing badge-app header on line 1"
    status=1
  fi

  if ! grep -q '^\]==\]$' "$f"; then
    echo "  FAIL missing closing ]==] delimiter"
    status=1
  fi

  for key in slug name api; do
    if ! grep -q "^$key=" "$f"; then
      echo "  FAIL manifest missing $key="
      status=1
    fi
  done

  if grep -qnE "$BANNED" "$f"; then
    echo "  FAIL uses identifiers absent from the sandbox:"
    grep -nE "$BANNED" "$f" | sed 's/^/    /'
    status=1
  fi

  if grep -qnE "$LEGACY" "$f"; then
    echo "  FAIL uses api=1 only factories (use badge.ui.*):"
    grep -nE "$LEGACY" "$f" | sed 's/^/    /'
    status=1
  fi

  # The bundled fonts have no em dashes, curly quotes or emoji.
  if LC_ALL=C grep -qn '[^ -~	]' "$f"; then
    echo "  FAIL non-ASCII bytes (bundled fonts render these as squares):"
    LC_ALL=C grep -n '[^ -~	]' "$f" | sed 's/^/    /'
    status=1
  fi

  bytes=$(wc -c < "$f")
  echo "  size ${bytes} bytes (main.lua cap 65536, Share bundle cap 49152)"
  if [ "$bytes" -gt 49152 ]; then
    echo "  WARN over the 48 KiB Share bundle cap - cannot be shared badge to badge"
    status=1
  fi

  # Lua syntax. Prefer PATH; fall back to the winget install location, which
  # only lands on PATH for shells started after `winget install DEVCOM.Lua`.
  if [ -z "$LUAC" ]; then
    if command -v luac >/dev/null 2>&1; then
      LUAC=luac
    elif [ -x "$LOCALAPPDATA_LUAC" ]; then
      LUAC="$LOCALAPPDATA_LUAC"
    fi
  fi
  if [ -n "$LUAC" ]; then
    if "$LUAC" -p "$f" 2>/dev/null; then
      echo "  syntax ok (luac -p)"
    else
      echo "  FAIL lua syntax:"
      "$LUAC" -p "$f" 2>&1 | sed 's/^/    /'
      status=1
    fi
  else
    echo "  skip syntax check (no luac found)"
  fi
done

if [ "$status" -eq 0 ]; then
  echo
  echo "all checks passed"
fi
exit $status
