#!/bin/bash
#
# AnyTLS-Go 服务端管理脚本 (v4)
#
# 功能:
# - 菜单驱动: 安装 | 更新 | 卸载
# - 自动从 GitHub API 获取最新版本
# - 创建专用的非 root 用户运行服务
# - 完全卸载清理

# --- 全局设置与变量 ---
set -eo pipefail

# 定义文件路径和目录
SERVICE_FILE="/etc/systemd/system/anytls.service"
BINARY_PATH="/usr/local/bin/anytls-server"
CONFIG_DIR="/etc/anytls"
VERSION_FILE="${CONFIG_DIR}/version"
SERVICE_NAME="anytls"

# --- 辅助函数 ---

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
  if [ -n "${TEMP_DIR-}" ] && [ -d "${TEMP_DIR}" ]; then
    rm -rf "${TEMP_DIR}"
  fi
}
trap cleanup EXIT INT TERM

# --- 核心功能函数 ---

# 1. 前置检查 (root权限和架构)
pre_check() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "此脚本需要以 root 用户权限运行。"
  fi

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64 | amd64) ARCH_TAG="linux_amd64" ;;
    aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
    *) log_error "不支持的系统架构: ${ARCH}" ;;
  esac
  log_info "检测到系统架构: ${ARCH} (${ARCH_TAG})"
}

# 2. 从 GitHub 获取最新版本信息
fetch_latest_info() {
  log_info "正在从 GitHub 获取最新版本信息..."
  API_URL="https://api.github.com/repos/anytls/anytls-go/releases/latest"
  API_RESPONSE=$(curl -sL --connect-timeout 10 --max-time 20 "${API_URL}")

  if [ -z "${API_RESPONSE}" ]; then
      log_error "从 GitHub API (${API_URL}) 获取响应失败，请检查网络连接。"
  fi

  # 使用更健壮的多重 grep 管道解析
  DOWNLOAD_URL=$(echo "${API_RESPONSE}" | grep "browser_download_url" | grep "${ARCH_TAG}" | grep "\.zip\"" | cut -d'"' -f4 | head -n 1)
  LATEST_VERSION_TAG=$(echo "${API_RESPONSE}" | grep -oE '"tag_name":\s*".*?"' | cut -d'"' -f4)

  if [ -z "${DOWNLOAD_URL}" ]; then
    log_error "在最新版本 [${LATEST_VERSION_TAG:-未知}] 中未能找到适配 [${ARCH_TAG}] 的下载文件。"
  fi
}

# 3. 停止并禁用服务
stop_and_disable_service() {
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        log_info "正在停止 ${SERVICE_NAME} 服务..."
        systemctl stop ${SERVICE_NAME}
    fi
    if systemctl is-enabled --quiet ${SERVICE_NAME}; then
        log_info "正在禁用 ${SERVICE_NAME} 服务..."
        systemctl disable ${SERVICE_NAME}
    fi
}

# 4. 卸载 AnyTLS
uninstall_anytls() {
    log_info "--- 开始卸载 AnyTLS ---"
    if [ ! -f "${BINARY_PATH}" ] && [ ! -f "${SERVICE_FILE}" ]; then
        log_warn "AnyTLS 未安装，无需卸载。"
        exit 0
    fi

    stop_and_disable_service

    if [ -f "${SERVICE_FILE}" ]; then
        log_info "删除 systemd 服务文件..."
        rm -f "${SERVICE_FILE}"
        systemctl daemon-reload
    fi

    if [ -f "${BINARY_PATH}" ]; then
        log_info "删除二进制文件..."
        rm -f "${BINARY_PATH}"
    fi

    if [ -d "${CONFIG_DIR}" ]; then
        log_info "删除配置文件目录..."
        rm -rf "${CONFIG_DIR}"
    fi

    if id "anytls" &>/dev/null; then
        log_info "删除专用用户 'anytls'..."
        userdel anytls
    fi

    echo ""
    log_info "✅ AnyTLS 已成功卸载。"
}

# 5. 更新 AnyTLS
update_anytls() {
    log_info "--- 开始更新 AnyTLS ---"
    if [ ! -f "${BINARY_PATH}" ]; then
        log_error "AnyTLS 未安装，请先执行安装操作。"
    fi
    if [ ! -f "${VERSION_FILE}" ]; then
        log_error "版本文件丢失，无法确定当前版本。建议卸载后重新安装。"
    fi

    CURRENT_VERSION=$(cat "${VERSION_FILE}")
    log_info "当前已安装版本: v${CURRENT_VERSION}"

    fetch_latest_info
    LATEST_VERSION=${LATEST_VERSION_TAG#v} # 移除 'v' 前缀

    if [ "${CURRENT_VERSION}" == "${LATEST_VERSION}" ]; then
        log_info "您已在使用最新版本 (v${CURRENT_VERSION})，无需更新。"
        exit 0
    fi

    log_info "发现新版本: v${LATEST_VERSION}，开始更新..."

    TEMP_DIR=$(mktemp -d)
    log_info "创建临时工作目录: ${TEMP_DIR}"
    cd "${TEMP_DIR}"

    log_info "正在下载新版本..."
    wget -q --show-progress "${DOWNLOAD_URL}" -O anytls.zip
    unzip -o anytls.zip > /dev/null

    log_info "停止当前服务以更新文件..."
    systemctl stop ${SERVICE_NAME}

    log_info "安装新版二进制文件..."
    install -m 755 anytls-server "${BINARY_PATH}"
    cd /

    log_info "更新本地版本记录..."
    echo "${LATEST_VERSION}" > "${VERSION_FILE}"

    log_info "正在重启 ${SERVICE_NAME} 服务..."
    systemctl restart ${SERVICE_NAME}
    sleep 2

    echo ""
    log_info "✅ AnyTLS 已成功更新至 v${LATEST_VERSION}！"
}


# 6. 安装 AnyTLS
install_anytls() {
    log_info "--- 开始安装 AnyTLS ---"
    if [ -f "${BINARY_PATH}" ]; then
        log_warn "检测到 AnyTLS 已安装。如需重新安装，请先执行卸载操作。"
        exit 1
    fi

    pre_check

    # 安装依赖
    install_dependencies() {
      if command -v apt-get &>/dev/null; then
        apt-get update -y && apt-get install -y curl wget unzip
      elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        (command -v dnf || command -v yum) install -y curl wget unzip
      else
        log_error "未检测到支持的包管理器，请手动安装 curl, wget, unzip"
      fi
    }
    install_dependencies

    # 获取并确认 IP
    get_public_ip() {
      log_info "正在检测公网 IP..." >&2
      curl -s --max-time 10 https://ipinfo.io/ip || curl -s --max-time 10 https://api.ipify.org || echo ""
    }
    SERVER_IP=$(get_public_ip)
    read -r -p "检测到服务器 IP [${SERVER_IP}]，回车确认或手动输入: " INPUT_IP
    SERVER_IP=${INPUT_IP:-$SERVER_IP}

    # 设置端口
    read -r -p "请输入监听端口 [1024-65535] (回车则随机生成): " PORT
    [ -z "$PORT" ] && PORT=$(shuf -i 20000-60000 -n 1)

    # ★★ 修改点: 输入密码时可见 ★★
    read -r -p "请输入连接密码 [建议12位以上] (回车则随机生成): " PASSWORD
    if [ -z "$PASSWORD" ]; then
      PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
      log_info "已随机生成密码: ${PASSWORD}"
    fi

    fetch_latest_info
    LATEST_VERSION=${LATEST_VERSION_TAG#v}
    log_info "将要安装的版本: v${LATEST_VERSION}"

    # 下载并安装
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    log_info "正在下载文件..."
    wget -q --show-progress "${DOWNLOAD_URL}" -O anytls.zip
    unzip -o anytls.zip > /dev/null
    install -m 755 anytls-server "${BINARY_PATH}"
    cd /

    # 创建用户和配置文件
    if ! id "anytls" &>/dev/null; then useradd -r -s /usr/sbin/nologin -d /dev/null anytls; fi
    mkdir -p "${CONFIG_DIR}"
    echo "${LATEST_VERSION}" > "${VERSION_FILE}"

    # 创建 systemd 服务
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=AnyTLS-Go Server
Documentation=https://github.com/anytls/anytls-go
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=anytls
Group=anytls
ExecStart=${BINARY_PATH} -l 0.0.0.0:${PORT} -p ${PASSWORD}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable --now ${SERVICE_NAME}
    sleep 2

    # 显示结果
    echo ""
    log_info "✅ AnyTLS 安装并启动成功！"
    echo "=================================================="
    echo "  服务器 IP     : ${SERVER_IP}"
    echo "  监听端口      : ${PORT}"
    echo "  连接密码      : ${PASSWORD}"
    echo "  当前版本      : v${LATEST_VERSION}"
    echo "--------------------------------------------------"
    systemctl status ${SERVICE_NAME} --no-pager | grep "Active:"
    echo "=================================================="
}

# --- 主菜单 ---
main_menu() {
    clear
    echo "========================================"
    echo "  AnyTLS-Go 服务端管理脚本 (v4)      "
    echo "========================================"
    echo
    echo "  1. 安装 AnyTLS"
    echo "  2. 更新 AnyTLS"
    echo "  3. 卸载 AnyTLS"
    echo
    echo "  4. 退出脚本"
    echo
    echo "----------------------------------------"
    read -r -p "请输入选项 [1-4]: " choice

    case $choice in
        1) install_anytls ;;
        2) update_anytls ;;
        3) uninstall_anytls ;;
        4) exit 0 ;;
        *) log_error "无效的选项，请输入 1-4 之间的数字。" ;;
    esac
}

# --- 脚本入口 ---
main_menu
