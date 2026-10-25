#!/usr/bin/env bash
# Print the "改动文件" block of a verification-record comment, as HTML, from git.
#
# Usage: changed-files.sh <ITEM-ID> [ignored-path ...]
#   Run inside the target repository. <ITEM-ID> is the Plane identifier
#   (e.g. FMTLAB-12); commits are matched by the whole-line trailer
#   "Refs: <ITEM-ID>", so FMTLAB-1 never matches FMTLAB-12.
#   Each ignored-path is a file the item changed that .gitignore hides from
#   git; it is listed with `git check-ignore -v` as evidence.
#
# Exits non-zero with a message on stderr when no commit carries the trailer,
# so an empty list is never pasted as "nothing changed".
set -euo pipefail

id="${1:?usage: changed-files.sh <ITEM-ID> [ignored-path ...]}"
shift

# quotePath=false: print non-ASCII paths as-is instead of octal escapes.
gitq() { git -c core.quotePath=false "$@"; }
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
li() { esc | sed -e 's|^|<li><code>|' -e 's|$|</code></li>|'; }

commits=$(gitq log --reverse --format=%H --grep="^Refs: ${id}\$")
if [ -z "$commits" ]; then
  echo "changed-files: no commit has trailer 'Refs: ${id}'" >&2
  exit 1
fi

# Validate ignored paths before printing anything, so a failure never leaves
# half a block on stdout.
ignored=""
for f in "$@"; do
  if ! out=$(gitq check-ignore -v -- "$f"); then
    echo "changed-files: '$f' is not ignored by git; it belongs in a commit, not here" >&2
    exit 1
  fi
  ignored+="${out}"$'\n'
done
ignored="${ignored%$'\n'}"

# One line, no whitespace between tags: Plane's web editor turns every
# newline between two tags into an empty paragraph or bullet when the
# comment is next saved from the browser.
{
  echo "<p>HEAD：<code>$(gitq rev-parse --short HEAD)</code></p>"
  echo "<p>提交</p><ul>"
  for c in $commits; do
    echo "<li><code>$(gitq log -1 --format='%h %s' "$c" | esc)</code><ul>"
    gitq show --name-status --format= "$c" | tr '\t' ' ' | li
    echo "</ul></li>"
  done
  echo "</ul>"

  echo "<p>文件并集</p><ul>"
  gitq log --grep="^Refs: ${id}\$" --name-only --format= | sed '/^$/d' | sort -u | li
  echo "</ul>"

  echo "<p>未提交改动（git status --porcelain）</p><ul>"
  dirty=$(gitq status --porcelain)
  if [ -z "$dirty" ]; then echo "<li>无</li>"; else printf '%s\n' "$dirty" | li; fi
  echo "</ul>"

  if [ -n "$ignored" ]; then
    echo "<p>git 看不到的改动（git check-ignore -v）</p><ul>"
    printf '%s\n' "$ignored" | tr '\t' ' ' | li
    echo "</ul>"
  fi
} | tr -d '\n'
echo
