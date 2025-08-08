---

**AnyTLS-Go 一键安装脚本指南**

**最后更新:** 2025-08-08

**支持系统:** Ubuntu 20.04+、Debian 11+、CentOS/RHEL、Alpine Linux  
**功能:** 自动检测 IP、配置端口密码、编译部署、创建 Systemd 服务、TLS 证书集成、防火墙配置等

---

## 🌟 主要功能

- **跨平台支持**
  - Ubuntu/Debian 系列系统
  - CentOS/RHEL 系列系统
  - Alpine Linux (适合容器化部署)

- **核心功能**
  - 自动检测公网 IP
  - 支持自定义或随机生成端口和密码
  - 自动安装依赖
  - 自动 clone、编译 **anytls-go**
  - 自动配置 Systemd 服务（支持自启）

- **安全增强**
  - 自动配置防火墙规则
  - 可选 Let's Encrypt TLS 证书集成
  - 密码强度检查

- **用户体验**
  - 生成二维码便于快速导入配置
  - 交互式管理菜单
  - 故障排除向导

- **维护便利**
  - 更新脚本，支持保留配置
  - 状态监控和日志分析
  - 版本检查和更新提示

---

## 📦 安装

### 基本安装

```bash
wget -O install_anytls.sh https://raw.githubusercontent.com/10000ge10000/anytls/main/install_anytls.sh && chmod +x install_anytls.sh && sudo ./install_anytls.sh
```

### 高级安装选项

```bash
# 使用指定端口和密码
sudo ./install_anytls.sh --port 8443 --password your_password

# 启用 TLS 证书
sudo ./install_anytls.sh --tls

# 显示交互式菜单
sudo ./install_anytls.sh --menu

# 查看所有选项
sudo ./install_anytls.sh --help
```

## 📦 管理

### 更新

```bash
sudo ./install_anytls.sh --update
```

### 卸载

```bash
wget -O uninstall_anytls.sh https://raw.githubusercontent.com/10000ge10000/anytls/main/uninstall_anytls.sh && chmod +x uninstall_anytls.sh && sudo ./uninstall_anytls.sh
```

> 安装过程会提示：
> - 公网 IP（自动检测）
> - 监听端口（留空随机）
> - 连接密码（留空随机）
> - 是否配置 TLS 证书
> - 是否配置防火墙

---

## ⚙️ 默认配置说明

| 配置项     | 默认行为                          |
|------------|-----------------------------------|
| 监听端口   | 用户输入或随机（>=1024）          |
| 密码       | 用户输入或随机（16 位）           |
| TLS 证书   | 可选 Let's Encrypt 证书或自签名   |
| 防火墙     | 自动配置（可选）                  |
| 系统服务   | Systemd 管理                      |

---

## 🧩 常用管理命令

安装后，服务基于 Systemd 运行。管理命令：

```bash
# 查看状态
systemctl status anytls

# 重启服务
systemctl restart anytls

# 停止服务
systemctl stop anytls

# 设置开机自启（默认已启用）
systemctl enable anytls

# 查看日志
journalctl -u anytls -f --no-pager
```

### 使用脚本管理

```bash
# 查看服务状态
sudo ./install_anytls.sh --check-status

# 显示管理菜单
sudo ./install_anytls.sh --menu

# 更新到最新版本
sudo ./install_anytls.sh --update
```

---

## 🔧 配置修改

### 手动编辑配置

编辑配置文件，自定义端口和密码：

```bash
sudo nano /etc/systemd/system/anytls.service
```

修改：

```ini
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:端口 -p 密码
```

应用更改：

```bash
sudo systemctl daemon-reload
sudo systemctl restart anytls
```

### 配置 TLS 证书

如果您在安装时未配置 TLS 证书，可以随时添加：

```bash
sudo ./install_anytls.sh --tls
```

---

## 🛠️ 故障排除

如果遇到问题，可以使用内置的故障排除向导：

```bash
sudo ./install_anytls.sh --menu
# 选择 "故障排除向导" 选项
```

常见问题解决方法：

1. **服务无法启动**
   - 检查端口是否被占用: `netstat -tuln | grep <端口>`
   - 查看日志: `journalctl -u anytls -n 50`

2. **无法连接到服务**
   - 确认防火墙是否开放端口: `sudo ./install_anytls.sh --menu` → 配置防火墙
   - 检查服务状态: `systemctl status anytls`

3. **TLS 证书问题**
   - 证书续期: `certbot renew --force-renewal`
   - 重新配置: `sudo ./install_anytls.sh --tls`

---

## 📌 客户端注意事项

- 使用 Let's Encrypt 证书时，客户端无需跳过证书验证
- 使用自签名证书时，客户端需跳过证书验证
- 使用脚本生成或自定义的密码
- 推荐使用 **anytls-client** 或支持 **AnyTLS** 协议的客户端
- 可通过扫描二维码快速导入配置（需支持的客户端）

---

## 📖 项目源

[https://github.com/anytls/anytls-go](https://github.com/anytls/anytls-go)

---

## 📝 更新日志

### v4.0.0 (2025-08-08)
- 添加对 CentOS/RHEL 系列系统的支持
- 增加 Alpine Linux 支持（适合容器化部署）
- 添加 Let's Encrypt TLS 证书集成
- 添加防火墙自动配置选项
- 添加更新脚本，支持在不丢失配置的情况下更新
- 增加状态监控和简单的日志分析功能
- 安装完成后提供连接信息的二维码
- 增加交互式菜单，便于初学者使用
- 添加简单的故障排除向导
- 在脚本中添加版本号和更新日志
- 提供版本检查功能，提示用户升级

### v3.0.0 (旧版)
- 自动识别系统架构 (amd64, arm64)
- 自动检测包管理器 (apt, dnf, yum)
- 自动从 GitHub API 获取最新版本 (采用更健壮的解析逻辑)
- 支持自定义端口和密码
- 创建专用的非 root 用户运行服务，提升安全性
- 注册 systemd 服务并设置开机自启

---
