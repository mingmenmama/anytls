# AnyTLS-Go 一键安装脚本

该项目提供了一个适用于 Ubuntu 20.04+ 和 Debian 11+ 系统的一键安装脚本，可用于部署 [anytls-go](https://github.com/anytls/anytls-go) 服务端（`anytls-server`）。支持交互式设置监听端口与连接密码，并自动创建 Systemd 服务，支持开机自启。

## 🌟 功能特点

- 自动检测服务器公网 IP，并让用户确认
- 支持自定义监听端口和密码（也可随机生成）
- 自动安装依赖（Go / Git / curl）
- 自动 clone 并编译 `anytls-go`
- 自动创建 Systemd 服务，支持开机启动
- **不使用 TLS 证书**，默认使用自签名证书（客户端需跳过验证）

## 📦 安装步骤

### 1. 下载脚本

```bash
wget -O install_anytls.sh https://your-github-url/install_anytls.sh
2. 赋予执行权限
bash
复制
编辑
chmod +x install_anytls.sh
3. 运行脚本（需要 root 权限）
bash
复制
编辑
sudo ./install_anytls.sh
脚本将会提示你输入或确认以下内容：

当前服务器公网 IP（自动检测）

AnyTLS 监听端口（可留空随机生成）

连接密码（可留空随机生成）

⚙️ 默认行为
配置项	默认行为
监听端口	用户输入或随机生成（1024+）
密码	用户输入或随机生成（16位）
TLS证书	不使用，默认使用自签名证书

🧩 服务管理
安装完成后，anytls-server 会以 systemd 服务运行。可使用以下命令管理：

bash
复制
编辑
# 查看服务状态
systemctl status anytls

# 重启服务
systemctl restart anytls

# 停止服务
systemctl stop anytls

# 启用开机启动（默认已启用）
systemctl enable anytls
🔧 修改配置
若需更改监听端口或密码：

编辑服务配置：

bash
复制
编辑
sudo nano /etc/systemd/system/anytls.service
找到以下行，并根据需要修改端口（-l）或密码（-p）：

ini
复制
编辑
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:端口 -p 密码
使更改生效：

bash
复制
编辑
sudo systemctl daemon-reload
sudo systemctl restart anytls
📌 客户端使用注意
客户端必须跳过证书验证，因为服务端默认使用自签名证书。

请使用脚本中生成或你自定义的密码进行连接。

建议配合 anytls-client 或支持 AnyTLS 协议的客户端使用。

📖 项目来源
项目仓库：https://github.com/anytls/anytls-go
