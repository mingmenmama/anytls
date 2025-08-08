#!/bin/bash
#
# AnyTLS-Go 服务端一键卸载脚本 (v4.0.0)
#
# 功能:
# - 停止并禁用 systemd 服务
# - 删除 systemd 服务文件
# - 删除 anytls-server 二进制文件
# - 删除为服务创建的 'anytls' 用户
# - 清理防火墙规则
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

# 检测操作系统类型
detect_os() {
  log_info "正在检测操作系统类型..."
  
  # 检测是否为 Alpine
  if [ -f /etc/alpine-release ]; then
    OS_TYPE="alpine"
    return
  fi
  
  # 检测是否存在 /etc/os-release 文件
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    
    case "$OS_ID" in
      "ubuntu"|"debian")
        OS_TYPE="debian"
        ;;
      "centos"|"rocky"|"almalinux"|"rhel"|"fedora")
        OS_TYPE="rhel"
        ;;
      *)
        OS_TYPE="unknown"
        ;;
    esac
  else
    # 尝试其他检测方法
    if [ -f /etc/redhat-release ]; then
      OS_TYPE="rhel"
    else
      OS_TYPE="unknown"
    fi
  fi
  
  log_info "检测到操作系统类型: ${OS_TYPE}"
}

# 清理防火墙规则
cleanup_firewall() {
  log_info "正在清理防火墙规则..."
  
  # 获取端口号
  PORT=$(grep -oP 'ExecStart=.*?-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/anytls.service 2>/dev/null || echo "")
  
  if [ -z "$PORT" ]; then
    log_warn "无法确定端口号，跳过防火墙清理"
    return
  fi
  
  case "$OS_TYPE" in
    "debian")
      if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        log_info "正在从 UFW 中删除规则..."
        ufw delete allow "$PORT/tcp" || true
      fi
      ;;
    "rhel")
      if command -v firewall-cmd &>/dev/null && firewall-cmd --state | grep -q "running"; then
        log_info "正在从 firewalld 中删除规则..."
        firewall-cmd --permanent --remove-port="$PORT/tcp" || true
        firewall-cmd --reload || true
      fi
      ;;
    "alpine")
      log_info "尝试清理 iptables 规则..."
      if command -v iptables &>/dev/null; then
        iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
        # 保存规则以便持久化
        if [ -d /etc/iptables ]; then
          iptables-save > /etc/iptables/rules.v4 || true
        fi
      fi
      ;;
    *)
      log_warn "未识别的操作系统类型，跳过防火墙清理"
      ;;
  esac
}

# 清理 TLS 证书
cleanup_tls() {
  log_info "检查是否使用了 Let's Encrypt 证书..."
  
  # 检查服务文件中是否包含证书配置
  if [ -f /etc/systemd/system/anytls.service ] && grep -q "\-\-cert" /etc/systemd/system/anytls.service; then
    DOMAIN=$(grep -oP 'ExecStart=.*?--cert\s+/etc/letsencrypt/live/\K[^/]+' /etc/systemd/system/anytls.service || echo "")
    
    if [ -n "$DOMAIN" ]; then
      log_info "检测到域名: ${DOMAIN}"
      read -r -p "是否要删除 Let's Encrypt 证书? (y/n): " delete_cert
      
      if [[ "$delete_cert" =~ ^[Yy]$ ]]; then
        if command -v certbot &>/dev/null; then
          log_info "正在删除证书..."
          certbot delete --cert-name "$DOMAIN" || true
        else
          log_warn "未找到 certbot 命令，无法删除证书"
        fi
      else
        log_info "保留证书，以便将来使用"
      fi
    fi
  else
    log_info "未检测到使用 Let's Encrypt 证书"
  fi
}

# --- 主逻辑开始 ---

# 显示欢迎信息
echo "=================================================="
echo "     AnyTLS-Go 一键卸载脚本 v4.0.0"
echo "=================================================="

# 1. 权限检查
if [ "$(id -u)" -ne 0 ]; then
    log_error "此脚本需要以 root 用户权限运行"
fi

# 2. 确认卸载
read -r -p "确定要卸载 AnyTLS-Go 吗? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "已取消卸载"
    exit 0
fi

# 3. 检测操作系统
detect_os

log_info "开始卸载 AnyTLS-Go..."
echo "--------------------------------------------------"

# 4. 清理 TLS 证书
cleanup_tls

# 5. 停止并禁用 systemd 服务
SERVICE_NAME="anytls.service"
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
    log_info "正在停止 AnyTLS 服务..."
    systemctl stop anytls || true
    log_info "正在禁用 AnyTLS 服务开机自启..."
    systemctl disable anytls || true
else
    log_warn "未找到 ${SERVICE_NAME}，跳过服务停止和禁用步骤"
fi

# 6. 清理防火墙规则
cleanup_firewall

# 7. 删除 systemd 服务文件
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
if [ -f "${SERVICE_FILE}" ]; then
    log_info "正在删除 systemd 服务文件: ${SERVICE_FILE}"
    rm -f "${SERVICE_FILE}"
    log_info "正在重载 systemd 配置..."
    systemctl daemon-reload
else
    log_warn "未找到服务文件 ${SERVICE_FILE}，跳过删除"
fi

# 8. 删除二进制文件
BINARY_FILE="/usr/local/bin/anytls-server"
if [ -f "${BINARY_FILE}" ]; then
    log_info "正在删除二进制文件: ${BINARY_FILE}"
    rm -f "${BINARY_FILE}"
else
    log_warn "未找到二进制文件 ${BINARY_FILE}，跳过删除"
fi

# 9. 删除专用用户
USER_NAME="anytls"
if id "${USER_NAME}" &>/dev/null; then
    log_info "正在删除专用用户: ${USER_NAME}"
    userdel "${USER_NAME}" || true
else
    log_warn "未找到用户 ${USER_NAME}，跳过删除"
fi

echo "--------------------------------------------------"
log_info "✅ AnyTLS-Go 卸载完成！"
echo ""

exit 0
