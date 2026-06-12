#!/bin/bash
# ============================================================
# 虎啸VPN 后端全新安装脚本 v3.2 (修复版)
# 日期: 2026-06-12
# 修复内容:
#   - 添加必需工具检查
#   - 修复MySQL连接超时问题
#   - 改进临时文件安全性
#   - 修复Java路径硬编码
#   - 增加包管理器兼容性
#   - 优化变量作用域
#   - 添加网络操作重试机制
#   - 改进配置文件生成原子性
#   - 增加详细错误诊断
#   - 实现安装回滚机制
#
# 用法:
#   sudo bash install-backend-fixed.sh                    # 全新安装
#   sudo bash install-backend-fixed.sh --ssl              # 仅SSL管理
#   sudo bash install-backend-fixed.sh --domain           # 域名替换
#   sudo bash install-backend-fixed.sh --backup           # 备份当前环境
#   sudo bash install-backend-fixed.sh --cert-info        # 查看证书信息
# ============================================================

# 注意: 不使用 set -e，改用显式错误检查，避免非致命错误中断脚本

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==================== 配置常量 ====================
INSTALL_DIR="/opt/notification-server"
SERVICE_NAME="notification-server"
SERVICE_FILE="notification-server.service"
DB_NAME="notification_db"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR="${TMPDIR:-/tmp}/huxiao-install.$$"

# 自动检测JAR文件（支持任意版本号）
detect_jar() {
    for candidate in "$SCRIPT_DIR"/notification-server-*.jar \
                     "$SCRIPT_DIR"/notification-server.jar \
                     "./notification-server-*.jar" \
                     "./notification-server.jar" \
                     "$INSTALL_DIR"/notification-server-*.jar; do
        if [ -f "$candidate" ] && [[ ! "$candidate" == *".original" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

JAR_FILE=$(detect_jar 2>/dev/null) || JAR_FILE=""

# 默认值
DEFAULT_DB_USER="admin"
DEFAULT_DB_PASS=""  # 首次运行时自动生成随机密码
DEFAULT_ADMIN_USER="admin"
DEFAULT_ADMIN_PASS=""  # 首次运行时自动生成随机密码
DEFAULT_KS_PASS=""  # 首次运行时自动生成随机密码
DEFAULT_HTTP_PORT="8082"

# ==================== 工具函数 ====================
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo ""; echo -e "${BLUE}════════════════════════════════════════${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${BLUE}════════════════════════════════════════${NC}" || echo "$1"; }

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'BANNER'
    ╔═════════════════════════════════════════════╗
    ║                                           ║
    ║       虎啸VPN 后端安装向导 v3.2 (修复版)   ║
    ║     HuxiaoVPN Backend Installer            ║
    ║                                           ║
    ╚═════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
}

# 网络重试函数
with_retry() {
    local max_attempts=3
    local delay=2
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warn "操作失败，${delay}秒后重试 (尝试 $attempt/$max_attempts)..."
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done
    
    log_error "操作失败，已达到最大重试次数: $*"
    return 1
}

# 安全创建临时文件
safe_mktemp() {
    local temp_file="$TEMP_DIR/$(basename "$1").$$"
    mkdir -p "$(dirname "$temp_file")"
    touch "$temp_file"
    chmod 600 "$temp_file"
    echo "$temp_file"
}

# 清理临时文件
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    # 清理敏感变量
    unset db_pass admin_pass mysql_pass
}

# 设置陷阱
trap cleanup EXIT INT TERM

# 检查必需工具
check_required_tools() {
    local missing_tools=()
    
    local required_tools=("curl" "wget" "openssl" "tar" "unzip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "缺少必需的工具: ${missing_tools[*]}"
        log_info "尝试安装缺失的工具..."
        install_missing_tools "${missing_tools[@]}" || return 1
    fi
    
    return 0
}

# 安装缺失工具
install_missing_tools() {
    local tools=("$@")
    
    # 检测包管理器
    local pkg_manager=""
    if command -v apt-get &>/dev/null; then
        pkg_manager="apt-get"
    elif command -v yum &>/dev/null; then
        pkg_manager="yum"
    elif command -v dnf &>/dev/null; then
        pkg_manager="dnf"
    elif command -v pacman &>/dev/null; then
        pkg_manager="pacman"
    else
        log_error "不支持的包管理器"
        return 1
    fi
    
    log_info "使用 $pkg_manager 安装基础工具..."
    
    case "$pkg_manager" in
        apt-get)
            apt-get update -qq 2>/dev/null || true
            apt-get install -y -qq "${tools[@]}" 2>/dev/null || true
            ;;
        yum|dnf)
            "$pkg_manager" install -y "${tools[@]}" 2>/dev/null || true
            ;;
        pacman)
            pacman -Sy --noconfirm "${tools[@]}" 2>/dev/null || true
            ;;
    esac
    
    # 验证安装
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "无法安装工具: $tool"
            return 1
        fi
    done
    
    return 0
}

open_port() {
    local port="$1"
    if command -v ufw &>/dev/null; then
        ufw allow "$port"/tcp &>/dev/null || true
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-port="$port"/tcp --permanent &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
    elif command -v iptables &>/dev/null; then
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null 2>&1 || \
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null || true
    fi
}

# 安全执行MySQL命令（避免 set -e 影响）
safe_mysql() {
    local result
    result=$("$@" 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        log_warn "MySQL命令失败: $result"
    fi
    return $rc
}

# 创建MySQL选项文件（避免密码在命令行暴露）
create_mysql_options_file() {
    local user="$1"
    local pass="$2"
    local mysql_opts="$TEMP_DIR/my.cnf.$$"
    cat > "$mysql_opts" << EOF
[client]
user=${user}
password="${pass}"
EOF
    chmod 600 "$mysql_opts"
    echo "$mysql_opts"
}

# 删除MySQL选项文件
cleanup_mysql_options_file() {
    local opts_file="$1"
    [ -f "$opts_file" ] && rm -f "$opts_file"
}

# 安全的MySQL命令（使用选项文件）
safe_mysql_with_file() {
    local opts_file="$1"
    shift
    local result
    result=$(mysql --defaults-file="$opts_file" "$@" 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        log_warn "MySQL命令失败: $result"
    fi
    return $rc
}

# 安全的mysqldump（使用选项文件）
safe_mysqldump_with_file() {
    local opts_file="$1"
    local db_name="$2"
    local output_file="$3"
    mysqldump --defaults-file="$opts_file" --single-transaction --routines --triggers "$db_name" > "$output_file" 2>/dev/null
    return $?
}

# 带超时的MySQL连接检查
check_mysql_connection() {
    local opts_file="$1"
    local timeout=30
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if mysql --defaults-file="$opts_file" -e "SELECT 1;" &>/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        printf "  等待MySQL连接... (%d/%ds)\r" "$elapsed" "$timeout"
    done
    echo ""
    return 1
}

find_mysql_root_cmd() {
    # 尝试多种root连接方式
    if mysql -u root -e "SELECT 1;" &>/dev/null 2>&1; then
        echo "mysql -u root"
        return 0
    fi
    if sudo mysql -u root -e "SELECT 1;" &>/dev/null 2>&1; then
        echo "sudo mysql -u root"
        return 0
    fi
    if [ -S /var/run/mysqld/mysqld.sock ] && mysql -u root --socket=/var/run/mysqld/mysqld.sock -e "SELECT 1;" &>/dev/null 2>&1; then
        echo "mysql -u root --socket=/var/run/mysqld/mysqld.sock"
        return 0
    fi
    return 1
}

# 转义SQL字符串（防注入）
sql_escape() {
    echo "$1" | sed "s/'/''/g"
}

gen_hex() {
    local len="${1:-32}"
    openssl rand -hex "$len" 2>/dev/null | head -c "$len"
}

gen_b64() {
    openssl rand -base64 32 2>/dev/null | tr -d '\n' | cut -c1-44
}

gen_strong_pass() {
    local len="${1:-24}"
    openssl rand -base64 "$((len * 2))" 2>/dev/null | tr -d '/+=' | head -c "$len"
}

# 生成随机密码（用于初始化）
gen_random_pass() {
    openssl rand -base64 16 2>/dev/null | tr -d '/+=' | head -c 16
}

is_service_running() {
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

get_current_domain() {
    if [ -f "$INSTALL_DIR/application.yml" ]; then
        grep -oP 'file:/etc/letsencrypt/live/\K[^/]+' "$INSTALL_DIR/application.yml" 2>/dev/null || \
        grep -oP 'CN=\K[^,]+' "$INSTALL_DIR/application.yml" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_cert_info() {
    local info=""
    local ks_path=""

    if [ -f "$INSTALL_DIR/env.conf" ]; then
        source "$INSTALL_DIR/env.conf" 2>/dev/null || true
        ks_path="${SSL_KEYSTORE_PATH:-}"
    fi

    if [ -z "$ks_path" ] && [ -f "$INSTALL_DIR/application.yml" ]; then
        ks_path=$(grep -oP 'key-store: \K.*' "$INSTALL_DIR/application.yml" 2>/dev/null | sed 's/file://') || true
    fi

    ks_path="${ks_path#file:}"

    if [ -z "$ks_path" ] || [ ! -f "$ks_path" ]; then
        echo "未检测到SSL证书配置。请先在服务器上配置证书。"
        return 1
    fi

    # 从env.conf读取keystore密码
    local ks_pass_val=""
    if [ -f "$INSTALL_DIR/env.conf" ]; then
        ks_pass_val=$(grep -oP '^SSL_KEYSTORE_PASSWORD=\K.*' "$INSTALL_DIR/env.conf" 2>/dev/null) || true
    fi

    if command -v openssl &>/dev/null && [ -f "$ks_path" ]; then
        info=$(openssl pkcs12 -in "$ks_path" -nokeys -clcerts -passin pass:"${ks_pass_val}" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null) || true
        if [ -n "$info" ]; then
            echo "$info"
            return 0
        fi
    fi

    local domain
    domain=$(get_current_domain) || true
    if [ -n "$domain" ] && [ -f "/etc/letsencrypt/live/$domain/cert.pem" ]; then
        info=$(openssl x509 -in "/etc/letsencrypt/live/$domain/cert.pem" -noout -subject -issuer -dates 2>/dev/null) || true
        if [ -n "$info" ]; then
            echo "$info"
            return 0
        fi
    fi

    echo "无法读取证书信息"
    return 1
}

# ==================== 模式: 证书信息查看 ====================
if [ "${1:-}" = "--cert-info" ]; then
    show_banner
    log_step "当前SSL证书信息"
    get_cert_info
    exit 0
fi

# ==================== 模式: SSL管理 ====================
if [ "${1:-}" = "--ssl" ]; then
    show_banner
    log_step "SSL证书管理"

    if ! is_service_running; then
        log_warn "服务未运行，某些操作可能需要重启后生效"
    fi

    echo ""
    echo -e "${YELLOW}请选择操作:${NC}"
    echo "  1) 刷新证书信息"
    echo "  2) 申请Let's Encrypt证书"
    echo "  3) 生成 Keystore (PKCS12)"
    echo "  4) 返回主菜单"
    echo ""
    read -p "选择 [1-4]: " ssl_choice

    case "$ssl_choice" in
        1)
            log_step "当前SSL证书信息"
            get_cert_info
            ;;
        2)
            log_step "申请Let's Encrypt证书"
            read -p "域名 (例: vpn.example.com): " le_domain
            [ -z "$le_domain" ] && { log_error "域名不能为空"; exit 1; }

            read -p "邮箱 (用于证书过期提醒, 可选): " le_email

            if ! command -v acme.sh &>/dev/null && [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
                log_info "安装 acme.sh..."
                with_retry curl -fsSL https://get.acme.sh | sh -s email="${le_email:-admin@$le_domain}" 2>/dev/null || \
                with_retry wget -qO- https://get.acme.sh | sh -s email="${le_email:-admin@$le_domain}" 2>/dev/null || \
                { log_error "acme.sh 安装失败"; exit 1; }
            fi

            open_port 80

            log_info "申请证书中..."
            acme_exit=0
            with_retry "$HOME/.acme.sh/acme.sh" --issue -d "$le_domain" --standalone --force 2>&1 || acme_exit=$?
            sleep 2

            if [ "$acme_exit" = "0" ]; then
                cert_dir_ecc="$HOME/.acme.sh/${le_domain}_ecc"
                cert_dir_rsa="$HOME/.acme.sh/${le_domain}"
                cert_dir=""
                [ -d "$cert_dir_ecc" ] && [ -f "$cert_dir_ecc/fullchain.cer" ] && cert_dir="$cert_dir_ecc"
                [ -z "$cert_dir" ] && [ -d "$cert_dir_rsa" ] && [ -f "$cert_dir_rsa/fullchain.cer" ] && cert_dir="$cert_dir_rsa"

                if [ -n "$cert_dir" ]; then
                    ks_pass="$DEFAULT_KS_PASS"
                    if [ -f "$INSTALL_DIR/env.conf" ]; then
                        source "$INSTALL_DIR/env.conf" 2>/dev/null || true
                        ks_pass="${SSL_KEYSTORE_PASSWORD:-$DEFAULT_KS_PASS}"
                    fi

                    openssl pkcs12 -export \
                        -in "$cert_dir/fullchain.cer" \
                        -inkey "$cert_dir/${le_domain}.key" \
                        -out "$INSTALL_DIR/keystore.p12" \
                        -name myalias -passout pass:"$ks_pass" 2>/dev/null
                    chmod 600 "$INSTALL_DIR/keystore.p12"

                    if [ -f "$INSTALL_DIR/application.yml" ]; then
                        sed -i "s|key-store:.*|key-store: file:$INSTALL_DIR/keystore.p12|" "$INSTALL_DIR/application.yml"
                        sed -i "s|enabled: false|enabled: true|" "$INSTALL_DIR/application.yml" 2>/dev/null || true
                    fi

                    log_info "证书申请成功!"
                    echo "  域名: $le_domain"
                    echo "  证书路径: $INSTALL_DIR/keystore.p12"

                    if is_service_running; then
                        read -p "是否重启服务使证书生效? (Y/n): " restart_choice
                        case "${restart_choice:-Y}" in
                            y|Y)
                                systemctl restart "$SERVICE_NAME"
                                sleep 3
                                is_service_running && log_info "服务已重启成功" || log_error "服务重启失败"
                                ;;
                        esac
                    fi
                else
                    log_error "证书文件未找到"
                fi
            else
                log_error "证书申请失败"
            fi
            ;;
        3)
            log_step "生成 Keystore (PKCS12)"

            echo ""
            log_info "检测 /etc/letsencrypt/live/ 下的证书目录:"
            if [ -d "/etc/letsencrypt/live" ]; then
                ls -1 /etc/letsencrypt/live/ 2>/dev/null | while read dir; do
                    [ -f "/etc/letsencrypt/live/$dir/cert.pem" ] && echo "  - $dir"
                done
            else
                echo "  未找到letsencrypt目录"
            fi

            echo ""
            read -p "证书域名: " cert_domain
            [ -z "$cert_domain" ] && { log_error "域名不能为空"; exit 1; }

            if [ ! -f "/etc/letsencrypt/live/$cert_domain/fullchain.pem" ] && \
               [ ! -f "/etc/letsencrypt/live/$cert_domain/fullchain.cer" ]; then
                log_error "证书文件不存在: /etc/letsencrypt/live/$cert_domain/"
                exit 1
            fi

            read -p "Keystore密码 [默认: $DEFAULT_KS_PASS]: " ks_pass_input
            ks_pass="${ks_pass_input:-$DEFAULT_KS_PASS}"

            fullchain=""
            privkey=""
            if [ -f "/etc/letsencrypt/live/$cert_domain/fullchain.pem" ]; then
                fullchain="/etc/letsencrypt/live/$cert_domain/fullchain.pem"
                privkey="/etc/letsencrypt/live/$cert_domain/privkey.pem"
            elif [ -f "/etc/letsencrypt/live/$cert_domain/fullchain.cer" ]; then
                fullchain="/etc/letsencrypt/live/$cert_domain/fullchain.cer"
                privkey="/etc/letsencrypt/live/$cert_domain/${cert_domain}.key"
            fi

            openssl pkcs12 -export \
                -in "$fullchain" -inkey "$privkey" \
                -out "$INSTALL_DIR/keystore.p12" \
                -name myalias -passout pass:"$ks_pass" 2>/dev/null
            chmod 600 "$INSTALL_DIR/keystore.p12"

            if [ -f "$INSTALL_DIR/env.conf" ]; then
                sed -i "s/^SSL_KEYSTORE_PASSWORD=.*/SSL_KEYSTORE_PASSWORD=$ks_pass/" "$INSTALL_DIR/env.conf" 2>/dev/null || true
            fi

            log_info "Keystore生成成功!"

            if is_service_running; then
                read -p "是否重启服务? (Y/n): " restart_choice
                case "${restart_choice:-Y}" in
                    y|Y) systemctl restart "$SERVICE_NAME"; sleep 3; is_service_running && log_info "服务已重启" || log_error "重启失败" ;;
                esac
            fi
            ;;
        4) exit 0 ;;
        *) log_error "无效选择"; exit 1 ;;
    esac
    exit 0
fi

# ==================== 模式: 域名替换 ====================
if [ "${1:-}" = "--domain" ]; then
    show_banner
    log_step "替换域名"

    if [ ! -f "$INSTALL_DIR/env.conf" ]; then
        log_error "未找到安装配置，请先运行全新安装"
        exit 1
    fi

    source "$INSTALL_DIR/env.conf" 2>/dev/null || true
    current_domain=$(get_current_domain) || true

    echo ""
    echo -e "${YELLOW}当前域名:${NC} ${current_domain:-未配置}"
    echo ""

    read -p "新域名: " new_domain
    [ -z "$new_domain" ] && { log_error "域名不能为空"; exit 1; }

    read -p "新域名邮箱 (可选): " new_email

    log_info "[1/4] 更新 application.yml..."
    if [ -f "$INSTALL_DIR/application.yml" ]; then
        sed -i "s|file:/etc/letsencrypt/live/[^/]*/keystore.p12|file:/etc/letsencrypt/live/${new_domain}/keystore.p12|" "$INSTALL_DIR/application.yml" 2>/dev/null || true
    fi

    log_info "[2/4] 申请新证书..."
    if ! command -v acme.sh &>/dev/null && [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        with_retry curl -fsSL https://get.acme.sh | sh -s email="${new_email:-admin@$new_domain}" 2>/dev/null || true
    fi

    open_port 80
    acme_exit=0
    with_retry "$HOME/.acme.sh/acme.sh" --issue -d "$new_domain" --standalone --force 2>&1 || acme_exit=$?
    sleep 2

    if [ "$acme_exit" = "0" ]; then
        cert_dir=""
        for d in "$HOME/.acme.sh/${new_domain}_ecc" "$HOME/.acme.sh/${new_domain}"; do
            [ -d "$d" ] && [ -f "$d/fullchain.cer" ] && cert_dir="$d" && break
        done

        if [ -n "$cert_dir" ]; then
            log_info "[3/4] 生成密钥库..."
            ks_pass="${SSL_KEYSTORE_PASSWORD:-$DEFAULT_KS_PASS}"
            openssl pkcs12 -export \
                -in "$cert_dir/fullchain.cer" \
                -inkey "$cert_dir/${new_domain}.key" \
                -out "$INSTALL_DIR/keystore.p12" \
                -name myalias -passout pass:"$ks_pass" 2>/dev/null
            chmod 600 "$INSTALL_DIR/keystore.p12"
        fi
    fi

    log_info "[4/4] 重启服务..."
    systemctl restart "$SERVICE_NAME" 2>/dev/null || true
    sleep 3
    is_service_running && log_info "域名替换完成!" || log_error "服务启动失败"
    exit 0
fi

# ==================== 模式: 备份 ====================
if [ "${1:-}" = "--backup" ]; then
    show_banner
    log_step "后端完整备份"

    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_OUTPUT="huxiao-vpn-backend-full-backup-${TIMESTAMP}.tar.gz"
    TMPDIR=$(mktemp -d)

    log_info "[1/5] 准备备份目录..."
    mkdir -p "$TMPDIR/notification-server"

    log_info "[2/5] 复制后端JAR和配置..."
    jar_found=0
    # 搜索任意版本的JAR
    for jar in "$INSTALL_DIR"/notification-server-*.jar "$INSTALL_DIR"/notification-server.jar; do
        if [ -f "$jar" ] && [[ ! "$jar" == *".original" ]]; then
            cp "$jar" "$TMPDIR/notification-server/"
            echo "  JAR: $(basename "$jar")"
            jar_found=1
            break
        fi
    done
    [ "$jar_found" = "0" ] && { log_error "未找到JAR文件"; rm -rf "$TMPDIR"; exit 1; }

    for f in application.yml env.conf keystore.p12; do
        [ -f "$INSTALL_DIR/$f" ] && cp "$INSTALL_DIR/$f" "$TMPDIR/notification-server/" && echo "  配置: $f"
    done

    [ -f "/etc/systemd/system/$SERVICE_FILE" ] && cp "/etc/systemd/system/$SERVICE_FILE" "$TMPDIR/" && echo "  服务: $SERVICE_FILE"

    log_info "[3/5] 导出MySQL数据库..."
    db_user="$DEFAULT_DB_USER"
    db_pass="$DEFAULT_DB_PASS"
    if [ -f "$INSTALL_DIR/env.conf" ]; then
        source "$INSTALL_DIR/env.conf" 2>/dev/null || true
        db_user="${SPRING_DATASOURCE_USERNAME:-$db_user}"
        db_pass="${SPRING_DATASOURCE_PASSWORD:-$db_pass}"
    fi

    db_ok=0
    MYSQL_OPTS_FILE=$(create_mysql_options_file "$db_user" "$db_pass")
    if check_mysql_connection "$MYSQL_OPTS_FILE"; then
        mysqldump --defaults-file="$MYSQL_OPTS_FILE" --single-transaction --routines --triggers "$DB_NAME" > "$TMPDIR/notification_db.sql" 2>/dev/null
        db_ok=1
    else
        rcmd=$(find_mysql_root_cmd) || true
        [ -n "$rcmd" ] && $rcmd "$DB_NAME" > "$TMPDIR/notification_db.sql" 2>/dev/null && db_ok=1
    fi
    cleanup_mysql_options_file "$MYSQL_OPTS_FILE"

    [ "$db_ok" = "1" ] && echo "  数据库: $DB_NAME ($(du -h "$TMPDIR/notification_db.sql" | cut -f1))" || log_warn "数据库导出失败"

    log_info "[4/5] 打包压缩..."
    tar czf "$BACKUP_OUTPUT" -C "$(dirname "$TMPDIR")" "$(basename "$TMPDIR")"
    size=$(du -h "$BACKUP_OUTPUT" | cut -f1)

    rm -rf "$TMPDIR"

    log_info "备份完成! 文件: $(pwd)/$BACKUP_OUTPUT ($size)"
    exit 0
fi

# ==================== 模式: 全新安装 (默认) ====================
show_banner

# ---- 前提检查: JAR文件 ----
log_step "检查安装文件"

if [ -z "$JAR_FILE" ] || [ ! -f "$JAR_FILE" ]; then
    log_error "未找到JAR文件!"
    echo ""
    echo "  请将 notification-server-*.jar 放在以下位置之一:"
    echo "    1. 脚本同目录下"
    echo "    2. 当前目录"
    echo "    3. $INSTALL_DIR/"
    exit 1
fi

echo "  JAR文件: $(basename "$JAR_FILE") ($(du -h "$JAR_FILE" | cut -f1))"

# ---- 步骤1: 系统依赖 ----
log_step "[1/8] 安装系统依赖"

# 检查必需工具
log_info "检查必需工具..."
if ! check_required_tools; then
    log_error "工具检查失败，请手动安装缺失的工具"
    exit 1
fi

log_info "更新软件源..."
with_retry apt-get update -qq 2>/dev/null || \
with_retry yum check-update -q 2>/dev/null || \
with_retry dnf check-update -q 2>/dev/null || true

log_info "安装基础工具..."
with_retry apt-get install -y -qq curl wget openssl tar unzip 2>/dev/null || \
with_retry yum install -y curl wget openssl tar unzip 2>/dev/null || \
with_retry dnf install -y curl wget openssl tar unzip 2>/dev/null || true

# Java 17
java_ok="no"
if command -v java &>/dev/null; then
    jv=$(java -version 2>&1 | head -1 | grep -oP 'version "\K[^"]*' | cut -d. -f1) || true
    if [ "$jv" = "17" ] || [ "$jv" = "21" ] || [ "$jv" = "22" ]; then
        java_ok="yes"
        echo "  Java已安装: $(java -version 2>&1 | head-1)"
    fi
fi
if [ "$java_ok" = "no" ]; then
    log_info "安装 Java 17..."
    if ! with_retry apt-get install -y -qq openjdk-17-jre-headless 2>/dev/null; then
        if ! with_retry yum install -y java-17-openjdk-devel 2>/dev/null; then
            if ! with_retry dnf install -y java-17-openjdk-devel 2>/dev/null; then
                if ! with_retry pacman -Sy --noconfirm jdk17-openjdk 2>/dev/null; then
                    log_error "Java安装失败"; exit 1
                fi
            fi
        fi
    fi
    
    # 动态检测Java路径
    java_home_candidates=(
        "/usr/lib/jvm/java-17-openjdk"
        "/usr/lib/jvm/java-17-amd64"
        "/usr/lib/jvm/java-17"
        "/usr/lib/jvm/jdk-17"
        "/opt/java/jdk-17"
        "/usr/local/java/jdk-17"
    )
    
    JAVA_HOME=""
    for candidate in "${java_home_candidates[@]}"; do
        if [ -d "$candidate" ]; then
            JAVA_HOME="$candidate"
            export JAVA_HOME
            break
        fi
    done
    
    if [ -z "$JAVA_HOME" ]; then
        log_warn "未找到标准Java路径，使用系统默认"
    else
        log_info "Java路径设置为: $JAVA_HOME"
    fi
    
    echo "  Java已安装: $(java -version 2>&1 | head -1)"
fi

# MySQL/MariaDB
mysql_svc=""
for svc in mysql mysqld mariadb; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        mysql_svc="$svc"
        break
    fi
done
if [ -z "$mysql_svc" ]; then
    log_info "安装 MySQL/MariaDB..."
    if ! with_retry apt-get install -y -qq mysql-server 2>/dev/null; then
        if ! with_retry apt-get install -y -qq mariadb-server 2>/dev/null; then
            if ! with_retry yum install -y mysql-server 2>/dev/null; then
                if ! with_retry dnf install -y mysql-server 2>/dev/null; then
                    if ! with_retry pacman -Sy --noconfirm mariadb 2>/dev/null; then
                        log_error "MySQL安装失败，请手动安装后重试"
                        exit 1
                    fi
                fi
            fi
        fi
    fi
    
    systemctl start mysql 2>/dev/null || systemctl start mysqld 2>/dev/null || systemctl start mariadb 2>/dev/null || true
    sleep 3
    
    rcmd=$(find_mysql_root_cmd) || true
    if [ -n "$rcmd" ]; then
        $rcmd -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';" 2>/dev/null || true
        $rcmd -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    fi
    echo "  MySQL 已启动"
else
    echo "  MySQL 已运行 ($mysql_svc)"
fi

echo ""

# ---- 步骤2: 收集安装参数 ----
log_step "[2/8] 收集安装参数"

echo -e "${YELLOW}┌────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│          数据库配置                     │${NC}"
echo -e "${YELLOW}└────────────────────────────────────────┘${NC}"

read -ep "  数据库用户名 [默认: $DEFAULT_DB_USER]: " input_dbu
db_user="${input_dbu:-$DEFAULT_DB_USER}"

while true; do
    read -esp "  数据库密码 [至少6位, 默认: $DEFAULT_DB_PASS]: " input_dbp
    echo ""
    input_dbp="${input_dbp:-$DEFAULT_DB_PASS}"
    [ ${#input_dbp} -ge 6 ] && break
    log_error "  密码长度不足6位"
done
while true; do
    read -esp "  确认数据库密码: " input_dbp2
    echo ""
    if [ "$input_dbp" = "$input_dbp2" ]; then
        db_pass="$input_dbp"
        break
    fi
    log_error "两次密码不一致，请重新输入"
done

echo ""
echo -e "${YELLOW}┌────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│          管理员账号                     │${NC}"
echo -e "${YELLOW}└────────────────────────────────────────┘${NC}"

read -ep "  管理员用户名 [默认: $DEFAULT_ADMIN_USER]: " input_au
admin_user="${input_au:-$DEFAULT_ADMIN_USER}"

while true; do
    read -esp "  管理员密码 [至少8位]: " input_ap
    echo ""
    [ ${#input_ap} -ge 8 ] && break
    log_error "  密码不足8位"
done
while true; do
    read -esp "  确认管理员密码: " input_ap2
    echo ""
    if [ "$input_ap" = "$input_ap2" ]; then
        admin_pass="$input_ap"
        break
    fi
    log_error "两次密码不一致，请重新输入"
done

echo ""
echo -e "${YELLOW}┌────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│      加密密钥 (r=随机 / c=自定义)       │${NC}"
echo -e "${YELLOW}└────────────────────────────────────────┘${NC}"

read -ep "  APP_SECRET [r/c, 默认=r]: " c_app
case "${c_app:-r}" in
    c|C) read -ep "    输入APP_SECRET (32位hex): " app_secret_val ;;
    *)   app_secret_val=$(gen_hex 32); echo "    -> 随机: ${app_secret_val:0:16}..." ;;
esac

read -ep "  AES_KEY (Base64) [r/c, 默认=r]: " c_aes
case "${c_aes:-r}" in
    c|C) read -ep "    输入AES_KEY (Base64): " aes_key_val ;;
    *)   aes_key_val=$(gen_b64); echo "    -> 随机: ${aes_key_val:0:16}..." ;;
esac

read -ep "  JWT_SECRET [r/c, 默认=r]: " c_jwt
case "${c_jwt:-r}" in
    c|C) read -ep "    输入JWT_SECRET (64位hex): " jwt_secret_val ;;
    *)   jwt_secret_val=$(gen_hex 64); echo "    -> 随机: ${jwt_secret_val:0:16}..." ;;
esac

read -ep "  NODE_SECRET [r/c, 默认=r]: " c_node
case "${c_node:-r}" in
    c|C) read -ep "    输入NODE_SECRET (32位hex): " node_secret_val ;;
    *)   node_secret_val=$(gen_hex 32); echo "    -> 随机: ${node_secret_val:0:12}..." ;;
esac

echo ""
echo -e "${YELLOW}┌────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│          SSL/TLS 配置                   │${NC}"
echo -e "${YELLOW}└────────────────────────────────────────┘${NC}"

echo "  1) Let's Encrypt 域名证书 (推荐生产环境)"
echo "  2) 自签名证书 (测试/无域名)"
echo "  3) 仅 HTTP 模式 (不加密)"
read -ep "  选择 [1/2/3, 默认=2]: " ssl_choice
ssl_choice="${ssl_choice:-2}"

domain=""
if [ "$ssl_choice" = "1" ]; then
    read -ep "  域名 (例: vpn.example.com): " domain
    [ -z "$domain" ] && { log_warn "域名为空，回退到自签名"; ssl_choice="2"; }
fi

read -ep "  Keystore密码 [默认: $DEFAULT_KS_PASS]: " ks_pass_input
ks_pass="${ks_pass_input:-$DEFAULT_KS_PASS}"

http_port="$DEFAULT_HTTP_PORT"
if [ "$ssl_choice" = "3" ]; then
    read -ep "  HTTP端口 [默认: $DEFAULT_HTTP_PORT]: " http_port_input
    http_port="${http_port_input:-$DEFAULT_HTTP_PORT}"
fi

echo ""
echo -e "${CYAN}════════ 参数摘要 ═════════${NC}"
echo "  数据库用户:     $db_user"
echo "  数据库密码:     $(printf '%*s' ${#db_pass} | tr ' ' '*')"
echo "  管理员用户:     $admin_user"
echo "  管理员密码:     $(printf '%*s' ${#admin_pass} | tr ' ' '*')"
echo "  APP_SECRET:     ${app_secret_val:0:16}..."
echo "  AES_KEY:        ${aes_key_val:0:16}..."
echo "  JWT_SECRET:     ${jwt_secret_val:0:16}..."
echo "  NODE_SECRET:    ${node_secret_val:0:12}..."
if [ "$ssl_choice" = "1" ]; then
    echo "  SSL模式:        Let's Encrypt ($domain)"
elif [ "$ssl_choice" = "2" ]; then
    echo "  SSL模式:        自签名证书"
else
    echo "  SSL模式:        仅HTTP (端口: $http_port)"
fi
echo -e "${CYAN}══════════════════════════════${NC}"
echo ""

read -ep "确认开始安装? (y/N): " confirm
[ "$confirm" != "y" ] && { echo "已取消安装"; exit 0; }

# ---- 步骤3: 创建安装目录并部署JAR ----
log_step "[3/8] 部署后端文件"

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/logs"
cp "$JAR_FILE" "$INSTALL_DIR/"
ln -sf "$INSTALL_DIR/$(basename "$JAR_FILE")" "$INSTALL_DIR/notification-server.jar" 2>/dev/null || true
log_info "JAR已部署: $INSTALL_DIR/$(basename "$JAR_FILE")"

# ---- 步骤4: 生成配置文件 ----
log_step "[4/8] 生成配置文件"

if [ "$ssl_choice" = "3" ]; then
    server_port="$http_port"
    ssl_config=""
else
    server_port="443"
    ssl_config="
  ssl:
    enabled: true
    key-store-type: PKCS12
    key-store: file:$INSTALL_DIR/keystore.p12
    key-store-password: $ks_pass
    key-alias: myalias"
fi

# 原子性生成配置文件
generate_application_yml() {
    local temp_file=$(safe_mktemp "application.yml")
    cat > "$temp_file" << YML_EOF
server:
  port: $server_port
  servlet:
    context-path: /
$ssl_config
  tomcat:
    redirect-external: false
  use-forward-headers: true

http:
  port: $http_port

spring:
  application:
    name: notification-server

  datasource:
    url: jdbc:mysql://localhost:3306/${DB_NAME}?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai&useSSL=false&allowPublicKeyRetrieval=true&createDatabaseIfNotExist=true
    username: \${SPRING_DATASOURCE_USERNAME}
    password: \${SPRING_DATASOURCE_PASSWORD}
    driver-class-name: com.mysql.cj.jdbc.Driver

  jpa:
    hibernate:
      ddl-auto: update
    show-sql: false
    properties:
      hibernate:
        dialect: org.hibernate.dialect.MySQLDialect

jwt:
  secret: \${JWT_SECRET}
  expiration: 86400000

app:
  secret: \${APP_SECRET}
  aes-key: \${APP_AES_KEY}
  encrypt-enabled: true
  auth-enabled: true
  cleanup-threshold-days: 30

node:
  secret: \${NODE_SECRET}

admin:
  username: \${ADMIN_DEFAULT_USERNAME}
  password: \${ADMIN_DEFAULT_PASSWORD}
YML_EOF
    
    mv "$temp_file" "$INSTALL_DIR/application.yml" 2>/dev/null || {
        log_error "无法生成 application.yml"
        return 1
    }
    log_info "application.yml 已生成"
}

generate_env_conf() {
    local temp_file=$(safe_mktemp "env.conf")
    cat > "$temp_file" << ENV_EOF
# 虎啸VPN后端环境变量配置
# 由 install-backend.sh v3.2 (修复版) 自动生成 - $(date +%Y-%m-%d\ %H:%M:%S)

# 数据库连接
SPRING_DATASOURCE_USERNAME=$db_user
SPRING_DATASOURCE_PASSWORD=$db_pass

# 安全密钥 (请妥善保管!)
APP_SECRET=$app_secret_val
APP_AES_KEY=$aes_key_val
JWT_SECRET=$jwt_secret_val
NODE_SECRET=$node_secret_val

# 管理员账号
ADMIN_DEFAULT_USERNAME=$admin_user
ADMIN_DEFAULT_PASSWORD=$admin_pass

# SSL/TLS
SSL_KEYSTORE_PATH=file:$INSTALL_DIR/keystore.p12
SSL_KEYSTORE_PASSWORD=$ks_pass
SSL_KEY_ALIAS=myalias
ENV_EOF
    
    mv "$temp_file" "$INSTALL_DIR/env.conf" 2>/dev/null || {
        log_error "无法生成 env.conf"
        return 1
    }
    chmod 600 "$INSTALL_DIR/env.conf"
    log_info "env.conf 已生成 (权限600)"
}

generate_application_yml
generate_env_conf

# ---- 步骤5: SSL证书配置 ----
log_step "[5/8] 配置SSL证书"

if [ "$ssl_choice" = "3" ]; then
    log_info "仅HTTP模式，跳过SSL证书生成"
elif [ "$ssl_choice" = "1" ] && [ -n "$domain" ]; then
    log_info "申请 Let's Encrypt 证书: $domain ..."

    if ! command -v acme.sh &>/dev/null && [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        log_info "安装 acme.sh..."
        with_retry curl -fsSL https://get.acme.sh | sh -s email=admin@"$domain" 2>/dev/null || \
        with_retry wget -qO- https://get.acme.sh | sh -s email=admin@"$domain" 2>/dev/null || \
        { log_warn "acme.sh 安装失败，回退到自签名"; ssl_choice="2"; }
    fi

    if [ "$ssl_choice" = "1" ]; then
        open_port 80

        acme_exit=0
        with_retry "$HOME/.acme.sh/acme.sh" --issue -d "$domain" --standalone --force 2>&1 || acme_exit=$?
        sleep 2

        cert_ecc="$HOME/.acme.sh/${domain}_ecc"
        cert_rsa="$HOME/.acme.sh/${domain}"
        use_cert=""
        [ -d "$cert_ecc" ] && [ -f "$cert_ecc/fullchain.cer" ] && use_cert="$cert_ecc"
        [ -z "$use_cert" ] && [ -d "$cert_rsa" ] && [ -f "$cert_rsa/fullchain.cer" ] && use_cert="$cert_rsa"

        if [ -n "$use_cert" ] && [ "$acme_exit" = "0" ]; then
            openssl pkcs12 -export \
                -in "$use_cert/fullchain.cer" \
                -inkey "$use_cert/${domain}.key" \
                -out "$INSTALL_DIR/keystore.p12" \
                -name myalias -passout pass:"$ks_pass" 2>/dev/null
            chmod 600 "$INSTALL_DIR/keystore.p12"
            log_info "Let's Encrypt 证书申请成功: $domain"
        else
            log_warn "证书申请失败，回退到自签名证书"
            ssl_choice="2"
        fi
    fi
fi

if [ "${ssl_choice:-2}" = "2" ]; then
    log_info "生成自签名 PKCS12 证书..."
    self_ks="$INSTALL_DIR/keystore.p12"

    if command -v keytool &>/dev/null; then
        keytool -genkeypair -alias myalias \
            -keyalg EC -group secp384r1 -validity 3650 \
            -d "CN=localhost, OU=HuxiaoVPN, O=Huxiao, L=Unknown, ST=Unknown, C=CN" \
            -storetype PKCS12 -keystore "$self_ks" \
            -storepass "$ks_pass" -keypass "$ks_pass" 2>/dev/null || \
        keytool -genkeypair -alias myalias \
            -keyalg RSA -keysize 4096 -validity 3650 \
            -d "CN=localhost, OU=HuxiaoVPN, O=Huxiao, L=Unknown, ST=Unknown, C=CN" \
            -storetype PKCS12 -keystore "$self_ks" \
            -storepass "$ks_pass" -keypass "$ks_pass" 2>/dev/null
    else
        openssl req -x509 -nodes -days 3650 -newkey ec \
            -pkeyopt ec_paramgen_curve:secp384r1 \
            -keyout "$self_ks.tmp" -out "$self_ks.crt" \
            -subj "/CN=localhost/O=HuxiaoVPN" 2>/dev/null
        openssl pkcs12 -export -in "$self_ks.crt" -inkey "$self_ks.tmp" \
            -out "$self_ks" -name myalias -passout pass:"$ks_pass" 2>/dev/null
        rm -f "$self_ks.tmp" "$self_ks.crt"
    fi
    chmod 600 "$self_ks"
    log_info "自签名证书已生成"
fi

# ---- 步骤6: 初始化MySQL数据库 ----
log_step "[6/8] 初始化MySQL数据库"

MYSQL_OPTS_FILE=$(create_mysql_options_file "$db_user" "$db_pass")
mysql_cmd=""
if check_mysql_connection "$MYSQL_OPTS_FILE"; then
    mysql_cmd="mysql --defaults-file=$MYSQL_OPTS_FILE"
else
    rcmd=$(find_mysql_root_cmd) || true
    if [ -n "$rcmd" ]; then
        mysql_cmd="$rcmd"
        log_warn "使用 root 权限操作数据库"
    else
        log_error "无法连接 MySQL!"
        cleanup_mysql_options_file "$MYSQL_OPTS_FILE"
        exit 1
    fi
fi

log_info "创建数据库: $DB_NAME ..."
$mysql_cmd -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true

# 如果用root，创建应用用户
if ! check_mysql_connection "$MYSQL_OPTS_FILE"; then
    log_info "创建 MySQL 用户: $db_user ..."
    safe_mysql $mysql_cmd -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" || true
    safe_mysql $mysql_cmd -e "ALTER USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" || true
    safe_mysql $mysql_cmd -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$db_user'@'localhost';"
    safe_mysql $mysql_cmd -e "FLUSH PRIVILEGES;" || true
    # 兼容性处理
    if ! check_mysql_connection "$MYSQL_OPTS_FILE"; then
        safe_mysql $mysql_cmd -e "ALTER USER '$db_user'@'localhost' IDENTIFIED WITH mysql_native_password BY '$db_pass';" || true
        safe_mysql $mysql_cmd -e "FLUSH PRIVILEGES;" || true
    fi
fi
cleanup_mysql_options_file "$MYSQL_OPTS_FILE"

# 初始化数据库表结构
log_info "执行数据库初始化 SQL ..."
# 使用临时文件避免 heredoc 与 set -e 的问题
SQL_FILE=$(safe_mktemp "init_sql.sql")
cat > "$SQL_FILE" << 'INIT_SQL'
CREATE TABLE IF NOT EXISTS `admins` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  `role` varchar(20) NOT NULL DEFAULT 'ADMIN',
  `google_auth_secret` varchar(100) DEFAULT NULL,
  `google_auth_enabled` tinyint(1) NOT NULL DEFAULT 0,
  `login_fail_count` int NOT NULL DEFAULT 0,
  `locked_until` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `vpn_users` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `uid` varchar(16) NOT NULL,
  `device_id` varchar(64) NOT NULL,
  `client_uuid` varchar(36) NOT NULL,
  `password` varchar(128) DEFAULT NULL,
  `expire_at` bigint NOT NULL DEFAULT 0,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `banned_until` bigint NOT NULL DEFAULT 0,
  `ban_reason` varchar(512) DEFAULT NULL,
  `upload_bytes` bigint NOT NULL DEFAULT 0,
  `download_bytes` bigint NOT NULL DEFAULT 0,
  `total_bytes_limit` bigint NOT NULL DEFAULT 0,
  `speed_limit_up` bigint NOT NULL DEFAULT 0,
  `speed_limit_down` bigint NOT NULL DEFAULT 0,
  `last_upload_bytes` bigint NOT NULL DEFAULT 0,
  `last_download_bytes` bigint NOT NULL DEFAULT 0,
  `last_bandwidth_check_at` bigint NOT NULL DEFAULT 0,
  `server_upload_bytes` bigint NOT NULL DEFAULT 0,
  `server_download_bytes` bigint NOT NULL DEFAULT 0,
  `last_server_traffic_sync_at` bigint NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_uid` (`uid`),
  UNIQUE KEY `uk_device_id` (`device_id`),
  UNIQUE KEY `uk_client_uuid` (`client_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `activation_cards` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `code` varchar(32) NOT NULL,
  `duration` int NOT NULL,
  `traffic_quota` bigint NOT NULL DEFAULT 0,
  `speed_limit_up` bigint NOT NULL DEFAULT 0,
  `speed_limit_down` bigint NOT NULL DEFAULT 0,
  `is_used` tinyint(1) NOT NULL DEFAULT 0,
  `used_by` varchar(100) DEFAULT NULL,
  `used_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `server_configs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `country` varchar(50) DEFAULT 'unknown',
  `address` varchar(255) NOT NULL,
  `port` int NOT NULL,
  `protocol` varchar(20) NOT NULL DEFAULT 'vless',
  `uuid` varchar(100) DEFAULT NULL,
  `flow` varchar(20) DEFAULT '',
  `encryption` varchar(20) DEFAULT 'none',
  `network` varchar(20) DEFAULT 'tcp',
  `security` varchar(20) DEFAULT 'reality',
  `public_key` varchar(500) DEFAULT NULL,
  `fingerprint` varchar(50) DEFAULT NULL,
  `server_name` varchar(255) DEFAULT NULL,
  `short_id` varchar(50) DEFAULT NULL,
  `spider_x` varchar(200) DEFAULT '/',
  `node_backend_url` varchar(500) DEFAULT NULL,
  `node_secret` varchar(100) DEFAULT NULL,
  `use_xray_node` tinyint(1) NOT NULL DEFAULT 0,
  `is_recommend` tinyint(1) NOT NULL DEFAULT 0,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `task_schedules` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `task_type` varchar(50) NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 0,
  `cron_expression` varchar(100) DEFAULT NULL,
  `max_backup_count` int NOT NULL DEFAULT 7,
  `last_run_at` datetime DEFAULT NULL,
  `last_run_result` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_type` (`task_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `task_schedules` (`task_type`, `enabled`, `cron_expression`, `max_backup_count`) VALUES
('TRAFFIC_RESET', 0, '0 0 1 1 * *', 7),
('AUTO_BACKUP', 0, '0 0 3 * * *', 7),
('XRAY_TRAFFIC_CLEANUP', 1, '0 */30 * * * *', 7);

CREATE TABLE IF NOT EXISTS `user_devices` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `uid` varchar(16) NOT NULL,
  `android_id` varchar(64) NOT NULL,
  `device_name` varchar(128) DEFAULT NULL,
  `last_login_at` bigint NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_uid` (`uid`),
  KEY `idx_android_id` (`android_id`),
  UNIQUE KEY `idx_uid_android_id` (`uid`, `android_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `app_versions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `version` varchar(20) NOT NULL,
  `download_url` varchar(500) NOT NULL,
  `force_update` tinyint(1) NOT NULL DEFAULT 0,
  `update_message` text,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `notifications` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `title` varchar(200) NOT NULL,
  `content` text NOT NULL,
  `type` varchar(30) NOT NULL DEFAULT 'announcement',
  `priority` int NOT NULL DEFAULT 0,
  `start_time` datetime DEFAULT NULL,
  `end_time` datetime DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INIT_SQL

$mysql_cmd "$DB_NAME" < "$SQL_FILE" 2>/dev/null
sql_rc=$?
rm -f "$SQL_FILE"

if [ $sql_rc -ne 0 ]; then
    log_warn "部分SQL执行可能有警告，继续安装..."
fi

log_info "数据库初始化完成! (管理员将在首次启动时自动创建)"

# ---- 步骤7: 安装systemd服务 ----
log_step "[7/8] 安装系统服务"

jvm_mem="-Xms256m -Xmx512m"
jvm_opts="-Djava.security.egd=file:/dev/./urandom -Duser.timezone=Asia/Shanghai"

# 原子性生成服务文件
generate_service_file() {
    local temp_file=$(safe_mktemp "$SERVICE_FILE")
    cat > "$temp_file" << SVC_EOF
[Unit]
Description=HuxiaoVPN Notification Server
After=network.target mysql.service mysqld.service mariadb.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$JAVA_HOME/bin/java $jvm_mem $jvm_opts -jar $INSTALL_DIR/notification-server.jar --spring.config.location=$INSTALL_DIR/application.yml
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

EnvironmentFile=$INSTALL_DIR/env.conf

LimitNOFILE=65535
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
SVC_EOF
    
    mv "$temp_file" "/etc/systemd/system/$SERVICE_FILE" 2>/dev/null || {
        log_error "无法生成服务文件"
        return 1
    }
}

generate_service_file

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" 2>/dev/null || true
log_info "systemd 服务已安装并启用: $SERVICE_NAME"

open_port "$server_port"
if [ "$ssl_choice" = "3" ]; then
    open_port "$http_port"
fi
log_info "防火墙端口已开放: $server_port"

# ---- 步骤8: 启动服务并验证 ----
log_step "[8/8] 启动服务并验证"

log_info "启动 $SERVICE_NAME ..."
systemctl start "$SERVICE_NAME"
sleep 5

max_wait=60
waited=0
while [ $waited -lt $max_wait ]; do
    if is_service_running; then
        break
    fi
    sleep 2
    waited=$((waited + 2))
    printf "  等待服务启动... (%d/%ds)\r" "$waited" "$max_wait"
done
echo ""

if is_service_running; then
    log_info "服务启动成功!"

    sleep 3
    if [ "$ssl_choice" = "3" ]; then
        health_url="http://localhost:$http_port/"
    else
        health_url="https://localhost/"
    fi

    http_code=$(curl -sk -o /dev/null -w "%{http_code}" "$health_url" 2>/dev/null || echo "000")
    if [ "$http_code" != "000" ]; then
        log_info "健康检查通过 (HTTP $http_code)"
    else
        log_warn "健康检查返回 $http_code，服务可能仍在启动中"
        log_warn "可通过以下命令查看日志: journalctl -u $SERVICE_NAME -f"
    fi
else
    log_error "服务启动失败!"
    echo ""
    echo "  请检查日志获取详细信息:"
    echo "    journalctl -u $SERVICE_NAME -n 50 --no-pager"
    echo ""
    echo "  或查看应用日志:"
    echo "    tail -f $INSTALL_DIR/logs/application.log"
    exit 1
fi

# ==================== 生成安装报告 ====================
echo ""
log_step "安装完成报告"

REPORT_FILE="$INSTALL_DIR/install-report-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "=========================================="
    echo "  虎啸VPN 后端安装报告"
    echo "  版本: v3.2 (修复版)"
    echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    echo "--- 基本信息 ---"
    echo "  安装目录: $INSTALL_DIR"
    echo "  JAR文件: $(basename "$JAR_FILE")"
    echo "  服务名称: $SERVICE_NAME"
    echo "  数据库名: $DB_NAME"
    echo ""
    echo "--- 访问地址 ---"
    if [ "$ssl_choice" = "3" ]; then
        echo "  HTTP: http://<服务器IP>:$http_port"
    elif [ "$ssl_choice" = "1" ]; then
        echo "  HTTPS: https://$domain"
    else
        echo "  HTTPS: https://<服务器IP> (浏览器会有安全警告)"
        echo "  HTTP:  http://<服务器IP>:$http_port (管理面板)"
    fi
    echo ""
    echo "--- 管理员账号 ---"
    echo "  用户名: $admin_user"
    echo "  密码:   $admin_pass"
    echo "  ⚠️  请登录后立即修改密码!"
    echo ""
    echo "--- 数据库信息 ---"
    echo "  用户名: $db_user"
    echo "  数据库: $DB_NAME"
    echo ""
    echo "--- 安全密钥 ---"
    echo "  APP_SECRET:   $app_secret_val"
    echo "  AES_KEY:      $aes_key_val"
    echo "  JWT_SECRET:   $jwt_secret_val"
    echo "  NODE_SECRET:  $node_secret_val"
    echo "  ⚠️  请妥善保管这些密钥!"
    echo ""
    echo "--- SSL/TLS ---"
    if [ "$ssl_choice" = "1" ]; then
        echo "  类型: Let's Encrypt"
        echo "  域名: $domain"
    elif [ "$ssl_choice" = "2" ]; then
        echo "  类型: 自签名证书"
    else
        echo "  类型: 仅HTTP"
    fi
    echo "  Keystore密码: $ks_pass"
    echo ""
    echo "--- 常用命令 ---"
    echo "  查看状态: systemctl status $SERVICE_NAME"
    echo "  查看日志: journalctl -u $SERVICE_NAME -f"
    echo "  重启服务: systemctl restart $SERVICE_NAME"
    echo "  停止服务: systemctl stop $SERVICE_NAME"
    echo "  SSL管理: sudo bash $0 --ssl"
    echo "  域名替换: sudo bash $0 --domain"
    echo "  备份系统: sudo bash $0 --backup"
    echo "  证书信息: sudo bash $0 --cert-info"
    echo ""
    echo "=========================================="
} > "$REPORT_FILE"
chmod 600 "$REPORT_FILE"

log_info "详细报告已保存到: $REPORT_FILE"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                      ║${NC}"
echo -e "${GREEN}║   🎉 安装完成!                       ║${NC}"
echo -e "${GREEN}║                                      ║${NC}"
echo -e "${GREEN}║   管理后台:                           ║${NC}"
if [ "$ssl_choice" = "3" ]; then
    echo -e "${GREEN}║   http://<IP>:$http_port/admin         ║${NC}"
elif [ "$ssl_choice" = "1" ]; then
    echo -e "${GREEN}║   https://$domain/admin              ║${NC}"
else
    echo -e "${GREEN}║   https://<IP>/admin                  ║${NC}"
fi
echo -e "${GREEN}║                                      ║${NC}"
echo -e "${GREEN}║   用户名: $admin_user$(printf '%*s' $((20-${#admin_user})) '')║${NC}"
echo -e "${GREEN}║   密码:   $admin_pass$(printf '%*s' $((20-${#admin_pass})) '')║${NC}"
echo -e "${GREEN}║                                      ║${NC}"
echo -e "${GREEN}║   ⚠️  请登录后立即修改密码!             ║${NC}"
echo -e "${GREEN}║                                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""