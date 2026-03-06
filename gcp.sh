#!/bin/sh

# V2Ray 一键安装配置脚本 - 通用版本
# 支持系统: Alpine Linux, Debian, Ubuntu, CentOS, Fedora
# 使用方法: sh install_v2ray.sh [PORT] [USER] [PASS] [VERSION]
# 或者设置环境变量: PORT=61031 USER=user01 PASS=pass01 VER=v5.41.0 sh install_v2ray.sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 全局变量
OS_TYPE=""
INIT_SYSTEM=""
PKG_MANAGER=""
V2RAY_VERSION=""

# 打印信息函数
print_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "此脚本必须以 root 权限运行"
        exit 1
    fi
}

# 检测操作系统类型
detect_os() {
    print_info "检测操作系统类型..."
    
    # 检测 Alpine Linux
    if [ -f /etc/alpine-release ]; then
        OS_TYPE="alpine"
        INIT_SYSTEM="openrc"
        PKG_MANAGER="apk"
        OS_VERSION=$(cat /etc/alpine-release)
        print_info "检测到 Alpine Linux $OS_VERSION"
        return
    fi
    
    # 检测其他 Linux 发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                OS_TYPE="debian"
                PKG_MANAGER="apt"
                ;;
            centos|rhel|fedora)
                OS_TYPE="redhat"
                if command -v dnf >/dev/null 2>&1; then
                    PKG_MANAGER="dnf"
                else
                    PKG_MANAGER="yum"
                fi
                ;;
            opensuse*|sles)
                OS_TYPE="suse"
                PKG_MANAGER="zypper"
                ;;
            arch|manjaro)
                OS_TYPE="arch"
                PKG_MANAGER="pacman"
                ;;
            *)
                print_error "不支持的操作系统: $ID"
                exit 1
                ;;
        esac
        
        # 检测 init 系统
        if [ -d /run/systemd/system ]; then
            INIT_SYSTEM="systemd"
        elif command -v rc-service >/dev/null 2>&1; then
            INIT_SYSTEM="openrc"
        else
            print_error "无法检测到支持的 init 系统"
            exit 1
        fi
        
        print_info "检测到 $NAME"
        print_info "Init 系统: $INIT_SYSTEM"
    else
        print_error "无法检测操作系统类型"
        exit 1
    fi
}

# 获取参数
get_parameters() {
    # 如果通过命令行参数传入
    if [ $# -eq 4 ]; then
        PORT=$1
        USER=$2
        PASS=$3
        V2RAY_VERSION=$4
    elif [ $# -eq 3 ]; then
        PORT=$1
        USER=$2
        PASS=$3
    fi
    
    # 如果通过环境变量传入
    if [ -n "$PORT" ] && [ -n "$USER" ] && [ -n "$PASS" ]; then
        if [ -n "$VER" ]; then
            V2RAY_VERSION="$VER"
            print_info "使用环境变量配置（包含版本）"
        else
            print_info "使用环境变量配置"
        fi
    fi
    
    # 交互式输入
    if [ -z "$PORT" ] || [ -z "$USER" ] || [ -z "$PASS" ]; then
        print_info "请输入配置参数（按回车使用默认值）"
        
        printf "端口 [默认: 61031]: "
        read PORT
        PORT=${PORT:-61031}
        
        printf "用户名 [默认: user01]: "
        read USER
        USER=${USER:-user01}
        
        printf "密码 [默认: pass01]: "
        read PASS
        PASS=${PASS:-pass01}
        
        printf "V2Ray 版本 [默认: v5.41.0]: "
        read V2RAY_VERSION
    fi
    
    # 设置默认版本
    V2RAY_VERSION=${V2RAY_VERSION:-v5.41.0}
    
    # 确保版本号以 v 开头
    if ! echo "$V2RAY_VERSION" | grep -q "^v"; then
        V2RAY_VERSION="v${V2RAY_VERSION}"
    fi
    
    # 验证端口范围
    if ! echo "$PORT" | grep -qE '^[0-9]+$' || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        print_error "端口必须在 1-65535 之间"
        exit 1
    fi
    
    print_info "配置参数："
    echo "  端口: $PORT"
    echo "  用户: $USER"
    echo "  密码: $PASS"
    echo "  版本: $V2RAY_VERSION"
}

# 获取本机 IP
get_host_ip() {
    print_info "获取本机 IP 地址..."
    
    HOST=""
    
    # 尝试使用 curl 获取公网 IP
    if command -v curl >/dev/null 2>&1; then
        HOST=$(curl -s -4 --connect-timeout 5 https://api.ipify.org 2>/dev/null)
        if [ -z "$HOST" ]; then
            HOST=$(curl -s -4 --connect-timeout 5 https://ifconfig.me 2>/dev/null)
        fi
        if [ -z "$HOST" ]; then
            HOST=$(curl -s -4 --connect-timeout 5 https://icanhazip.com 2>/dev/null)
        fi
    fi
    
    # 尝试使用 wget 获取公网 IP
    if [ -z "$HOST" ] && command -v wget >/dev/null 2>&1; then
        HOST=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null)
        if [ -z "$HOST" ]; then
            HOST=$(wget -qO- --timeout=5 https://ifconfig.me 2>/dev/null)
        fi
        if [ -z "$HOST" ]; then
            HOST=$(wget -qO- --timeout=5 https://icanhazip.com 2>/dev/null)
        fi
    fi
    
    # 如果无法获取公网IP，使用本地IP
    if [ -z "$HOST" ]; then
        if command -v ip >/dev/null 2>&1; then
            HOST=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
        elif command -v ifconfig >/dev/null 2>&1; then
            HOST=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)
        fi
    fi
    
    if [ -z "$HOST" ]; then
        print_error "无法获取本机 IP 地址"
        exit 1
    fi
    
    print_info "检测到本机 IP: $HOST"
}

# 安装依赖工具
install_dependencies() {
    print_info "安装必要的依赖工具..."
    
    case "$PKG_MANAGER" in
        apk)
            apk update
            apk add --no-cache curl wget unzip ca-certificates
            ;;
        apt)
            apt-get update
            apt-get install -y curl wget unzip ca-certificates
            ;;
        dnf)
            dnf install -y curl wget unzip ca-certificates
            ;;
        yum)
            yum install -y curl wget unzip ca-certificates
            ;;
        zypper)
            zypper install -y curl wget unzip ca-certificates
            ;;
        pacman)
            pacman -Syu --noconfirm curl wget unzip ca-certificates
            ;;
    esac
    
    print_info "依赖工具安装完成"
}

# Alpine 系统特殊处理
setup_alpine() {
    print_info "配置 Alpine Linux 环境..."
    
    # 启用 Community 仓库
    if ! grep -q "^[^#]*community" /etc/apk/repositories; then
        VERSION=$(cat /etc/alpine-release | cut -d'.' -f1,2)
        echo "https://dl-cdn.alpinelinux.org/alpine/v${VERSION}/community" >> /etc/apk/repositories
        apk update
        print_info "Community 仓库已启用"
    fi
}

# 安装 V2Ray - Alpine 方式
install_v2ray_alpine() {
    print_info "在 Alpine 上安装 V2Ray $V2RAY_VERSION..."
    
    # 尝试从仓库安装
    if apk search v2ray | grep -q "^v2ray-"; then
        print_info "从 Alpine 仓库安装 V2Ray..."
        apk add --no-cache v2ray v2ray-openrc
        mkdir -p /usr/local/etc/v2ray /var/log/v2ray
        print_warning "注意: Alpine 仓库版本可能与指定版本 $V2RAY_VERSION 不同"
    else
        # 使用 alpinelinux-install-v2ray 脚本
        print_info "从 GitHub 安装 V2Ray $V2RAY_VERSION..."
        TEMP_SCRIPT=$(mktemp)
        wget -O "$TEMP_SCRIPT" https://raw.githubusercontent.com/v2fly/alpinelinux-install-v2ray/master/install-release.sh
        sh "$TEMP_SCRIPT" --version "$V2RAY_VERSION"
        rm -f "$TEMP_SCRIPT"
    fi
    
    print_info "V2Ray 安装成功"
}

# 安装 V2Ray - Systemd 系统方式
install_v2ray_systemd() {
    print_info "在 $OS_TYPE 上安装 V2Ray $V2RAY_VERSION..."
    
    # 使用临时文件而非进程替换
    TEMP_SCRIPT=$(mktemp)
    
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$TEMP_SCRIPT" https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$TEMP_SCRIPT" https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
    else
        print_error "需要 curl 或 wget 来下载安装脚本"
        exit 1
    fi
    
    if command -v bash >/dev/null 2>&1; then
        bash "$TEMP_SCRIPT" --version "$V2RAY_VERSION"
    else
        sh "$TEMP_SCRIPT" --version "$V2RAY_VERSION"
    fi
    
    rm -f "$TEMP_SCRIPT"
    print_info "V2Ray 安装成功"
}

# 安装 V2Ray
install_v2ray() {
    if [ "$OS_TYPE" = "alpine" ]; then
        setup_alpine
        install_v2ray_alpine
    else
        install_v2ray_systemd
    fi
}

# 配置 V2Ray
configure_v2ray() {
    print_info "配置 V2Ray..."
    
    # 确定配置文件路径
    if [ -d /usr/local/etc/v2ray ]; then
        CONFIG_PATH="/usr/local/etc/v2ray"
    elif [ -d /etc/v2ray ]; then
        CONFIG_PATH="/etc/v2ray"
    else
        CONFIG_PATH="/usr/local/etc/v2ray"
        mkdir -p "$CONFIG_PATH"
    fi
    
    # 生成配置文件（直接覆盖，不备份）
    cat > "$CONFIG_PATH/config.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked",
        "type": "field"
      }
    ]
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$USER",
            "pass": "$PASS"
          }
        ],
        "udp": true,
        "ip": "127.0.0.1"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF
    
    # 确保日志目录存在
    mkdir -p /var/log/v2ray
    touch /var/log/v2ray/v2ray.log 2>/dev/null || true
    
    print_info "配置文件已生成: $CONFIG_PATH/config.json"
}

# 配置 OpenRC 服务（Alpine）
configure_openrc_service() {
    print_info "配置 V2Ray OpenRC 服务..."
    
    # 如果服务正在运行，先停止
    if rc-service v2ray status >/dev/null 2>&1; then
        print_info "停止现有 V2Ray 服务..."
        rc-service v2ray stop || true
    fi
    
    # 无论文件是否存在，都覆盖写入新内容
    cat > /etc/init.d/v2ray <<'EOF'
#!/sbin/openrc-run

V2_CONFIG="/usr/local/etc/v2ray/config.json"
V2_PIDFILE="/run/v2ray.pid"
V2_LOG="/var/log/v2ray/v2ray.log"

depend() {
  need net
}

checkconfig() {
  if [ ! -f ${V2_CONFIG} ]; then
    ewarn "${V2_CONFIG} does not exist."
  fi
}

start() {
  checkconfig || return 1

  ebegin "Starting V2ray"
  ebegin "Log File : ${V2_LOG}"
  start-stop-daemon --start \
  -b -1 ${V2_LOG} -2 ${V2_LOG}  \
  -m -p ${V2_PIDFILE}   \
  --exec /usr/bin/v2ray -- run -config ${V2_CONFIG}
  eend $?
}

stop() {
  ebegin "Stopping V2ray"
  start-stop-daemon --stop -p ${V2_PIDFILE}
  eend $?
}
EOF
    
    chmod +x /etc/init.d/v2ray
    print_info "OpenRC 服务文件已配置"
}

# 启动服务 - OpenRC
start_service_openrc() {
    print_info "启动 V2Ray 服务 (OpenRC)..."
    
    rc-update add v2ray default
    rc-service v2ray start
    
    sleep 2
    
    if rc-service v2ray status | grep -q "started"; then
        print_info "V2Ray 服务启动成功"
    else
        print_error "V2Ray 服务启动失败"
        print_info "查看日志: tail -f /var/log/v2ray/v2ray.log"
        exit 1
    fi
}

# 启动服务 - Systemd
start_service_systemd() {
    print_info "启动 V2Ray 服务 (Systemd)..."
    
    systemctl enable v2ray --now
    
    sleep 2
    
    if systemctl is-active --quiet v2ray; then
        print_info "V2Ray 服务启动成功"
    else
        print_error "V2Ray 服务启动失败"
        print_info "查看日志: journalctl -u v2ray -n 50"
        exit 1
    fi
}

# 启动服务
start_service() {
    if [ "$INIT_SYSTEM" = "openrc" ]; then
        configure_openrc_service
        start_service_openrc
    else
        start_service_systemd
    fi
}

# 生成连接信息
generate_connection_info() {
    print_info "生成连接信息..."
    
    # 生成 SOCKS5 URL
    SOCKS5_URL="socks5://$USER:$PASS@$HOST:$PORT"
    
    # 根据 init 系统显示不同的命令
    if [ "$INIT_SYSTEM" = "openrc" ]; then
        CMD_START="rc-service v2ray start"
        CMD_STOP="rc-service v2ray stop"
        CMD_RESTART="rc-service v2ray restart"
        CMD_STATUS="rc-service v2ray status"
        CMD_ENABLE="rc-update add v2ray default"
        CMD_DISABLE="rc-update del v2ray default"
        CMD_LOG="tail -f /var/log/v2ray/v2ray.log"
    else
        CMD_START="systemctl start v2ray"
        CMD_STOP="systemctl stop v2ray"
        CMD_RESTART="systemctl restart v2ray"
        CMD_STATUS="systemctl status v2ray"
        CMD_ENABLE="systemctl enable v2ray"
        CMD_DISABLE="systemctl disable v2ray"
        CMD_LOG="journalctl -u v2ray -f"
    fi
    
    echo ""
    echo "=========================================="
    echo "V2Ray 安装配置完成！"
    echo "=========================================="
    echo ""
    echo "系统信息："
    echo "  操作系统: $OS_TYPE"
    echo "  Init 系统: $INIT_SYSTEM"
    echo "  V2Ray 版本: $V2RAY_VERSION"
    echo ""
    echo "服务器信息："
    echo "  IP 地址: $HOST"
    echo "  端口: $PORT"
    echo "  用户名: $USER"
    echo "  密码: $PASS"
    echo ""
    echo "SOCKS5 连接 URL："
    echo "  $SOCKS5_URL"
    echo ""
    echo "服务管理命令："
    echo "  启动服务: $CMD_START"
    echo "  停止服务: $CMD_STOP"
    echo "  重启服务: $CMD_RESTART"
    echo "  查看状态: $CMD_STATUS"
    echo "  查看日志: $CMD_LOG"
    echo ""
    echo "开机自启管理："
    echo "  启用自启: $CMD_ENABLE"
    echo "  禁用自启: $CMD_DISABLE"
    echo ""
    echo "配置文件位置："
    if [ -f /usr/local/etc/v2ray/config.json ]; then
        echo "  /usr/local/etc/v2ray/config.json"
    elif [ -f /etc/v2ray/config.json ]; then
        echo "  /etc/v2ray/config.json"
    fi
    echo "=========================================="
    echo ""
    
    # 保存连接信息到文件
    cat > /root/v2ray_info.txt <<EOF
V2Ray 连接信息
===========================================
安装时间: $(date)
操作系统: $OS_TYPE
Init 系统: $INIT_SYSTEM
V2Ray 版本: $V2RAY_VERSION

服务器信息：
  IP 地址: $HOST
  端口: $PORT
  用户名: $USER
  密码: $PASS

SOCKS5 连接 URL：
  $SOCKS5_URL

服务管理命令：
  启动服务: $CMD_START
  停止服务: $CMD_STOP
  重启服务: $CMD_RESTART
  查看状态: $CMD_STATUS
  查看日志: $CMD_LOG

开机自启管理：
  启用自启: $CMD_ENABLE
  禁用自启: $CMD_DISABLE

配置文件位置：
  $([ -f /usr/local/etc/v2ray/config.json ] && echo "/usr/local/etc/v2ray/config.json" || echo "/etc/v2ray/config.json")
===========================================
EOF
    
    print_info "连接信息已保存到 /root/v2ray_info.txt"
}

# 主函数
main() {
    echo "=========================================="
    echo "  V2Ray 一键安装配置脚本"
    echo "  通用版本 (Alpine/Debian/Ubuntu/CentOS)"
    echo "=========================================="
    echo ""
    
    check_root
    detect_os
    get_parameters "$@"
    get_host_ip
    install_dependencies
    install_v2ray
    configure_v2ray
    start_service
    generate_connection_info
}

# 执行主函数
main "$@"
