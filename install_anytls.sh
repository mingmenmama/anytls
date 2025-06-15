#!/bin/bash
# 安装 AnyTLS-Go 服务端，支持 systemd、自定义端口/密码、架构自动识别

set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 请以 root 用户运行本脚本"
  exit 1
fi

# 判断架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_TAG="linux_amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
  *) echo "❌ 不支持的系统架构: $ARCH"; exit 1 ;;
esac

# 安装依赖
echo "📦 安装必要依赖..."
apt update -y
apt install -y curl wget unzip

# 获取本机 IP（只取公网 IPv4）
get_local_ip() {
  hostname -I | tr ' ' '\n' | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -vE '^127|^10\.|^192\.168|^172\.(1[6-9]|2[0-9]|3[01])' | head -n 1
}
SERVER_IP=$(get_local_ip)

if [ -z "$SERVER_IP" ]; then
  echo "⚠️ 未找到公网 IP，可能未联网或需手动输入"
  read -p "请输入服务器公网 IP: " SERVER_IP
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

# 获取最新版本号和下载链接
echo "🌐 正在获取 anytls-server 最新版本..."

GITHUB_LATEST_URL="https://github.com/anytls/anytls-go/releases/latest"
LATEST_HTML=$(curl -sL "$GITHUB_LATEST_URL")

ZIP_NAME=$(echo "$LATEST_HTML" | grep -oE "anytls_[0-9.]+_${ARCH_TAG}\.zip" | head -n 1)
VERSION=$(echo "$ZIP_NAME" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")

if [ -z "$ZIP_NAME" ]; then
  echo "❌ 未找到适配系统架构的下载链接"
  exit 1
fi

DOWNLOAD_URL="https://github.com/anytls/anytls-go/releases/download/v${VERSION}/${ZIP_NAME}"
echo "✅ 最新版本: $VERSION"
echo "📥 下载链接: $DOWNLOAD_URL"

# 下载并解压
mkdir -p /opt/anytls && cd /opt/anytls
wget -q --show-progress "$DOWNLOAD_URL" -O anytls.zip
unzip -o anytls.zip
chmod +x anytls-server
mv anytls-server /usr/local/bin/

# 设置 systemd 服务
echo "🛠 创建 systemd 服务文件..."
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

# 启动并设置开机自启
systemctl daemon-reload
systemctl enable anytls
systemctl restart anytls

# 输出配置信息
echo ""
echo "✅ AnyTLS 安装成功！连接信息如下："
echo "🌐 IP地址   : $SERVER_IP"
echo "📦 监听端口 : $PORT"
echo "🔐 连接密码 : $PASSWORD"
echo "🚀 版本     : v$VERSION"
echo "🧩 服务状态 : systemctl status anytls"
