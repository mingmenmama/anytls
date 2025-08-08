---

# AnyTLS-Go 一键安装脚本指南

**最后更新:** 2025-08-08

**支持系统:** Ubuntu 20.04+、Debian 11+、CentOS/RHEL、Alpine Linux  
**功能:** 自动检测 IP、智能端口分配、防止端口冲突、TLS 证书集成、多系统兼容

---

## 🌟 主要功能

- **全面的系统支持**
  - Ubuntu/Debian 系列
  - CentOS/RHEL/Rocky/Alma 系列
  - Alpine Linux (适合容器化部署)

- **智能端口管理**
  - 自动检测端口占用情况
  - 提供多种端口冲突解决方案
  - 支持自定义或智能随机端口分配

- **安全增强**
  - 自动配置系统防火墙
  - 可选 Let's Encrypt TLS 证书集成
  - 非 root 用户运行服务，提升安全性

- **用户友好界面**
  - 交互式管理菜单
  - 提供二维码便于快速配置客户端
  - 故障排除向导，快速解决常见问题

- **维护便利**
  - 实时状态监控和日志分析
  - 在线版本检查与更新提示
  - 兼容性检查与升级建议

---

## 📦 快速开始

### 基础安装

```bash
wget -O install_anytls.sh https://raw.githubusercontent.com/10000ge10000/anytls/main/install_anytls.sh && chmod +x install_anytls.sh && sudo ./install_anytls.sh
```

### 高级安装选项

```bash
# 指定端口和密码
sudo ./install_anytls.sh --port 8443 --password your_secure_password

# 启用 TLS 证书
sudo ./install_anytls.sh --tls

# 显示管理菜单
sudo ./install_anytls.sh --menu

# 查看所有选项
sudo ./install_anytls.sh --help
```

### 管理命令

```bash
# 更新到最新版本
sudo ./install_anytls.sh --update

# 查看当前状态
sudo ./install_anytls.sh --check-status

# 卸载服务
wget -O uninstall_anytls.sh https://raw.githubusercontent.com/10000ge10000/anytls/main/uninstall_anytls.sh && chmod +x uninstall_anytls.sh && sudo ./uninstall_anytls.sh
```

---

## ⚙️ 智能端口冲突处理

最新版本添加了智能端口冲突处理机制，可以：

- 自动检测端口是否被占用
- 显示占用端口的进程信息
- 提供多种解决方案：
  1. 尝试释放端口（终止占用进程）
  2. 自动查找其他可用端口
  3. 手动指定新端口

这确保了安装过程顺畅，避免了因端口冲突导致的安装失败。

---

## 🛡️ 多系统防火墙配置

脚本可以根据不同的操作系统自动配置防火墙规则：

| 操作系统 | 防火墙工具 | 配置方式 |
|---------|-----------|---------|
| Ubuntu/Debian | UFW | 自动添加规则并启用 |
| CentOS/RHEL | Firewalld | 添加永久规则并重载 |
| Alpine | iptables | 添加规则并尝试持久化 |

---

## 🔧 服务管理

### 系统服务命令

```bash
# 查看状态
systemctl status anytls

# 启动服务
systemctl start anytls

# 停止服务
systemctl stop anytls

# 重启服务
systemctl restart anytls

# 查看日志
journalctl -u anytls -f --no-pager
```

### 交互式管理菜单

```bash
sudo ./install_anytls.sh --menu
```

菜单提供以下功能：
- 安装/更新/卸载服务
- 查看服务状态和连接信息
- 配置 TLS 证书和防火墙
- 查看日志和故障排除

---

## 🔒 TLS 证书配置

脚本支持自动申请和配置 Let's Encrypt 免费 TLS 证书：

```bash
sudo ./install_anytls.sh --tls
```

或在安装后通过菜单配置：

```bash
sudo ./install_anytls.sh --menu
# 选择选项 6) 配置 Let's Encrypt 证书
```

证书将自动续期，确保服务始终使用有效证书。

---

## 📱 客户端连接

### 连接信息

安装完成后，服务器会显示连接信息，包括：
- 服务器 IP 地址
- 端口
- 密码
- 连接字符串
- 二维码（可直接扫描导入客户端）

也可以随时查看连接信息：

```bash
sudo ./install_anytls.sh --menu
# 选择选项 5) 查看连接信息
```

### 客户端设置说明

- 使用 Let's Encrypt 证书时，客户端无需跳过证书验证
- 使用自签名证书时，客户端需启用跳过证书验证选项
- 使用脚本生成的连接字符串可快速配置客户端

---

## 🛠️ 故障排除

如果遇到问题，可以使用内置的故障排除向导：

```bash
sudo ./install_anytls.sh --menu
# 选择选项 9) 故障排除向导
```

向导可以帮助解决以下问题：
- 服务无法启动（包括端口冲突解决）
- 无法连接到服务
- 防火墙配置问题
- TLS 证书问题
- 性能问题

---

## 📖 项目源

AnyTLS-Go 项目: [https://github.com/anytls/anytls-go](https://github.com/anytls/anytls-go)  
安装脚本项目: [https://github.com/10000ge10000/anytls](https://github.com/10000ge10000/anytls)

---

## 📝 更新日志

### v4.0.0 (2025-08-08)
- 添加智能端口冲突检测和处理功能
- 增加对 CentOS/RHEL/Rocky/Alma 系列系统的完整支持
- 添加 Alpine Linux 支持
- 集成 Let's Encrypt TLS 证书申请和配置
- 提供交互式管理菜单和故障排除向导
- 添加二维码生成功能
- 支持多种防火墙自动配置
- 增强服务状态监控和日志分析
- 提供在线版本检查和更新

### v3.0.0
- 自动识别系统架构 (amd64, arm64)
- 自动检测包管理器 (apt, dnf, yum)
- 自动从 GitHub API 获取最新版本
- 支持自定义端口和密码
- 创建专用的非 root 用户运行服务
- 注册 systemd 服务并设置开机自启

---
