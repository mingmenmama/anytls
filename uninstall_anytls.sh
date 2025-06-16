#!/bin/bash
#
# AnyTLS-Go 服务端一键卸载脚本
#
# 功能:
# - 停止并禁用 systemd 服务
# - 删除 systemd 服务文件
# - 删除 anytls-server 二进制文件
# - 删除为服务创建的 'anytls' 用户
# - 自动检查 root 权限

# --- 全局设置 ---
# 如果命令失败，立即退出脚本
set -e

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

# --- 主逻辑开始 ---

# 1. 权限检查
if [ "$(id -u)" -ne 0 ]; then
    log_error "此脚本需要以 root 用户权限运行。"
fi

log_info "开始卸载 AnyTLS-Go..."
echo "--------------------------------------------------"

# 2. 停止并禁用 systemd 服务
SERVICE_NAME="anytls.service"
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
    log_info "正在停止 AnyTLS 服务..."
    systemctl stop anytls
    log_info "正在禁用 AnyTLS 服务开机自启..."
    systemctl disable anytls
else
    log_warn "未找到 ${SERVICE_NAME}，跳过服务停止和禁用步骤。"
fi

# 3. 删除 systemd 服务文件
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
if [ -f "${SERVICE_FILE}" ]; then
    log_info "正在删除 systemd 服务文件: ${SERVICE_FILE}"
    rm -f "${SERVICE_FILE}"
    log_info "正在重载 systemd 配置..."
    systemctl daemon-reload
else
    log_warn "未找到服务文件 ${SERVICE_FILE}，跳过删除。"
fi

# 4. 删除二进制文件
BINARY_FILE="/usr/local/bin/anytls-server"
if [ -f "${BINARY_FILE}" ]; then
    log_info "正在删除二进制文件: ${BINARY_FILE}"
    rm -f "${BINARY_FILE}"
else
    log_warn "未找到二进制文件 ${BINARY_FILE}，跳过删除。"
fi

# 5. 删除专用用户
USER_NAME="anytls"
if id "${USER_NAME}" &>/dev/null; then
    log_info "正在删除专用用户: ${USER_NAME}"
    userdel "${USER_NAME}"
else
    log_warn "未找到用户 ${USER_NAME}，跳过删除。"
fi

echo "--------------------------------------------------"
log_info "✅ AnyTLS-Go 卸载完成！"
echo ""

exit 0
