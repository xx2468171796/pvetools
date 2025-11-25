# PVETOOLS工具介绍

## 国内使用
```bash
# 下载并运行安装脚本
wget https://gitee.com/Poker-Face/pvetools/raw/master/pvetools.sh
chmod +x pvetools.sh
./pvetools.sh
```
## 国外
```bash
# 下载并运行安装脚本
wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh
chmod +x pvetools.sh
./pvetools.sh
```
# 🖥️ PVETools - Proxmox VE 综合管理工具

<div align="center">

![Version](https://img.shields.io/badge/版本-v3.2-blue)
![PVE](https://img.shields.io/badge/PVE-7.x%20%2F%208.x%20%2F%209.x-green)
![License](https://img.shields.io/badge/许可-MIT-orange)
![Platform](https://img.shields.io/badge/平台-Linux-lightgrey)

**一站式 Proxmox VE 运维管理脚本**

集成 VM/CT 管理、Docker 配置、存储管理、硬盘直通等功能

[快速开始](#-快速开始) •
[功能介绍](#-功能模块) •
[使用指南](USAGE.md) •
[常见问题](#-常见问题)

</div>

---

## 📢 项目信息

**作者**：孤独制作  
**电报群**：[点击加入](https://t.me/+RZMe7fnvvUg1OWJl)  
**兼容版本**：PVE 7.x / 8.x / 9.x

---

## ✨ 功能模块

### 🔹 VM/CT 管理
| 功能 | 说明 |
|------|------|
| 即时操作 | 启动、重启、关机、停止、挂起 VM/CT |
| 快照管理 | 创建快照、恢复快照 |
| 定时任务 | 定时重启、定时创建快照、定时回滚快照 |
| 批量操作 | 支持多个 VMID 批量操作 |

### 🔹 Docker 配置
| 功能 | 说明 |
|------|------|
| 宿主机配置 | 配置 PVE 宿主机支持 LXC 运行 Docker |
| 容器配置 | 配置 LXC 容器的 Docker 运行环境 |
| Docker 安装 | 在容器内自动安装 Docker |

### 🔹 存储管理
| 功能 | 说明 |
|------|------|
| LVM-Thin 存储 | 将物理磁盘初始化为 LVM-Thin 存储 |
| 硬盘直通 | 将物理磁盘直通到 QEMU 虚拟机 |
| 直通管理 | 查看、删除已配置的磁盘直通 |

### 🔹 系统工具
| 功能 | 说明 |
|------|------|
| 快捷命令 | 安装 `pvetools` 系统命令 |
| 系统信息 | 查看 PVE 版本、系统信息 |
| 第三方工具 | Linux 换源、科技lion工具箱、S-UI 面板 |

---

## 🚀 快速开始

### 一键运行（推荐）

```bash
# 下载并运行
wget -qO pvetools.sh https://raw.githubusercontent.com/YOUR_USERNAME/PVEt/main/pvetools.sh && bash pvetools.sh
```

### 本地安装

```bash
# 1. 下载脚本
wget -O pvetools.sh https://raw.githubusercontent.com/YOUR_USERNAME/PVEt/main/pvetools.sh

# 2. 添加执行权限
chmod +x pvetools.sh

# 3. 运行脚本
./pvetools.sh

# 4. (可选) 安装快捷命令 - 选择菜单 [4] -> [1]
# 之后可直接使用 pvetools 命令
```

### 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Proxmox VE 7.x / 8.x / 9.x |
| 权限 | root 用户 |
| 依赖 | 基本无依赖，LVM 功能需要 `lvm2` 包 |

---

## 📖 主菜单预览

```
╔══════════════════════════════════════════════════════════════╗
║                  PVETools v3.2                               ║
║                Proxmox VE 综合管理工具                        ║
╚══════════════════════════════════════════════════════════════╝
  孤独制作 | https://t.me/+RZMe7fnvvUg1OWJl

  PVE 版本: 8.x  |  环境: 宿主机

请选择功能模块:

  [1] VM/CT 管理      - 即时操作、快照、定时任务
  [2] Docker 配置     - LXC 容器 Docker 支持
  [3] 存储管理        - LVM-Thin、硬盘直通
  [4] 系统工具        - 快捷命令、换源、系统信息
  [5] 帮助

  [0] 退出
```

---

## 🔧 命令行用法

```bash
# 交互式菜单
pvetools

# 直接安装快捷命令
pvetools install

# 显示帮助信息
pvetools -h
pvetools --help

# 内部 cron 调用（定时任务使用）
pvetools --cron snap-create <type> <vmid> <prefix> <keep> <days>
pvetools --cron snap-rollback <type> <vmid> latest <prefix>
```

---

## 📁 文件位置

| 类型 | 路径 |
|------|------|
| 脚本位置 | `/usr/local/bin/pvetools` (安装后) |
| 日志文件 | `/var/log/pvetools.log` |
| 定时重启 | `/etc/cron.d/pve-auto-restart-<VMID>` |
| 定时快照 | `/etc/cron.d/pve-auto-snap-<VMID>` |
| 定时回滚 | `/etc/cron.d/pve-auto-rollback-<VMID>` |
| 快照记录 | `/var/lib/pve-auto/snaps-<type>-<VMID>.list` |

---

## ❓ 常见问题

<details>
<summary><b>Q: 提示"请以 root 身份运行此脚本"</b></summary>

A: 本脚本需要 root 权限运行，请使用以下方式：
```bash
sudo ./pvetools.sh
# 或切换到 root 用户
su -
./pvetools.sh
```
</details>

<details>
<summary><b>Q: 定时任务没有执行</b></summary>

A: 检查 cron 服务状态：
```bash
systemctl status cron
# 查看 cron 日志
journalctl -u cron -f
```
</details>

<details>
<summary><b>Q: 快照创建失败</b></summary>

A: 确认虚拟机磁盘支持快照功能：
- ✅ 支持：ZFS、LVM-thin、Ceph RBD、本地目录 (qcow2)
- ❌ 不支持：LVM、本地目录 (raw)
</details>

<details>
<summary><b>Q: Docker 配置后容器无法启动</b></summary>

A: 确保完成以下步骤：
1. 配置宿主机（需重启 PVE）
2. 配置目标容器
3. 在容器内安装 Docker
</details>

<details>
<summary><b>Q: 硬盘直通后 VM 无法识别磁盘</b></summary>

A: 检查以下几点：
1. 确认 VM 已关机再进行直通配置
2. 检查磁盘是否被其他 VM 占用
3. 尝试更换接口类型（SCSI/SATA/VirtIO）
</details>

---

## 🙏 致谢

本工具集成了以下优秀的第三方工具：

| 工具 | 作者 | 链接 |
|------|------|------|
| Linux 一键换源 | SuperManito | [GitHub](https://github.com/SuperManito/LinuxMirrors) |
| 科技lion工具箱 | kejilion | [GitHub](https://github.com/kejilion/sh) |
| S-UI 面板 | alireza0 | [GitHub](https://github.com/alireza0/s-ui) |

---

## 📝 更新日志

### v3.2
- 新增：系统工具集成第三方工具
  - Linux 一键换源 (SuperManito)
  - 科技lion工具箱 (kejilion)
  - S-UI 面板安装 (alireza0)

### v3.1
- 新增：硬盘直通功能
  - 支持将物理磁盘直通到 QEMU VM
  - 支持 SCSI/SATA/VirtIO 接口类型
  - 查看和删除直通配置

### v3.0
- 重构：三合一统一脚本
  - 整合 VM/CT 管理、Docker 配置、存储管理
  - 全新交互式菜单界面
  - 统一的 Y/N 确认操作
  - 美化输出格式

### v2.0
- Docker LXC 配置功能
- LVM-Thin 存储管理

### v1.0
- 初始版本
- 定时重启、快照管理

---

## 📜 许可证

本项目采用 MIT 许可证，详见 [LICENSE](LICENSE) 文件。

---

## 🤝 反馈与支持

如有问题或建议，欢迎：

- 📮 提交 [Issue](https://github.com/YOUR_USERNAME/PVEt/issues)
- 💬 加入 [电报群](https://t.me/+RZMe7fnvvUg1OWJl) 交流

---

<div align="center">

**⭐ 如果觉得有用，欢迎 Star 支持！**

Made with ❤️ for PVE Users

</div>
