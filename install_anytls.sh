#!/bin/bash
#
# AnyTLS-Go 服务端一键安装脚本 (v3 - 增强解析)
#
# 功能:
# - 自动识别系统架构 (amd64, arm64)
# - 自动检测包管理器 (apt, dnf, yum)
# - 自动从 GitHub API 获取最新版本 (采用更健壮的解析逻辑)
# - 支持自定义端口和密码
# - 创建专用的非 root 用户运行服务，提升安全性
# - 注册 systemd 服务并设置开机自启

# --- 全局设置 ---
# set -e: 如果命令失败，立即退出脚本
# set -o pipefail: 如果管道中的任何命令失败，则整个管道视为失败
set -eo pipefail

# --- 函数定义 ---

# 日志函数，带颜色区分
log_info() {
  echo -e "\033[32m[INFO]\033[0m $1"
}
log_warn() {
  echo -e "\033[33m[WARN]\033[0m $1"
}
log_error() {
  echo -e "\033[31m[ERROR]\033[0m $1" >&2
  exit 1
}

# 脚本退出时，执行清理操作
cleanup() {
  # 如果 TEMP_DIR 变量存在且是一个目录，则删除
  if [ -d "${TEMP_DIR}" ]; then
    log_info "执行清理操作，删除临时目录 ${TEMP_DIR}"
    rm -rf "${TEMP_DIR}"
  fi
}
trap cleanup EXIT INT TERM

# 自动检测包管理器并安装依赖
install_dependencies() {
  log_info "正在安装必要依赖 (curl, wget, unzip)..."
  if command -v apt-get &>/dev/null; then
    apt-get update -y
    apt-get install -y curl wget unzip
  elif command -v dnf &>/dev/null; then
    dnf install -y curl wget unzip
  elif command -v yum &>/dev/null; then
    yum install -y curl wget unzip
  else
    log_error "未检测到支持的包管理器 (apt/dnf/yum)，请手动安装 curl, wget, unzip"
  fi
}

# 使用外部服务获取公网 IP
get_public_ip() {
  log_info "正在检测公网 IP..." >&2
  curl -s --max-time 10 https://ipinfo.io/ip || \
  curl -s --max-time 10 https://api.ipify.org || \
  curl -s --max-time 10 https://icanhazip.com || \
  echo ""
}

# --- 主逻辑开始 ---

# 1. 权限检查
if [ "$(id -u)" -ne 0 ]; then
  log_error "此脚本需要以 root 用户权限运行。"
fi

# 2. 架构检查
ARCH=$(uname -m)
case "$ARCH" in
  x86_64 | amd64) ARCH_TAG="linux_amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
  *) log_error "不支持的系统架构: ${ARCH}" ;;
esac
log_info "检测到系统架构: ${ARCH} (${ARCH_TAG})"

# 3. 安装依赖
install_dependencies

# 4. 获取并确认服务器 IP
SERVER_IP=$(get_public_ip)
if [ -z "$SERVER_IP" ]; then
  log_warn "自动获取公网 IP 失败，请手动输入。"
  read -r -p "请输入服务器公网 IP 地址: " SERVER_IP
  [ -z "$SERVER_IP" ] && log_error "未提供 IP 地址，脚本终止。"
fi

read -r -p "检测到服务器 IP 为 [${SERVER_IP}]，是否确认使用此 IP？(Y/n): " confirm_ip
if [[ "${confirm_ip}" =~ ^[nN]$ ]]; then
    read -r -p "请重新输入服务器公网 IP 地址: " SERVER_IP
    [ -z "$SERVER_IP" ] && log_error "未提供 IP 地址，脚本终止。"
fi
log_info "将使用 IP: ${SERVER_IP}"

# 5. 设置监听端口
read -r -p "请输入 AnyTLS 监听端口 [1024-65535] (回车则随机生成): " PORT
[ -z "$PORT" ] && PORT=$(od -An -N2 -i /dev/random | awk '{print int($1%40000)+20000}')
log_info "使用端口: ${PORT}"

# 6. 设置连接密码
read -r -sp "请输入 AnyTLS 连接密码 [建议12位以上] (回车则随机生成): " PASSWORD
echo # read -sp 后需要换行
if [ -z "$PASSWORD" ]; then
  PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
  log_info "已随机生成密码: ${PASSWORD}"
else
  log_info "密码已设置。"
fi

# 6.1 选择出站 IP 优先级交互
echo
echo "请选择出站 IP 优先级选项："
echo "  1) 仅 IPv4 (会尝试通过 sysctl 禁用 IPv6，请谨慎)"
echo "  2) 仅 IPv6 (尽量优先 IPv6，不能完全禁用 IPv4 在所有系统上)"
echo "  3) IPv4 优先 (默认)"
echo "  4) IPv6 优先"
read -r -p "选择 (1-4) [3]: " IP_PREF
IP_PREF=${IP_PREF:-3}

apply_ip_preference() {
  # 备份 gai.conf
  if [ -f /etc/gai.conf ]; then
    cp /etc/gai.conf /root/gai.conf.bak.$(date +%s)
    log_info "备份 /etc/gai.conf 到 /root/gai.conf.bak.$(date +%s)"
  fi

  case "$1" in
    1)
      # 仅 IPv4: 提高 IPv4 映射优先级并禁用 IPv6（持久化）
      echo "# anytls: prefer only IPv4 (added by install script)" >> /etc/gai.conf || true
      echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf || true
      cat > /etc/sysctl.d/99-anytls-disable-ipv6.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
      log_warn "已写入 /etc/sysctl.d/99-anytls-disable-ipv6.conf，将在 sysctl --system 时生效（已立即生效）。"
      sysctl --system >/dev/null 2>&1 || true
      ;;
    2)
      # 仅 IPv6: 优先 IPv6（无法在所有系统上完全禁用 IPv4），设置优先级
      echo "# anytls: prefer only IPv6 (added by install script)" >> /etc/gai.conf || true
      echo "precedence ::/0  100" >> /etc/gai.conf || true
      echo "precedence ::ffff:0:0/96  0" >> /etc/gai.conf || true
      ;;
    3)
      # IPv4 优先
      echo "# anytls: prefer IPv4 (added by install script)" >> /etc/gai.conf || true
      echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf || true
      ;;
    4)
      # IPv6 优先
      echo "# anytls: prefer IPv6 (added by install script)" >> /etc/gai.conf || true
      echo "precedence ::/0  100" >> /etc/gai.conf || true
      echo "precedence ::ffff:0:0/96  10" >> /etc/gai.conf || true
      ;;
    *)
      log_warn "未知选择 ${1}，不修改 IP 优先级。"
      ;;
  esac
}

# 在继续安装前应用用户的 IP 偏好
apply_ip_preference "$IP_PREF"

# 7. 从 GitHub API 获取最新版本信息
log_info "正在从 GitHub 获取最新版本信息..."
API_URL="https://api.github.com/repos/anytls/anytls-go/releases/latest"
API_RESPONSE=$(curl -sL --connect-timeout 10 --max-time 30 "${API_URL}")

if [ -z "${API_RESPONSE}" ]; then
    log_error "从 GitHub API (${API_URL}) 获取响应失败，请检查网络连接。"
fi

# ==================== 修改核心点 ====================
# 采用更稳定、更简单的多重 grep 管道来解析 JSON 文本
DOWNLOAD_URL=$(echo "${API_RESPONSE}" | \
    grep "browser_download_url" | \
    grep "${ARCH_TAG}" | \
    grep "\.zip\"" | \
    cut -d'"' -f4 | \
    head -n 1)
# ====================================================

if [ -z "${DOWNLOAD_URL}" ]; then
  VERSION_TAG=$(echo "${API_RESPONSE}" | grep -oE '"tag_name":\s*".*?"' | cut -d'"' -f4)
  log_error "在版本 [${VERSION_TAG:-未知}] 中未能找到适配 [${ARCH_TAG}] 的下载文件。请前往 'https://github.com/anytls/anytls-go/releases' 页面确认。"
fi

VERSION=$(echo "${DOWNLOAD_URL}" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
log_info "成功定位到最新版本 v${VERSION}"
log_info "下载链接: ${DOWNLOAD_URL}"

# 8. 下载并安装
TEMP_DIR=$(mktemp -d)
chmod 700 "${TEMP_DIR}"
log_info "创建临时工作目录: ${TEMP_DIR}"
cd "${TEMP_DIR}"

log_info "正在下载文件..."
wget -q --show-progress "${DOWNLOAD_URL}" -O anytls.zip || { log_error "下载失败"; exit 1; }
log_info "下载完成，正在解压..."
unzip -o anytls.zip > /dev/null
log_info "正在安装二进制文件到 /usr/local/bin/ ..."
install -m 755 anytls-server /usr/local/bin/anytls-server
cd / # 操作完毕，离开临时目录

# 9. 创建服务所需用户
if ! id "anytls" &>/dev/null; then
    log_info "创建专用的系统用户 'anytls' 用于运行服务..."
    useradd -r -s /usr/sbin/nologin -d /dev/null anytls
fi

# 10. 创建 systemd 服务
log_info "正在创建 systemd 服务文件..."
[ -f /etc/systemd/system/anytls.service ] && cp /etc/systemd/system/anytls.service /root/anytls.service.bak.$(date +%s)

# 创建 /etc/anytls 目录并写入 EnvironmentFile
mkdir -p /etc/anytls
cat > /etc/anytls/anytls.env <<EOV
PORT=${PORT}
PASSWORD=${PASSWORD}
EOV
chown root:anytls /etc/anytls || true
chmod 0750 /etc/anytls || true
chown root:anytls /etc/anytls/anytls.env || true
chmod 0640 /etc/anytls/anytls.env || true

log_info "已创建 /etc/anytls/anytls.env，并设置了安全权限。"

cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS-Go Server
Documentation=https://github.com/anytls/anytls-go
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=anytls
Group=anytls
EnvironmentFile=/etc/anytls/anytls.env
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:${PORT} -p ${PASSWORD}
Restart=on-failure
RestartSec=5
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# 11. 启动服务
log_info "正在重载 systemd 并启动 anytls 服务..."
systemctl daemon-reload
systemctl enable --now anytls

# 等待2秒确保服务已启动，然后检查状态
sleep 2
SERVICE_STATUS=$(systemctl is-active anytls)

# 12. 显示最终结果
echo ""
echo -e "\033[1;32m✅ AnyTLS 安装并启动成功！\033[0m"
echo "=================================================="
echo "  服务器 IP (Address)  : ${SERVER_IP}"
echo "  监听端口 (Port)       : ${PORT}"
echo "  连接密码 (Password)  : ${PASSWORD}"
echo "  当前版本 (Version)   : v${VERSION}"
echo "--------------------------------------------------"
if [ "${SERVICE_STATUS}" = "active" ]; then
  echo -e "  服务状态: \033[32m运行中 (active)\033[0m"
else
  echo -e "  服务状态: \033[31m启动失败 (inactive)\033[0m"
fi
echo "=================================================="
echo "常用管理命令:"
echo "  启动服务: systemctl start anytls"
echo "  停止服务: systemctl stop anytls"
echo "  重启服务: systemctl restart anytls"
echo "  查看状态: systemctl status anytls"
echo "  查看日志: journalctl -u anytls -f --no-pager"
echo ""

# 临时目录会在脚本退出时由 trap 自动清理
exit 0
