#!/usr/bin/env bash
# 正式环境护栏。文字约束(CLAUDE.md 之类)靠 agent 自觉,这一道不靠。
#
# ── 判据是目录名,不是分支名,也不是环境变量 ────────────────────────────────
# 分支能被 checkout 改掉,目录不会。而且 Docker Compose 的项目名默认就取目录名,
# 容器名和卷名都带这个前缀——目录名已经是「这条命令会动到哪一套数据」的事实
# 判据。再引入第二种判据(ENV=prod、分支名)就会出现「一处说这是 UAT、一处说是
# 正式」的状态,而这类不一致恰好在最危险的那一刻才暴露。
#
# ── 只拦不可逆、且没有 undo 的操作 ────────────────────────────────────────
# 拦得越多,被整体关掉的可能越大。所以这里只有三条硬拦截 + 一条软确认,不追求
# 全面防护。换个写法(`docker rm -v`、手删 /var/lib/docker/volumes/)照样绕得
# 过去——真正的兜底仍然是「不在正式环境目录里做试验」。
#
# 占位符由 env-tiers/setup-tiers skill 填写:
#   __PROD_DIR__      正式环境的目录名(目录名,不是路径)
#   __DATA_VOLUME__   compose 里声明的卷名;实际卷名是 <PROD_DIR>_<DATA_VOLUME>
#   __PROD_OVERRIDE__ 正式环境必须带上的 compose override 文件名
#   __UAT_DIR__       UAT 的目录名,只出现在提示文案里
set -uo pipefail

PROD_DIR="__PROD_DIR__"
DATA_VOLUME="__DATA_VOLUME__"
PROD_OVERRIDE="__PROD_OVERRIDE__"
UAT_DIR="__UAT_DIR__"

FULL_VOLUME="${PROD_DIR}_${DATA_VOLUME}"

INPUT=$(cat)

# python3 不在时两个变量都是空,下面 CMD 为空即放行——fail-open 是刻意的:
# 一道解析不出输入的护栏如果改成 fail-closed,会把这个项目里所有 Bash 调用
# 全堵死,结果必然是有人直接把 hook 关掉,连那三条硬拦截一起失去。
CWD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null || echo "")
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")

[ -z "$CMD" ] && exit 0

# ── 这条命令是不是打在正式环境上 ──────────────────────────────────────────
#
# 主判据:session 的目录名等于 PROD_DIR。worktree 的目录名各不相同,天然被排除,
# 不需要额外的路径前缀例外。
#
# 补充判据:hook 拿到的 cwd 是 session 的工作目录,不是命令实际执行的目录。
# `cd ../<PROD_DIR> && docker compose down -v` 会带着一个无害的 cwd 通过主判据。
# 所以命令文本里出现 `cd` 到该目录时同样按正式环境处理。代价是偶尔误伤(例如在
# UAT 里 `cd ../<PROD_DIR> && git log`),而误伤只是多挨一次拦截,方向是安全的。
in_prod=0
[ "$(basename "$CWD")" = "$PROD_DIR" ] && in_prod=1
printf '%s' "$CMD" | grep -qE "\bcd[[:space:]]+[^[:space:];&|]*/?${PROD_DIR}(/|[[:space:]]|$)" && in_prod=1

[ "$in_prod" -eq 0 ] && exit 0

# ── 硬拦截:会清掉真实数据且没有 undo ─────────────────────────────────────

# compose down 带 -v/--volumes
if printf '%s' "$CMD" | grep -qE 'docker[[:space:]]+compose\b' \
   && printf '%s' "$CMD" | grep -qE '\bdown\b' \
   && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-v|--volumes)([[:space:]]|$)'; then
  cat >&2 <<MSG
拦下了:这里是正式环境目录,\`down -v\` 会删掉 ${FULL_VOLUME}——真实数据。
恢复只能退回上一次备份,那之间的写入没有别处可取。

要重启正式环境用:
  just up
要清空数据做试验,去 ${UAT_DIR}/。
MSG
  exit 2
fi

# 直接删/清卷。prune 不带项目名,会把这台机器上所有未使用的卷一起带走。
if printf '%s' "$CMD" | grep -qE 'docker[[:space:]]+volume[[:space:]]+(rm|prune)'; then
  cat >&2 <<MSG
拦下了:${FULL_VOLUME} 是正式环境的真实数据,删掉只能退回上一次备份。
确实要删就自己在终端执行,不要经 agent。
MSG
  exit 2
fi

# git clean -x 会把被 gitignore 的文件一起删——凭证文件和本地备份目录通常正好
# 都被 gitignore,于是在 clean 眼里它们是「无主文件」,而它们恰恰最不能丢。
if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+clean\b' \
   && printf '%s' "$CMD" | grep -qE '[[:space:]]-[a-zA-Z]*[xX]'; then
  cat >&2 <<'MSG'
拦下了:`git clean -x` 会删掉被 gitignore 的文件——凭证和本地数据库快照通常都在
这一类里,它们在 clean 眼里是无主文件,却是唯一一份。
MSG
  exit 2
fi

# ── 软确认:会静默把正式环境退回开发配置 ──────────────────────────────────
#
# 不带 override 的 `up` 会让 compose 只读基础文件,源码 bind mount 回来,于是
# 后续 `git merge` 时前后端在半新半旧的代码之间反复热重载。这个错误不毁数据,
# 但它是静默的——容器照样起来,页面照样能开。所以问一句,而不是拦死。
if printf '%s' "$CMD" | grep -qE 'docker[[:space:]]+compose\b' \
   && printf '%s' "$CMD" | grep -qE '\b(up|restart)\b' \
   && ! printf '%s' "$CMD" | grep -q "$PROD_OVERRIDE"; then
  PROD_OVERRIDE="$PROD_OVERRIDE" python3 - <<'PY'
import json, os
override = os.environ["PROD_OVERRIDE"]
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": (
        f"正式环境目录下没带 {override}。这样起会退回开发配置——源码 bind mount "
        "回来,之后 git merge 会让服务在半新半旧的代码之间反复热重载。确认要这样起吗?\n"
        f"  正式:docker compose -f docker-compose.yml -f {override} up -d --build"
    ),
}}))
PY
  exit 0
fi

exit 0
