#!/bin/bash
# anytls-go 安装脚本（使用 release 中预编译文件）
set -e

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_TAG="linux-amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux-arm64" ;;
  *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户运行本脚本。"
    exit 1
fi

echo "安装依赖..."
apt update -y
apt install -y curl wget tar

# 获取公网 IP
get_ip() {
    ip=$(curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me)
    echo "$ip"
}
SERVER_IP=$(get_ip)
echo "检测到服务器 IP：$SERVER_IP"
read -p "确认使用此 IP？（回车默认）：" CONFIRM_IP
[ -n "$CONFIRM_IP" ] && SERVER_IP="$CONFIRM_IP"

# 输入端口
read -p "请输入监听端口（回车随机）：" PORT
[ -z "$PORT" ] && PORT=$(shuf -i 20000-65535 -n 1)

# 输入密码
read -p "请输入连接密码（至少12位，回车随机）：" PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
fi

# 下载最新版 anytls-server
echo "下载最新版本 anytls-server..."
LATEST_URL=$(curl -s https://api.github.com/repos/anytls/anytls-go/releases/latest \
  | grep browser_download_url | grep "$ARCH_TAG" | grep anytls-server \
  | cut -d '"' -f 4)

[ -z "$LATEST_URL" ] && echo "未能获取最新版本下载链接" && exit 1

mkdir -p /opt/anytls
cd /opt/anytls
wget -q --show-progress "$LATEST_URL" -O anytls-server.tar.gz
tar -xzf anytls-server.tar.gz
chmod +x anytls-server
mv anytls-server /usr/local/bin/

# 写入 systemd 服务
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

# 输出信息
echo "✅ 安装完成"
echo "📍 监听地址：$SERVER_IP:$PORT"
echo "🔐 连接密码：$PASSWORD"
echo "🛠 查看状态：systemctl status anytls"
echo "📄 配置文件：/etc/systemd/system/anytls.service"
