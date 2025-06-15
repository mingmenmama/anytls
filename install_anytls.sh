#!/bin/bash
# AnyTLS-Go 一键安装脚本 - 自动拉取最新版 release 进行安装
# 支持架构：x86_64 / arm64
# 支持系统：Ubuntu 20.04+ / Debian 11+

set -e

# 判断架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_TAG="linux_amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
  *)
    echo "❌ 不支持的架构: $ARCH"
    exit 1
    ;;
esac

# 检查是否为 root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请以 root 用户运行本脚本。"
    exit 1
fi

# 安装依赖
echo "📦 安装必要依赖..."
apt update -y
apt install -y curl wget unzip jq

# 自动获取公网 IP
get_ip() {
    curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me
}
SERVER_IP=$(get_ip)
echo "🌐 检测到服务器 IP：$SERVER_IP"
read -p "确认使用此 IP？（回车默认）：" INPUT_IP
[ -n "$INPUT_IP" ] && SERVER_IP="$INPUT_IP"

# 获取监听端口
read -p "📥 请输入监听端口 (1024-65535)，回车随机生成: " PORT
[ -z "$PORT" ] && PORT=$(shuf -i 20000-60000 -n 1)
echo "✅ 使用端口: $PORT"

# 获取连接密码
read -p "🔐 请输入连接密码 (≥12位)，回车生成随机密码: " PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    echo "🔐 随机生成密码: $PASSWORD"
fi

# 获取 anytls-server 最新版本下载链接
echo "🌐 正在获取 anytls-server 最新版本下载地址..."

LATEST_RELEASE_JSON=$(curl -s https://api.github.com/repos/anytls/anytls-go/releases/latest)

DOWNLOAD_URL=$(echo "$LATEST_RELEASE_JSON" | jq -r \
  ".assets[] | select(.name | test(\"anytls_.*_${ARCH_TAG}\\.zip\")) | .browser_download_url")

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ 未找到匹配系统架构 [$ARCH_TAG] 的 anytls-server 下载链接。"
    exit 1
fi

VERSION=$(echo "$LATEST_RELEASE_JSON" | jq -r '.tag_name')
echo "✅ 获取成功: 版本 $VERSION"
echo "📥 下载链接: $DOWNLOAD_URL"

# 下载并安装
mkdir -p /opt/anytls && cd /opt/anytls
wget -q --show-progress "$DOWNLOAD_URL" -O anytls.zip
unzip -o anytls.zip
chmod +x anytls-server
mv anytls-server /usr/local/bin/

# 配置 systemd 服务
echo "🛠 配置 systemd 服务..."
cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS Server
After=network.target

[Service]
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:$PORT -p $PASSWORD
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable anytls
systemctl restart anytls

# 输出结果
echo ""
echo "✅ AnyTLS 安装完成，配置信息如下："
echo "🌐 IP地址   : $SERVER_IP"
echo "📦 监听端口 : $PORT"
echo "🔐 连接密码 : $PASSWORD"
echo "📄 配置文件 : /etc/systemd/system/anytls.service"
echo "🧩 服务状态 : systemctl status anytls"
echo "🚀 当前版本 : $VERSION"
