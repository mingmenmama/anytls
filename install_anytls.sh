#!/bin/bash
# 安装 AnyTLS-Go 服务端，支持 systemd、自定义端口/密码、架构自动识别
# 优化版：增强了兼容性、安全性与健壮性

# --- 全局设置 ---
# set -e: 命令失败时立即退出
# set -o pipefail: 管道中的命令失败也视为失败
set -eo pipefail

# --- 函数定义 ---

# 日志函数
log_info() {
  echo "INFO: $1"
}
log_warn() {
  echo "WARN: $1"
}
log_error() {
  echo "ERROR: $1" >&2
  exit 1
}

# 1. [优化] 增加退出清理机制
cleanup() {
  log_info "执行清理操作..."
  # 如果 TEMP_DIR 变量存在且是一个目录，则删除
  [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ] && rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT INT TERM

# 2. [优化] 自动检测包管理器并安装依赖
install_dependencies() {
  log_info "安装必要依赖..."
  if command -v apt-get &>/dev/null; then
    apt-get update -y
    apt-get install -y curl wget unzip
  elif command -v dnf &>/dev/null; then
    dnf install -y curl wget unzip
  elif command -v yum &>/dev/null; then
    yum install -y curl wget unzip
  else
    log_error "未知的包管理器，请手动安装 curl, wget, unzip"
  fi
}

# 3. [优化] 使用外部服务获取公网 IP，更可靠
get_public_ip() {
  log_info "正在检测公网 IP..."
  # 尝试多个服务，增加成功率
  curl -s https://ipinfo.io/ip || curl -s https://api.ipify.org || curl -s https://icanhazip.com || echo ""
}

# --- 主逻辑开始 ---

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  log_error "请以 root 用户运行本脚本"
fi

# 判断架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_TAG="linux_amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
  *) log_error "不支持的系统架构: $ARCH" ;;
esac
log_info "检测到系统架构: ${ARCH}"

# 安装依赖
install_dependencies

# 获取并确认 IP
SERVER_IP=$(get_public_ip)
if [ -z "$SERVER_IP" ]; then
  log_warn "自动获取公网 IP 失败，请手动输入"
  read -r -p "请输入服务器公网 IP: " SERVER_IP
  [ -z "$SERVER_IP" ] && log_error "未提供 IP 地址，脚本终止"
fi

read -r -p "检测到服务器 IP: ${SERVER_IP}，确认使用此 IP？(Y/n): " confirm_ip
# 如果用户输入了 n 或 N，则重新输入
if [[ "$confirm_ip" =~ ^[nN]$ ]]; then
    read -r -p "请重新输入服务器公网 IP: " SERVER_IP
    [ -z "$SERVER_IP" ] && log_error "未提供 IP 地址，脚本终止"
fi
log_info "将使用 IP: ${SERVER_IP}"


# 用户输入端口
read -r -p "请输入监听端口 (1024-65535)，回车随机生成: " PORT
[ -z "$PORT" ] && PORT=$(shuf -i 20000-60000 -n 1)
log_info "使用端口: ${PORT}"

# 4. [优化] 使用 read -sp 安全输入密码
read -r -sp "请输入连接密码 (≥12位)，回车生成随机密码: " PASSWORD
echo # 换行
if [ -z "$PASSWORD" ]; then
  PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
  log_info "随机生成密码: ${PASSWORD}"
else
  log_info "已设置密码"
fi


# 5. [优化] 使用 GitHub API 获取最新版本，更稳定
log_info "正在获取 anytls-server 最新版本..."
API_URL="https://api.github.com/repos/anytls/anytls-go/releases/latest"

# 使用 curl 和 grep/cut 解析 JSON，避免引入 jq 依赖
LATEST_ASSET_INFO=$(curl -sL "${API_URL}" | grep -oE "browser_download_url\": \".*?${ARCH_TAG}\.zip\"")

if [ -z "${LATEST_ASSET_INFO}" ]; then
  log_error "无法找到适配 (${ARCH_TAG}) 的最新版本，请检查网络或 GitHub API 状态"
fi

DOWNLOAD_URL=$(echo "${LATEST_ASSET_INFO}" | cut -d '"' -f 4)
VERSION=$(echo "${DOWNLOAD_URL}" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")

if [ -z "$DOWNLOAD_URL" ] || [ -z "$VERSION" ]; then
    log_error "从 API 响应中解析下载链接或版本号失败"
fi

log_info "最新版本: v${VERSION}"
log_info "下载链接: ${DOWNLOAD_URL}"

# 6. [优化] 使用临时目录进行下载和解压
TEMP_DIR=$(mktemp -d)
log_info "创建临时目录: ${TEMP_DIR}"
cd "${TEMP_DIR}"

log_info "开始下载..."
wget -q --show-progress "${DOWNLOAD_URL}" -O anytls.zip
log_info "解压文件..."
unzip -o anytls.zip

# 安装二进制文件
install -m 755 anytls-server /usr/local/bin/anytls-server
cd / # 返回根目录，避免临时目录被占用

# 7. [优化] 创建专用用户运行服务，更安全
if ! id "anytls" &>/dev/null; then
    log_info "创建专用用户 'anytls'..."
    useradd -r -s /usr/sbin/nologin -d /dev/null anytls
fi

# 设置 systemd 服务
log_info "创建 systemd 服务文件..."
cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS Server
After=network.target
Wants=network.target

[Service]
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:${PORT} -p ${PASSWORD}
# 7. [优化] 使用非 root 用户运行
User=anytls
Group=anytls
Restart=on-failure
RestartSec=5
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# 启动并设置开机自启
log_info "重载 systemd 并启动服务..."
systemctl daemon-reload
# 8. [优化] 合并 enable 和 start 命令
systemctl enable --now anytls

# 等待一小会儿，让服务有时间启动
sleep 2

# 输出配置信息
echo ""
echo "✅ AnyTLS 安装成功！连接信息如下："
echo "=========================================="
echo "  🌐 IP地址     : ${SERVER_IP}"
echo "  📦 监听端口  : ${PORT}"
echo "  🔐 连接密码  : ${PASSWORD}"
echo "  🚀 版本       : v${VERSION}"
echo "=========================================="
echo "  服务状态检查 : systemctl status anytls"
echo "  日志查看     : journalctl -u anytls -f"
echo ""

# 临时目录会在脚本退出时由 trap 自动清理
