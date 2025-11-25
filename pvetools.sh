# PVETools - Proxmox VE 虚拟机/容器管理工具

> 一款功能强大的 PVE 定时任务管理脚本，支持虚拟机和容器的定时重启、快照管理等功能。

**作者**：孤独制作  
**电报群**：https://t.me/+RZMe7fnvvUg1OWJl  
**兼容版本**：PVE 7.x / 8.x / 9.x

---

## 📋 功能概览

### 定时任务管理
- ✅ 设置单个/批量 VM/容器 定时重启
- ✅ 设置定时创建快照（含保留策略）
- ✅ 设置定时回滚快照
- ✅ 查看/删除已配置的定时任务

### 立即操作
- ✅ 立即重启指定 VM/容器
- ✅ 立即暂停（挂起）指定 VM/容器
- ✅ 立即停止（强制断电）指定 VM/容器
- ✅ 立即关机（优雅关机）指定 VM/容器
- ✅ 立即创建快照
- ✅ 立即恢复快照

### 其他功能
- ✅ 自动检测 PVE 版本
- ✅ 自动识别 VM (QEMU) 和 LXC 容器
- ✅ 安装快捷命令 `pvetools`

---

## 🚀 快速开始

### 安装

```bash
# 方式1: 直接下载运行
wget -O pvetools.sh https://your-url/pvetools.sh
chmod +x pvetools.sh
./pvetools.sh

# 方式2: 安装为系统命令（运行脚本后选择菜单 13）
./pvetools.sh
# 选择 13) 安装/更新 快捷命令 pvetools
# 之后可直接使用 pvetools 命令
```

### 运行要求

- **操作系统**：Proxmox VE 7.x / 8.x / 9.x
- **权限**：需要 root 权限运行
- **依赖**：无额外依赖，使用系统自带工具

---

## 📖 使用说明

### 主菜单

运行脚本后将显示交互式主菜单：

```
==== PVE 定时重启管理 ====
孤独制作 | 电报群: https://t.me/+RZMe7fnvvUg1OWJl
当前 PVE 版本: 8.x (兼容 PVE 7/8/9)
提示: 某些操作(重启/关机/启动/快照/回滚)可能需要等待 PVE 返回，请耐心等待。
  1) 新增/更新 单个 VM/容器 的重启策略
  2) 批量设置 多个 VM/容器 使用同一策略
  3) 设置 定时创建快照 (含保留策略)
  4) 设置 定时回滚快照
  5) 列出已设置的定时任务
  6) 删除某个 VMID 的定时任务
  7) 立即重启 指定 VM/容器
  8) 立即暂停 指定 VM/容器
  9) 立即停止 指定 VM/容器
 10) 立即关机 指定 VM/容器
 11) 创建快照 指定 VM/容器
 12) 恢复快照 指定 VM/容器
 13) 安装/更新 快捷命令 pvetools
 14) 退出
```

### 定时策略选项

设置定时任务时，支持以下策略：

| 策略 | 说明 | 示例 |
|------|------|------|
| 每天 | 每天在指定时间执行 | 每天 03:00 |
| 每周 | 每周指定星期+时间执行 | 每周一 03:00 |
| 每月 | 每月指定日期+时间执行 | 每月1日 03:00 |
| 自定义 | 使用标准 cron 表达式 | `0 3 * * *` |

**星期输入格式**：
- 数字：0-7（0和7都表示周日）
- 英文：mon, tue, wed, thu, fri, sat, sun
- 中文：周一, 周二, ..., 周日 或 一, 二, ..., 日

### 快照保留策略

定时创建快照时，支持设置保留策略：

- **保留数量 (N)**：最多保留最近 N 个快照
- **保留天数 (D)**：只保留 D 天内的快照
- **组合规则**：同时满足以上两个条件才会被保留

示例：
- N=7, D=30 → 保留最近7个且30天内的快照
- N=100, D=7 → 近似只按7天保留
- N=7, D=0 → 只按数量保留最近7个

---

## 📁 文件说明

### 配置文件位置

| 文件类型 | 路径 |
|----------|------|
| 定时重启任务 | `/etc/cron.d/pve-auto-restart-<VMID>` |
| 定时快照任务 | `/etc/cron.d/pve-auto-snap-<VMID>` |
| 定时回滚任务 | `/etc/cron.d/pve-auto-rollback-<VMID>` |
| 快照追踪文件 | `/var/lib/pve-auto/snaps-<type>-<VMID>.list` |

### Cron 文件格式示例

```bash
# Managed by pve-restart-scheduler
# ACTION=reboot TYPE=vm VMID=100 NAME=myvm CREATED=2024-01-15_10:30:00
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * * root /bin/sleep 0m && /usr/sbin/qm reboot 100
```

---

## ⚙️ 命令行参数

### 帮助信息

```bash
./pvetools.sh -h
./pvetools.sh --help
```

### Cron 子命令（内部使用）

```bash
# 定时创建快照（由 cron 自动调用）
./pvetools.sh --cron snap-create <type> <id> <prefix> <keep_count> <max_days>

# 定时回滚快照（由 cron 自动调用）
./pvetools.sh --cron snap-rollback <type> <id> latest <prefix>
./pvetools.sh --cron snap-rollback <type> <id> name <snapname>
```

---

## 🔧 故障排除

### 常见问题

**Q: 提示"未找到 qm 或 pct 命令"**  
A: 请确保在 Proxmox VE 主机上运行此脚本

**Q: 提示"请以 root 身份运行此脚本"**  
A: 使用 `sudo ./pvetools.sh` 或切换到 root 用户

**Q: 定时任务没有执行**  
A: 检查 cron 服务状态：
```bash
systemctl status cron
# 或
systemctl status crond
```

**Q: 快照创建失败**  
A: 确认虚拟机磁盘支持快照（如 ZFS、LVM-thin、Ceph RBD 等）

### 查看日志

```bash
# 查看 cron 日志
journalctl -u cron -f

# 查看系统日志中的 pvetools 相关信息
grep pvetools /var/log/syslog
```

---

## 📝 更新日志

### v1.0.0
- 初始版本
- 支持 PVE 7.x / 8.x / 9.x
- 定时重启、快照创建、快照回滚功能
- 交互式菜单操作

---

## 📜 许可证

本脚本仅供学习和个人使用，请勿用于商业用途。

---

## 🤝 反馈与支持

如有问题或建议，欢迎加入电报群交流：  
**https://t.me/+RZMe7fnvvUg1OWJl**

---

**⭐ 如果觉得有用，欢迎分享给更多 PVE 用户！**

