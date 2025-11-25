#!/usr/bin/env bash
# =============================================================================
#  PVETools v3.0 - Proxmox VE 统一管理工具
# =============================================================================
#  功能说明:
#    本脚本整合了 PVE 日常运维的四大功能模块：
#    1. VM/CT 管理 - 即时操作、快照管理、定时任务
#    2. Docker 配置 - LXC 容器 Docker 支持配置
#    3. 存储管理 - 磁盘扩容为 LVM-Thin 存储
#    4. 硬盘直通 - 将物理磁盘直通到 VM
#
#  使用方法:
#    ./pvetools.sh              # 交互式菜单
#    pvetools                   # 安装后的快捷命令
#    pvetools install           # 安装快捷命令
#    pvetools -h|--help         # 显示帮助
#
#  兼容版本: PVE 7.x / 8.x / 9.x
#  作者: 孤独制作
#  电报群: https://t.me/+RZMe7fnvvUg1OWJl
# =============================================================================

set -Eeuo pipefail
shopt -s nocasematch

# =============================================================================
# 全局配置
# =============================================================================

VERSION="3.1"
SCRIPT_NAME="PVETools"
SCRIPT_ABS="${SCRIPT_ABS:-$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")}"

# 日志配置
LOG_FILE="/var/log/pvetools.log"
VERBOSE="${VERBOSE:-1}"

# Cron 配置
CRON_DIR="/etc/cron.d"
CRON_PREFIX="pve-auto-restart-"
SNAP_CRON_PREFIX="pve-auto-snap-"
RB_CRON_PREFIX="pve-auto-rollback-"

# 状态目录
STATE_DIR="/var/lib/pve-auto"
SNAP_TRACK_PREFIX="snaps"
SNAP_NAME_PREFIX="auto"

# PVE 命令
QM_BIN="${QM_BIN:-$(command -v qm 2>/dev/null || echo /usr/sbin/qm)}"
PCT_BIN="${PCT_BIN:-$(command -v pct 2>/dev/null || echo /usr/sbin/pct)}"
SLEEP_BIN="${SLEEP_BIN:-$(command -v sleep 2>/dev/null || echo /bin/sleep)}"
DATE_BIN="${DATE_BIN:-$(command -v date 2>/dev/null || echo /bin/date)}"

# =============================================================================
# 颜色定义 - 统一主题
# =============================================================================

# 基础颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 加粗颜色
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'
BOLD_PURPLE='\033[1;35m'
BOLD_CYAN='\033[1;36m'
BOLD_WHITE='\033[1;37m'
DIM='\033[2m'

# =============================================================================
# 工具函数 - 日志和输出
# =============================================================================

# 写入日志文件
# 参数: $1=级别 $2=消息
_write_log() {
  local level="$1" msg="$2"
  local ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts][$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# 日志函数 - 信息
log() {
  echo -e "${BOLD_GREEN}[信息]${NC} $*"
  _write_log "INFO" "$*"
}

# 日志函数 - 警告
warn() {
  echo -e "${BOLD_YELLOW}[警告]${NC} $*"
  _write_log "WARN" "$*"
}

# 日志函数 - 错误（不退出）
err() {
  echo -e "${BOLD_RED}[错误]${NC} $*"
  _write_log "ERROR" "$*"
}

# 日志函数 - 致命错误（退出）
error() {
  echo -e "${BOLD_RED}[错误]${NC} $*"
  _write_log "FATAL" "$*"
  exit 1
}

# 日志函数 - 调试（仅在 VERBOSE=1 时显示）
debug() {
  [[ "$VERBOSE" == "1" ]] && echo -e "${DIM}[调试]${NC} $*" || true
  _write_log "DEBUG" "$*"
}

# 日志函数 - 步骤提示
step() {
  echo -e "${BOLD_PURPLE}[步骤]${NC} $*"
  _write_log "STEP" "$*"
}

# 成功提示（含广告）
success_tip() {
  echo ""
  echo -e "${BOLD_GREEN}✓${NC} 操作完成 | ${BOLD_CYAN}孤独制作${NC} | 电报群: ${BOLD_BLUE}https://t.me/+RZMe7fnvvUg1OWJl${NC}"
}

# =============================================================================
# 工具函数 - 交互
# =============================================================================

# 暂停等待用户按键
pause() {
  echo ""
  read -rp "按回车键继续..." _
}

# 确认提示 - 默认Y
# 参数: $1=提示消息
# 返回: 0=确认, 1=取消
confirm_yes() {
  local prompt="${1:-确认执行?}"
  local answer
  read -rp "${prompt} [Y/n]: " answer
  [[ -z "$answer" || "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# 确认提示 - 默认N（用于危险操作）
# 参数: $1=提示消息
# 返回: 0=确认, 1=取消
confirm_no() {
  local prompt="${1:-确认执行?}"
  local answer
  read -rp "${prompt} [y/N]: " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# 数字输入验证
# 参数: $1=输入值 $2=最小值 $3=最大值
# 返回: 0=有效, 1=无效
is_valid_number() {
  local input="$1" min="$2" max="$3"
  [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge "$min" ]] && [[ "$input" -le "$max" ]]
}

# =============================================================================
# 工具函数 - UI 组件
# =============================================================================

# 显示主横幅
show_banner() {
  clear
  echo ""
  echo -e "${BOLD_CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD_CYAN}║${NC}              ${BOLD_WHITE}PVETools v${VERSION}${NC} - Proxmox VE 统一管理工具           ${BOLD_CYAN}║${NC}"
  echo -e "${BOLD_CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOLD_CYAN}║${NC}  作者: ${BOLD_GREEN}孤独制作${NC}  |  电报群: ${BOLD_BLUE}https://t.me/+RZMe7fnvvUg1OWJl${NC}  ${BOLD_CYAN}║${NC}"
  echo -e "${BOLD_CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# 显示小横幅（子菜单用）
show_sub_banner() {
  local title="$1"
  echo ""
  echo -e "${BOLD_BLUE}┌──────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD_BLUE}│${NC}  ${BOLD_WHITE}${title}${NC}"
  echo -e "${BOLD_BLUE}└──────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# 显示分隔线
show_divider() {
  echo -e "${DIM}────────────────────────────────────────────────────────────────────${NC}"
}

# 显示操作摘要框
# 参数: 标题 和 多行内容（通过管道传入）
show_summary_box() {
  local title="$1"
  echo ""
  echo -e "${BOLD_PURPLE}┌─────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD_PURPLE}│${NC}  ${BOLD_WHITE}${title}${NC}"
  echo -e "${BOLD_PURPLE}├─────────────────────────────────────────────────────────────────┤${NC}"
  while IFS= read -r line; do
    echo -e "${BOLD_PURPLE}│${NC}  ${line}"
  done
  echo -e "${BOLD_PURPLE}└─────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# 显示成功结果框
show_success_box() {
  local title="$1"
  echo ""
  echo -e "${BOLD_GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD_GREEN}║${NC}  ${BOLD_WHITE}✓ ${title}${NC}"
  echo -e "${BOLD_GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  while IFS= read -r line; do
    echo -e "${BOLD_GREEN}║${NC}  ${line}"
  done
  echo -e "${BOLD_GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# 显示错误结果框
show_error_box() {
  local title="$1"
  echo ""
  echo -e "${BOLD_RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD_RED}║${NC}  ${BOLD_WHITE}✗ ${title}${NC}"
  echo -e "${BOLD_RED}╠══════════════════════════════════════════════════════════════════╣${NC}"
  while IFS= read -r line; do
    echo -e "${BOLD_RED}║${NC}  ${line}"
  done
  echo -e "${BOLD_RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# =============================================================================
# 环境检测函数
# =============================================================================

# 检查 root 权限
require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    error "请以 root 身份运行此脚本。使用: sudo $0"
  fi
}

# 检测 PVE 版本
# 返回: 主版本号 (7/8/9) 或 "unknown"
detect_pve_version() {
  local pve_version=""
  
  # 方式1: 从 pveversion 命令获取
  if command -v pveversion &>/dev/null; then
    pve_version=$(pveversion 2>/dev/null | grep -oE 'pve-manager/[0-9]+' | grep -oE '[0-9]+' | head -1 || echo "")
  fi
  
  # 方式2: 从 /etc/pve/.version 获取
  if [[ -z "$pve_version" ]] && [[ -f "/etc/pve/.version" ]]; then
    pve_version=$(head -1 /etc/pve/.version 2>/dev/null | grep -oE '^[0-9]+' || echo "")
  fi
  
  # 方式3: 从 dpkg 获取
  if [[ -z "$pve_version" ]] && command -v dpkg &>/dev/null; then
    pve_version=$(dpkg -l pve-manager 2>/dev/null | awk '/pve-manager/{print $3}' | grep -oE '^[0-9]+' || echo "")
  fi
  
  echo "${pve_version:-unknown}"
}

# 检测 cgroup 版本
detect_cgroup_version() {
  if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    echo "v2"
  elif [[ -d /sys/fs/cgroup/cpu ]]; then
    echo "v1"
  else
    echo "unknown"
  fi
}

# 检测运行环境（PVE 宿主机 或 LXC 容器）
detect_environment() {
  local in_lxc=false
  
  # 检查 /proc/1/environ
  if [[ -f /proc/1/environ ]] && grep -qa "container=lxc" /proc/1/environ 2>/dev/null; then
    in_lxc=true
  fi
  
  # 检查 systemd-detect-virt
  if command -v systemd-detect-virt &>/dev/null; then
    local virt_type
    virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
    if [[ "$virt_type" == "lxc" ]]; then
      in_lxc=true
    fi
  fi
  
  # 检查 /proc/1/cgroup
  if [[ -f /proc/1/cgroup ]] && grep -q "lxc" /proc/1/cgroup 2>/dev/null; then
    in_lxc=true
  fi
  
  if [[ "$in_lxc" == true ]]; then
    echo "lxc"
  else
    echo "pve_host"
  fi
}

# 检查 PVE 环境
check_pve_env() {
  if [[ ! -x "$QM_BIN" && ! -x "$PCT_BIN" ]]; then
    warn "未找到 qm 或 pct 命令"
    return 1
  fi
  return 0
}

# 确保状态目录存在
ensure_state_dir() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
}

# 重载 cron 服务（兼容多种 cron 实现）
reload_cron_service() {
  if command -v systemctl &>/dev/null; then
    systemctl reload cron 2>/dev/null || true
    systemctl reload crond 2>/dev/null || true
    systemctl reload cronie 2>/dev/null || true
  fi
  if command -v pkill &>/dev/null; then
    pkill -HUP cron 2>/dev/null || true
  fi
}

# =============================================================================
# 全局变量（运行时填充）
# =============================================================================

PVE_VERSION=""
CGROUP_VERSION=""
ENV_TYPE=""

# 初始化环境变量
init_environment() {
  PVE_VERSION=$(detect_pve_version)
  CGROUP_VERSION=$(detect_cgroup_version)
  ENV_TYPE=$(detect_environment)
  ensure_state_dir
}

# =============================================================================
# VM/CT 公共函数
# =============================================================================

# 检测 VMID 类型（VM 或 CT）
# 参数: $1=VMID
# 返回: "vm" / "ct" / "none"
detect_type() {
  local id="$1"
  if [[ -x "$QM_BIN" ]] && "$QM_BIN" config "$id" &>/dev/null; then
    echo "vm"
    return 0
  fi
  if [[ -x "$PCT_BIN" ]] && "$PCT_BIN" config "$id" &>/dev/null; then
    echo "ct"
    return 0
  fi
  echo "none"
  return 1
}

# 获取 VM/CT 名称
# 参数: $1=VMID
# 返回: 名称或 "-"
get_name() {
  local id="$1"
  local type name
  type="$(detect_type "$id" 2>/dev/null || echo none)"
  
  if [[ "$type" == "vm" ]]; then
    name="$("$QM_BIN" config "$id" 2>/dev/null | awk '/^name:/{print $2; exit}')"
    if [[ -z "$name" || "$name" == "-" ]]; then
      name="$("$QM_BIN" list 2>/dev/null | awk -v id="$id" '$1 == id {for(i=2;i<=NF;i++){if($i!~/running|stopped/){printf "%s ",$i}}; exit}')"
      name="${name## }"; name="${name%% }"
    fi
    echo "${name:--}"
  elif [[ "$type" == "ct" ]]; then
    name="$("$PCT_BIN" config "$id" 2>/dev/null | awk '/^hostname:/{print $2; exit}')"
    if [[ -z "$name" || "$name" == "-" ]]; then
      name="$("$PCT_BIN" list 2>/dev/null | awk -v id="$id" '$1 == id {for(i=3;i<=NF;i++){if($i!~/running|stopped/){printf "%s ",$i}}; exit}')"
      name="${name## }"; name="${name%% }"
    fi
    echo "${name:--}"
  else
    echo "-"
  fi
}

# 获取 VM/CT 状态
# 参数: $1=VMID $2=类型(vm/ct)
# 返回: "running" / "stopped" / "unknown"
get_status() {
  local id="$1" type="$2"
  local status
  if [[ "$type" == "vm" ]]; then
    status=$("$QM_BIN" status "$id" 2>/dev/null | awk '{print $2}')
  else
    status=$("$PCT_BIN" status "$id" 2>/dev/null | awk '{print $2}')
  fi
  echo "${status:-unknown}"
}

# 列出所有 VM 并返回数组
# 设置全局数组: VM_IDS, VM_NAMES, VM_STATUSES
list_vms() {
  VM_IDS=()
  VM_NAMES=()
  VM_STATUSES=()
  
  if [[ ! -x "$QM_BIN" ]]; then return; fi
  
  while IFS= read -r line; do
    local vmid name status
    vmid=$(echo "$line" | awk '{print $1}')
    [[ "$vmid" =~ ^[0-9]+$ ]] || continue
    status=$(echo "$line" | awk '{print $3}')
    name=$(echo "$line" | awk '{print $2}')
    VM_IDS+=("$vmid")
    VM_NAMES+=("$name")
    VM_STATUSES+=("$status")
  done < <("$QM_BIN" list 2>/dev/null | tail -n +2)
}

# 列出所有 CT 并返回数组
# 设置全局数组: CT_IDS, CT_NAMES, CT_STATUSES
list_cts() {
  CT_IDS=()
  CT_NAMES=()
  CT_STATUSES=()
  
  if [[ ! -x "$PCT_BIN" ]]; then return; fi
  
  while IFS= read -r line; do
    local ctid name status
    ctid=$(echo "$line" | awk '{print $1}')
    [[ "$ctid" =~ ^[0-9]+$ ]] || continue
    status=$(echo "$line" | awk '{print $2}')
    name=$(echo "$line" | awk '{print $3}')
    CT_IDS+=("$ctid")
    CT_NAMES+=("$name")
    CT_STATUSES+=("$status")
  done < <("$PCT_BIN" list 2>/dev/null | tail -n +2)
}

# 显示 VM/CT 列表并让用户选择
# 返回: 选择的 VMID（通过 SELECTED_VMID 和 SELECTED_TYPE）
select_vmct() {
  local all_ids=() all_names=() all_types=() all_statuses=()
  
  # 收集 VM
  list_vms
  for i in "${!VM_IDS[@]}"; do
    all_ids+=("${VM_IDS[$i]}")
    all_names+=("${VM_NAMES[$i]}")
    all_types+=("vm")
    all_statuses+=("${VM_STATUSES[$i]}")
  done
  
  # 收集 CT
  list_cts
  for i in "${!CT_IDS[@]}"; do
    all_ids+=("${CT_IDS[$i]}")
    all_names+=("${CT_NAMES[$i]}")
    all_types+=("ct")
    all_statuses+=("${CT_STATUSES[$i]}")
  done
  
  if [[ ${#all_ids[@]} -eq 0 ]]; then
    warn "未找到任何 VM 或容器"
    return 1
  fi
  
  echo ""
  echo -e "${BOLD_WHITE}当前 VM/CT 列表:${NC}"
  show_divider
  printf "  ${BOLD_WHITE}%-4s %-6s %-4s %-20s %s${NC}\n" "编号" "VMID" "类型" "名称" "状态"
  show_divider
  
  for i in "${!all_ids[@]}"; do
    local num=$((i+1))
    local type_label status_color
    if [[ "${all_types[$i]}" == "vm" ]]; then
      type_label="VM"
    else
      type_label="CT"
    fi
    if [[ "${all_statuses[$i]}" == "running" ]]; then
      status_color="${BOLD_GREEN}"
    else
      status_color="${YELLOW}"
    fi
    printf "  [${BOLD_CYAN}%2d${NC}] %-6s %-4s %-20s ${status_color}%s${NC}\n" \
      "$num" "${all_ids[$i]}" "$type_label" "${all_names[$i]:0:18}" "${all_statuses[$i]}"
  done
  
  show_divider
  echo ""
  
  local choice
  read -rp "请输入编号 [1-${#all_ids[@]}]: " choice
  
  if ! is_valid_number "$choice" 1 "${#all_ids[@]}"; then
    err "无效的编号"
    return 1
  fi
  
  local idx=$((choice-1))
  SELECTED_VMID="${all_ids[$idx]}"
  SELECTED_TYPE="${all_types[$idx]}"
  SELECTED_NAME="${all_names[$idx]}"
  SELECTED_STATUS="${all_statuses[$idx]}"
  
  return 0
}

# 执行命令并显示等待提示
# 参数: 命令及参数
run_cmd() {
  local rc
  echo -e "${BOLD_CYAN}⏳${NC} 正在执行，请稍候..."
  echo -e "${DIM}→ $*${NC}"
  "$@"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo -e "${BOLD_GREEN}✓${NC} 完成"
  else
    echo -e "${BOLD_RED}✗${NC} 命令执行失败，退出码: $rc"
  fi
  return $rc
}

# =============================================================================
# VM/CT 即时操作函数
# =============================================================================

# 立即重启 VM/CT
action_reboot() {
  show_sub_banner "立即重启 VM/CT"
  
  if ! select_vmct; then return; fi
  
  echo "将重启: ${SELECTED_TYPE^^} ${SELECTED_VMID} (${SELECTED_NAME})"
  if ! confirm_yes "确认重启?"; then
    log "已取消"
    return
  fi
  
  if [[ "$SELECTED_TYPE" == "vm" ]]; then
    run_cmd "$QM_BIN" reboot "$SELECTED_VMID"
  else
    run_cmd "$PCT_BIN" reboot "$SELECTED_VMID"
  fi
  
  success_tip
}

# 立即启动 VM/CT
action_start() {
  show_sub_banner "立即启动 VM/CT"
  
  if ! select_vmct; then return; fi
  
  if [[ "$SELECTED_STATUS" == "running" ]]; then
    warn "${SELECTED_TYPE^^} ${SELECTED_VMID} 已在运行中"
    return
  fi
  
  echo "将启动: ${SELECTED_TYPE^^} ${SELECTED_VMID} (${SELECTED_NAME})"
  if ! confirm_yes "确认启动?"; then
    log "已取消"
    return
  fi
  
  if [[ "$SELECTED_TYPE" == "vm" ]]; then
    run_cmd "$QM_BIN" start "$SELECTED_VMID"
  else
    run_cmd "$PCT_BIN" start "$SELECTED_VMID"
  fi
  
  success_tip
}

# 立即关机 VM/CT（优雅关机）
action_shutdown() {
  show_sub_banner "立即关机 VM/CT"
  
  if ! select_vmct; then return; fi
  
  echo "将关机: ${SELECTED_TYPE^^} ${SELECTED_VMID} (${SELECTED_NAME})"
  if ! confirm_yes "确认关机?"; then
    log "已取消"
    return
  fi
  
  if [[ "$SELECTED_TYPE" == "vm" ]]; then
    run_cmd "$QM_BIN" shutdown "$SELECTED_VMID"
  else
    run_cmd "$PCT_BIN" shutdown "$SELECTED_VMID"
  fi
  
  success_tip
}

# 立即停止 VM/CT（强制断电）
action_stop() {
  show_sub_banner "立即停止 VM/CT (强制)"
  
  if ! select_vmct; then return; fi
  
  echo -e "${BOLD_YELLOW}警告: 强制停止相当于直接断电，可能导致数据丢失！${NC}"
  echo "将停止: ${SELECTED_TYPE^^} ${SELECTED_VMID} (${SELECTED_NAME})"
  if ! confirm_no "确认强制停止?"; then
    log "已取消"
    return
  fi
  
  if [[ "$SELECTED_TYPE" == "vm" ]]; then
    run_cmd "$QM_BIN" stop "$SELECTED_VMID"
  else
    run_cmd "$PCT_BIN" stop "$SELECTED_VMID"
  fi
  
  success_tip
}

# 立即暂停 VM/CT
action_suspend() {
  show_sub_banner "立即暂停 VM/CT"
  
  if ! select_vmct; then return; fi
  
  echo "将暂停: ${SELECTED_TYPE^^} ${SELECTED_VMID} (${SELECTED_NAME})"
  if ! confirm_yes "确认暂停?"; then
    log "已取消"
    return
  fi
  
  if [[ "$SELECTED_TYPE" == "vm" ]]; then
    run_cmd "$QM_BIN" suspend "$SELECTED_VMID"
  else
    run_cmd "$PCT_BIN" suspend "$SELECTED_VMID"
  fi
  
  success_tip
}

# =============================================================================
# VM/CT 快照管理函数
# =============================================================================

# 创建快照
action_snapshot_create() {
  show_sub_banner "创建快照"
  
  if ! select_vmct; then return; fi
  
  local default_name snap desc
  default_name="snap-$($DATE_BIN +%Y%m%d-%H%M%S)"
  
  read -rp "请输入快照名称 [默认: ${default_name}]: " snap
  snap=${snap:-$default_name}
  
  read -rp "请输入快照描述 (可选): " desc
  
  echo ""
  echo "将为 ${SELECTED_TYPE^^} ${SELECTED_VMID} (${SELECTED_NAME}) 创建快照: ${snap}"
  if ! confirm_yes "确认创建?"; then
    log "已取消"
    return
  fi
  
  local rc=0
  if [[ "$SELECTED_TYPE" == "vm" ]]; then
    if [[ -n "$desc" ]]; then
      run_cmd "$QM_BIN" snapshot "$SELECTED_VMID" "$snap" --description "$desc"; rc=$?
    else
      run_cmd "$QM_BIN" snapshot "$SELECTED_VMID" "$snap"; rc=$?
    fi
  else
    if [[ -n "$desc" ]]; then
      run_cmd "$PCT_BIN" snapshot "$SELECTED_VMID" "$snap" --description "$desc"; rc=$?
    else
      run_cmd "$PCT_BIN" snapshot "$SELECTED_VMID" "$snap"; rc=$?
    fi
  fi
  
  [[ $rc -eq 0 ]] && success_tip
}

# 收集快照名称列表
# 参数: $1=类型 $2=VMID
# 设置全局数组: SNAP_NAMES
collect_snapshots() {
  local type="$1" id="$2"
  local out
  SNAP_NAMES=()
  
  if [[ "$type" == "vm" ]]; then
    out="$($QM_BIN listsnapshot "$id" 2>/dev/null || true)"
  else
    out="$($PCT_BIN listsnapshot "$id" 2>/dev/null || true)"
  fi
  
  [[ -z "$out" ]] && return 0
  
  while IFS= read -r line; do
    # 清理树形字符并提取快照名
    local name
    name=$(echo "$line" | sed 's/[│└├─→>*│┃┗┛┏┓┣┫┳┻╋║╚╝╔╗╠╣╦╩╬`|]/ /g' | awk '{print $1}')
    # 过滤无效名称
    if [[ -n "$name" && ! "$name" =~ ^(Name|current|Parent|Date|Description|Size|VMID|Time|RAM|snaptime)$ && ! "$name" =~ ^[0-9]+$ ]]; then
      SNAP_NAMES+=("$name")
    fi
  done <<< "$out"
}

# 恢复快照
action_snapshot_restore() {
  show_sub_banner "恢复快照"
  
  if ! select_vmct; then return; fi
  
  echo "可用快照列表:"
  if [[ "$SELECTED_TYPE" == "vm" ]]; then
    "$QM_BIN" listsnapshot "$SELECTED_VMID" 2>/dev/null || echo "(无快照)"
  else
    "$PCT_BIN" listsnapshot "$SELECTED_VMID" 2>/dev/null || echo "(无快照)"
  fi
  
  collect_snapshots "$SELECTED_TYPE" "$SELECTED_VMID"
  
  if [[ ${#SNAP_NAMES[@]} -eq 0 ]]; then
    warn "该实例没有可用的快照"
    return
  fi
  
  echo ""
  echo -e "${BOLD_WHITE}选择要恢复的快照:${NC}"
  for i in "${!SNAP_NAMES[@]}"; do
    printf "  [${BOLD_CYAN}%2d${NC}] %s\n" "$((i+1))" "${SNAP_NAMES[$i]}"
  done
  echo ""
  
  local choice snap
  read -rp "请输入编号或快照名称: " choice
  
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#SNAP_NAMES[@]} )); then
    snap="${SNAP_NAMES[$((choice-1))]}"
  elif [[ -n "$choice" ]]; then
    snap="$choice"
  else
    err "无效的输入"
    return
  fi
  
  echo ""
  echo -e "${BOLD_YELLOW}警告: 恢复快照会覆盖当前状态！${NC}"
  echo "将恢复 ${SELECTED_TYPE^^} ${SELECTED_VMID} 到快照: ${snap}"
  if ! confirm_no "确认恢复?"; then
    log "已取消"
    return
  fi
  
  local rc=0
  if [[ "$SELECTED_TYPE" == "vm" ]]; then
    run_cmd "$QM_BIN" rollback "$SELECTED_VMID" "$snap"; rc=$?
  else
    run_cmd "$PCT_BIN" rollback "$SELECTED_VMID" "$snap"; rc=$?
  fi
  
  if [[ $rc -eq 0 ]]; then
    if confirm_yes "恢复完成。是否立即启动该实例?"; then
      if [[ "$SELECTED_TYPE" == "vm" ]]; then
        run_cmd "$QM_BIN" start "$SELECTED_VMID"
      else
        run_cmd "$PCT_BIN" start "$SELECTED_VMID"
      fi
    fi
    success_tip
  fi
}

# =============================================================================
# 定时任务函数
# =============================================================================

# 验证时间格式 HH:MM
valid_hhmm() {
  [[ "$1" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]
}

# 转换星期输入为 cron 格式
to_cron_dow() {
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

# 交互式设置定时计划
# 设置全局变量: CRON_MIN CRON_HOUR CRON_DOM CRON_MON CRON_DOW SCHEDULE_DESC
prompt_schedule() {
  local choice time dow dom
  
  while true; do
    echo ""
    echo -e "${BOLD_WHITE}选择定时策略:${NC}"
    echo "  [1] 每天在指定时间"
    echo "  [2] 每周在指定星期+时间"
    echo "  [3] 每月在指定日期+时间"
    echo "  [4] 自定义 cron 表达式"
    echo "  [0] 取消"
    echo ""
    read -rp "请选择 [0-4]: " choice
    
    case "$choice" in
      1)
        while true; do
          read -rp "请输入时间 (HH:MM, 24小时制): " time
          if valid_hhmm "$time"; then break; else err "时间格式无效，请重试"; fi
        done
        CRON_MIN="${time##*:}"
        CRON_HOUR="${time%%:*}"
        CRON_DOM="*"; CRON_MON="*"; CRON_DOW="*"
        SCHEDULE_DESC="每天 ${CRON_HOUR}:${CRON_MIN}"
        return 0
        ;;
      2)
        while true; do
          read -rp "请输入星期 (0-7, 0/7=周日, 或 mon/周一 等): " dow
          local d="$(to_cron_dow "$dow")"
          if [[ "$d" != "-1" ]]; then dow="$d"; break; else err "星期无效，请重试"; fi
        done
        while true; do
          read -rp "请输入时间 (HH:MM, 24小时制): " time
          if valid_hhmm "$time"; then break; else err "时间格式无效，请重试"; fi
        done
        CRON_MIN="${time##*:}"
        CRON_HOUR="${time%%:*}"
        CRON_DOM="*"; CRON_MON="*"; CRON_DOW="$dow"
        SCHEDULE_DESC="每周${dow}的 ${CRON_HOUR}:${CRON_MIN}"
        return 0
        ;;
      3)
        while true; do
          read -rp "请输入日期 (1-31): " dom
          if [[ "$dom" =~ ^([1-9]|[12][0-9]|3[01])$ ]]; then break; else err "日期无效，请重试"; fi
        done
        while true; do
          read -rp "请输入时间 (HH:MM, 24小时制): " time
          if valid_hhmm "$time"; then break; else err "时间格式无效，请重试"; fi
        done
        CRON_MIN="${time##*:}"
        CRON_HOUR="${time%%:*}"
        CRON_DOM="$dom"; CRON_MON="*"; CRON_DOW="*"
        SCHEDULE_DESC="每月${CRON_DOM}日 ${CRON_HOUR}:${CRON_MIN}"
        return 0
        ;;
      4)
        echo "请输入完整 cron 表达式（5段: 分 时 日 月 周），例如: 0 3 * * *"
        read -rp "> " cron_expr
        local count
        count=$(echo "$cron_expr" | awk '{print NF}')
        if [[ "$count" -eq 5 ]]; then
          CRON_MIN=$(echo "$cron_expr" | awk '{print $1}')
          CRON_HOUR=$(echo "$cron_expr" | awk '{print $2}')
          CRON_DOM=$(echo "$cron_expr" | awk '{print $3}')
          CRON_MON=$(echo "$cron_expr" | awk '{print $4}')
          CRON_DOW=$(echo "$cron_expr" | awk '{print $5}')
          SCHEDULE_DESC="自定义: $cron_expr"
          return 0
        else
          err "格式无效，需要5段表达式"
        fi
        ;;
      0)
        return 1
        ;;
      *)
        err "无效选项"
        ;;
    esac
  done
}

# 写入重启定时任务
write_cron_restart() {
  local id="$1" type="$2" name="$3"
  local cron_file="$CRON_DIR/${CRON_PREFIX}${id}"
  local cmd
  
  if [[ "$type" == "vm" ]]; then
    cmd="$QM_BIN reboot $id"
  else
    cmd="$PCT_BIN reboot $id"
  fi
  
  mkdir -p "$CRON_DIR"
  
  {
    echo "# Managed by PVETools - 定时重启任务"
    echo "# TYPE=$type VMID=$id NAME=${name:-'-'} CREATED=$($DATE_BIN +%F_%T)"
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    echo "${CRON_MIN} ${CRON_HOUR} ${CRON_DOM} ${CRON_MON:-*} ${CRON_DOW} root $cmd"
  } > "$cron_file"
  
  chmod 0644 "$cron_file"
  reload_cron_service
}

# 设置定时重启
action_schedule_restart() {
  show_sub_banner "设置定时重启"
  
  if ! select_vmct; then return; fi
  
  echo "为 ${SELECTED_TYPE^^} ${SELECTED_VMID} (${SELECTED_NAME}) 设置定时重启"
  
  if ! prompt_schedule; then
    log "已取消"
    return
  fi
  
  write_cron_restart "$SELECTED_VMID" "$SELECTED_TYPE" "$SELECTED_NAME"
  
  log "定时重启已设置: $SCHEDULE_DESC"
  log "配置文件: $CRON_DIR/${CRON_PREFIX}${SELECTED_VMID}"
  success_tip
}

# 列出已设置的定时任务
action_list_schedules() {
  show_sub_banner "查看定时任务"
  
  shopt -s nullglob
  local files=("$CRON_DIR/${CRON_PREFIX}"* "$CRON_DIR/${SNAP_CRON_PREFIX}"* "$CRON_DIR/${RB_CRON_PREFIX}"*)
  
  if [[ ${#files[@]} -eq 0 ]]; then
    warn "未找到已设置的定时任务"
    return
  fi
  
  echo ""
  printf "  ${BOLD_WHITE}%-8s %-12s %-4s %-20s %s${NC}\n" "VMID" "任务类型" "类型" "定时表达式" "命令"
  show_divider
  
  for f in "${files[@]}"; do
    local id type cronline action
    local fname="${f##*/}"
    
    # 提取 VMID
    id="${fname#${CRON_PREFIX}}"; id="${id#${SNAP_CRON_PREFIX}}"; id="${id#${RB_CRON_PREFIX}}"
    
    # 判断任务类型
    if [[ "$fname" == "${CRON_PREFIX}"* ]]; then
      action="重启"
    elif [[ "$fname" == "${SNAP_CRON_PREFIX}"* ]]; then
      action="快照"
    else
      action="回滚"
    fi
    
    # 提取类型
    type=$(grep -oE "TYPE=[^ ]+" "$f" 2>/dev/null | cut -d= -f2 || echo "-")
    
    # 提取 cron 表达式
    cronline=$(awk '/^[^#]/ && NF>=6 {print $1,$2,$3,$4,$5; exit}' "$f" 2>/dev/null || echo "-")
    
    printf "  %-8s %-12s %-4s %-20s\n" "$id" "$action" "${type^^}" "$cronline"
  done
  
  echo ""
}

# 删除定时任务
action_delete_schedule() {
  show_sub_banner "删除定时任务"
  
  action_list_schedules
  
  local vmid
  read -rp "请输入要删除任务的 VMID: " vmid
  
  if [[ -z "$vmid" || ! "$vmid" =~ ^[0-9]+$ ]]; then
    err "无效的 VMID"
    return
  fi
  
  local targets=("$CRON_DIR/${CRON_PREFIX}${vmid}" "$CRON_DIR/${SNAP_CRON_PREFIX}${vmid}" "$CRON_DIR/${RB_CRON_PREFIX}${vmid}")
  local found=()
  
  for t in "${targets[@]}"; do
    [[ -f "$t" ]] && found+=("$t")
  done
  
  if [[ ${#found[@]} -eq 0 ]]; then
    warn "未找到 VMID ${vmid} 的任何定时任务"
    return
  fi
  
  echo "将删除以下任务文件:"
  for f in "${found[@]}"; do
    echo "  - $f"
  done
  echo ""
  
  if confirm_yes "确认删除?"; then
    rm -f -- "${found[@]}"
    reload_cron_service
    log "已删除 ${#found[@]} 个任务"
    success_tip
  else
    log "已取消"
  fi
}

# =============================================================================
# Docker 配置模块
# =============================================================================

# 列出 LXC 容器并让用户选择
select_ct_only() {
  list_cts
  
  if [[ ${#CT_IDS[@]} -eq 0 ]]; then
    warn "未找到任何 LXC 容器"
    return 1
  fi
  
  echo ""
  echo -e "${BOLD_WHITE}LXC 容器列表:${NC}"
  show_divider
  printf "  ${BOLD_WHITE}%-4s %-6s %-20s %s${NC}\n" "编号" "CTID" "名称" "状态"
  show_divider
  
  for i in "${!CT_IDS[@]}"; do
    local num=$((i+1))
    local status_color
    if [[ "${CT_STATUSES[$i]}" == "running" ]]; then
      status_color="${BOLD_GREEN}"
    else
      status_color="${YELLOW}"
    fi
    printf "  [${BOLD_CYAN}%2d${NC}] %-6s %-20s ${status_color}%s${NC}\n" \
      "$num" "${CT_IDS[$i]}" "${CT_NAMES[$i]:0:18}" "${CT_STATUSES[$i]}"
  done
  
  show_divider
  echo ""
  
  local choice
  read -rp "请输入编号 [1-${#CT_IDS[@]}]: " choice
  
  if ! is_valid_number "$choice" 1 "${#CT_IDS[@]}"; then
    err "无效的编号"
    return 1
  fi
  
  local idx=$((choice-1))
  SELECTED_CTID="${CT_IDS[$idx]}"
  SELECTED_CT_NAME="${CT_NAMES[$idx]}"
  SELECTED_CT_STATUS="${CT_STATUSES[$idx]}"
  
  return 0
}

# 配置容器支持 Docker（宿主机端）
action_docker_configure_host() {
  show_sub_banner "配置容器支持 Docker (宿主机端)"
  
  if [[ "$ENV_TYPE" != "pve_host" ]]; then
    err "此功能只能在 PVE 宿主机上运行"
    return
  fi
  
  if ! select_ct_only; then return; fi
  
  local config_file="/etc/pve/lxc/${SELECTED_CTID}.conf"
  
  if [[ ! -f "$config_file" ]]; then
    err "配置文件不存在: $config_file"
    return
  fi
  
  # 检查当前是否为特权容器
  local current_unprivileged
  current_unprivileged=$(grep "^unprivileged:" "$config_file" | awk '{print $2}' || echo "")
  local current_type="特权"
  [[ "$current_unprivileged" == "1" ]] && current_type="非特权"
  
  echo ""
  echo -e "${BOLD_WHITE}容器权限配置:${NC}"
  echo "  [1] 特权容器 (推荐，Docker 完全兼容)"
  echo "  [2] 非特权容器 (更安全，但可能有限制)"
  echo ""
  echo -e "当前容器类型: ${BOLD_CYAN}${current_type}${NC}"
  echo ""
  
  local privilege_choice
  read -rp "请选择 [1-2, 默认 1]: " privilege_choice
  privilege_choice="${privilege_choice:-1}"
  
  local use_privileged=true
  [[ "$privilege_choice" == "2" ]] && use_privileged=false
  
  # 检查容器状态
  if [[ "$SELECTED_CT_STATUS" == "running" ]]; then
    warn "容器 ${SELECTED_CTID} 正在运行"
    if confirm_yes "是否停止容器以进行配置?"; then
      step "停止容器..."
      pct stop "$SELECTED_CTID"
      local wait_count=0
      while pct status "$SELECTED_CTID" 2>/dev/null | grep -q "running" && [[ $wait_count -lt 30 ]]; do
        sleep 1
        ((wait_count++))
      done
      log "容器已停止"
    else
      err "容器必须停止才能修改配置"
      return
    fi
  fi
  
  # 备份配置
  local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$config_file" "$backup_file"
  log "配置已备份到: $backup_file"
  
  # 添加配置
  step "添加 Docker 所需配置..."
  
  # 设置特权/非特权
  if [[ "$use_privileged" == true ]]; then
    if grep -q "^unprivileged:" "$config_file"; then
      sed -i "s|^unprivileged:.*|unprivileged: 0|" "$config_file"
    else
      echo "unprivileged: 0" >> "$config_file"
    fi
    log "已设置: unprivileged: 0"
  fi
  
  # 设置 features
  local current_features new_features=""
  current_features=$(grep "^features:" "$config_file" | sed 's/^features: *//' || echo "")
  
  if [[ -z "$current_features" ]]; then
    new_features="nesting=1,keyctl=1"
  else
    [[ ! "$current_features" =~ nesting=1 ]] && new_features="${current_features},nesting=1" || new_features="$current_features"
    [[ ! "$new_features" =~ keyctl=1 ]] && new_features="${new_features},keyctl=1"
  fi
  
  if grep -q "^features:" "$config_file"; then
    sed -i "s|^features:.*|features: $new_features|" "$config_file"
  else
    echo "features: $new_features" >> "$config_file"
  fi
  log "已设置: features: $new_features"
  
  # 添加 LXC 配置
  grep -q "^lxc.apparmor.profile:" "$config_file" || echo "lxc.apparmor.profile: unconfined" >> "$config_file"
  
  if [[ "$CGROUP_VERSION" == "v2" ]]; then
    grep -q "^lxc.cgroup2.devices.allow:" "$config_file" || echo "lxc.cgroup2.devices.allow: a" >> "$config_file"
  else
    grep -q "^lxc.cgroup.devices.allow:" "$config_file" || echo "lxc.cgroup.devices.allow: a" >> "$config_file"
  fi
  
  grep -q "^lxc.cap.drop:" "$config_file" || echo "lxc.cap.drop:" >> "$config_file"
  grep -q "^lxc.mount.auto:" "$config_file" || echo "lxc.mount.auto: proc:rw sys:rw" >> "$config_file"
  
  log "Docker 配置已添加"
  
  # 显示配置预览
  echo ""
  echo -e "${BOLD_WHITE}当前容器配置预览:${NC}"
  show_divider
  grep -E "^(unprivileged|features|lxc\.):" "$config_file" | head -20
  show_divider
  
  echo ""
  if confirm_yes "是否现在启动容器?"; then
    step "启动容器..."
    if pct start "$SELECTED_CTID"; then
      sleep 3
      log "容器已启动"
    else
      err "容器启动失败，请检查配置"
    fi
  fi
  
  success_tip
  echo ""
  echo -e "${BOLD_YELLOW}下一步:${NC}"
  echo "  1. 进入容器: pct enter $SELECTED_CTID"
  echo "  2. 在容器内安装 Docker"
}

# 在容器内安装 Docker
action_docker_install_container() {
  show_sub_banner "安装/配置 Docker (容器内)"
  
  if [[ "$ENV_TYPE" != "lxc" ]]; then
    warn "此功能需要在 LXC 容器内运行"
    echo "请先进入容器: pct enter <CTID>"
    return
  fi
  
  echo ""
  echo -e "${BOLD_WHITE}请选择操作:${NC}"
  echo "  [1] 安装 Docker"
  echo "  [2] 仅配置已安装的 Docker"
  echo "  [0] 返回"
  echo ""
  
  local choice
  read -rp "请选择 [0-2]: " choice
  
  case "$choice" in
    1)
      step "检测操作系统..."
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
          ubuntu|debian)
            docker_install_debian
            ;;
          centos|rhel|rocky|almalinux)
            docker_install_rhel
            ;;
          *)
            err "不支持的操作系统: $ID"
            return
            ;;
        esac
      else
        err "无法检测操作系统"
        return
      fi
      docker_configure_daemon
      ;;
    2)
      docker_configure_daemon
      ;;
    0)
      return
      ;;
    *)
      err "无效选项"
      ;;
  esac
}

# Debian/Ubuntu 安装 Docker
docker_install_debian() {
  step "在 Debian/Ubuntu 上安装 Docker..."
  
  apt-get update -qq || { err "apt-get update 失败"; return 1; }
  
  apt-get install -y ca-certificates curl gnupg lsb-release || { err "安装依赖失败"; return 1; }
  
  install -m 0755 -d /etc/apt/keyrings
  
  local gpg_file="/etc/apt/keyrings/docker.gpg"
  [[ -f "$gpg_file" ]] && rm -f "$gpg_file"
  
  local docker_dist_id="$ID"
  [[ "$ID" == "linuxmint" || "$ID" == "pop" ]] && docker_dist_id="ubuntu"
  
  curl -fsSL "https://download.docker.com/linux/${docker_dist_id}/gpg" | gpg --dearmor -o "$gpg_file" || { err "添加 GPG key 失败"; return 1; }
  chmod a+r "$gpg_file"
  
  local version_codename
  version_codename=$(lsb_release -cs 2>/dev/null || grep "VERSION_CODENAME" /etc/os-release | cut -d= -f2 | tr -d '"')
  
  echo "deb [arch=$(dpkg --print-architecture) signed-by=$gpg_file] https://download.docker.com/linux/${docker_dist_id} ${version_codename} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { err "Docker 安装失败"; return 1; }
  
  log "Docker 安装完成"
}

# RHEL/CentOS 安装 Docker
docker_install_rhel() {
  step "在 RHEL/CentOS 上安装 Docker..."
  
  local pkg_manager="yum"
  command -v dnf &>/dev/null && pkg_manager="dnf"
  
  $pkg_manager install -y yum-utils || { err "安装 yum-utils 失败"; return 1; }
  
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || { err "添加仓库失败"; return 1; }
  
  $pkg_manager install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { err "Docker 安装失败"; return 1; }
  
  log "Docker 安装完成"
}

# 配置 Docker daemon
docker_configure_daemon() {
  step "配置 Docker daemon..."
  
  mkdir -p /etc/docker
  
  local daemon_json="/etc/docker/daemon.json"
  [[ -f "$daemon_json" ]] && cp "$daemon_json" "${daemon_json}.backup.$(date +%Y%m%d_%H%M%S)"
  
  cat > "$daemon_json" <<'EOF'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "default-cgroupns-mode": "host"
}
EOF
  
  log "Docker daemon 配置完成"
  
  if command -v systemctl &>/dev/null; then
    systemctl daemon-reload
    systemctl enable docker 2>/dev/null || true
    systemctl restart docker
    log "Docker 服务已启动"
  fi
  
  # 验证
  sleep 3
  if docker --version &>/dev/null && docker info &>/dev/null; then
    log "Docker 运行正常"
    docker --version
    
    echo ""
    if confirm_yes "是否运行 Docker 测试 (hello-world)?"; then
      docker run --rm hello-world && log "Docker 测试成功!"
    fi
  else
    err "Docker 启动异常，请检查日志"
  fi
  
  success_tip
}

# =============================================================================
# 存储管理模块
# =============================================================================

# 获取分区路径（支持各种磁盘类型）
get_partition_path() {
  local dev="$1" part_num="${2:-1}"
  local name="${dev##*/}"
  if [[ "$name" =~ ^(nvme[0-9]+n[0-9]+|mmcblk[0-9]+|loop[0-9]+|nbd[0-9]+)$ ]]; then
    echo "${dev}p${part_num}"
  else
    echo "${dev}${part_num}"
  fi
}

# 获取设备标识符
get_device_id() {
  local dev="$1"
  local name="${dev##*/}"
  case "$name" in
    sd[a-z])       echo "${name#sd}" ;;
    sd[a-z][a-z])  echo "${name#sd}" ;;
    vd[a-z])       echo "vd${name#vd}" ;;
    nvme*)         echo "$name" ;;
    mmcblk*)       echo "$name" ;;
    *)             echo "$name" ;;
  esac
}

# 获取磁盘类型描述
get_disk_type() {
  local dev="$1"
  local name="${dev##*/}"
  local tran=$(lsblk -dn -o TRAN "$dev" 2>/dev/null | tr -d ' ' || echo "")
  case "$name" in
    nvme*)    echo "NVMe" ;;
    mmcblk*)  echo "MMC" ;;
    vd*)      echo "VirtIO" ;;
    sd*)
      case "$tran" in
        sata)   echo "SATA" ;;
        sas)    echo "SAS" ;;
        usb)    echo "USB" ;;
        *)      echo "SCSI" ;;
      esac ;;
    *)        echo "未知" ;;
  esac
}

# 检查磁盘状态
check_disk_status() {
  local dev="$1" name="${dev##*/}"
  if findmnt -rn -o SOURCE / 2>/dev/null | grep -qE "${dev}|${name}"; then echo "系统盘"; return 0; fi
  if findmnt -rn -o SOURCE /boot 2>/dev/null | grep -qE "${dev}|${name}"; then echo "系统盘"; return 0; fi
  if findmnt -rn -o SOURCE /boot/efi 2>/dev/null | grep -qE "${dev}|${name}"; then echo "系统盘"; return 0; fi
  local pv_info=$(pvs --noheadings -o pv_name,vg_name 2>/dev/null || true)
  if echo "$pv_info" | grep -E "${dev}|${name}" 2>/dev/null | grep -qE "pve|root|system"; then echo "系统盘"; return 0; fi
  if findmnt -rn -o SOURCE 2>/dev/null | grep -qE "${dev}|${name}"; then echo "使用中"; return 0; fi
  if echo "$pv_info" | grep -qE "${dev}|${name}"; then echo "使用中"; return 0; fi
  echo "可用"
}

# 添加磁盘为 LVM-Thin 存储
action_add_disk() {
  show_sub_banner "添加磁盘为 LVM-Thin 存储"
  step "扫描可用磁盘..."
  local -a DISKS
  mapfile -t DISKS < <(lsblk -dn -o NAME,TYPE,RO 2>/dev/null | awk '$2=="disk" && $3==0 {print $1}')
  if [[ ${#DISKS[@]} -eq 0 ]]; then err "未检测到可用磁盘"; return; fi
  
  declare -A DISK_STATUS
  local safe_count=0
  for i in "${!DISKS[@]}"; do
    local dev="/dev/${DISKS[$i]}"
    DISK_STATUS[$i]=$(check_disk_status "$dev")
    [[ "${DISK_STATUS[$i]}" == "可用" ]] && ((safe_count++)) || true
  done
  
  echo ""
  echo -e "${BOLD_CYAN}====================== 可用磁盘列表 ======================${NC}"
  printf "  ${BOLD_WHITE}%-4s %-10s %-8s %-8s %-14s %s${NC}\n" "编号" "设备" "容量" "类型" "型号" "状态"
  show_divider
  for i in "${!DISKS[@]}"; do
    local dev="/dev/${DISKS[$i]}"
    local size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null | tr -d ' ')
    local model=$(lsblk -dn -o MODEL "$dev" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-12)
    local dtype=$(get_disk_type "$dev")
    local status="${DISK_STATUS[$i]}"
    local num_color status_text
    case "$status" in
      "系统盘") num_color="${BOLD_RED}"; status_text="${BOLD_RED}[禁止]${NC}" ;;
      "使用中") num_color="${BOLD_YELLOW}"; status_text="${BOLD_YELLOW}[使用中]${NC}" ;;
      *) num_color="${BOLD_GREEN}"; status_text="${BOLD_GREEN}[可用]${NC}" ;;
    esac
    printf "  ${num_color}[%2d]${NC} %-10s ${BOLD_CYAN}%-8s${NC} %-8s %-14s %b\n" \
      "$((i+1))" "${DISKS[$i]}" "$size" "$dtype" "${model:--}" "$status_text"
  done
  echo ""
  
  local idx
  read -rp "请输入磁盘编号 [1-${#DISKS[@]}]: " idx
  if ! is_valid_number "$idx" 1 "${#DISKS[@]}"; then err "无效的编号"; return; fi
  
  local selected_idx=$((idx-1))
  local selected_status="${DISK_STATUS[$selected_idx]}"
  local dev="/dev/${DISKS[$selected_idx]}"
  
  # 系统盘保护
  if [[ "$selected_status" == "系统盘" ]]; then
    echo -e "\n${BOLD_RED}⛔ 严重警告: ${dev} 是系统盘！继续操作将导致系统崩溃！${NC}"
    echo "如果确实知道自己在做什么，请输入: DESTROY-SYSTEM"
    local confirm_code
    read -rp "请输入确认码（或按回车取消）: " confirm_code
    if [[ "$confirm_code" != "DESTROY-SYSTEM" ]]; then log "操作已取消"; return; fi
    warn "用户确认销毁系统盘！"
  fi
  
  local devid=$(get_device_id "$dev")
  local vg="vg_$devid" tp="thin_$devid" stid="lvmthin_$devid"
  local part=$(get_partition_path "$dev" 1)
  local size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null | tr -d ' ')
  
  echo ""
  echo -e "${BOLD_PURPLE}操作摘要:${NC}"
  echo "  目标: ${dev} (${size})"
  echo "  VG: ${vg}, ThinPool: ${tp}, 存储ID: ${stid}"
  echo ""
  
  local has_data="no"
  wipefs -n "$dev" 2>/dev/null | grep -qE '.' && has_data="yes"
  lsblk -no NAME "$dev" 2>/dev/null | tail -n +2 | grep -q . && has_data="yes"
  
  [[ "$has_data" == "yes" ]] && echo -e "${BOLD_RED}⚠️  磁盘有数据，将被清除！${NC}"
  
  if ! confirm_no "确认执行?"; then log "已取消"; return; fi
  
  log "开始执行..."
  
  if [[ "$has_data" == "yes" ]]; then
    step "清理磁盘..."
    for mp in $(findmnt -rn -o TARGET,SOURCE 2>/dev/null | grep "${dev##*/}" | awk '{print $1}' || true); do
      umount -lf "$mp" 2>/dev/null || true
    done
    for vg_name in $(pvs --noheadings -o vg_name "${dev}"* 2>/dev/null | tr -d ' ' | sort -u | grep -v '^$' || true); do
      lvchange -an "$vg_name" 2>/dev/null || true
      vgchange -an "$vg_name" 2>/dev/null || true
      yes | vgremove -ff "$vg_name" 2>/dev/null || true
    done
    for pv in $(pvs --noheadings -o pv_name 2>/dev/null | tr -d ' ' | grep "^${dev}" || true); do
      pvremove -ff "$pv" 2>/dev/null || true
    done
    wipefs -af "$dev" 2>/dev/null || true
    sgdisk --zap-all "$dev" >/dev/null 2>&1 || true
    dd if=/dev/zero of="$dev" bs=1M count=10 2>/dev/null || true
    partprobe "$dev" 2>/dev/null || true
    sleep 2
  fi
  
  step "创建分区..."
  parted -s "$dev" mklabel gpt
  parted -s "$dev" mkpart primary 0% 100%
  partprobe "$dev" 2>/dev/null || true
  sleep 2
  for i in {1..30}; do [[ -b "$part" ]] && break; sleep 1; done
  [[ ! -b "$part" ]] && { err "分区未出现"; return; }
  
  step "创建 LVM-Thin..."
  wipefs -af "$part" 2>/dev/null || true
  pvcreate -ff -y "$part" || { err "PV 创建失败"; return; }
  vgs "$vg" &>/dev/null && { vgchange -an "$vg" 2>/dev/null || true; vgremove -ff "$vg" 2>/dev/null || true; }
  vgcreate "$vg" "$part" || { err "VG 创建失败"; return; }
  lvcreate -l 100%FREE --type thin-pool -n "$tp" "$vg" || { err "ThinPool 创建失败"; return; }
  
  step "注册 PVE 存储..."
  if ! pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$stid"; then
    pvesm add lvmthin "$stid" --vgname "$vg" --thinpool "$tp" --content images,rootdir || { err "注册失败"; return; }
  fi
  
  echo ""
  echo -e "${BOLD_GREEN}✓ 操作成功！存储ID: ${stid}${NC}"
  success_tip
}

# =============================================================================
# 硬盘直通功能
# =============================================================================

# 获取磁盘的 by-id 路径
# 参数: $1=设备名（如 sdb）
# 返回: by-id 路径或空
get_disk_by_id() {
  local dev_name="$1"
  local by_id=""
  
  # 查找 /dev/disk/by-id/ 下的链接
  for link in /dev/disk/by-id/*; do
    [[ ! -L "$link" ]] && continue
    local target=$(readlink -f "$link" 2>/dev/null)
    if [[ "$target" == "/dev/${dev_name}" ]]; then
      # 优先选择 ata-/scsi-/nvme- 开头的（排除 wwn-/lvm- 等）
      local name="${link##*/}"
      if [[ "$name" =~ ^(ata-|scsi-|nvme-|usb-) ]]; then
        by_id="$link"
        break
      elif [[ -z "$by_id" ]]; then
        by_id="$link"
      fi
    fi
  done
  
  echo "$by_id"
}

# 检查磁盘是否已被 VM 直通
# 参数: $1=设备名或 by-id 路径
# 返回: "vmid:接口" 或空
check_disk_passthrough() {
  local disk="$1"
  local dev_name="${disk##*/}"
  
  # 如果是 /dev/sdX 格式，获取 by-id
  if [[ "$disk" =~ ^/dev/[a-z] ]]; then
    dev_name="${disk##*/}"
  fi
  
  # 扫描所有 VM 配置
  for conf in /etc/pve/qemu-server/*.conf; do
    [[ ! -f "$conf" ]] && continue
    local vmid="${conf##*/}"
    vmid="${vmid%.conf}"
    
    # 查找包含此磁盘的配置行
    while IFS= read -r line; do
      if [[ "$line" =~ ^(scsi|sata|virtio|ide)([0-9]+):.*(/dev/disk/by-id/|/dev/${dev_name}) ]]; then
        local iface="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        echo "${vmid}:${iface}"
        return 0
      fi
    done < "$conf"
  done
  
  echo ""
}

# 获取 VM 下一个可用的磁盘槽位
# 参数: $1=VMID $2=接口类型(scsi/sata/virtio)
# 返回: 下一个可用槽位号
get_next_disk_slot() {
  local vmid="$1" iface="$2"
  local max_slot=0
  local used_slots=()
  
  # 读取 VM 配置，找出已用的槽位
  local conf="/etc/pve/qemu-server/${vmid}.conf"
  [[ ! -f "$conf" ]] && { echo "0"; return; }
  
  while IFS= read -r line; do
    if [[ "$line" =~ ^${iface}([0-9]+): ]]; then
      used_slots+=("${BASH_REMATCH[1]}")
    fi
  done < "$conf"
  
  # 找到下一个未使用的槽位
  for ((i=0; i<30; i++)); do
    local found=false
    for slot in "${used_slots[@]}"; do
      [[ "$slot" == "$i" ]] && { found=true; break; }
    done
    if [[ "$found" == false ]]; then
      echo "$i"
      return
    fi
  done
  
  echo "-1"
}

# 列出仅 QEMU VM（排除 LXC）
select_vm_only() {
  list_vms
  
  if [[ ${#VM_IDS[@]} -eq 0 ]]; then
    warn "未找到任何 QEMU 虚拟机"
    return 1
  fi
  
  echo ""
  echo -e "${BOLD_WHITE}QEMU 虚拟机列表:${NC}"
  show_divider
  printf "  ${BOLD_WHITE}%-4s %-6s %-20s %s${NC}\n" "编号" "VMID" "名称" "状态"
  show_divider
  
  for i in "${!VM_IDS[@]}"; do
    local num=$((i+1))
    local status_color
    if [[ "${VM_STATUSES[$i]}" == "running" ]]; then
      status_color="${BOLD_GREEN}"
    else
      status_color="${YELLOW}"
    fi
    printf "  [${BOLD_CYAN}%2d${NC}] %-6s %-20s ${status_color}%s${NC}\n" \
      "$num" "${VM_IDS[$i]}" "${VM_NAMES[$i]:0:18}" "${VM_STATUSES[$i]}"
  done
  
  show_divider
  echo ""
  
  local choice
  read -rp "请输入编号 [1-${#VM_IDS[@]}]: " choice
  
  if ! is_valid_number "$choice" 1 "${#VM_IDS[@]}"; then
    err "无效的编号"
    return 1
  fi
  
  local idx=$((choice-1))
  SELECTED_VMID="${VM_IDS[$idx]}"
  SELECTED_VM_NAME="${VM_NAMES[$idx]}"
  SELECTED_VM_STATUS="${VM_STATUSES[$idx]}"
  
  return 0
}

# 硬盘直通到 VM
action_disk_passthrough() {
  show_sub_banner "硬盘直通到 VM"
  
  if [[ "$ENV_TYPE" != "pve_host" ]]; then
    err "此功能只能在 PVE 宿主机上运行"
    return
  fi
  
  # 选择目标 VM
  echo -e "${BOLD_WHITE}第一步: 选择目标虚拟机${NC}"
  if ! select_vm_only; then return; fi
  
  log "已选择: VM ${SELECTED_VMID} (${SELECTED_VM_NAME})"
  
  # 扫描可直通的磁盘
  step "扫描可直通的磁盘..."
  local -a DISKS
  mapfile -t DISKS < <(lsblk -dn -o NAME,TYPE,RO 2>/dev/null | awk '$2=="disk" && $3==0 {print $1}')
  
  if [[ ${#DISKS[@]} -eq 0 ]]; then
    err "未检测到可用磁盘"
    return
  fi
  
  # 检测每个磁盘状态
  declare -A DISK_STATUS DISK_BYID DISK_PT_INFO
  local available_count=0
  
  for i in "${!DISKS[@]}"; do
    local dev="/dev/${DISKS[$i]}"
    local status=$(check_disk_status "$dev")
    local by_id=$(get_disk_by_id "${DISKS[$i]}")
    local pt_info=$(check_disk_passthrough "${DISKS[$i]}")
    
    DISK_STATUS[$i]="$status"
    DISK_BYID[$i]="$by_id"
    DISK_PT_INFO[$i]="$pt_info"
    
    # 如果已被直通，更新状态
    if [[ -n "$pt_info" ]]; then
      DISK_STATUS[$i]="已直通"
    fi
    
    [[ "${DISK_STATUS[$i]}" == "可用" ]] && ((available_count++)) || true
  done
  
  echo ""
  echo -e "${BOLD_WHITE}第二步: 选择要直通的磁盘${NC}"
  echo -e "${BOLD_CYAN}====================== 磁盘列表 ======================${NC}"
  printf "  ${BOLD_WHITE}%-4s %-8s %-8s %-8s %-12s %s${NC}\n" "编号" "设备" "容量" "类型" "状态" "by-id"
  show_divider
  
  for i in "${!DISKS[@]}"; do
    local dev="/dev/${DISKS[$i]}"
    local size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null | tr -d ' ')
    local dtype=$(get_disk_type "$dev")
    local status="${DISK_STATUS[$i]}"
    local by_id="${DISK_BYID[$i]}"
    local by_id_short=""
    
    # 截取 by-id 显示
    if [[ -n "$by_id" ]]; then
      by_id_short="${by_id##*/}"
      [[ ${#by_id_short} -gt 30 ]] && by_id_short="${by_id_short:0:27}..."
    else
      by_id_short="-"
    fi
    
    local num_color status_text
    case "$status" in
      "系统盘") num_color="${BOLD_RED}"; status_text="${BOLD_RED}[禁止]${NC}" ;;
      "使用中") num_color="${BOLD_YELLOW}"; status_text="${BOLD_YELLOW}[使用中]${NC}" ;;
      "已直通") num_color="${BOLD_PURPLE}"; status_text="${BOLD_PURPLE}[已直通]${NC}" ;;
      *) num_color="${BOLD_GREEN}"; status_text="${BOLD_GREEN}[可用]${NC}" ;;
    esac
    
    printf "  ${num_color}[%2d]${NC} %-8s ${BOLD_CYAN}%-8s${NC} %-8s %b %-30s\n" \
      "$((i+1))" "${DISKS[$i]}" "$size" "$dtype" "$status_text" "$by_id_short"
    
    # 如果已直通，显示绑定信息
    if [[ -n "${DISK_PT_INFO[$i]}" ]]; then
      local pt_vmid="${DISK_PT_INFO[$i]%%:*}"
      local pt_iface="${DISK_PT_INFO[$i]##*:}"
      echo -e "       ${DIM}└─ 已绑定到 VM ${pt_vmid} (${pt_iface})${NC}"
    fi
  done
  
  echo ""
  
  local idx
  read -rp "请输入磁盘编号 [1-${#DISKS[@]}]: " idx
  
  if ! is_valid_number "$idx" 1 "${#DISKS[@]}"; then
    err "无效的编号"
    return
  fi
  
  local selected_idx=$((idx-1))
  local selected_status="${DISK_STATUS[$selected_idx]}"
  local selected_dev="/dev/${DISKS[$selected_idx]}"
  local selected_byid="${DISK_BYID[$selected_idx]}"
  
  # 系统盘保护
  if [[ "$selected_status" == "系统盘" ]]; then
    echo -e "\n${BOLD_RED}⛔ 严重警告: ${selected_dev} 是系统盘！直通将导致系统无法访问该磁盘！${NC}"
    echo "如果确实知道自己在做什么，请输入: PASSTHROUGH-SYSTEM"
    local confirm_code
    read -rp "请输入确认码（或按回车取消）: " confirm_code
    if [[ "$confirm_code" != "PASSTHROUGH-SYSTEM" ]]; then
      log "操作已取消"
      return
    fi
    warn "用户确认直通系统盘！"
  fi
  
  # 已直通警告
  if [[ "$selected_status" == "已直通" ]]; then
    local pt_vmid="${DISK_PT_INFO[$selected_idx]%%:*}"
    warn "此磁盘已被 VM ${pt_vmid} 直通使用"
    if ! confirm_no "确定要重复直通吗？这可能导致数据损坏！"; then
      log "操作已取消"
      return
    fi
  fi
  
  # 检查 by-id
  if [[ -z "$selected_byid" ]]; then
    warn "未找到此磁盘的 by-id 路径，将使用 ${selected_dev}"
    echo "注意: 使用 /dev/sdX 路径在重启后可能发生变化"
    if ! confirm_yes "是否继续?"; then
      return
    fi
    selected_byid="$selected_dev"
  fi
  
  # 选择接口类型
  echo ""
  echo -e "${BOLD_WHITE}第三步: 选择接口类型${NC}"
  echo "  [1] SCSI (推荐 - 性能好，支持热插拔)"
  echo "  [2] SATA (兼容性好)"
  echo "  [3] VirtIO (最高性能，需要驱动)"
  echo ""
  
  local iface_choice
  read -rp "请选择 [1-3, 默认 1]: " iface_choice
  iface_choice="${iface_choice:-1}"
  
  local iface_type
  case "$iface_choice" in
    1) iface_type="scsi" ;;
    2) iface_type="sata" ;;
    3) iface_type="virtio" ;;
    *) iface_type="scsi" ;;
  esac
  
  # 获取下一个可用槽位
  local slot=$(get_next_disk_slot "$SELECTED_VMID" "$iface_type")
  if [[ "$slot" == "-1" ]]; then
    err "没有可用的 ${iface_type} 槽位"
    return
  fi
  
  local disk_config="${iface_type}${slot}"
  
  # 显示操作摘要
  echo ""
  echo -e "${BOLD_PURPLE}操作摘要:${NC}"
  echo "  目标 VM:    ${SELECTED_VMID} (${SELECTED_VM_NAME})"
  echo "  磁盘:       ${selected_dev}"
  echo "  by-id:      ${selected_byid}"
  echo "  接口:       ${disk_config}"
  echo ""
  
  if [[ "$SELECTED_VM_STATUS" == "running" ]]; then
    warn "VM 正在运行，热添加可能需要重启才能生效"
  fi
  
  if ! confirm_yes "确认直通?"; then
    log "操作已取消"
    return
  fi
  
  # 执行直通
  step "执行硬盘直通..."
  local qm_cmd="$QM_BIN set $SELECTED_VMID --${disk_config} ${selected_byid}"
  debug "执行: $qm_cmd"
  
  if $QM_BIN set "$SELECTED_VMID" --"${disk_config}" "${selected_byid}"; then
    echo ""
    echo -e "${BOLD_GREEN}✓ 硬盘直通成功！${NC}"
    echo "  VM: ${SELECTED_VMID}"
    echo "  磁盘: ${disk_config} = ${selected_byid}"
    
    if [[ "$SELECTED_VM_STATUS" == "running" ]]; then
      echo ""
      echo -e "${BOLD_YELLOW}提示: VM 正在运行，可能需要重启才能识别新磁盘${NC}"
    fi
    
    success_tip
  else
    err "硬盘直通失败"
  fi
}

# 列出已直通的磁盘
action_list_passthrough() {
  show_sub_banner "查看已直通磁盘"
  
  echo ""
  printf "  ${BOLD_WHITE}%-6s %-15s %-10s %s${NC}\n" "VMID" "VM名称" "接口" "磁盘路径"
  show_divider
  
  local found=0
  
  for conf in /etc/pve/qemu-server/*.conf; do
    [[ ! -f "$conf" ]] && continue
    local vmid="${conf##*/}"
    vmid="${vmid%.conf}"
    local vm_name=$(get_name "$vmid")
    
    while IFS= read -r line; do
      if [[ "$line" =~ ^(scsi|sata|virtio|ide)([0-9]+):.*(/dev/disk/by-id/[^,]+|/dev/sd[a-z]+) ]]; then
        local iface="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        local disk_path="${BASH_REMATCH[3]}"
        printf "  %-6s %-15s ${BOLD_CYAN}%-10s${NC} %s\n" "$vmid" "${vm_name:0:13}" "$iface" "$disk_path"
        ((found++))
      fi
    done < "$conf"
  done
  
  echo ""
  
  if [[ $found -eq 0 ]]; then
    warn "未找到任何直通磁盘配置"
  else
    log "共找到 ${found} 个直通配置"
  fi
}

# 移除磁盘直通
action_remove_passthrough() {
  show_sub_banner "移除磁盘直通"
  
  # 收集所有直通配置
  local -a PT_VMIDS PT_NAMES PT_IFACES PT_PATHS
  local idx=0
  
  for conf in /etc/pve/qemu-server/*.conf; do
    [[ ! -f "$conf" ]] && continue
    local vmid="${conf##*/}"
    vmid="${vmid%.conf}"
    local vm_name=$(get_name "$vmid")
    
    while IFS= read -r line; do
      if [[ "$line" =~ ^(scsi|sata|virtio|ide)([0-9]+):.*(/dev/disk/by-id/[^,]+|/dev/sd[a-z]+) ]]; then
        PT_VMIDS+=("$vmid")
        PT_NAMES+=("$vm_name")
        PT_IFACES+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]}")
        PT_PATHS+=("${BASH_REMATCH[3]}")
        ((idx++))
      fi
    done < "$conf"
  done
  
  if [[ ${#PT_VMIDS[@]} -eq 0 ]]; then
    warn "未找到任何直通磁盘配置"
    return
  fi
  
  echo ""
  printf "  ${BOLD_WHITE}%-4s %-6s %-12s %-10s %s${NC}\n" "编号" "VMID" "VM名称" "接口" "磁盘路径"
  show_divider
  
  for i in "${!PT_VMIDS[@]}"; do
    printf "  [${BOLD_CYAN}%2d${NC}] %-6s %-12s ${BOLD_YELLOW}%-10s${NC} %s\n" \
      "$((i+1))" "${PT_VMIDS[$i]}" "${PT_NAMES[$i]:0:10}" "${PT_IFACES[$i]}" "${PT_PATHS[$i]}"
  done
  
  echo ""
  
  local choice
  read -rp "请输入要移除的编号 [1-${#PT_VMIDS[@]}]: " choice
  
  if ! is_valid_number "$choice" 1 "${#PT_VMIDS[@]}"; then
    err "无效的编号"
    return
  fi
  
  local sel_idx=$((choice-1))
  local sel_vmid="${PT_VMIDS[$sel_idx]}"
  local sel_iface="${PT_IFACES[$sel_idx]}"
  local sel_path="${PT_PATHS[$sel_idx]}"
  
  echo ""
  echo -e "${BOLD_PURPLE}将移除:${NC}"
  echo "  VM: ${sel_vmid} (${PT_NAMES[$sel_idx]})"
  echo "  接口: ${sel_iface}"
  echo "  磁盘: ${sel_path}"
  echo ""
  
  # 检查 VM 状态
  local vm_status=$(get_status "$sel_vmid" "vm")
  if [[ "$vm_status" == "running" ]]; then
    warn "VM 正在运行，移除后需要重启才能完全释放磁盘"
  fi
  
  if ! confirm_no "确认移除?"; then
    log "操作已取消"
    return
  fi
  
  step "移除直通配置..."
  if $QM_BIN set "$sel_vmid" --delete "${sel_iface}"; then
    echo ""
    echo -e "${BOLD_GREEN}✓ 直通配置已移除${NC}"
    
    if [[ "$vm_status" == "running" ]]; then
      echo -e "${BOLD_YELLOW}提示: 请重启 VM ${sel_vmid} 以完全释放磁盘${NC}"
    fi
    
    success_tip
  else
    err "移除失败"
  fi
}

# =============================================================================
# 系统工具
# =============================================================================

# 安装快捷命令
action_install_shortcut() {
  show_sub_banner "安装快捷命令"
  local dst="/usr/local/sbin/pvetools"
  mkdir -p "/usr/local/sbin"
  if command -v install &>/dev/null; then
    install -m 0755 "$SCRIPT_ABS" "$dst"
  else
    cp -f "$SCRIPT_ABS" "$dst" 2>/dev/null || ln -sf "$SCRIPT_ABS" "$dst"
    chmod 0755 "$dst" 2>/dev/null || true
  fi
  log "已安装: $dst"
  echo "现在可以直接运行: pvetools"
  success_tip
}

# 显示系统信息
action_show_info() {
  show_sub_banner "系统信息"
  echo -e "${BOLD_WHITE}PVE 环境:${NC}"
  echo "  PVE 版本:    ${PVE_VERSION:-unknown}"
  echo "  cgroup 版本: ${CGROUP_VERSION:-unknown}"
  echo "  运行环境:    ${ENV_TYPE:-unknown}"
  echo ""
  echo -e "${BOLD_WHITE}脚本信息:${NC}"
  echo "  版本:        v${VERSION}"
  echo "  路径:        ${SCRIPT_ABS}"
  echo "  日志文件:    ${LOG_FILE}"
  echo ""
  if [[ "$ENV_TYPE" == "pve_host" ]]; then
    echo -e "${BOLD_WHITE}VM 数量:${NC}"
    list_vms; echo "  虚拟机: ${#VM_IDS[@]} 个"
    list_cts; echo "  容器:   ${#CT_IDS[@]} 个"
  fi
}

# Linux 一键换源
# 来源: SuperManito/LinuxMirrors
# 项目地址: https://github.com/SuperManito/LinuxMirrors
# 感谢 SuperManito 提供的优秀换源脚本
action_change_mirrors() {
  show_sub_banner "Linux 一键换源"
  
  echo -e "${BOLD_WHITE}脚本来源:${NC}"
  echo "  项目: SuperManito/LinuxMirrors"
  echo "  地址: https://github.com/SuperManito/LinuxMirrors"
  echo ""
  echo -e "${BOLD_WHITE}请选择线路:${NC}"
  echo "  [1] 国内服务器 (Gitee 镜像，推荐国内使用)"
  echo "  [2] 海外服务器 (GitHub 原版)"
  echo ""
  echo "  [0] 返回"
  echo ""
  
  local choice
  read -rp "请选择 [0-2]: " choice
  
  case "$choice" in
    1)
      log "使用国内 Gitee 镜像..."
      echo ""
      echo -e "${BOLD_CYAN}正在执行换源脚本，请按提示操作...${NC}"
      echo ""
      bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh)
      ;;
    2)
      log "使用海外 GitHub 源..."
      echo ""
      echo -e "${BOLD_CYAN}正在执行换源脚本，请按提示操作...${NC}"
      echo ""
      bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh)
      ;;
    0)
      return
      ;;
    *)
      err "无效选项"
      return
      ;;
  esac
  
  echo ""
  success_tip
}

# 科技lion工具箱
# 来源: kejilion
# 项目地址: https://github.com/kejilion/sh
# 感谢 kejilion 提供的综合运维工具箱
action_kejilion_toolbox() {
  show_sub_banner "科技lion工具箱"
  
  echo -e "${BOLD_WHITE}脚本来源:${NC}"
  echo "  作者: 科技lion (kejilion)"
  echo "  地址: https://github.com/kejilion/sh"
  echo ""
  echo -e "${BOLD_YELLOW}说明:${NC} 这是一个功能丰富的 Linux 运维工具箱"
  echo ""
  
  if ! confirm_yes "是否运行科技lion工具箱?"; then
    log "已取消"
    return
  fi
  
  echo ""
  echo -e "${BOLD_CYAN}正在启动工具箱，请按提示操作...${NC}"
  echo ""
  bash <(curl -sL kejilion.sh)
  
  echo ""
  success_tip
}

# S-UI 面板安装
# 来源: alireza0/s-ui
# 项目地址: https://github.com/alireza0/s-ui
# Sing-box 代理面板
action_sui_install() {
  show_sub_banner "S-UI 面板安装"
  
  echo -e "${BOLD_WHITE}脚本来源:${NC}"
  echo "  项目: S-UI (Sing-box 面板)"
  echo "  作者: alireza0"
  echo "  地址: https://github.com/alireza0/s-ui"
  echo ""
  
  if ! confirm_yes "是否安装 S-UI 面板?"; then
    log "已取消"
    return
  fi
  
  echo ""
  echo -e "${BOLD_CYAN}正在执行安装脚本，请按提示操作...${NC}"
  echo ""
  bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
  
  echo ""
  success_tip
}

# 显示帮助信息
show_help() {
  cat << EOF

${BOLD_CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}
${BOLD_CYAN}║${NC}              ${BOLD_WHITE}PVETools v${VERSION}${NC} - Proxmox VE 统一管理工具
${BOLD_CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}

${BOLD_WHITE}用法:${NC}
  pvetools              运行交互式菜单
  pvetools install      安装快捷命令到 /usr/local/sbin/pvetools
  pvetools -h|--help    显示此帮助

${BOLD_WHITE}功能模块:${NC}
  • VM/CT 管理    - 即时操作、快照管理、定时任务
  • Docker 配置   - LXC 容器 Docker 支持配置
  • 存储管理      - LVM-Thin 存储、硬盘直通

${BOLD_WHITE}兼容版本:${NC} PVE 7.x / 8.x / 9.x

${BOLD_WHITE}作者:${NC} 孤独制作
${BOLD_WHITE}电报群:${NC} https://t.me/+RZMe7fnvvUg1OWJl

EOF
}

# =============================================================================
# 菜单系统
# =============================================================================

# VM/CT 管理子菜单
menu_vmct() {
  while true; do
    show_sub_banner "VM/CT 管理"
    echo -e "${BOLD_WHITE}即时操作:${NC}"
    echo "  [1] 启动 VM/CT"
    echo "  [2] 重启 VM/CT"
    echo "  [3] 关机 VM/CT (优雅)"
    echo "  [4] 停止 VM/CT (强制)"
    echo "  [5] 暂停 VM/CT"
    echo ""
    echo -e "${BOLD_WHITE}快照管理:${NC}"
    echo "  [6] 创建快照"
    echo "  [7] 恢复快照"
    echo ""
    echo -e "${BOLD_WHITE}定时任务:${NC}"
    echo "  [8] 设置定时重启"
    echo "  [9] 查看定时任务"
    echo " [10] 删除定时任务"
    echo ""
    echo "  [0] 返回主菜单"
    echo ""
    
    local choice
    read -rp "请选择 [0-10]: " choice
    
    case "$choice" in
      1) action_start; pause ;;
      2) action_reboot; pause ;;
      3) action_shutdown; pause ;;
      4) action_stop; pause ;;
      5) action_suspend; pause ;;
      6) action_snapshot_create; pause ;;
      7) action_snapshot_restore; pause ;;
      8) action_schedule_restart; pause ;;
      9) action_list_schedules; pause ;;
      10) action_delete_schedule; pause ;;
      0) return ;;
      *) err "无效选项" ;;
    esac
  done
}

# Docker 配置子菜单
menu_docker() {
  while true; do
    show_sub_banner "Docker 配置"
    echo "  [1] 配置容器支持 Docker (宿主机端)"
    echo "  [2] 安装/配置 Docker (容器内)"
    echo ""
    echo "  [0] 返回主菜单"
    echo ""
    
    local choice
    read -rp "请选择 [0-2]: " choice
    
    case "$choice" in
      1) action_docker_configure_host; pause ;;
      2) action_docker_install_container; pause ;;
      0) return ;;
      *) err "无效选项" ;;
    esac
  done
}

# 存储管理子菜单
menu_storage() {
  while true; do
    show_sub_banner "存储管理"
    echo -e "${BOLD_WHITE}LVM 存储:${NC}"
    echo "  [1] 添加磁盘为 LVM-Thin 存储"
    echo ""
    echo -e "${BOLD_WHITE}硬盘直通:${NC}"
    echo "  [2] 硬盘直通到 VM"
    echo "  [3] 查看已直通磁盘"
    echo "  [4] 移除磁盘直通"
    echo ""
    echo "  [0] 返回主菜单"
    echo ""
    
    local choice
    read -rp "请选择 [0-4]: " choice
    
    case "$choice" in
      1) action_add_disk; pause ;;
      2) action_disk_passthrough; pause ;;
      3) action_list_passthrough; pause ;;
      4) action_remove_passthrough; pause ;;
      0) return ;;
      *) err "无效选项" ;;
    esac
  done
}

# 系统工具子菜单
menu_system() {
  while true; do
    show_sub_banner "系统工具"
    echo -e "${BOLD_WHITE}本地工具:${NC}"
    echo "  [1] 安装快捷命令 pvetools"
    echo "  [2] 查看系统信息"
    echo ""
    echo -e "${BOLD_WHITE}第三方工具:${NC}"
    echo "  [3] Linux 一键换源 (SuperManito)"
    echo "  [4] 科技lion工具箱 (kejilion)"
    echo "  [5] S-UI 面板安装 (alireza0)"
    echo ""
    echo "  [0] 返回主菜单"
    echo ""
    
    local choice
    read -rp "请选择 [0-5]: " choice
    
    case "$choice" in
      1) action_install_shortcut; pause ;;
      2) action_show_info; pause ;;
      3) action_change_mirrors; pause ;;
      4) action_kejilion_toolbox; pause ;;
      5) action_sui_install; pause ;;
      0) return ;;
      *) err "无效选项" ;;
    esac
  done
}

# 主菜单
menu_main() {
  while true; do
    show_banner
    
    if [[ "$PVE_VERSION" != "unknown" ]]; then
      echo -e "  PVE 版本: ${BOLD_CYAN}${PVE_VERSION}.x${NC}  |  环境: ${BOLD_CYAN}${ENV_TYPE}${NC}"
      echo ""
    fi
    
    echo -e "${BOLD_WHITE}请选择功能模块:${NC}"
    echo ""
    echo "  [1] VM/CT 管理      - 即时操作、快照、定时任务"
    echo "  [2] Docker 配置     - LXC 容器 Docker 支持"
    echo "  [3] 存储管理        - LVM-Thin、硬盘直通"
    echo "  [4] 系统工具        - 快捷命令、换源、系统信息"
    echo "  [5] 帮助"
    echo ""
    echo "  [0] 退出"
    echo ""
    
    local choice
    read -rp "请选择 [0-5]: " choice
    
    case "$choice" in
      1) menu_vmct ;;
      2) menu_docker ;;
      3) menu_storage ;;
      4) menu_system ;;
      5) show_help; pause ;;
      0) echo "再见!"; exit 0 ;;
      *) err "无效选项" ;;
    esac
  done
}

# =============================================================================
# 入口点
# =============================================================================

# 处理命令行参数
case "${1:-}" in
  -h|--help|help)
    show_help
    exit 0
    ;;
  install)
    require_root
    action_install_shortcut
    exit 0
    ;;
esac

# 检查权限
require_root

# 初始化环境
init_environment

# 启动主菜单
menu_main
