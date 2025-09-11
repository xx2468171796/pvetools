#!/usr/bin/env bash

# PVE VM/LXC 定时重启管理脚本（交互式）
# 功能：
# - 为单个或多个 VM/LXC 设置 cron 定时重启任务
# - 列出/删除已配置的定时任务
# - 手动立即重启指定 VM/LXC
#
# 说明：
# - 任务以 /etc/cron.d/pve-auto-restart-<VMID> 文件形式保存
# - 使用绝对路径调用 /usr/sbin/qm 与 /usr/sbin/pct，确保在 cron 环境下可用
# - 需在 PVE 主机上以 root 运行

set -Eeuo pipefail

CRON_DIR="/etc/cron.d"
CRON_PREFIX="pve-auto-restart-"   # 重启计划文件前缀
SNAP_CRON_PREFIX="pve-auto-snap-"  # 定时创建快照计划文件前缀
RB_CRON_PREFIX="pve-auto-rollback-" # 定时回滚计划文件前缀

STATE_DIR="/var/lib/pve-auto"
SNAP_TRACK_PREFIX="snaps"           # 追踪本脚本创建的快照名
SNAP_NAME_PREFIX="auto"            # 自动创建的快照名前缀

QM_BIN="${QM_BIN:-$(command -v qm || echo /usr/sbin/qm)}"
PCT_BIN="${PCT_BIN:-$(command -v pct || echo /usr/sbin/pct)}"
SLEEP_BIN="${SLEEP_BIN:-$(command -v sleep || echo /bin/sleep)}"
DATE_BIN="${DATE_BIN:-$(command -v date || echo /bin/date)}"
SCRIPT_ABS="${SCRIPT_ABS:-$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")}"

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "请以 root 身份运行此脚本。"
    exit 1
  fi
}

check_env() {
  if [[ ! -x "$QM_BIN" && ! -x "$PCT_BIN" ]]; then
    echo "未找到 qm 或 pct 命令，请在 Proxmox VE 主机上运行。"
    exit 1
  fi
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

# 统一的长耗时操作提示封装
run_cmd() {
  # 用法: run_cmd <命令> [参数...]
  # 显示等待提示，执行命令，返回原始退出码
  local rc
  echo "⏳ 正在等待 PVE 执行命令，请稍候…"
  echo "→ $*"
  "$@"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "✅ 完成"
  else
    echo "❌ 命令执行失败，退出码: $rc"
  fi
  return $rc
}

# 成功提示（广告/群信息/快捷命令）
success_tip() {
  echo "—— 操作完成 ｜ 孤独制作 ｜ 电报群: https://t.me/+RZMe7fnvvUg1OWJl ｜ 快捷命令: pvetools"
}

pause() {
  read -rp "按回车继续..." _
}

detect_type() {
  local id="$1"
  if [[ -x "$QM_BIN" ]] && "$QM_BIN" config "$id" &>/dev/null; then
    echo vm
    return 0
  fi
  if [[ -x "$PCT_BIN" ]] && "$PCT_BIN" config "$id" &>/dev/null; then
    echo ct
    return 0
  fi
  echo none
  return 1
}

get_name() {
  local id="$1" type
  type="$(detect_type "$id" 2>/dev/null || echo none)"
  if [[ "$type" == vm ]]; then
    "$QM_BIN" config "$id" 2>/dev/null | awk '/^name:/{print $2; exit}'
  elif [[ "$type" == ct ]]; then
    "$PCT_BIN" config "$id" 2>/dev/null | awk '/^hostname:/{print $2; exit}'
  else
    echo "-"
  fi
}

list_resources() {
  echo "=== 虚拟机 (QEMU) ==="
  echo "字段说明: VMID(编号)  NAME(名称)  STATUS(状态)  其他列按 PVE 显示"
  if [[ -x "$QM_BIN" ]]; then
    "$QM_BIN" list 2>/dev/null || echo "(无)"
  else
    echo "(未检测到 qm)"
  fi
  echo
  echo "=== 容器 (LXC) ==="
  echo "字段说明: VMID(编号)  STATUS(状态)  NAME(名称) 等，具体以 PVE 输出为准"
  if [[ -x "$PCT_BIN" ]]; then
    "$PCT_BIN" list 2>/dev/null || echo "(无)"
  else
    echo "(未检测到 pct)"
  fi
}

valid_hhmm() {
  [[ "$1" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]
}

to_cron_dow() {
  # 输入可为 0-7 或 mon..sun 中文简写/英文，全转为 0-7（0/7=周日）
  local in="$1"
  case "${in,,}" in
    0|7|sun|周日|日) echo 0;;
    1|mon|周一|一) echo 1;;
    2|tue|周二|二) echo 2;;
    3|wed|周三|三) echo 3;;
    4|thu|周四|四) echo 4;;
    5|fri|周五|五) echo 5;;
    6|sat|周六|六) echo 6;;
    *) echo -1;;
  esac
}

prompt_schedule() {
  # 输出：全局变量 CRON_MIN CRON_HOUR CRON_DOM CRON_MON CRON_DOW OFFSET_MIN 描述文本
  local choice time dow dom cron custom
  OFFSET_MIN=0
  while true; do
    echo "选择重启策略："
    echo "  1) 每天在指定时间"
    echo "  2) 每周在指定星期+时间"
    echo "  3) 每月在指定日期+时间"
    echo "  4) 使用自定义 cron 表达式"
    echo "  5) 取消"
    read -rp "请输入选项 [1-5]: " choice
    case "$choice" in
      1)
        while true; do
          read -rp "请输入时间 (HH:MM, 24小时制): " time
          if valid_hhmm "$time"; then break; else echo "时间格式无效"; fi
        done
        CRON_MIN="${time##*:}"
        CRON_HOUR="${time%%:*}"
        CRON_DOM="*"; CRON_MON="*"; CRON_DOW="*"
        SCHEDULE_DESC="每天 ${CRON_HOUR}:${CRON_MIN}"
        break
        ;;
      2)
        while true; do
          read -rp "请输入星期 (0-7, 周日=0或7，或 mon..sun/周一..周日): " dow
          local d="$(to_cron_dow "$dow")"
          if [[ "$d" != "-1" ]]; then dow="$d"; break; else echo "星期无效"; fi
        done
        while true; do
          read -rp "请输入时间 (HH:MM, 24小时制): " time
          if valid_hhmm "$time"; then break; else echo "时间格式无效"; fi
        done
        CRON_MIN="${time##*:}"
        CRON_HOUR="${time%%:*}"
        CRON_DOM="*"; CRON_MON="*"; CRON_DOW="$dow"
        SCHEDULE_DESC="每周$(echo "$dow")的 ${CRON_HOUR}:${CRON_MIN}"
        break
        ;;
      3)
        while true; do
          read -rp "请输入日期 (1-31): " dom
          if [[ "$dom" =~ ^([1-9]|[12][0-9]|3[01])$ ]]; then break; else echo "日期无效"; fi
        done
        while true; do
          read -rp "请输入时间 (HH:MM, 24小时制): " time
          if valid_hhmm "$time"; then break; else echo "时间格式无效"; fi
        done
        CRON_MIN="${time##*:}"
        CRON_HOUR="${time%%:*}"
        CRON_DOM="$dom"; CRON_MON="*"; CRON_DOW="*"
        SCHEDULE_DESC="每月${CRON_DOM}日 ${CRON_HOUR}:${CRON_MIN}"
        break
        ;;
      4)
        echo "请输入完整 cron 表达式（5段：min hour dom mon dow），例如：0 3 * * *"
        read -rp "> " custom
        # 简单校验 5 段
        local count
        count=$(awk '{print NF}' <<<"$custom")
        if [[ "$count" -eq 5 ]]; then
          CRON_MIN=$(awk '{print $1}' <<<"$custom")
          CRON_HOUR=$(awk '{print $2}' <<<"$custom")
          CRON_DOM=$(awk '{print $3}' <<<"$custom")
          CRON_MON=$(awk '{print $4}' <<<"$custom")
          CRON_DOW=$(awk '{print $5}' <<<"$custom")
          SCHEDULE_DESC="自定义: $custom"
          break
        else
          echo "格式无效，请重试"
        fi
        ;;
      5)
        return 1
        ;;
      *)
        echo "无效选项"
        ;;
    esac
  done

  # 可选偏移
  read -rp "是否添加固定延迟 (分钟，默认0，防止同一时刻同时重启)：" offset
  if [[ -n "${offset:-}" ]]; then
    if [[ "$offset" =~ ^[0-9]+$ ]]; then
      OFFSET_MIN="$offset"
    else
      echo "输入无效，使用 0"
      OFFSET_MIN=0
    fi
  fi
  return 0
}

write_cron_file() {
  local id="$1" type="$2" name="$3"
  local cron_file="$CRON_DIR/${CRON_PREFIX}${id}"
  local cmd
  if [[ "$type" == vm ]]; then
    cmd="$QM_BIN reboot $id"
  else
    cmd="$PCT_BIN reboot $id"
  fi

  mkdir -p "$CRON_DIR"

  {
    echo "# Managed by pve-restart-scheduler"
    echo "# ACTION=reboot TYPE=$type VMID=$id NAME=${name:-'-'} CREATED=$($DATE_BIN +%F_%T)"
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    # cron: min hour dom mon dow user command
    echo "${CRON_MIN} ${CRON_HOUR} ${CRON_DOM} ${CRON_MON:-*} ${CRON_DOW} root ${SLEEP_BIN} ${OFFSET_MIN:-0}m && $cmd"
  } >"$cron_file"

  chmod 0644 "$cron_file"
  chown root:root "$cron_file"

  # 尝试重载 cron（若失败不会中断）
  if command -v systemctl &>/dev/null; then
    systemctl reload cron 2>/dev/null || true
    systemctl reload crond 2>/dev/null || true
  fi
}

write_cron_snapshot_create() {
  local id="$1" type="$2" name="$3" keep_count="$4" max_days="$5" prefix="$6"
  local cron_file="$CRON_DIR/${SNAP_CRON_PREFIX}${id}"
  mkdir -p "$CRON_DIR"
  {
    echo "# Managed by pve-restart-scheduler"
    echo "# ACTION=snapshot_create TYPE=$type VMID=$id NAME=${name:-'-'} KEEP=$keep_count DAYS=$max_days PREFIX=$prefix CREATED=$($DATE_BIN +%F_%T)"
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    echo "${CRON_MIN} ${CRON_HOUR} ${CRON_DOM} ${CRON_MON:-*} ${CRON_DOW} root /bin/bash $SCRIPT_ABS --cron snap-create $type $id $prefix $keep_count $max_days"
  } >"$cron_file"
  chmod 0644 "$cron_file" && chown root:root "$cron_file"
  if command -v systemctl &>/dev/null; then
    systemctl reload cron 2>/dev/null || true
    systemctl reload crond 2>/dev/null || true
  fi
}

write_cron_snapshot_rollback() {
  local id="$1" type="$2" name="$3" mode="$4" prefix="$5"
  # mode: latest | name
  local cron_file="$CRON_DIR/${RB_CRON_PREFIX}${id}"
  mkdir -p "$CRON_DIR"
  {
    echo "# Managed by pve-restart-scheduler"
    echo "# ACTION=snapshot_rollback TYPE=$type VMID=$id TARGET_MODE=$mode TARGET=${name:-'-'} PREFIX=${prefix:-'-'} CREATED=$($DATE_BIN +%F_%T)"
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    if [[ "$mode" == latest ]]; then
      echo "${CRON_MIN} ${CRON_HOUR} ${CRON_DOM} ${CRON_MON:-*} ${CRON_DOW} root /bin/bash $SCRIPT_ABS --cron snap-rollback $type $id latest ${prefix:-$SNAP_NAME_PREFIX}"
    else
      echo "${CRON_MIN} ${CRON_HOUR} ${CRON_DOM} ${CRON_MON:-*} ${CRON_DOW} root /bin/bash $SCRIPT_ABS --cron snap-rollback $type $id name $name"
    fi
  } >"$cron_file"
  chmod 0644 "$cron_file" && chown root:root "$cron_file"
  if command -v systemctl &>/dev/null; then
    systemctl reload cron 2>/dev/null || true
    systemctl reload crond 2>/dev/null || true
  fi
}

add_or_update_single() {
  list_resources
  echo
  read -rp "请输入要设置的 VMID: " id
  if [[ -z "$id" || ! "$id" =~ ^[0-9]+$ ]]; then
    echo "VMID 无效"
    return
  fi
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then
    echo "未找到 VM/LXC: $id"
    return
  fi
  local name="$(get_name "$id")"
  echo "已检测到 $id ($type) 名称: ${name:-'-'}"
  if ! prompt_schedule; then
    echo "已取消"
    return
  fi
  write_cron_file "$id" "$type" "$name"
  echo "已保存：$SCHEDULE_DESC (延迟 ${OFFSET_MIN} 分钟) -> $CRON_DIR/${CRON_PREFIX}${id}"
}

add_or_update_batch() {
  list_resources
  echo
  read -rp "请输入多个 VMID（空格分隔）: " line
  read -ra ids <<<"$line"
  if [[ ${#ids[@]} -eq 0 ]]; then
    echo "未输入 VMID"
    return
  fi
  if ! prompt_schedule; then
    echo "已取消"
    return
  fi
  for id in "${ids[@]}"; do
    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
      echo "跳过无效 VMID: $id"
      continue
    fi
    local type name
    type="$(detect_type "$id" || true)"
    if [[ "$type" == none ]]; then
      echo "跳过不存在的 VM/LXC: $id"
      continue
    fi
    name="$(get_name "$id")"
    write_cron_file "$id" "$type" "$name"
    echo "OK: $id ($type) ${name:-'-'} -> $SCHEDULE_DESC 延迟${OFFSET_MIN}分"
  done
}

list_schedules() {
  shopt -s nullglob
  local files=("$CRON_DIR/${CRON_PREFIX}"* "$CRON_DIR/${SNAP_CRON_PREFIX}"* "$CRON_DIR/${RB_CRON_PREFIX}"*)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "未找到已设置的定时任务。"
    return
  fi
  printf "%-8s %-8s %-4s %-18s %s\n" "VMID" "动作" "类型" "计划(分钟 小时 日 月 周)" "命令"
  for f in "${files[@]}"; do
    local id type name cronline cmd action
    # 提取 VMID（兼容三种前缀）
    id="${f##*$CRON_DIR/}"
    id="${id##${CRON_PREFIX}}"; id="${id##${SNAP_CRON_PREFIX}}"; id="${id##${RB_CRON_PREFIX}}"
    action=$(awk -F'[ =]' '/^# ACTION=/{print $2; exit}' "$f" 2>/dev/null || echo -)
    type=$(awk -F'[ =]' '/^# .*TYPE=/{for(i=1;i<=NF;i++){if($i ~ /^TYPE=/){split($i,a,"=");print a[2];break}}}' "$f" 2>/dev/null || echo -)
    name=$(awk -F'[ =]' '/^# TYPE=/{print $0; exit}' "$f" 2>/dev/null | awk -F'NAME=' '{print $2}' | awk '{print $1}' )
    cronline=$(awk 'NF>=7 && $1 !~ /^#/ {print $1,$2,$3,$4,$5; exit}' "$f" 2>/dev/null)
    cmd=$(awk 'NF>=7 && $1 !~ /^#/ {$1=$2=$3=$4=$5=$6=""; sub(/^  +/,""); print; exit}' "$f" 2>/dev/null)
    printf "%-8s %-8s %-4s %-18s %s\n" "$id" "${action:-'-'}" "${type:-'-'}" "${cronline:-'-'}" "${cmd:-'-'}"
  done
}

remove_schedule() {
  list_schedules
  echo
  read -rp "请输入要删除任务的 VMID: " id
  local targets=("$CRON_DIR/${CRON_PREFIX}${id}" "$CRON_DIR/${SNAP_CRON_PREFIX}${id}" "$CRON_DIR/${RB_CRON_PREFIX}${id}")
  local found=()
  for t in "${targets[@]}"; do
    [[ -f "$t" ]] && found+=("$t")
  done
  if [[ ${#found[@]} -eq 0 ]]; then
    echo "未找到该 VMID 的任何计划任务。"
    return
  fi
  echo "将删除以下文件："
  printf ' - %s\n' "${found[@]}"
  read -rp "确认删除上述任务？[y/N]: " yn
  if [[ "${yn,,}" == y* ]]; then
    rm -f -- "${found[@]}"
    echo "已删除。"
    if command -v systemctl &>/dev/null; then
      systemctl reload cron 2>/dev/null || true
      systemctl reload crond 2>/dev/null || true
    fi
  else
    echo "已取消"
  fi
}

restart_now() {
  list_resources
  echo
  read -rp "请输入需要立即重启的 VMID: " id
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then
    echo "未找到 VM/LXC: $id"
    return
  fi
  read -rp "确认立即重启 $id ($type) ? [y/N]: " yn
  if [[ "${yn,,}" != y* ]]; then
    echo "已取消"
    return
  fi
  if [[ "$type" == vm ]]; then
    run_cmd "$QM_BIN" reboot "$id" || return
  else
    run_cmd "$PCT_BIN" reboot "$id" || return
  fi
  success_tip
}

suspend_now() {
  list_resources
  echo
  read -rp "请输入需要立即暂停(挂起)的 VMID: " id
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then
    echo "未找到 VM/LXC: $id"
    return
  fi
  read -rp "确认立即暂停 $id ($type) ? [y/N]: " yn
  if [[ "${yn,,}" != y* ]]; then
    echo "已取消"
    return
  fi
  if [[ "$type" == vm ]]; then
    run_cmd "$QM_BIN" suspend "$id" || return
  else
    run_cmd "$PCT_BIN" suspend "$id" || return
  fi
  success_tip
}

stop_now() {
  list_resources
  echo
  read -rp "请输入需要立即停止(强制)的 VMID: " id
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then
    echo "未找到 VM/LXC: $id"
    return
  fi
  read -rp "确认立即停止(相当于断电) $id ($type) ? [y/N]: " yn
  if [[ "${yn,,}" != y* ]]; then
    echo "已取消"
    return
  fi
  if [[ "$type" == vm ]]; then
    run_cmd "$QM_BIN" stop "$id" || return
  else
    run_cmd "$PCT_BIN" stop "$id" || return
  fi
  success_tip
}

shutdown_now() {
  list_resources
  echo
  read -rp "请输入需要立即关机(优雅)的 VMID: " id
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then
    echo "未找到 VM/LXC: $id"
    return
  fi
  read -rp "确认立即关机 $id ($type) ? [y/N]: " yn
  if [[ "${yn,,}" != y* ]]; then
    echo "已取消"
    return
  fi
  if [[ "$type" == vm ]]; then
    run_cmd "$QM_BIN" shutdown "$id" || return
  else
    run_cmd "$PCT_BIN" shutdown "$id" || return
  fi
  success_tip
}

create_snapshot() {
  list_resources
  echo
  read -rp "请输入需要创建快照的 VMID: " id
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then
    echo "未找到 VM/LXC: $id"
    return
  fi
  local default_name
  default_name="snap-$($DATE_BIN +%Y%m%d-%H%M%S)"
  read -rp "请输入快照名称(默认: ${default_name}): " snap
  snap=${snap:-$default_name}
  if [[ -z "$snap" ]]; then
    echo "快照名称无效"
    return
  fi
  read -rp "可选: 输入快照描述(留空跳过): " desc || true
  echo "将为 $id ($type) 创建快照: $snap"
  read -rp "确认创建? [y/N]: " yn
  if [[ "${yn,,}" != y* ]]; then
    echo "已取消"
    return
  fi
  local rc=0
  if [[ "$type" == vm ]]; then
    if [[ -n "${desc:-}" ]]; then
      run_cmd "$QM_BIN" snapshot "$id" "$snap" --description "$desc"; rc=$?
    else
      run_cmd "$QM_BIN" snapshot "$id" "$snap"; rc=$?
    fi
  else
    if [[ -n "${desc:-}" ]]; then
      run_cmd "$PCT_BIN" snapshot "$id" "$snap" --description "$desc"; rc=$?
    else
      run_cmd "$PCT_BIN" snapshot "$id" "$snap"; rc=$?
    fi
  fi
  if [[ $rc -eq 0 ]]; then success_tip; fi
}

schedule_snapshot_create() {
  list_resources
  echo
  read -rp "请输入要设置的 VMID: " id
  if [[ -z "$id" || ! "$id" =~ ^[0-9]+$ ]]; then
    echo "VMID 无效"; return
  fi
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then echo "未找到 VM/LXC: $id"; return; fi
  local name="$(get_name "$id")"
  echo "已检测到 $id ($type) 名称: ${name:-'-'}"
  if ! prompt_schedule; then echo "已取消"; return; fi
  echo "保留策略: 同时满足以下条件才会被保留 -> 排名在最近N个内 且 未超过D天。"
  echo "提示: 将 D=0 表示仅按数量保留；将 N 设为很大则近似仅按天数保留。"
  local keep_count max_days prefix
  read -rp "快照保留数量(默认7): " keep_count; keep_count=${keep_count:-7}
  if ! [[ "$keep_count" =~ ^[0-9]+$ ]]; then echo "数量无效，使用7"; keep_count=7; fi
  read -rp "快照最大保留天数(默认30, 0表示不按天限制): " max_days; max_days=${max_days:-30}
  if ! [[ "$max_days" =~ ^[0-9]+$ ]]; then echo "天数无效，使用30"; max_days=30; fi
  read -rp "快照名前缀(默认: ${SNAP_NAME_PREFIX}): " prefix; prefix=${prefix:-$SNAP_NAME_PREFIX}
  write_cron_snapshot_create "$id" "$type" "$name" "$keep_count" "$max_days" "$prefix"
  echo "已保存定时快照：$SCHEDULE_DESC 前缀=$prefix 保留N=$keep_count 天数=$max_days -> $CRON_DIR/${SNAP_CRON_PREFIX}${id}"
}

schedule_snapshot_rollback() {
  list_resources
  echo
  read -rp "请输入要设置的 VMID: " id
  if [[ -z "$id" || ! "$id" =~ ^[0-9]+$ ]]; then echo "VMID 无效"; return; fi
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then echo "未找到 VM/LXC: $id"; return; fi
  local name="$(get_name "$id")"
  echo "已检测到 $id ($type) 名称: ${name:-'-'}"
  if ! prompt_schedule; then echo "已取消"; return; fi
  echo "回滚目标："
  echo "  1) 最新的自动快照(按前缀)"
  echo "  2) 指定快照名称"
  read -rp "请选择 [1-2]: " m
  if [[ "$m" == 1 ]]; then
    local prefix
    read -rp "快照名前缀(默认: ${SNAP_NAME_PREFIX}): " prefix; prefix=${prefix:-$SNAP_NAME_PREFIX}
    write_cron_snapshot_rollback "$id" "$type" "" latest "$prefix"
    echo "已保存定时回滚到最新快照(前缀=$prefix)：$SCHEDULE_DESC -> $CRON_DIR/${RB_CRON_PREFIX}${id}"
  elif [[ "$m" == 2 ]]; then
    local snap
    read -rp "请输入快照名称: " snap
    if [[ -z "$snap" ]]; then echo "名称无效"; return; fi
    write_cron_snapshot_rollback "$id" "$type" "$snap" name ""
    echo "已保存定时回滚到快照 '$snap'：$SCHEDULE_DESC -> $CRON_DIR/${RB_CRON_PREFIX}${id}"
  else
    echo "无效选择"
  fi
}

restore_snapshot() {
  echo
  read -rp "请输入需要恢复快照的 VMID: " id
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then
    echo "未找到 VM/LXC: $id"
    return
  fi
  echo "可用快照列表: (名称=Snapshot Name, 描述=Description, 时间=Timestamp)"
  if [[ "$type" == vm ]]; then
    "$QM_BIN" listsnapshot "$id" 2>/dev/null || echo "(无快照)"
  else
    "$PCT_BIN" listsnapshot "$id" 2>/dev/null || echo "(无快照)"
  fi
  read -rp "请输入要恢复的快照名称(snapshot name): " snap
  if [[ -z "$snap" ]]; then
    echo "快照名称不能为空"
    return
  fi
  read -rp "确认恢复到快照 '$snap' ? 该操作会覆盖当前状态。[y/N]: " yn
  if [[ "${yn,,}" != y* ]]; then
    echo "已取消"
    return
  fi
  local rc=0
  if [[ "$type" == vm ]]; then
    run_cmd "$QM_BIN" rollback "$id" "$snap"; rc=$?
  else
    run_cmd "$PCT_BIN" rollback "$id" "$snap"; rc=$?
  fi
  read -rp "回滚完成。是否立即启动该实例? [y/N]: " start_yn
  if [[ "${start_yn,,}" == y* ]]; then
    if [[ "$type" == vm ]]; then
      run_cmd "$QM_BIN" start "$id"
    else
      run_cmd "$PCT_BIN" start "$id"
    fi
  fi
  if [[ $rc -eq 0 ]]; then success_tip; fi
}

restore_snapshot_v2() {
  echo
  read -rp "请输入需要恢复快照的 VMID: " id
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then
    echo "未找到 VM/LXC: $id"
    return
  fi
  echo "可用快照列表: (名称=Snapshot Name, 描述=Description, 时间=Timestamp)"
  # 展示原始列表（便于核对其他字段）
  if [[ "$type" == vm ]]; then "$QM_BIN" listsnapshot "$id" 2>/dev/null || true; else "$PCT_BIN" listsnapshot "$id" 2>/dev/null || true; fi
  # 解析名称并编号供选择
  local snap
  snap="$(choose_snapshot_interactive "$type" "$id")"
  if [[ -z "$snap" ]]; then
    echo "快照名称不能为空"
    return
  fi
  read -rp "确认恢复到快照 '$snap' ? 该操作会覆盖当前状态。[y/N]: " yn
  if [[ "${yn,,}" != y* ]]; then
    echo "已取消"
    return
  fi
  local rc=0
  if [[ "$type" == vm ]]; then
    run_cmd "$QM_BIN" rollback "$id" "$snap"; rc=$?
  else
    run_cmd "$PCT_BIN" rollback "$id" "$snap"; rc=$?
  fi
  read -rp "回滚完成。是否立即启动该实例? [y/N]: " start_yn
  if [[ "${start_yn,,}" == y* ]]; then
    if [[ "$type" == vm ]]; then
      run_cmd "$QM_BIN" start "$id"
    else
      run_cmd "$PCT_BIN" start "$id"
    fi
  fi
  if [[ $rc -eq 0 ]]; then success_tip; fi
}

# 安装/更新快捷命令 pvetools
install_shortcut() {
  local dst="/usr/local/sbin/pvetools"
  mkdir -p "/usr/local/sbin"
  if command -v install &>/dev/null; then
    install -m 0755 "$SCRIPT_ABS" "$dst" || true
  else
    cp -f "$SCRIPT_ABS" "$dst" 2>/dev/null || ln -sf "$SCRIPT_ABS" "$dst"
    chmod 0755 "$dst" 2>/dev/null || true
  fi
  echo "已安装/更新快捷命令：$dst"
  echo "现在可以直接运行：pvetools"
  success_tip
}

schedule_snapshot_rollback_v2() {
  list_resources
  echo
  read -rp "请输入要设置的 VMID: " id
  if [[ -z "$id" || ! "$id" =~ ^[0-9]+$ ]]; then echo "VMID 无效"; return; fi
  local type="$(detect_type "$id" || true)"
  if [[ "$type" == none ]]; then echo "未找到 VM/LXC: $id"; return; fi
  local name="$(get_name "$id")"
  echo "已检测到 $id ($type) 名称: ${name:-'-'}"
  if ! prompt_schedule; then echo "已取消"; return; fi
  echo "回滚目标："
  echo "  1) 最新的自动快照(按前缀)"
  echo "  2) 指定快照(编号或名称)"
  read -rp "请选择 [1-2]: " m
  if [[ "$m" == 1 ]]; then
    local prefix
    read -rp "快照名前缀(默认: ${SNAP_NAME_PREFIX}): " prefix; prefix=${prefix:-$SNAP_NAME_PREFIX}
    write_cron_snapshot_rollback "$id" "$type" "" latest "$prefix"
    echo "已保存定时回滚到最新快照(前缀=$prefix)：$SCHEDULE_DESC -> $CRON_DIR/${RB_CRON_PREFIX}${id}"
  elif [[ "$m" == 2 ]]; then
    local snap
    echo "列出并选择需要回滚的快照:"
    snap="$(choose_snapshot_interactive "$type" "$id")"
    if [[ -z "$snap" ]]; then echo "名称无效"; return; fi
    write_cron_snapshot_rollback "$id" "$type" "$snap" name ""
    echo "已保存定时回滚到快照 '$snap'：$SCHEDULE_DESC -> $CRON_DIR/${RB_CRON_PREFIX}${id}"
  else
    echo "无效选择"
  fi
}

main_menu() {
  while true; do
    echo
    echo "==== PVE 定时重启管理 ===="
    echo "孤独制作 | 电报群: https://t.me/+RZMe7fnvvUg1OWJl"
    echo "提示: 某些操作(重启/关机/启动/快照/回滚)可能需要等待 PVE 返回，请耐心等待。"
    echo "  1) 新增/更新 单个 VM/容器 的重启策略"
    echo "  2) 批量设置 多个 VM/容器 使用同一策略"
    echo "  3) 设置 定时创建快照 (含保留策略)"
    echo "  4) 设置 定时回滚快照"
    echo "  5) 列出已设置的定时任务"
    echo "  6) 删除某个 VMID 的定时任务"
    echo "  7) 立即重启 指定 VM/容器"
    echo "  8) 立即暂停 指定 VM/容器"
    echo "  9) 立即停止 指定 VM/容器"
    echo " 10) 立即关机 指定 VM/容器"
    echo " 11) 创建快照 指定 VM/容器"
    echo " 12) 恢复快照 指定 VM/容器"
    echo " 13) 安装/更新 快捷命令 pvetools"
    echo " 14) 退出"
    read -rp "请选择 [1-14]: " op
    case "$op" in
      1) add_or_update_single; pause ;;
      2) add_or_update_batch; pause ;;
      3) schedule_snapshot_create; pause ;;
      4) schedule_snapshot_rollback_v2; pause ;;
      5) list_schedules; pause ;;
      6) remove_schedule; pause ;;
      7) restart_now; pause ;;
      8) suspend_now; pause ;;
      9) stop_now; pause ;;
     10) shutdown_now; pause ;;
     11) create_snapshot; pause ;;
     12) restore_snapshot_v2; pause ;;
     13) install_shortcut; pause ;;
     14) exit 0 ;;
      *) echo "无效选项" ;;
    esac
  done
}

usage() {
  cat <<EOF
用法: $0
 - 直接运行进入交互式菜单

说明:
 - 任务会写入: ${CRON_DIR}/${CRON_PREFIX}<VMID>
 - 支持 VM (qm) 与 LXC (pct)，自动识别
 - 时间单位 24 小时制，周日可用 0 或 7
 - 立即操作：重启/暂停/停止/关机/创建快照/恢复快照
 - 定时任务：重启、创建快照(含保留策略)、回滚快照

关于本脚本:
 - 孤独制作 | 电报群: https://t.me/+RZMe7fnvvUg1OWJl
EOF
}

require_root
check_env

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ------------------
# 非交互子命令（供 cron 调用）
#   --cron snap-create <type> <id> <prefix> <keep_count> <max_days>
#   --cron snap-rollback <type> <id> latest <prefix>
#   --cron snap-rollback <type> <id> name <snapname>
# ------------------

parse_timestamp_from_name() {
  # 期望名称: <prefix>-YYYYmmdd-HHMMSS
  local name="$1"
  if [[ "$name" =~ ([0-9]{8})-([0-9]{6})$ ]]; then
    echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}" # YYYYmmddHHMMSS
  else
    echo ""
  fi
}

collect_snapshot_names() {
  local type="$1" id="$2"
  local out
  if [[ "$type" == vm ]]; then
    out="$($QM_BIN listsnapshot "$id" 2>/dev/null || true)"
  else
    out="$($PCT_BIN listsnapshot "$id" 2>/dev/null || true)"
  fi
  [[ -z "$out" ]] && return 0
  awk 'BEGIN{IGNORECASE=1}
    /^[[:space:]]*$/ {next}
    /name[[:space:]]+|^name$|^NAME$|^Parent|^Date|^Description/ {next}
    /----/ {next}
    {
      gsub(/[│└├─>*]/, " ")
      n=$1
      if (match($0, /[A-Za-z0-9_.:-]+/)) { n=substr($0, RSTART, RLENGTH) }
      if (n != "" && n !~ /^(name|NAME|Parent|Date|Description)$/) { print n }
    }
  ' <<< "$out" | awk 'NF' | awk '!seen[$0]++'
}

choose_snapshot_interactive() {
  local type="$1" id="$2"; shift 2
  mapfile -t __snaps < <(collect_snapshot_names "$type" "$id")
  if [[ ${#__snaps[@]} -gt 0 ]]; then
    echo "现有快照列表:"
    local i=1
    for s in "${__snaps[@]}"; do printf "  %2d) %s\n" "$i" "$s"; ((i++)); done
    read -rp "请输入编号选择，或直接输入名称: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#__snaps[@]} )); then
      echo "${__snaps[$((sel-1))]}"; return 0
    fi
    if [[ -n "$sel" ]]; then echo "$sel"; return 0; fi
    echo ""; return 1
  else
    echo "(未解析到快照列表，可手动输入名称)"
    read -rp "请输入快照名称: " name
    [[ -n "$name" ]] && echo "$name" || echo ""
  fi
}

cron_snap_create() {
  local type="$1" id="$2" prefix="$3" keep_count="$4" max_days="$5"
  ensure_state_dir
  local ts snap desc list_file
  ts="$($DATE_BIN +%Y%m%d-%H%M%S)"
  snap="${prefix}-${ts}"
  desc="auto snapshot by scheduler ${ts}"
  if [[ "$type" == vm ]]; then
    "$QM_BIN" snapshot "$id" "$snap" --description "$desc" || true
  else
    "$PCT_BIN" snapshot "$id" "$snap" --description "$desc" || true
  fi
  list_file="$STATE_DIR/${SNAP_TRACK_PREFIX}-${type}-${id}.list"
  { echo "$snap"; [[ -f "$list_file" ]] && cat "$list_file"; } | awk 'NF' | awk '!seen[$0]++' >"${list_file}.tmp" && mv "${list_file}.tmp" "$list_file"

  # 生成待保留列表（按名称时间倒序）
  mapfile -t snaps < <(grep -E "^${prefix}-[0-9]{8}-[0-9]{6}$" "$list_file" 2>/dev/null | sort -r)
  local keep=()
  local delete=()
  local cutoff_ts
  if [[ "$max_days" -gt 0 ]]; then
    cutoff_ts=$($DATE_BIN -d "-$max_days days" +%Y%m%d%H%M%S)
  else
    cutoff_ts=0
  fi
  local i=0
  for s in "${snaps[@]}"; do
    local s_ts_raw="$(parse_timestamp_from_name "$s")"
    local s_ts="${s_ts_raw:-99999999999999}"
    if (( i < keep_count )) && { [[ "$cutoff_ts" == 0 ]] || [[ "$s_ts" -ge "$cutoff_ts" ]]; }; then
      keep+=("$s")
      ((i++))
    else
      delete+=("$s")
    fi
  done

  for s in "${delete[@]}"; do
    if [[ "$type" == vm ]]; then
      "$QM_BIN" delsnapshot "$id" "$s" 2>/dev/null || true
    else
      "$PCT_BIN" delsnapshot "$id" "$s" 2>/dev/null || true
    fi
  done
  printf "%s\n" "${keep[@]}" >"$list_file" 2>/dev/null || true
}

cron_snap_rollback() {
  local type="$1" id="$2" mode="$3" arg="$4"
  local target=""
  if [[ "$mode" == latest ]]; then
    local prefix="$arg"
    local list_file="$STATE_DIR/${SNAP_TRACK_PREFIX}-${type}-${id}.list"
    if [[ -f "$list_file" ]]; then
      target=$(grep -E "^${prefix}-[0-9]{8}-[0-9]{6}$" "$list_file" | sort -r | head -n1)
    fi
    if [[ -z "$target" ]]; then
      echo "未找到可用的自动快照(前缀=$prefix)"; return 1
    fi
  else
    target="$arg"
  fi
  if [[ "$type" == vm ]]; then
    "$QM_BIN" rollback "$id" "$target"
  else
    "$PCT_BIN" rollback "$id" "$target"
  fi
}

if [[ "${1:-}" == "--cron" ]]; then
  shift
  subcmd="${1:-}"
  case "$subcmd" in
    snap-create)
      shift
      cron_snap_create "$@"
      exit $?
      ;;
    snap-rollback)
      shift
      cron_snap_rollback "$@"
      exit $?
      ;;
    *)
      echo "未知的 --cron 子命令"
      exit 2
      ;;
  esac
fi

main_menu
