# PVETOOLS工具介绍

## 国内使用
```bash
# 下载并运行安装脚本
bash <(curl -sSL https://gitee.com/Poker-Face/pvetools/raw/master/pvetools.sh)
```
## 国外
```bash
# 下载并运行安装脚本
wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh
chmod +x pvetools.sh
./pvetools.sh
```

**概览**
- `pvetools.sh` 是一个在 Proxmox VE 主机上运行的交互式管理脚本，支持为 QEMU 虚拟机(`qm`)和 LXC 容器(`pct`)创建定时任务与执行常见操作。
- 主要功能：定时重启、定时创建快照（含保留策略）、定时回滚快照、立即操作（重启/暂停/停止/关机/创建或恢复快照）。
- 广告与支持：孤独制作 ｜ 电报群 https://t.me/+RZMe7fnvvUg1OWJl

**运行环境**
- 仅在 PVE 主机上使用
- 以 `root` 身份执行。
- 脚本内部使用绝对路径调用系统命令，确保 cron 环境可用。

**安装与快捷命令**
- 菜单内提供“安装/更新快捷命令”：会将脚本安装到 `/usr/local/sbin/pvetools`。
- 安装后可直接运行：`pvetools`

**核心特性**
- 定时重启
  - 每天/每周/每月/自定义 cron 表达式
  - 支持延迟偏移（分钟），避免同一时刻并发重启
- 定时快照（含清理策略）
  - 设定快照前缀、保留数量 N、最大保留天数 D
  - 清理策略为“交集”：仅保留同时满足“最近 N 个”且“未超过 D 天”的快照
  - 将 D=0 可实现“仅按数量保留”；将 N 设很大近似“仅按天数保留”
- 定时回滚快照
  - 回滚到最新自动快照（按前缀）或指定快照（支持编号选择）
- 立即操作
  - 重启/暂停/停止/关机/创建快照/恢复快照（可选回滚后立即启动）
- 编号选择快照
  - 自动解析 `qm listsnapshot` / `pct listsnapshot` 的输出，编号列出可用快照，输入编号或名称即可
- 友好等待提示
  - 对耗时操作显示“正在等待 PVE 执行命令”，完成后统一成功提示

**菜单结构（简要）**
- 1 新增/更新 单个 VM/容器 的重启策略
- 2 批量设置 多个 VM/容器 使用同一策略
- 3 设置 定时创建快照（含保留策略）
- 4 设置 定时回滚快照（支持编号选择）
- 5 列出已设置的定时任务（重启/快照/回滚）
- 6 删除某个 VMID 的所有定时任务
- 7–12 立即操作（重启/暂停/停止/关机/创建/恢复）
- 13 安装/更新 快捷命令 `pvetools`
- 14 退出

**定时任务说明**
- 定时任务写入到 `/etc/cron.d`：
  - 重启：`/etc/cron.d/pve-auto-restart-<VMID>`
  - 定时快照：`/etc/cron.d/pve-auto-snap-<VMID>`
  - 定时回滚：`/etc/cron.d/pve-auto-rollback-<VMID>`
- 每条任务带有元数据头：`ACTION=... TYPE=vm|ct VMID=...` 便于识别。
- 脚本会尝试 `systemctl reload cron`/`crond` 重载定时任务（失败不影响 cron 周期性加载）。

**快照清理策略（重要）**
- 仅清理由脚本创建且匹配前缀的快照，避免误删手工快照。
- 保留规则为“交集”：
  - 同时满足“在最近 N 个内”且“未超过 D 天”才保留；其他将被清理。
  - 示例：每天创建一次，N=3、D=30，最终保留最近 3 个。

**命令行子命令（供 cron 调用）**
- `--cron snap-create <vm|ct> <id> <prefix> <keep_count> <max_days>`
- `--cron snap-rollback <vm|ct> <id> latest <prefix>`
- `--cron snap-rollback <vm|ct> <id> name <snapshot_name>`

**使用提示**
- 有些操作（重启/关机/启动/快照/回滚）需要等待 PVE 执行完毕；脚本会显示等待提示与完成提示。
- 若移动脚本位置，请重新设置定时任务（任务中包含脚本的绝对路径）。
- 请确保底层存储支持快照，否则创建/回滚会返回 PVE 错误。

**卸载快捷命令**
- 删除 `/usr/local/sbin/pvetools` 即可（对定时任务无影响）。

**故障排查**
- 未找到 `qm`/`pct`：确认在 PVE 主机上执行、并以 `root` 运行。
- 定时不生效：检查 `/etc/cron.d/*` 文件权限为 `0644`，并确认 cron 服务正在运行。
- 快照解析列表为空：不同版本输出格式略有差异，可直接手动输入快照名称。

**版权与支持**
- 本脚本不添加版权头，欢迎在内部环境使用与二次定制。
- 反馈与交流：电报群 https://t.me/+RZMe7fnvvUg1OWJl

