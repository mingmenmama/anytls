#!/bin/bash
# AnyTLS-Go 一键安装脚本 - 使用 release 版，不编译
# 适用系统: Ubuntu 20.04+/Debian 11+
set -e

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_TAG="linux-amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux-arm64" ;;
  *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 用户运行本脚本。"
    exit 1
fi

# 安装必要依赖
echo "📦 安装依赖..."
apt update -y
apt install -y curl wget tar

# 获取服务器公网 IP
get_ip() {
    curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me
}
SERVER_IP=$(get_ip)
echo "🌐 检测到服务器 IP：$SERVER_IP"
read -p "若有误，请手动输入修正（回车保持不变）: " CONFIRM_IP
[ -n "$CONFIRM_IP" ] && SERVER_IP="$CONFIRM_IP"
echo "✅ 使用 IP: $SERVER_IP"

# 获取端口
read -p "📥 请输入 anytls 监听端口 (1024-65535)，留空随机生成: " PORT
[ -z "$PORT" ] && PORT=$(shuf -i 20000-60000 -n 1)
echo "✅ 使用端口: $PORT"

# 获取密码
read -p "🔐 请输入 anytls 密码 (>=12 位)，留空随机生成: " PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    echo "🔐 随机生成密码: $PASSWORD"
fi

echo "🚀 开始安装 anytls-go 服务端..."

# 下载 release 版 anytls-server
echo "📡 获取最新版本下载链接..."
LATEST_URL=$(curl -s https://api.github.com/repos/anytls/anytls-go/releases/latest \
  | grep -E "browser_download_url.*${ARCH_TAG}.*anytls-server" \
  | cut -d '"' -f 4 | head -n 1)

if [[ -z "$LATEST_URL" ]]; then
  echo "❌ 未能获取 anytls-server 的下载链接，请检查发布页。"
  exit 1
fi

echo "📥 下载 anytls-server..."
mkdir -p /opt/anytls
cd /opt/anytls
wget -q --show-progress "$LATEST_URL" -O anytls-server.tar.gz
tar -xzf anytls-server.tar.gz
chmod +x anytls-server
mv anytls-server /usr/local/bin/

# 创建 systemd 服务
echo "🛠 设置 systemd 服务..."
cat >/etc/systemd/system/anytls.service <<EOF
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

# 输出连接信息
echo -e "\n✅ 安装完成！连接信息如下："
echo "🌐 IP 地址   : $SERVER_IP"
echo "📦 监听端口 : $PORT"
echo "🔐 连接密码 : $PASSWORD"
echo "🧩 状态检查 : systemctl status anytls"
echo "📄 服务配置 : /etc/systemd/system/anytls.service"
