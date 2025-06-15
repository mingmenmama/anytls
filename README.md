当然可以！以下是整理后，便于直接一键复制的简洁版 Markdown 格式：

---

# AnyTLS-Go 一键安装脚本指南

**支持系统：** Ubuntu 20.04+ 和 Debian 11+  
**功能：** 自动检测 IP、配置端口密码、编译部署、创建 Systemd 服务、支持开机自启

---

## 🌟 主要功能

- 自动检测公网 IP（确认）
- 支持自定义或随机生成端口和密码
- 自动安装依赖（Go、Git、curl）
- 自动 clone、编译 **anytls-go**
- 自动配置 Systemd 服务（支持自启）
- 默认使用自签名证书（无需 TLS 证书认证）

---

## 📦 安装步骤

```bash
# 1. 下载脚本
wget -O install_anytls.sh https://raw.githubusercontent.com/mingmenmama/anytls/refs/heads/main/install_anytls.sh && chmod +x install_anytls.sh && sudo ./install_anytls.sh
```

> 脚本会在安装过程中提示：
> - 公网 IP（自动检测）
> - 监听端口（留空随机）
> - 连接密码（留空随机）

---

## ⚙️ 默认配置说明

| 配置项     | 默认行为                         |
|------------|----------------------------------|
| 监听端口   | 用户输入或随机（>=1024）         |
| 密码       | 用户输入或随机（16 位）         |
| TLS 证书   | 不使用，自签名，自带跳过验证方法 |

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
```

---

## 🔧 配置修改

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

---

## 📌 客户端注意事项

- 需跳过证书验证（自签名默认）
- 使用脚本生成或自定义的密码
- 推荐使用 **anytls-client** 或支持 **AnyTLS** 协议的客户端

---

## 📖 项目源

[https://github.com/anytls/anytls-go](https://github.com/anytls/anytls-go)

---

你可以直接复制以上内容使用！如果需要我帮你做成更加丰富的排版或导出成其他格式，也告诉我！
