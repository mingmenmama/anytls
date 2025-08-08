#!/bin/bash
#
# AnyTLS-Go 服务端一键更新脚本 (v4.0.0)
#
# 功能:
# - 保留现有配置
# - 下载并安装最新版本
# - 自动重启服务

# --- 全局设置 ---
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
  if [ -n "${TEMP_DIR-}" ] && [ -d "${TEMP_DIR}" ]; then
    log_info "执行清理操作，删除临时目录 ${TEMP_DIR}"
    rm -rf "${TEMP_DIR}"
  fi
}
trap cleanup EXIT INT TERM

# --- 主逻辑开始 ---

# 显示欢迎信息
echo "=================================================="
echo "     AnyTLS-Go 一键更新脚本 v4.0.0"
echo "=================================================="

# 1. 权限检查
if [ "$(id -u)" -ne 0 ]; then
  log_error "此脚本需要以 root 用户权限运行"
fi

# 2. 检查服务是否已安装
if [ ! -f "/usr/local/bin/anytls-server" ]; then
  log_error "未检测到 AnyTLS-Go 的安装，请先安装"
fi

# 3. 备份当前配置
if [ -f "/etc/systemd/system/anytls.service" ]; then
  log_info "备份当前配置..."
  # 提取服务配置
  CURRENT_CMD=$(grep "ExecStart=" /etc/systemd/system/anytls.service | sed 's/ExecStart=//')
  
  # 解析配置参数
  CURRENT_PORT=$(echo "$CURRENT_CMD" | grep -oP '\-l\s+0.0.0.0:\K[0-9]+' || echo "")
  CURRENT_PASSWORD=$(echo "$CURRENT_CMD" | grep -oP '\-p\s+\K[^ ]+' || echo "")
  CURRENT_TLS_PARAMS=$(echo "$CURRENT_CMD" | grep -oP '(--cert\s+[^ ]+\s+--key\s+[^ ]+)' || echo "")
  
  # 如果找不到配置，询问用户
  if [ -z "$CURRENT_PORT" ]; then
    read -r -p "无法检测到当前端口，请手动输入当前使用的端口: " CURRENT_PORT
    [ -z "$CURRENT_PORT" ] && log_error "未提供端口，更新终止"
  fi
  if [ -z "$CURRENT_PASSWORD" ]; then
    read -r -sp "无法检测到当前密码，请手动输入当前使用的密码: " CURRENT_PASSWORD
    [ -z "$CURRENT_PASSWORD" ] && log_error "未提供密码，更新终止"
    echo
  fi
else
  log_error "未找到 AnyTLS 服务配置文件，无法更新"
fi

# 4. 停止服务
log_info "停止 AnyTLS 服务..."
systemctl stop anytls

# 5. 检测架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64 | amd64) ARCH_TAG="linux_amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
  *) log_error
