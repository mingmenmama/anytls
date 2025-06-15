#!/bin/bash
# AnyTLS-Go 一键安装脚本（自动检测版本 + 修复 IP 和 jq 错误）

set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请以 root 用户运行本脚本。"
    exit 1
fi

# 判断系统架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_TAG="linux_amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
  *) echo "❌ 不支持的系统架构: $ARCH"; exit 1 ;;
esac

# 安装依赖
echo "📦 安装必要依赖..."
apt update -y
apt install -y curl wget unzip jq

# 尝试获取公网 IP（多重备选）
get_ip() {
  IP=$(curl -s --max-time 5 https://api.ip.sb/ip) || \
  IP=$(curl -s --max-time 5 https://ip-api.com/json | jq -r '.query') || \
  IP=$(curl -s --max-time 5 https://ipinfo.io/ip)
  echo "$IP"
}

SERVER_IP=$(get_ip)

# 验证获取的 IP
if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "⚠️  无法自动获取服务器公网 IP。请手动输入："
  read -p "IP地址: " SERVER_IP
fi

echo "🌐 检测到服务器 IP：$SERVER_IP"
read -p "确认使用此 IP？（回车默认）: " INPUT_IP
[ -n "$INPUT_IP" ] && SERVER_IP="$INPUT_IP"

# 用户输入端口
read -p "📥 请输入监听端口 (1024-65535)，回车随机生成: " PORT
[ -z "$PORT" ] && PORT=$(shuf -i 20000-60000 -n 1)
echo "✅ 使用端口: $PORT"

# 用户输入密码
read -p "🔐 请输入连接密码 (≥12位)，回车生成随机密码: " PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    echo "🔐 随机生成密码: $PASSWORD"
fi

# 获取最新版下载链接
echo "🌐 正在获取 anytls-server 最新版本下载地址..."

RELEASE_JSON=$(curl -s https://api.github.com/repos/anytls/anytls-go/releases/latest)

DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r \
  ".assets[] | select(.name | test(\"anytls_.*_${ARCH_TAG}\\.zip\")) | .browser_download_url")

VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ 未找到适配 $ARCH_TAG 架构的下载链接。"
    exit 1
fi

echo "✅ 获取成功: 版本 $VERSION"
echo "📥 下载链接: $DOWNLOAD_URL"

# 下载并安装
mkdir -p /opt/anytls && cd /opt/anytls
wget -q --show-progress "$DOWNLOAD_URL" -O anytls.zip
unzip -o anytls.zip
chmod +x anytls-server
mv anytls-server /usr/local/bin/

# 设置 systemd 服务
echo "🛠 设置 systemd 服务..."
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
echo "✅ 安装成功！连接信息如下："
echo "🌐 IP地址   : $SERVER_IP"
echo "📦 监听端口 : $PORT"
echo "🔐 连接密码 : $PASSWORD"
echo "🛠 systemd服务 : systemctl status anytls"
echo "🚀 当前版本 : $VERSION"
