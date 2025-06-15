#!/bin/bash
# anytls-go 自动安装脚本
# 支持: Ubuntu 20.04+ / Debian 11+
# 功能: 安装 Go 环境、Git，编译 anytls-server，并创建 systemd 服务
set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户或 sudo 运行此脚本。"
    exit 1
fi

echo "初始化：安装基础依赖..."
apt-get update -y
apt-get install -y curl git golang-go

# 自动检测服务器公网 IP
get_ip() {
    local ip=""
    ip=$(ip -o -4 addr show scope global | awk '{print $4}' | cut -d'/' -f1 | head -n1)
    if [ -z "$ip" ]; then
        ip=$(curl -4 -s --connect-timeout 3 ifconfig.me || curl -4 -s --connect-timeout 3 icanhazip.com)
    fi
    if [ -z "$ip" ]; then
        read -p "未能自动检测公网 IP，请手动输入服务器 IP: " ip
    fi
    echo "$ip"
}
SERVER_IP=$(get_ip)
echo "检测到服务器 IP：$SERVER_IP"
read -p "若有误，请手动输入修正（回车保持不变）: " input_ip
if [ -n "$input_ip" ]; then SERVER_IP="$input_ip"; fi
echo "使用 IP: $SERVER_IP"

# 设置监听端口
while true; do
    read -p "请输入 anytls 监听端口 (1024-65535)，留空随机生成: " PORT
    if [ -z "$PORT" ]; then
        PORT=$(shuf -i 1024-65535 -n 1)
        echo "随机端口: $PORT"
        break
    elif [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ]; then
        echo "使用端口: $PORT"
        break
    else
        echo "无效输入！请输入 1024-65535 范围内的数字或直接回车跳过。"
    fi
done

# 设置连接密码
while true; do
    read -p "请输入 anytls 密码 (>=12 位)，留空随机生成: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
        echo "随机生成密码: $PASSWORD"
        break
    elif [ ${#PASSWORD} -lt 12 ]; then
        echo "密码太短，请输入至少 12 位长度的密码！"
    else
        break
    fi
done

echo "开始安装 anytls-go 服务端..."

# 克隆并编译 anytls-go
echo "克隆 anytls-go 源码..."
if [ ! -d "/opt/anytls-go" ]; then
    git clone https://github.com/anytls/anytls-go.git /opt/anytls-go
else
    echo "检测到已有 /opt/anytls-go，尝试更新..."
    cd /opt/anytls-go && git pull
fi

echo "编译 anytls-server..."
cd /opt/anytls-go/cmd/anytls-server
go build -o anytls-server
mv anytls-server /usr/local/bin/
chmod +x /usr/local/bin/anytls-server

echo "编译 anytls-client (可选)..."
cd /opt/anytls-go/cmd/anytls-client
go build -o anytls-client
mv anytls-client /usr/local/bin/
chmod +x /usr/local/bin/anytls-client

# 创建 systemd 服务文件
SERVICE_FILE="/etc/systemd/system/anytls.service"
echo "创建 systemd 服务: $SERVICE_FILE"
cat > $SERVICE_FILE <<EOF
[Unit]
Description=AnyTLS Server Service
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:$PORT -p $PASSWORD
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
echo "启用并启动 anytls 服务..."
systemctl daemon-reload
systemctl enable anytls.service
systemctl restart anytls.service

echo "安装完成！"
echo "配置摘要：监听端口 = $PORT ，连接密码 = $PASSWORD"
echo "服务已启动，使用 'systemctl status anytls' 查看状态。"
echo "提示：客户端配置时请跳过证书验证（anytls 使用自签名证书）."
