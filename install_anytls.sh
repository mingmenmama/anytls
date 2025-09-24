#!/bin/bash
#
# AnyTLS-Go 服务端一键安装脚本 (v3 - 增强解析)
#

set -eo pipefail

# --- 日志函数 ---
log_info() { echo -e "\033[32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[31m[ERROR]\033[0m $1" >&2; exit 1; }

# --- 清理函数 ---
cleanup() {
  [ -d "${TEMP_DIR}" ] && { log_info "删除临时目录 ${TEMP_DIR}"; rm -rf "${TEMP_DIR}"; }
}
trap cleanup EXIT INT TERM

# --- 安装依赖 ---
install_dependencies() {
  log_info "安装必要依赖 (curl, wget, unzip)..."
  if command -v apt-get &>/dev/null; then
    apt-get update -y
    apt-get install -y curl wget unzip
  elif command -v dnf &>/dev/null; then
    dnf install -y curl wget unzip
  elif command -v yum &>/dev/null; then
    yum install -y curl wget unzip
  else
    log_error "未检测到支持的包管理器 (apt/dnf/yum)"
  fi
}

# --- 获取公网 IP ---
get_public_ip() {
  log_info "检测公网 IP..." >&2
  curl -s --max-time 10 https://ipinfo.io/ip || \
  curl -s --max-time 10 https://api.ipify.org || \
  curl -s --max-time 10 https://icanhazip.com || echo ""
}

# --- 权限和架构检查 ---
[ "$(id -u)" -ne 0 ] && log_error "请以 root 用户运行"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH_TAG="linux_amd64" ;;
  aarch64|arm64) ARCH_TAG="linux_arm64" ;;
  *) log_error "不支持的系统架构: $ARCH" ;;
esac
log_info "系统架构: $ARCH ($ARCH_TAG)"

install_dependencies

# --- 获取服务器 IP ---
SERVER_IP=$(get_public_ip)
[ -z "$SERVER_IP" ] && read -r -p "请输入服务器公网 IP: " SERVER_IP
read -r -p "确认使用 IP [$SERVER_IP]? (Y/n): " confirm_ip
[[ "$confirm_ip" =~ ^[nN]$ ]] && read -r -p "请重新输入服务器公网 IP: " SERVER_IP
log_info "使用 IP: $SERVER_IP"

# --- 设置端口和密码 ---
read -r -p "请输入 AnyTLS 监听端口 (回车随机生成): " PORT
[ -z "$PORT" ] && PORT=$(shuf -i 20000-60000 -n 1 2>/dev/null || od -An -N2 -i /dev/random | awk '{print int($1%40000)+20000}')
log_info "使用端口: $PORT"

read -r -sp "请输入 AnyTLS 密码 (回车随机生成): " PASSWORD
echo
[ -z "$PASSWORD" ] && PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c16 2>/dev/null || openssl rand -base64 12 | tr -d "=+/" | cut -c1-12 2>/dev/null || echo "defaultpassword")
log_info "密码: $PASSWORD"

# --- IP 优先级交互 ---
echo
echo "请选择出站 IP 优先级："
echo "  1) IPv4 优先 (默认)"
echo "  2) IPv6 优先"
echo "  3) 仅 IPv4"
echo "  4) 仅 IPv6"
read -r -p "选择 [1-4] (默认: 1): " IP_PREF
IP_PREF=${IP_PREF:-1}

apply_ip_preference() {
  [ -f /etc/gai.conf ] && cp /etc/gai.conf /root/gai.conf.bak.$(date +%s)
  case "$1" in
    1) # IPv4 优先
      echo "# anytls: IPv4 优先" >> /etc/gai.conf
      echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
      sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
      sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
      ;;
    2) # IPv6 优先
      echo "# anytls: IPv6 优先" >> /etc/gai.conf
      echo "precedence ::/0  100" >> /etc/gai.conf
      echo "precedence ::ffff:0:0/96  10" >> /etc/gai.conf
      ;;
    3) # 仅 IPv4
      cat > /etc/sysctl.d/99-anytls-disable-ipv6.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
      sysctl --system >/dev/null
      ;;
    4) # 仅 IPv6
      log_warn "警告：仅IPv6模式将阻塞所有IPv4出站流量，确保服务器支持IPv6且VPN客户端也支持IPv6"
      read -p "确认继续？ (y/N): " confirm
      [[ "$confirm" =~ ^[yY]$ ]] || { log_info "跳过IP优先级设置"; return; }
      sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
      sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
      iptables -F
      iptables -A OUTPUT -p tcp -4 -j DROP
      iptables -A OUTPUT -p udp -4 -j DROP
      ;;
  esac
}

apply_ip_preference "$IP_PREF"

# --- 获取最新版本 ---
log_info "获取最新版本..."
API_URL="https://api.github.com/repos/anytls/anytls-go/releases/latest"
API_RESPONSE=$(curl -sL --connect-timeout 10 --max-time 30 "$API_URL")
[ -z "$API_RESPONSE" ] && log_error "获取 GitHub API 失败"

DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "$ARCH_TAG" | grep "\.zip\"" | cut -d'"' -f4 | head -n1)
[ -z "$DOWNLOAD_URL" ] && log_error "未找到适配 $ARCH_TAG 的下载文件"

VERSION=$(echo "$DOWNLOAD_URL" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
log_info "版本 v$VERSION"
log_info "下载链接: $DOWNLOAD_URL"

# --- 下载与安装 ---
TEMP_DIR=$(mktemp -d)
chmod 700 "$TEMP_DIR"
cd "$TEMP_DIR"
wget -q --show-progress "$DOWNLOAD_URL" -O anytls.zip || log_error "下载失败"
unzip -o anytls.zip > /dev/null
install -m 755 anytls-server /usr/local/bin/anytls-server
cd /

# --- 创建用户 ---
id anytls &>/dev/null || useradd -r -s /usr/sbin/nologin -d /dev/null anytls

# --- systemd 服务 ---
mkdir -p /etc/anytls
cat > /etc/anytls/anytls.env <<EOV
PORT=$PORT
PASSWORD=$PASSWORD
EOV
chown root:anytls /etc/anytls /etc/anytls/anytls.env
chmod 0750 /etc/anytls
chmod 0640 /etc/anytls/anytls.env

cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS-Go Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=anytls
Group=anytls
EnvironmentFile=/etc/anytls/anytls.env
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:\${PORT} -p \${PASSWORD}
Restart=on-failure
RestartSec=5
LimitNPROC=10000
LimitNOFILE=1000000
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/etc/anytls
ProtectHome=yes
PrivateDevices=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now anytls
sleep 2
SERVICE_STATUS=$(systemctl is-active anytls)

echo ""
echo -e "\033[1;32m✅ AnyTLS 安装并启动成功！\033[0m"
echo "服务器 IP: $SERVER_IP"
echo "监听端口: $PORT"
echo "连接密码: $PASSWORD"
echo "版本: v$VERSION"
echo "服务状态: $SERVICE_STATUS"
echo "管理命令: systemctl start|stop|restart anytls, journalctl -u anytls -f"
exit 0
