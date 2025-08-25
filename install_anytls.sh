#!/bin/bash
#
# AnyTLS-Go 服务端一键安装脚本 (v4.0.0 - 全面增强版)
#
# 功能:
# - 支持更多系统: Ubuntu/Debian/CentOS/RHEL/Alpine
# - 自动识别系统架构 (amd64, arm64)
# - 自动从 GitHub API 获取最新版本
# - 支持自定义端口和密码
# - 支持 Let's Encrypt 证书集成
# - 自动配置防火墙规则
# - 创建专用的非 root 用户运行服务
# - 注册 systemd 服务并设置开机自启
# - 提供二维码输出连接信息
# - 提供更新和状态监控功能

# --- 版本信息 ---
SCRIPT_VERSION="4.0.0"
SCRIPT_DATE="2025-08-08"

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
log_debug() {
  if [ "${DEBUG_MODE}" = "true" ]; then
    echo -e "\033[36m[DEBUG]\033[0m $1"
  fi
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

# 检查端口是否可用
check_port_available() {
  local port=$1
  
  log_debug "检查端口 ${port} 是否可用..."
  
  # 使用不同命令检查端口，确保兼容不同系统
  if command -v lsof &>/dev/null; then
    if lsof -i:${port} &>/dev/null; then
      log_debug "端口 ${port} 被占用 (lsof 检测)"
      return 1 # 端口被占用
    fi
  elif command -v netstat &>/dev/null; then
    if netstat -tuln | grep -q ":${port} "; then
      log_debug "端口 ${port} 被占用 (netstat 检测)"
      return 1 # 端口被占用
    fi
  elif command -v ss &>/dev/null; then
    if ss -tuln | grep -q ":${port} "; then
      log_debug "端口 ${port} 被占用 (ss 检测)"
      return 1 # 端口被占用
    fi
  else
    log_warn "未找到 lsof、netstat 或 ss 命令，无法可靠检查端口状态"
    # 尝试使用更基本的方法检查
    if ! (echo > /dev/tcp/127.0.0.1/${port}) 2>/dev/null; then
      log_debug "端口 ${port} 可能可用 (基本检测)"
      return 0 # 可能可用
    else
      log_debug "端口 ${port} 可能被占用 (基本检测)"
      return 1 # 可能被占用
    fi
  fi
  
  log_debug "端口 ${port} 可用"
  return 0 # 端口可用
}

# 查找可用端口
find_available_port() {
  log_info "正在查找可用端口..."
  
  # 从随机范围内查找可用端口
  local attempts=0
  local max_attempts=10
  local port
  
  while [ $attempts -lt $max_attempts ]; do
    port=$(shuf -i 20000-60000 -n 1)
    if check_port_available $port; then
      log_info "找到可用端口: ${port}"
      echo $port
      return 0
    fi
    attempts=$((attempts + 1))
  done
  
  log_error "无法找到可用端口，请手动指定一个未被使用的端口"
}

# 获取并处理占用端口的进程信息
get_port_process_info() {
  local port=$1
  local process_info=""
  
  if command -v lsof &>/dev/null; then
    process_info=$(lsof -i:${port} | tail -n +2)
  elif command -v netstat &>/dev/null; then
    process_info=$(netstat -tulnp 2>/dev/null | grep ":${port} ")
  elif command -v ss &>/dev/null; then
    process_info=$(ss -tulnp | grep ":${port} ")
  fi
  
  echo "$process_info"
}

# 尝试释放被占用的端口
try_release_port() {
  local port=$1
  local force=$2
  
  log_info "尝试释放端口 ${port}..."
  
  # 获取占用端口的进程 PID
  local pid=""
  
  if command -v lsof &>/dev/null; then
    pid=$(lsof -t -i:${port} 2>/dev/null | head -n 1)
  elif command -v netstat &>/dev/null; then
    pid=$(netstat -tulnp 2>/dev/null | grep ":${port} " | awk '{print $7}' | cut -d/ -f1 | head -n 1)
  elif command -v ss &>/dev/null; then
    pid=$(ss -tulnp | grep ":${port} " | grep -oP 'pid=\K\d+' | head -n 1)
  fi
  
  if [ -n "$pid" ]; then
    log_info "找到占用端口 ${port} 的进程 PID: ${pid}"
    
    # 获取进程名称以供确认
    local process_name=$(ps -p $pid -o comm= 2>/dev/null || echo "未知进程")
    
    if [ "$force" != "force" ]; then
      read -r -p "确认终止进程 ${process_name} (PID: ${pid})? (y/n): " confirm
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "已取消终止进程"
        return 1
      fi
    fi
    
    log_info "正在终止进程 ${process_name} (PID: ${pid})..."
    kill -15 $pid 2>/dev/null
    
    # 等待进程终止
    sleep 2
    
    # 检查进程是否仍在运行
    if kill -0 $pid 2>/dev/null; then
      log_warn "进程未响应正常终止信号，尝试强制终止..."
      kill -9 $pid 2>/dev/null
      sleep 1
    fi
    
    # 再次检查端口是否已释放
    if check_port_available $port; then
      log_info "成功释放端口 ${port}"
      return 0
    else
      log_warn "无法释放端口 ${port}，可能需要手动处理"
      return 1
    fi
  else
    log_warn "无法找到占用端口 ${port} 的进程"
    return 1
  fi
}

# 处理端口冲突
handle_port_conflict() {
  local port=$1
  
  # 显示占用端口的进程信息
  log_warn "端口 ${port} 已被占用!"
  echo "占用端口的进程信息:"
  local process_info=$(get_port_process_info $port)
  
  if [ -n "$process_info" ]; then
    echo "$process_info"
  else
    echo "无法获取占用端口的进程信息"
  fi
  
  echo ""
  echo "请选择操作:"
  echo "1) 尝试释放端口 (终止占用进程)"
  echo "2) 使用其他可用端口"
  echo "3) 手动指定新端口"
  
  read -r -p "请选择 [1-3]: " port_action
  
  case $port_action in
    1)
      if try_release_port $port; then
        echo $port
      else
        # 如果无法释放端口，提示使用其他端口
        echo "无法释放端口，将使用其他可用端口"
        local new_port=$(find_available_port)
        echo $new_port
      fi
      ;;
    2)
      local new_port=$(find_available_port)
      echo $new_port
      ;;
    3)
      local valid_port=0
      while [ $valid_port -eq 0 ]; do
        read -r -p "请输入新端口 [1024-65535]: " manual_port
        
        # 验证输入是否为数字
        if [[ ! "$manual_port" =~ ^[0-9]+$ ]]; then
          echo "请输入有效的数字端口"
          continue
        fi
        
        # 验证端口范围
        if [ $manual_port -lt 1024 ] || [ $manual_port -gt 65535 ]; then
          echo "端口必须在 1024-65535 范围内"
          continue
        fi
        
        # 检查端口是否可用
        if ! check_port_available $manual_port; then
          echo "端口 ${manual_port} 也被占用，请选择其他端口"
          continue
        fi
        
        valid_port=1
      done
      
      echo $manual_port
      ;;
    *)
      log_warn "无效的选择，将使用其他可用端口"
      local new_port=$(find_available_port)
      echo $new_port
      ;;
  esac
}

# 更新现有服务的端口
update_service_port() {
  local old_port=$1
  local new_port=$2
  
  if [ -f "/etc/systemd/system/anytls.service" ]; then
    log_info "更新服务配置，端口从 ${old_port} 改为 ${new_port}..."
    
    # 提取现有配置
    local current_password=$(grep -oP 'ExecStart=.*?-p\s+\K[^ ]+' /etc/systemd/system/anytls.service || echo "")
    local current_tls_params=$(grep -oP 'ExecStart=.*?(--cert.*?)($|\s)' /etc/systemd/system/anytls.service || echo "")
    
    # 更新服务文件
    sed -i "s|ExecStart=.*|ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:${new_port} -p ${current_password} ${current_tls_params}|" /etc/systemd/system/anytls.service
    
    # 重载配置
    systemctl daemon-reload
    
    # 尝试重启服务
    if systemctl is-active --quiet anytls; then
      log_info "正在重启服务..."
      systemctl restart anytls
    fi
    
    log_info "服务配置已更新"
    return 0
  else
    log_warn "未找到服务配置文件，无法更新"
    return 1
  fi
}

# 检测操作系统类型和版本
detect_os() {
  log_info "正在检测操作系统..."
  
  # 检测是否为 Alpine
  if [ -f /etc/alpine-release ]; then
    OS_TYPE="alpine"
    OS_VERSION=$(cat /etc/alpine-release | cut -d. -f1,2)
    log_info "检测到 Alpine Linux ${OS_VERSION}"
    return
  fi
  
  # 检测是否存在 /etc/os-release 文件
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_VERSION_ID=$VERSION_ID
    
    case "$OS_ID" in
      "ubuntu")
        OS_TYPE="debian"
        if [ "$(echo "$OS_VERSION_ID" | cut -d. -f1)" -lt 20 ]; then
          log_warn "检测到 Ubuntu ${OS_VERSION_ID}，建议使用 Ubuntu 20.04 或更高版本"
        fi
        log_info "检测到 Ubuntu ${OS_VERSION_ID}"
        ;;
      "debian")
        OS_TYPE="debian"
        if [ "$(echo "$OS_VERSION_ID" | cut -d. -f1)" -lt 11 ]; then
          log_warn "检测到 Debian ${OS_VERSION_ID}，建议使用 Debian 11 或更高版本"
        fi
        log_info "检测到 Debian ${OS_VERSION_ID}"
        ;;
      "centos")
        OS_TYPE="rhel"
        log_info "检测到 CentOS ${OS_VERSION_ID}"
        ;;
      "rocky" | "almalinux")
        OS_TYPE="rhel"
        log_info "检测到 ${OS_ID^} ${OS_VERSION_ID}"
        ;;
      "rhel" | "fedora")
        OS_TYPE="rhel"
        log_info "检测到 ${OS_ID^} ${OS_VERSION_ID}"
        ;;
      *)
        OS_TYPE="unknown"
        log_warn "未能明确识别操作系统类型: ${OS_ID} ${OS_VERSION_ID}，将尝试通用安装方法"
        ;;
    esac
  else
    # 尝试其他检测方法
    if [ -f /etc/redhat-release ]; then
      OS_TYPE="rhel"
      OS_VERSION_ID=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -n1)
      log_info "检测到 Red Hat 系列发行版 ${OS_VERSION_ID}"
    else
      OS_TYPE="unknown"
      log_warn "无法确定操作系统类型，将尝试通用安装方法"
    fi
  fi
}

# 自动检测包管理器并安装依赖
install_dependencies() {
  log_info "正在安装必要依赖..."
  
  case "$OS_TYPE" in
    "debian")
      log_info "使用 apt 安装依赖..."
      apt-get update -y
      apt-get install -y curl wget unzip git ufw qrencode
      ;;
    "rhel")
      log_info "使用 yum/dnf 安装依赖..."
      if command -v dnf &>/dev/null; then
        dnf install -y curl wget unzip git firewalld qrencode
      else
        yum install -y curl wget unzip git firewalld qrencode
      fi
      ;;
    "alpine")
      log_info "使用 apk 安装依赖..."
      apk update
      apk add curl wget unzip git iptables qrencode
      ;;
    *)
      log_warn "未检测到支持的包管理器，尝试安装基本依赖..."
      # 尝试几种常见的包管理器
      if command -v apt-get &>/dev/null; then
        apt-get update -y
        apt-get install -y curl wget unzip git qrencode
      elif command -v dnf &>/dev/null; then
        dnf install -y curl wget unzip git qrencode
      elif command -v yum &>/dev/null; then
        yum install -y curl wget unzip git qrencode
      elif command -v apk &>/dev/null; then
        apk update
        apk add curl wget unzip git qrencode
      else
        log_error "未检测到支持的包管理器 (apt/dnf/yum/apk)，请手动安装依赖"
      fi
      ;;
  esac
  
  # 检查是否安装成功
  for cmd in curl wget unzip git; do
    if ! command -v $cmd &>/dev/null; then
      log_error "安装 $cmd 失败，请检查网络连接或手动安装"
    fi
  done
  
  log_info "依赖安装完成"
}

# 配置防火墙
configure_firewall() {
  log_info "正在配置防火墙，开放端口 ${PORT}..."
  
  case "$OS_TYPE" in
    "debian")
      # 检查 UFW 是否已安装
      if command -v ufw &>/dev/null; then
        ufw allow "$PORT/tcp" comment "AnyTLS"
        if ! ufw status | grep -q "active"; then
          log_info "防火墙未启用，正在启用 UFW..."
          ufw --force enable
        fi
        log_info "UFW 防火墙规则已添加"
      else
        log_warn "未检测到 UFW，尝试使用 iptables..."
        iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
        log_info "已使用 iptables 添加防火墙规则，但系统重启后可能失效"
      fi
      ;;
    "rhel")
      # 检查 firewalld 是否已安装
      if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --zone=public --add-port="$PORT/tcp" --permanent
        firewall-cmd --reload
        log_info "Firewalld 防火墙规则已添加"
      else
        log_warn "未检测到 firewalld，尝试使用 iptables..."
        iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
        log_info "已使用 iptables 添加防火墙规则，但系统重启后可能失效"
      fi
      ;;
    "alpine")
      # Alpine 使用 iptables
      if command -v iptables &>/dev/null; then
        iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
        # 保存规则以便持久化
        if [ -d /etc/iptables ]; then
          iptables-save > /etc/iptables/rules.v4
          log_info "已保存 iptables 规则"
        else
          log_warn "iptables 规则已添加，但系统重启后可能失效"
        fi
      else
        log_warn "未检测到 iptables，跳过防火墙配置"
      fi
      ;;
    *)
      log_warn "未识别的操作系统类型，跳过防火墙配置"
      ;;
  esac
}

# 使用外部服务获取公网 IP
get_public_ip() {
  # 日志输出到 stderr(2)，避免被命令替换 `$(...)` 捕获
  log_info "正在检测公网 IP..." >&2
  # 依次尝试多个可靠的 IP 查询服务
  curl -s --max-time 10 https://ipinfo.io/ip || \
  curl -s --max-time 10 https://api.ipify.org || \
  curl -s --max-time 10 https://icanhazip.com || \
  curl -s --max-time 10 https://ifconfig.me || \
  echo ""
}

check_for_updates() {
  log_info "已禁用自动更新功能，始终使用当前脚本版本: $SCRIPT_VERSION"
}



# 生成二维码
generate_qrcode() {
  local content="$1"
  local title="$2"
  
  if command -v qrencode &>/dev/null; then
    echo -e "\n$title:"
    qrencode -t ANSIUTF8 "$content"
    log_info "扫描上方二维码快速导入配置"
  else
    log_warn "未安装 qrencode，跳过二维码生成"
  fi
}

# 生成连接字符串
generate_connection_string() {
  local protocol="$1"
  local ip="$2"
  local port="$3"
  local password="$4"
  
  # 使用 URL 编码处理密码中的特殊字符
  local encoded_password=$(echo -n "$password" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
  
  # 返回格式化的连接字符串
  echo "${protocol}://${encoded_password}@${ip}:${port}"
}

# 检查客户端工具是否支持 TLS 证书
install_and_configure_certbot() {
  log_info "正在配置 Let's Encrypt 证书..."
  
  # 确认域名信息
  read -r -p "请输入您的域名 (例如: example.com): " DOMAIN_NAME
  if [ -z "$DOMAIN_NAME" ]; then
    log_warn "未提供域名，跳过证书配置"
    return 1
  fi
  
  # 安装 certbot
  case "$OS_TYPE" in
    "debian")
      apt-get update
      apt-get install -y certbot
      ;;
    "rhel")
      if command -v dnf &>/dev/null; then
        dnf install -y certbot
      else
        yum install -y certbot
      fi
      ;;
    "alpine")
      apk add certbot
      ;;
    *)
      log_error "未支持的操作系统类型，无法安装 certbot"
      return 1
      ;;
  esac
  
  # 获取证书
  log_info "正在申请 Let's Encrypt 证书..."
  
  # 停止可能占用 80 端口的服务
  systemctl stop anytls 2>/dev/null || true
  
  certbot certonly --standalone --preferred-challenges http \
    --agree-tos --no-eff-email \
    -d "$DOMAIN_NAME" -m "admin@${DOMAIN_NAME}" \
    --keep-until-expiring
  
  # 检查证书是否获取成功
  if [ -d "/etc/letsencrypt/live/${DOMAIN_NAME}" ]; then
    log_info "证书获取成功!"
    
    # 配置证书路径
    CERT_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem"
    
    # 设置 certbot 自动续期的 hook
    mkdir -p /etc/letsencrypt/renewal-hooks/post
    cat > /etc/letsencrypt/renewal-hooks/post/anytls-reload.sh <<EOF
#!/bin/bash
systemctl restart anytls
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/post/anytls-reload.sh
    
    # 修改 anytls 的权限，使其可以读取证书
    usermod -a -G ssl-cert anytls 2>/dev/null || true
    
    # 返回证书路径
    echo "$CERT_PATH:$KEY_PATH:$DOMAIN_NAME"
    return 0
  else
    log_error "证书申请失败，请检查域名是否正确指向此服务器，以及 80 端口是否被占用"
    return 1
  fi
}

# 显示使用说明
show_help() {
  echo "AnyTLS-Go 一键安装脚本 v${SCRIPT_VERSION}"
  echo ""
  echo "用法: $0 [选项]"
  echo ""
  echo "选项:"
  echo "  -h, --help        显示此帮助信息"
  echo "  -p, --port PORT   指定监听端口"
  echo "  -pw, --password PASS  指定连接密码"
  echo "  -i, --ip IP       指定服务器 IP"
  echo "  --tls             配置 Let's Encrypt TLS 证书"
  echo "  --no-firewall     跳过防火墙配置"
  echo "  --no-update-check 跳过版本更新检查"
  echo "  --check-status    只检查 anytls 服务状态"
  echo "  --update          更新现有安装"
  echo "  --debug           启用调试模式"
  echo ""
  echo "例子:"
  echo "  $0 --port 8443 --password mysecretpassword"
  echo "  $0 --tls --ip mydomain.com"
  echo "  $0 --update"
  echo ""
  exit 0
}

# 显示交互式菜单
show_menu() {
  clear
  echo "================ AnyTLS-Go 管理菜单 ================"
  echo "1) 安装 AnyTLS-Go"
  echo "2) 更新 AnyTLS-Go"
  echo "3) 卸载 AnyTLS-Go"
  echo "4) 查看服务状态"
  echo "5) 查看连接信息"
  echo "6) 配置 Let's Encrypt 证书"
  echo "7) 配置防火墙"
  echo "8) 查看日志"
  echo "9) 故障排除向导"
  echo "0) 退出"
  echo "==================================================="
  
  read -r -p "请选择操作 [0-9]: " menu_choice
  
  case $menu_choice in
    1) # 继续执行安装流程
       ;;
    2) perform_update
       exit 0
       ;;
    3) perform_uninstall
       exit 0
       ;;
    4) check_service_status
       exit 0
       ;;
    5) show_connection_info
       exit 0
       ;;
    6) configure_tls_certificate
       exit 0
       ;;
    7) configure_firewall_interactive
       exit 0
       ;;
    8) view_logs
       exit 0
       ;;
    9) troubleshoot_wizard
       exit 0
       ;;
    0) log_info "已取消操作"
       exit 0
       ;;
    *) log_warn "无效的选择，继续安装流程"
       ;;
  esac
}

# 更新功能
perform_update() {
  log_info "正在更新 AnyTLS-Go..."
  
  # 检查服务是否已安装
  if [ ! -f "/usr/local/bin/anytls-server" ]; then
    log_error "未检测到 AnyTLS-Go 的安装，请先安装"
  fi
  
  # 备份当前配置
  if [ -f "/etc/systemd/system/anytls.service" ]; then
    log_info "备份当前配置..."
    CURRENT_PORT=$(grep -oP 'ExecStart=.*?-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/anytls.service || echo "")
    CURRENT_PASSWORD=$(grep -oP 'ExecStart=.*?-p\s+\K[^ ]+' /etc/systemd/system/anytls.service || echo "")
    CURRENT_TLS_PARAMS=$(grep -oP 'ExecStart=.*?(--cert.*?)($|\s)' /etc/systemd/system/anytls.service || echo "")
    
    # 如果找不到配置，询问用户
    if [ -z "$CURRENT_PORT" ]; then
      read -r -p "无法检测到当前端口，请手动输入当前使用的端口: " CURRENT_PORT
    fi
    if [ -z "$CURRENT_PASSWORD" ]; then
      read -r -sp "无法检测到当前密码，请手动输入当前使用的密码: " CURRENT_PASSWORD
      echo
    fi
  else
    log_error "未找到 AnyTLS 服务配置文件，无法更新"
  fi
  
  # 停止服务
  log_info "停止 AnyTLS 服务..."
  systemctl stop anytls
  
  # 下载新版本
  API_URL="https://api.github.com/repos/anytls/anytls-go/releases/latest"
  API_RESPONSE=$(curl -sL --connect-timeout 10 --max-time 20 "${API_URL}")
  
  if [ -z "${API_RESPONSE}" ]; then
    log_error "从 GitHub API 获取响应失败，请检查网络连接"
  fi
  
  # 检测架构
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64 | amd64) ARCH_TAG="linux_amd64" ;;
    aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
    *) log_error "不支持的系统架构: ${ARCH}" ;;
  esac
  
  DOWNLOAD_URL=$(echo "${API_RESPONSE}" | \
    grep "browser_download_url" | \
    grep "${ARCH_TAG}" | \
    grep "\.zip\"" | \
    cut -d'"' -f4 | \
    head -n 1)
  
  if [ -z "${DOWNLOAD_URL}" ]; then
    VERSION_TAG=$(echo "${API_RESPONSE}" | grep -oE '"tag_name":\s*".*?"' | cut -d'"' -f4)
    log_error "在版本 [${VERSION_TAG:-未知}] 中未能找到适配 [${ARCH_TAG}] 的下载文件"
  fi
  
  VERSION=$(echo "${DOWNLOAD_URL}" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
  log_info "成功定位到最新版本 v${VERSION}"
  
  # 下载并安装
  TEMP_DIR=$(mktemp -d)
  cd "${TEMP_DIR}"
  
  log_info "正在下载文件..."
  wget -q --show-progress "${DOWNLOAD_URL}" -O anytls.zip
  log_info "下载完成，正在解压..."
  unzip -o anytls.zip > /dev/null
  
  log_info "正在更新二进制文件..."
  install -m 755 anytls-server /usr/local/bin/anytls-server
  cd / # 操作完毕，离开临时目录
  
  # 使用原来的配置启动服务
  log_info "使用原有配置重启服务..."
  
  # 重启服务
  systemctl daemon-reload
  systemctl restart anytls
  
  # 检查服务状态
  sleep 2
  SERVICE_STATUS=$(systemctl is-active anytls)
  
  if [ "${SERVICE_STATUS}" = "active" ]; then
    log_info "✅ AnyTLS-Go 已成功更新到 v${VERSION}!"
  else
    log_error "服务更新后启动失败，请检查日志: journalctl -u anytls -n 50"
  fi
}

# 卸载功能
perform_uninstall() {
  log_info "准备卸载 AnyTLS-Go..."
  read -r -p "确定要卸载 AnyTLS-Go 吗? (y/n): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "已取消卸载"
    return
  fi
  
  # 下载并执行卸载脚本
  wget -O uninstall_anytls.sh https://raw.githubusercontent.com/mingmenmama/anytls/main/uninstall_anytls.sh
  chmod +x uninstall_anytls.sh
  ./uninstall_anytls.sh
  
  # 清理下载的脚本
  rm -f uninstall_anytls.sh
}

# 检查服务状态
check_service_status() {
  if systemctl is-active --quiet anytls; then
    STATUS="运行中"
    STATUS_COLOR="\033[32m" # 绿色
  else
    STATUS="已停止"
    STATUS_COLOR="\033[31m" # 红色
  fi
  
  UPTIME=$(systemctl show anytls -p ActiveEnterTimestamp --value | xargs -I{} date -d {} "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")
  
  echo "=================================================="
  echo "AnyTLS-Go 服务状态:"
  echo "--------------------------------------------------"
  echo -e "状态: ${STATUS_COLOR}${STATUS}\033[0m"
  echo "启动时间: ${UPTIME}"
  echo "--------------------------------------------------"
  
  # 显示资源使用情况
  if systemctl is-active --quiet anytls; then
    PID=$(systemctl show -p MainPID anytls | cut -d= -f2)
    if [ -n "$PID" ] && [ "$PID" -ne 0 ]; then
      echo "资源使用情况:"
      echo "CPU: $(ps -p $PID -o %cpu | tail -n 1)%"
      echo "内存: $(ps -p $PID -o %mem | tail -n 1)%"
      echo "--------------------------------------------------"
    fi
  fi
  
  # 显示最近的日志
  echo "最近的日志条目:"
  journalctl -u anytls -n 5 --no-pager
  echo "--------------------------------------------------"
  echo "完整日志命令: journalctl -u anytls -f --no-pager"
  echo "=================================================="
}

# 显示连接信息
show_connection_info() {
  if [ ! -f "/etc/systemd/system/anytls.service" ]; then
    log_error "未检测到 AnyTLS 服务安装"
  fi
  
  # 提取连接信息
  PORT=$(grep -oP 'ExecStart=.*?-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/anytls.service || echo "未知")
  PASSWORD=$(grep -oP 'ExecStart=.*?-p\s+\K[^ ]+' /etc/systemd/system/anytls.service || echo "未知")
  SERVER_IP=$(curl -s --max-time 10 https://ipinfo.io/ip || echo "未知")
  
  # 检查是否使用了 TLS 证书
  if grep -q "\-\-cert" /etc/systemd/system/anytls.service; then
    DOMAIN=$(grep -oP 'ExecStart=.*?--cert\s+/etc/letsencrypt/live/\K[^/]+' /etc/systemd/system/anytls.service || echo "")
    if [ -n "$DOMAIN" ]; then
      SERVER_IP="$DOMAIN"
    fi
  fi
  
  # 生成连接字符串
  CONNECTION_STRING=$(generate_connection_string "anytls" "$SERVER_IP" "$PORT" "$PASSWORD")
  
  echo "=================================================="
  echo "AnyTLS-Go 连接信息:"
  echo "--------------------------------------------------"
  echo "服务器地址: ${SERVER_IP}"
  echo "端口: ${PORT}"
  echo "密码: ${PASSWORD}"
  echo "--------------------------------------------------"
  echo "连接字符串:"
  echo "${CONNECTION_STRING}"
  echo "--------------------------------------------------"
  
  # 生成二维码
  generate_qrcode "${CONNECTION_STRING}" "连接二维码"
  
  echo "=================================================="
}

# 查看日志
view_logs() {
  echo "正在显示 AnyTLS 服务日志..."
  journalctl -u anytls -f --no-pager
}

# 配置 TLS 证书
configure_tls_certificate() {
  result=$(install_and_configure_certbot)
  if [ $? -eq 0 ]; then
    # 解析返回的证书路径
    CERT_PATH=$(echo "$result" | cut -d: -f1)
    KEY_PATH=$(echo "$result" | cut -d: -f2)
    DOMAIN_NAME=$(echo "$result" | cut -d: -f3)
    
    # 更新服务配置
    log_info "正在更新 AnyTLS 服务配置以使用 TLS 证书..."
    
    # 提取当前端口和密码
    CURRENT_PORT=$(grep -oP 'ExecStart=.*?-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/anytls.service || echo "")
    CURRENT_PASSWORD=$(grep -oP 'ExecStart=.*?-p\s+\K[^ ]+' /etc/systemd/system/anytls.service || echo "")
    
    if [ -z "$CURRENT_PORT" ] || [ -z "$CURRENT_PASSWORD" ]; then
      log_error "无法检测到当前配置，请重新安装"
    fi
    
    # 修改 systemd 服务配置
    sed -i "s|ExecStart=.*|ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:${CURRENT_PORT} -p ${CURRENT_PASSWORD} --cert ${CERT_PATH} --key ${KEY_PATH}|" /etc/systemd/system/anytls.service
    
    # 重启服务
    systemctl daemon-reload
    systemctl restart anytls
    
    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet anytls; then
      log_info "✅ TLS 证书配置成功！服务现在使用域名: ${DOMAIN_NAME}"
    else
      log_error "服务配置后启动失败，请检查日志: journalctl -u anytls -n 50"
    fi
  fi
}

# 配置防火墙（交互模式）
configure_firewall_interactive() {
  log_info "正在配置防火墙..."
  
  PORT=$(grep -oP 'ExecStart=.*?-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/anytls.service || echo "")
  if [ -z "$PORT" ]; then
    read -r -p "请输入需要开放的端口: " PORT
  else
    read -r -p "检测到当前端口为 ${PORT}，是否使用此端口? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
      read -r -p "请输入新的端口: " PORT
    fi
  fi
  
  configure_firewall
  log_info "防火墙配置完成"
}

# 故障排除向导
troubleshoot_wizard() {
  echo "=================================================="
  echo "AnyTLS-Go 故障排除向导"
  echo "=================================================="
  echo "1) 服务无法启动"
  echo "2) 无法连接到服务"
  echo "3) 防火墙问题"
  echo "4) TLS 证书问题"
  echo "5) 性能问题"
  echo "6) 返回主菜单"
  echo "--------------------------------------------------"
  
  read -r -p "请选择问题类型 [1-6]: " problem_type
  
  case $problem_type in
    1) # 服务无法启动
       echo "正在检查服务启动问题..."
       echo "服务状态:"
       systemctl status anytls
       echo "服务日志:"
       journalctl -u anytls -n 30 --no-pager
       
       # 检查端口冲突
       PORT=$(grep -oP 'ExecStart=.*?-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/anytls.service || echo "")
       if [ -n "$PORT" ]; then
         echo ""
         echo "检查端口 ${PORT} 是否被占用:"
         if ! check_port_available "$PORT"; then
           echo -e "\033[31m[错误]\033[0m 端口 ${PORT} 已被占用!"
           
           # 显示占用端口的进程信息
           echo "占用端口的进程信息:"
           process_info=$(get_port_process_info "$PORT")
           if [ -n "$process_info" ]; then
             echo "$process_info"
           else
             echo "无法获取占用端口的进程信息"
           fi
           
           echo ""
           echo "您可以选择:"
           echo "1) 尝试释放端口 (终止占用进程)"
           echo "2) 为 AnyTLS 使用新的端口"
           
           read -r -p "请选择操作 [1-2]: " port_action
           
           case $port_action in
             1)
               if try_release_port "$PORT"; then
                 echo "端口已释放，正在重启服务..."
                 systemctl restart anytls
                 
                 # 检查服务是否成功启动
                 sleep 2
                 if systemctl is-active --quiet anytls; then
                   echo -e "\033[32m[成功]\033[0m 服务已成功重启"
                 else
                   echo -e "\033[31m[错误]\033[0m 服务重启失败，请检查日志"
                   journalctl -u anytls -n 10 --no-pager
                 fi
               fi
               ;;
             2)
               NEW_PORT=$(find_available_port)
               if [ -n "$NEW_PORT" ]; then
                 echo "正在更新服务配置，使用新端口: ${NEW_PORT}..."
                 
                 if update_service_port "$PORT" "$NEW_PORT"; then
                   # 尝试配置防火墙
                   PORT=$NEW_PORT
                   configure_firewall
                   
                   # 检查服务是否成功启动
                   sleep 2
                   if systemctl is-active --quiet anytls; then
                     echo -e "\033[32m[成功]\033[0m 服务已切换到端口 ${NEW_PORT} 并成功启动"
                   else
                     echo -e "\033[31m[错误]\033[0m 服务启动失败，请检查日志"
                     journalctl -u anytls -n 10 --no-pager
                   fi
                 fi
               fi
               ;;
           esac
         else
           echo -e "\033[32m[正常]\033[0m 端口 ${PORT} 未被占用，问题可能在其他地方"
         fi
       else
         echo "无法从服务配置中检测到端口号"
       fi
       
       echo ""
       echo "其他可能的解决方案:"
       echo "1. 检查配置文件权限: ls -la /etc/systemd/system/anytls.service"
       echo "2. 确保 anytls 用户有权限: id anytls"
       echo "3. 检查系统资源是否充足: free -m; df -h"
       echo "4. 尝试重新安装: ./install_anytls.sh --update"
       ;;
    2) # 无法连接到服务
       echo "正在检查连接问题..."
       PORT=$(grep -oP 'ExecStart=.*?-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/anytls.service || echo "未知")
       echo "检查端口是否开放:"
       netstat -tuln | grep $PORT
       echo "检查防火墙状态:"
       if command -v ufw &>/dev/null; then
         ufw status
       elif command -v firewall-cmd &>/dev/null; then
         firewall-cmd --list-all
       fi
       echo ""
       echo "可能的解决方案:"
       echo "1. 确保服务正在运行: systemctl start anytls"
       echo "2. 检查防火墙是否允许端口 $PORT: ufw allow $PORT/tcp 或 firewall-cmd --add-port=$PORT/tcp"
       echo "3. 检查服务器公网 IP 是否正确"
       ;;
    3) # 防火墙问题
       echo "正在配置防火墙..."
       PORT=$(grep -oP 'ExecStart=.*?-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/anytls.service || echo "")
       if [ -z "$PORT" ]; then
         read -r -p "请输入需要开放的端口: " PORT
       fi
       configure_firewall
       echo "防火墙配置完成。"
       ;;
    4) # TLS 证书问题
       echo "正在检查 TLS 证书问题..."
       if grep -q "\-\-cert" /etc/systemd/system/anytls.service; then
         DOMAIN=$(grep -oP 'ExecStart=.*?--cert\s+/etc/letsencrypt/live/\K[^/]+' /etc/systemd/system/anytls.service || echo "")
         echo "当前使用的域名: $DOMAIN"
         echo "证书状态:"
         certbot certificates
         echo ""
         echo "可能的解决方案:"
         echo "1. 尝试续期证书: certbot renew --force-renewal"
         echo "2. 检查证书权限: ls -la /etc/letsencrypt/live/$DOMAIN/"
         echo "3. 重新配置 TLS 证书: ./install_anytls.sh --tls"
       else
         echo "当前未使用 TLS 证书。是否要配置 TLS 证书？(y/n)"
         read -r confirm
         if [[ "$confirm" =~ ^[Yy]$ ]]; then
           configure_tls_certificate
         fi
       fi
       ;;
    5) # 性能问题
       echo "正在检查性能问题..."
       echo "系统资源使用情况:"
       echo "CPU 使用率:"
       top -bn1 | head -n 5
       echo "内存使用情况:"
       free -m
       echo "AnyTLS 资源使用情况:"
       PID=$(systemctl show -p MainPID anytls | cut -d= -f2)
       if [ -n "$PID" ] && [ "$PID" -ne 0 ]; then
         ps -p $PID -o pid,user,%cpu,%mem,cmd
       fi
       echo ""
       echo "可能的解决方案:"
       echo "1. 检查系统负载，考虑升级服务器"
       echo "2. 检查网络带宽使用情况"
       echo "3. 如果客户端连接过多，考虑限制连接数"
       ;;
    6) # 返回主菜单
       show_menu
       ;;
    *) log_warn "无效的选择"
       ;;
  esac
  
  read -r -p "按回车键继续..."
  troubleshoot_wizard
}

# --- 参数解析 ---
# 默认参数
PORT=""
PASSWORD=""
SERVER_IP=""
USE_TLS=false
SKIP_FIREWALL=false
SKIP_UPDATE_CHECK=false
CHECK_STATUS=false
UPDATE_MODE=false
SHOW_MENU_MODE=false
DEBUG_MODE=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      ;;
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    -pw|--password)
      PASSWORD="$2"
      shift 2
      ;;
    -i|--ip)
      SERVER_IP="$2"
      shift 2
      ;;
    --tls)
      USE_TLS=true
      shift
      ;;
    --no-firewall)
      SKIP_FIREWALL=true
      shift
      ;;
    --no-update-check)
      SKIP_UPDATE_CHECK=true
      shift
      ;;
    --check-status)
      CHECK_STATUS=true
      shift
      ;;
    --update)
      UPDATE_MODE=true
      shift
      ;;
    --menu)
      SHOW_MENU_MODE=true
      shift
      ;;
    --debug)
      DEBUG_MODE=true
      shift
      ;;
    *)
      log_warn "未知参数: $1"
      shift
      ;;
  esac
done

# --- 主逻辑开始 ---

# 显示欢迎信息
echo "=================================================="
echo "     AnyTLS-Go 一键安装脚本 v${SCRIPT_VERSION}"
echo "=================================================="

# 如果是状态检查模式，只检查状态后退出
if [ "$CHECK_STATUS" = true ]; then
  check_service_status
  exit 0
fi

# 如果是更新模式，只执行更新后退出
if [ "$UPDATE_MODE" = true ]; then
  perform_update
  exit 0
fi

# 如果是菜单模式，显示交互式菜单
if [ "$SHOW_MENU_MODE" = true ]; then
  show_menu
fi

# 检查更新
if [ "$SKIP_UPDATE_CHECK" != true ]; then
  check_for_updates
fi

# 1. 权限检查
if [ "$(id -u)" -ne 0 ]; then
  log_error "此脚本需要以 root 用户权限运行"
fi

# 2. 检测操作系统
detect_os

# 3. 架构检查
ARCH=$(uname -m)
case "$ARCH" in
  x86_64 | amd64) ARCH_TAG="linux_amd64" ;;
  aarch64 | arm64) ARCH_TAG="linux_arm64" ;;
  *) log_error "不支持的系统架构: ${ARCH}" ;;
esac
log_info "检测到系统架构: ${ARCH} (${ARCH_TAG})"

# 4. 安装依赖
install_dependencies

# 5. 获取并确认服务器 IP
if [ -z "$SERVER_IP" ]; then
  SERVER_IP=$(get_public_ip)
  if [ -z "$SERVER_IP" ]; then
    log_warn "自动获取公网 IP 失败，请手动输入"
    read -r -p "请输入服务器公网 IP 地址: " SERVER_IP
    [ -z "$SERVER_IP" ] && log_error "未提供 IP 地址，脚本终止"
  fi

  read -r -p "检测到服务器 IP 为 [${SERVER_IP}]，是否确认使用此 IP？(Y/n): " confirm_ip
  # 如果用户输入了 'n' 或 'N'
  if [[ "${confirm_ip}" =~ ^[nN]$ ]]; then
    read -r -p "请重新输入服务器公网 IP 地址: " SERVER_IP
    [ -z "$SERVER_IP" ] && log_error "未提供 IP 地址，脚本终止"
  fi
fi
log_info "将使用 IP: ${SERVER_IP}"

# 6. 设置监听端口
if [ -z "$PORT" ]; then
  read -r -p "请输入 AnyTLS 监听端口 [1024-65535] (回车则随机生成): " PORT
  if [ -z "$PORT" ]; then
    # 随机生成端口并确保可用
    PORT=$(find_available_port)
  else
    # 验证输入是否为数字
    if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
      log_warn "无效的端口号，将使用随机端口"
      PORT=$(find_available_port)
    elif [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
      log_warn "端口必须在 1024-65535 范围内，将使用随机端口"
      PORT=$(find_available_port)
    else
      # 检查用户输入的端口是否可用
      if ! check_port_available "$PORT"; then
        # 处理端口冲突
        NEW_PORT=$(handle_port_conflict "$PORT")
        PORT=$NEW_PORT
      fi
    fi
  fi
else
  # 检查命令行提供的端口是否可用
  if ! check_port_available "$PORT"; then
    log_warn "命令行指定的端口 ${PORT} 已被占用"
    NEW_PORT=$(handle_port_conflict "$PORT")
    PORT=$NEW_PORT
  fi
fi

log_info "使用端口: ${PORT}"

# 7. 设置连接密码
if [ -z "$PASSWORD" ]; then
  read -r -sp "请输入 AnyTLS 连接密码 [建议12位以上] (回车则随机生成): " PASSWORD
  echo # read -sp 后需要换行
  if [ -z "$PASSWORD" ]; then
    PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
    log_info "已随机生成密码: ${PASSWORD}"
  else
    log_info "密码已设置"
  fi
fi

# 8. 配置 TLS 证书（如果启用）
TLS_PARAMS=""
if [ "$USE_TLS" = true ]; then
  log_info "正在配置 TLS 证书..."
  result=$(install_and_configure_certbot)
  if [ $? -eq 0 ]; then
    # 解析返回的证书路径
    CERT_PATH=$(echo "$result" | cut -d: -f1)
    KEY_PATH=$(echo "$result" | cut -d: -f2)
    DOMAIN_NAME=$(echo "$result" | cut -d: -f3)
    
    # 更新 IP 为域名
    SERVER_IP="$DOMAIN_NAME"
    
    # 准备 TLS 参数
    TLS_PARAMS="--cert ${CERT_PATH} --key ${KEY_PATH}"
    log_info "TLS 证书配置完成"
  else
    log_warn "TLS 证书配置失败，将使用默认配置继续"
  fi
fi

# 9. 从 GitHub API 获取最新版本信息
log_info "正在从 GitHub 获取最新版本信息..."
API_URL="https://api.github.com/repos/anytls/anytls-go/releases/latest"
API_RESPONSE=$(curl -sL --connect-timeout 10 --max-time 20 "${API_URL}")

if [ -z "${API_RESPONSE}" ]; then
  log_error "从 GitHub API (${API_URL}) 获取响应失败，请检查网络连接"
fi

DOWNLOAD_URL=$(echo "${API_RESPONSE}" | \
  grep "browser_download_url" | \
  grep "${ARCH_TAG}" | \
  grep "\.zip\"" | \
  cut -d'"' -f4 | \
  head -n 1)

if [ -z "${DOWNLOAD_URL}" ]; then
  VERSION_TAG=$(echo "${API_RESPONSE}" | grep -oE '"tag_name":\s*".*?"' | cut -d'"' -f4)
  log_error "在版本 [${VERSION_TAG:-未知}] 中未能找到适配 [${ARCH_TAG}] 的下载文件。请前往 'https://github.com/anytls/anytls-go/releases' 页面确认。"
fi

VERSION=$(echo "${DOWNLOAD_URL}" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
log_info "成功定位到最新版本 v${VERSION}"
log_info "下载链接: ${DOWNLOAD_URL}"

# 10. 下载并安装
TEMP_DIR=$(mktemp -d)
log_info "创建临时工作目录: ${TEMP_DIR}"
cd "${TEMP_DIR}"

log_info "正在下载文件..."
wget -q --show-progress "${DOWNLOAD_URL}" -O anytls.zip
log_info "下载完成，正在解压..."
unzip -o anytls.zip > /dev/null

log_info "正在安装二进制文件到 /usr/local/bin/ ..."
install -m 755 anytls-server /usr/local/bin/anytls-server
cd / # 操作完毕，离开临时目录

# 11. 创建服务所需用户
if ! id "anytls" &>/dev/null; then
  log_info "创建专用的系统用户 'anytls' 用于运行服务..."
  useradd -r -s /usr/sbin/nologin -d /dev/null anytls
fi

# ==============================
# 12. 写入 systemd service 配置
# ==============================
cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/anytls -c /etc/anytls/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd
systemctl daemon-reexec
systemctl daemon-reload

# 启用并启动服务
systemctl enable --now anytls


# 13. 配置防火墙
if [ "$SKIP_FIREWALL" != true ]; then
  configure_firewall
fi

# 14. 启动服务
log_info "正在重载 systemd 并启动 anytls 服务..."
systemctl daemon-reload

# 在启动前再次检查端口是否可用
if ! check_port_available "$PORT"; then
  log_warn "启动前检测到端口 ${PORT} 已被占用，尝试处理..."
  NEW_PORT=$(handle_port_conflict "$PORT")
  
  if [ "$NEW_PORT" != "$PORT" ]; then
    log_info "更新服务配置为使用端口 ${NEW_PORT}..."
    update_service_port "$PORT" "$NEW_PORT"
    PORT=$NEW_PORT
  fi
fi

# 启动服务
systemctl enable --now anyt
