#!/bin/bash
# ============================================================================
#  虎啸VPN (Huxiao VPN) — 节点服务器管理脚本
#  功能: 安装 / 更新 / 卸载 Xray-core + 节点后端 + SSL 证书管理
#  适用系统: Ubuntu / Debian / CentOS / Rocky / AlmaLinux
#  架构: x86_64 / aarch64
#  用法: bash install-xray-node.sh
# ============================================================================
set -e

# -------------------- 配置区（可修改）---------------------------------------
XRAY_PORT=443                         # Xray VLESS 端口（REALITY 协议）
NODE_BACKEND_PORT=9080                # 节点后端端口
INSTALL_DIR="/opt/huxiao-node"        # 节点后端安装目录
XRAY_DIR="/usr/local/etc/xray"        # Xray 配置目录
XRAY_BIN="/usr/local/bin/xray"        # Xray 可执行文件路径
LOG_DIR="/var/log/huxiao"             # 日志目录
FALLBACK_DOMAIN="www.cloudflare.com"   # REALITY 回落伪装域名
# ---------------------------------------------------------------------------

_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_TMP_DIR=$(mktemp -d)

# ---- 全局变量（各函数共享）-------------------------------------------------
OS=""
UUID=""
PUBLIC_KEY=""
PRIVATE_KEY=""
SHORT_ID=""
NODE_SECRET=""
DOMAIN_NAME=""

# ---- 颜色输出 -------------------------------------------------------------
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; MAG='\033[35m'; DIM='\033[2m'; NC='\033[0m'; RESET='\033[0m'
info()  { echo -e "${CYAN}[信息]${RESET} $*" >&2; }
warn()  { echo -e "${YELLOW}[警告]${RESET} $*" >&2; }
error() { echo -e "${RED}[错误]${RESET} $*" >&2; }
ok()    { echo -e "${GREEN}[完成]${RESET} $*" >&2; }
title() { echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2; echo -e "${MAG}  $*${RESET}" >&2; echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2; }

# ---- 清理函数（脚本退出时自动调用）-----------------------------------------
cleanup() {
  local ec=$?
  [[ -d "$_TMP_DIR" ]] && rm -rf "$_TMP_DIR"
  if [[ $ec -ne 0 && $ec -ne 130 ]]; then
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${RED}  操作异常退出（退出码: $ec）${RESET}"
    echo -e "${RED}  请根据上方错误信息排查后重试${RESET}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  fi
  exit $ec
}
trap cleanup EXIT

# ---- 按任意键继续 ---------------------------------------------------------
pause() {
  echo ""
  read -r -p "  按 Enter 键返回菜单 ... "
}

# ============================================================================
#  获取 Xray 最新版本（从 GitHub API）
# ============================================================================
get_latest_xray_version() {
  info "正在从 GitHub 获取 Xray-core 最新版本..."
  local ver
  ver=$(curl -fsSL --connect-timeout 10 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null \
    | grep '"tag_name":' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/' | tr -d '[:space:]')
  if [[ -z "$ver" ]]; then
    warn "获取最新版本失败，降级使用默认版本 v26.3.27"
    echo "26.3.27"
  else
    info "最新版本: v${ver}"
    echo "$ver"
  fi
}

# ============================================================================
#  已安装的 Xray 版本
# ============================================================================
get_installed_xray_version() {
  if [[ -f "$XRAY_BIN" ]]; then
    "$XRAY_BIN" version 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1 || echo "未知"
  else
    echo "未安装"
  fi
}

# ============================================================================
#  环境检测（安装/更新共用）
# ============================================================================
check_env() {
  title "1/8  环境检测"

  if [[ $EUID -ne 0 ]]; then
    error "此脚本需要 root 权限运行，请使用 sudo 或切换为 root 用户。"
    exit 1
  fi
  info "✓ root 用户"

  if [[ -f /etc/os-release ]]; then
    . /etc/os-release; OS=$ID
    info "操作系统: $NAME $VERSION_ID"
  else
    error "无法识别操作系统类型"
    exit 1
  fi

  if curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" https://github.com 2>/dev/null | grep -qE "200|301|302"; then
    info "✓ 网络连通（GitHub）"
  else
    warn "无法访问 GitHub，部分下载可能失败，请检查代理设置"
  fi

  info "安装必要依赖..."
  if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq curl unzip wget openssl systemd chrony 2>/dev/null || true
  elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
    yum install -y curl unzip wget openssl systemd chrony 2>/dev/null || true
  fi
  ok "依赖检查完成"

  for port in ${XRAY_PORT} 80 "$NODE_BACKEND_PORT"; do
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
      local proc; proc=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1)
      warn "端口 $port 已被占用: $proc"
    fi
  done

  arch_detected=$(uname -m)
  info "架构: $arch_detected"
  ok "环境检测完成"
}

# ============================================================================
#  启用 BBR 加速
# ============================================================================
enable_bbr() {
  title "启用 BBR 加速"

  if [[ ! -f /proc/sys/net/ipv4/tcp_congestion_control ]]; then
    warn "内核不支持 TCP 拥塞控制调整"
    return 1
  fi

  local current
  current=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "")
  if [[ "$current" == "bbr" ]]; then
    ok "BBR 已启用 (当前: $current)"
    return 0
  fi

  info "当前拥塞控制: ${current:-未知}"

  # 加载 tcp_bbr 模块
  if ! lsmod 2>/dev/null | grep -q tcp_bbr; then
    modprobe tcp_bbr 2>/dev/null || true
  fi

  # 写入配置使其永久生效
  if ! grep -q "net.core.default_qdisc" /etc/sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
  fi
  if ! grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
  fi

  sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
  sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true

  local new_val
  new_val=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "")
  if [[ "$new_val" == "bbr" ]]; then
    ok "BBR 加速已启用"
  else
    warn "BBR 启用失败，当前: $new_val"
  fi
}

# ============================================================================
#  获取 Xray 下载架构名
# ============================================================================
get_xray_arch() {
  case "$(uname -m)" in
    x86_64)   echo "Xray-linux-64" ;;
    aarch64)  echo "Xray-linux-arm64-v8a" ;;
    *)
      error "不支持的 CPU 架构: $(uname -m)，仅支持 x86_64 / aarch64"
      exit 1
      ;;
  esac
}

# ============================================================================
#  安装 Xray-core
# ============================================================================
install_xray() {
  local version=$1
  local arch
  arch=$(get_xray_arch)

  if [[ -f "$XRAY_BIN" ]]; then
    local installed
    installed=$(get_installed_xray_version)
    info "已安装 Xray: $installed，目标版本: v${version}"
    read -r -p "是否重新安装/升级 Xray? [y/N]: " reinstall
    if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
      info "跳过 Xray 安装"
      return 0
    fi
  fi

  info "下载 Xray-core v${version} (${arch})..."
  cd "$_TMP_DIR"
  curl -L -o xray.zip \
    "https://github.com/XTLS/Xray-core/releases/download/v${version}/${arch}.zip" \
    --progress-bar
  if [[ ! -f xray.zip ]]; then
    error "Xray 下载失败，请检查网络"
    exit 1
  fi
  unzip -o xray.zip
  if [[ ! -f xray ]]; then
    error "解压失败，压缩包可能损坏"
    exit 1
  fi
  chmod +x xray
  mv xray "$XRAY_BIN"
  ok "Xray-core v${version} 已安装"

  # 下载 geo 数据（跳过已存在的）
  mkdir -p "$XRAY_DIR" "$LOG_DIR"
  for f in geoip.dat geosite.dat; do
    local url="https://github.com/Loyalsoldier/${f%.dat}/releases/latest/download/$f"
    if [[ ! -f "$XRAY_DIR/$f" ]]; then
      curl -L -o "$XRAY_DIR/$f" "$url" --progress-bar || warn "$f 下载失败"
    fi
  done
}

# ============================================================================
#  生成 Xray 配置
# ============================================================================
generate_xray_config() {
  title "2/8  生成 Xray 配置文件（VLESS + REALITY）"

  UUID=$(cat /proc/sys/kernel/random/uuid)

  info "生成 REALITY 密钥对..."
  KEY_OUTPUT=$("$XRAY_BIN" x25519 2>&1) || true
  PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i "private" | awk '{print $NF}')
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "public"  | awk '{print $NF}')
  SHORT_ID=$(openssl rand -hex 4)

  if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    error "REALITY 密钥生成失败！"
    echo "$KEY_OUTPUT"
    exit 1
  fi
  info "REALITY 密钥对生成成功"

  # 备份旧配置
  if [[ -f "$XRAY_DIR/config.json" ]]; then
    cp "$XRAY_DIR/config.json" "$XRAY_DIR/config.json.bak.$(date +%Y%m%d%H%M%S)"
    info "旧配置已备份"
  fi

  cat > "$XRAY_DIR/config.json" <<CONFEOF
{
  "log": {
    "loglevel": "warning",
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log"
  },
  "inbounds": [
    {
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "tag": "vless-inbound",
      "settings": {
        "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${FALLBACK_DOMAIN}:443",
          "serverNames": ["${FALLBACK_DOMAIN}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
CONFEOF
  ok "Xray 配置文件已写入: $XRAY_DIR/config.json"

  info "验证配置文件..."
  if "$XRAY_BIN" run -test -config "$XRAY_DIR/config.json" 2>&1; then
    ok "配置文件验证通过"
  else
    error "配置验证失败，请检查 $XRAY_DIR/config.json"
    exit 1
  fi
}

# ============================================================================
#  注册 Xray systemd 服务
# ============================================================================
setup_xray_service() {
  title "3/8  注册 Xray 系统服务"

  cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service - Huxiao VPN Node Proxy
Documentation=https://xtls.github.io
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${XRAY_BIN} run -config ${XRAY_DIR}/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3
LimitNOFILE=1000000
LimitNPROC=500

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable xray 2>/dev/null
  systemctl restart xray

  if systemctl is-active --quiet xray; then
    ok "Xray 服务已启动并已设置开机自启"
  else
    warn "Xray 启动失败，请查看日志: journalctl -u xray -n 30 --no-pager"
  fi
}

# ============================================================================
#  安装 Java 17
# ============================================================================
install_java() {
  title "4/8  安装 Java 17 运行环境"

  if command -v java &>/dev/null; then
    local jver
    jver=$(java -version 2>&1 | head -1)
    info "检测到: $jver"
    if echo "$jver" | grep -q '"17'; then
      ok "Java 17 已安装"
      return 0
    fi
  fi

  info "安装 OpenJDK 17..."
  if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get install -y -qq openjdk-17-jdk || {
      error "Java 17 安装失败，请手动安装后重试"
      exit 1
    }
  elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
    yum install -y java-17-openjdk || {
      error "Java 17 安装失败，请手动安装后重试"
      exit 1
    }
  else
    error "不支持的操作系统: $OS，请手动安装 Java 17"
    exit 1
  fi
  ok "Java 17 安装完成"
}

# ============================================================================
#  部署节点后端
# ============================================================================
setup_node_backend() {
  title "5/8  部署节点后端"

  mkdir -p "$INSTALL_DIR" "$LOG_DIR"

  echo ""
  echo -e "  ${YELLOW}请输入节点通信密钥 (node.secret):${NC}"
  echo -e "  ${DIM}此密钥用于主后端与节点后端通信认证，请与主后端配置一致${NC}"
  echo -n "  密钥: "
  read -r NODE_SECRET
  if [[ -z "$NODE_SECRET" ]]; then
    warn "密钥不能为空，已自动生成随机密钥"
    NODE_SECRET=$(openssl rand -hex 24)
  fi
  info "节点密钥已设置"

  # 查找 JAR 包
  JAR_FILE="$INSTALL_DIR/node-backend-1.1.3.jar"
  JAR_FOUND=""
  for jar_path in \
    "./node-backend-1.1.3.jar" \
    "$_SCRIPT_DIR/node-backend-1.1.3.jar" \
    "/root/node-backend-1.1.3.jar" \
    "$HOME/node-backend-1.1.3.jar" \
    "$INSTALL_DIR/node-backend-1.1.3.jar"; do
    if [[ -f "$jar_path" ]]; then
      cp "$jar_path" "$JAR_FILE"
      JAR_FOUND="1"
      info "JAR 已从 $jar_path 复制"
      break
    fi
  done
  if [[ -z "$JAR_FOUND" ]]; then
    warn "未找到 node-backend-1.1.3.jar，请上传后手动启动"
  fi

  # 备份旧配置
  if [[ -f "$INSTALL_DIR/application.yml" ]]; then
    cp "$INSTALL_DIR/application.yml" "$INSTALL_DIR/application.yml.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > "$INSTALL_DIR/application.yml" <<YMLEOF
# Huxiao VPN Node Backend Configuration
server:
  port: ${NODE_BACKEND_PORT}
  ssl:
    enabled: false
xray:
  config-path: ${XRAY_DIR}/config.json
  inbound-tag: vless-inbound
  restart-command: systemctl restart xray
  status-command: systemctl is-active xray
node:
  secret: ${NODE_SECRET}
  auth-enabled: true
logging:
  level:
    com.vpn.node: INFO
  file:
    path: ${LOG_DIR}
YMLEOF
  ok "节点后端配置文件已写入"

  # 注册 systemd 服务
  cat > /etc/systemd/system/huxiao-node.service <<EOF
[Unit]
Description=Huxiao VPN Node Backend
After=network-online.target xray.service
Wants=network-online.target xray.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/java -jar ${INSTALL_DIR}/node-backend-1.1.3.jar --server.port=${NODE_BACKEND_PORT}
ExecStop=/bin/kill -SIGTERM \$MAINPID
ExecReload=/bin/kill -SIGHUP \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=append:${LOG_DIR}/node-backend.log
StandardError=append:${LOG_DIR}/node-backend-error.log

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable huxiao-node 2>/dev/null

  if [[ -f "$JAR_FILE" ]]; then
    systemctl restart huxiao-node
    sleep 3
    if systemctl is-active --quiet huxiao-node; then
      ok "节点后端服务已启动"
    else
      warn "节点后端启动失败: journalctl -u huxiao-node -n 30 --no-pager"
    fi
  fi
}

# ============================================================================
#  SSL 证书申请与自动续期
# ============================================================================
setup_ssl() {
  title "6/8  SSL 证书申请与自动续期"

  echo ""
  echo "  虎啸VPN 节点使用 Xray REALITY 协议，本身不需要 SSL 证书。"
  echo "  但申请证书后可:"
  echo "    1) 节点后端 API 启用 HTTPS 加密通信"
  echo "    2) REALITY 回落展示真实 HTTPS 页面（防主动探测）"
  echo ""
  read -r -p "  请输入域名（留空跳过 SSL）: " DOMAIN_NAME
  if [[ -z "$DOMAIN_NAME" ]]; then
    info "跳过 SSL 配置，节点后端以 HTTP 模式运行"
    return 0
  fi

  # 校验域名是否能解析
  if ! nslookup "$DOMAIN_NAME" 2>/dev/null && ! host "$DOMAIN_NAME" 2>/dev/null && ! dig "$DOMAIN_NAME" 2>/dev/null; then
    warn "域名 $DOMAIN_NAME 可能未正确解析到本机，证书申请可能失败"
  fi

  ACME_HOME="/root/.acme.sh"
  if [[ ! -f "$ACME_HOME/acme.sh" ]]; then
    info "安装 acme.sh ..."
    curl -fsSL https://get.acme.sh | sh
    if [[ ! -f "$ACME_HOME/acme.sh" ]]; then
      error "acme.sh 安装失败"
      return 0
    fi
    ok "acme.sh 安装完成"
  else
    info "acme.sh 已安装"
  fi

  # 确保 acme.sh 在 PATH 中
  export PATH="$ACME_HOME:$PATH"

  # 检查 80 端口
  if ss -tlnp 2>/dev/null | grep -q ":80 "; then
    warn "80 端口被占用，无法使用 standalone 模式签发证书"
    warn "请确保 80 端口空闲后重新运行，或手动执行:"
    warn "  acme.sh --issue -d $DOMAIN_NAME --nginx"
    return 0
  fi

  info "申请 Let's Encrypt 证书（Standalone 模式）..."
  if ! "$ACME_HOME/acme.sh" --issue -d "$DOMAIN_NAME" --standalone --force 2>&1; then
    warn "证书签发失败，常见原因:"
    warn "  1. 域名 $DOMAIN_NAME 未解析到本机 IP"
    warn "  2. 防火墙未放行 80 端口（出站 + 入站）"
    warn "  3. Let's Encrypt 服务暂时不可用"
    warn "稍后可手动执行: acme.sh --issue -d $DOMAIN_NAME --standalone"
    return 0
  fi
  ok "证书签发成功"

  # 安装证书
  CERT_DIR="/etc/ssl/huxiao"
  mkdir -p "$CERT_DIR"
  "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN_NAME" \
    --key-file "$CERT_DIR/key.pem" \
    --fullchain-file "$CERT_DIR/cert.pem" \
    --reloadcmd "systemctl restart huxiao-node || true"
  ok "SSL 证书已安装到 $CERT_DIR"

  # 更新 application.yml 启用 HTTPS
  cat > "$INSTALL_DIR/application.yml" <<YMLEOF
# Huxiao VPN Node Backend Configuration (HTTPS)
server:
  port: ${NODE_BACKEND_PORT}
  ssl:
    enabled: true
    key-store-type: PEM
    certificate: ${CERT_DIR}/cert.pem
    key: ${CERT_DIR}/key.pem
xray:
  config-path: ${XRAY_DIR}/config.json
  inbound-tag: vless-inbound
  restart-command: systemctl restart xray
  status-command: systemctl is-active xray
node:
  secret: ${NODE_SECRET}
  auth-enabled: true
logging:
  level:
    com.vpn.node: INFO
  file:
    path: ${LOG_DIR}
YMLEOF
  systemctl restart huxiao-node
  ok "节点后端已启用 HTTPS（端口 ${NODE_BACKEND_PORT}）"

  # 自动续期 systemd timer
  cat > /etc/systemd/system/acme-renewal.service <<EOF
[Unit]
Description=acme.sh SSL Certificate Auto Renewal
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=${ACME_HOME}/acme.sh --cron --home ${ACME_HOME}
ExecStartPost=/bin/systemctl restart huxiao-node || true
User=root
EOF

  cat > /etc/systemd/system/acme-renewal.timer <<EOF
[Unit]
Description=acme.sh SSL Certificate Daily Renewal Check

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now acme-renewal.timer 2>/dev/null
  ok "SSL 自动续期定时器已启用（每日凌晨检查）"
}

# ============================================================================
#  配置防火墙
# ============================================================================
setup_firewall() {
  title "7/8  配置防火墙"

  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow ${XRAY_PORT}/tcp   comment "Xray VLESS+REALITY" 2>/dev/null || true
    ufw allow 80/tcp    comment "HTTP (SSL verify)" 2>/dev/null || true
    ufw allow "$NODE_BACKEND_PORT"/tcp comment "Huxiao Node Backend" 2>/dev/null || true
    ok "UFW 防火墙规则已添加"
  elif command -v firewall-cmd &>/dev/null; then
    for p in ${XRAY_PORT} 80 "$NODE_BACKEND_PORT"; do
      firewall-cmd --permanent --add-port="$p"/tcp 2>/dev/null || true
    done
    firewall-cmd --reload 2>/dev/null || true
    ok "Firewalld 防火墙规则已添加"
  else
    warn "未检测到 UFW 或 firewalld，请手动放行端口:"
    warn "  - ${XRAY_PORT}/tcp  (Xray)"
    warn "  - 80/tcp   (HTTP)"
    warn "  - ${NODE_BACKEND_PORT}/tcp (节点后端)"
  fi
}

# ============================================================================
#  保存节点信息到文件
# ============================================================================
save_node_info() {
  local ip
  ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "获取IP失败")
  local pub=${PUBLIC_KEY:-"生成失败"}
  local sid=${SHORT_ID:-"生成失败"}
  local sec=${NODE_SECRET:-"生成失败"}

  cat > "$INSTALL_DIR/node-info.txt" <<EOF
============================================
  虎啸VPN 节点信息
  生成时间: $(date '+%Y-%m-%d %H:%M:%S')
============================================
  服务器地址:   ${ip}
  端口:         ${XRAY_PORT}
  协议:         VLESS + XTLS-Vision + REALITY
  UUID:         ${UUID}
  PublicKey:    ${pub}
  ShortId:      ${sid}
  回落域名:     ${FALLBACK_DOMAIN}
  节点端口:     ${NODE_BACKEND_PORT}
  节点密钥:     ${sec}
  安装目录:     ${INSTALL_DIR}
  日志目录:     ${LOG_DIR}
============================================
EOF
  info "节点信息已保存: $INSTALL_DIR/node-info.txt"
}

# ============================================================================
#  输出安装结果
# ============================================================================
print_result() {
  title "✅ 虎啸VPN 节点服务器安装完成！"

  local ip
  ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "获取IP失败")
  local pub=${PUBLIC_KEY:-"生成失败"}
  local sid=${SHORT_ID:-"生成失败"}
  local sec=${NODE_SECRET:-"生成失败"}

  echo ""
  echo "  ┌─────────────────────────────────────────────┐"
  echo "  │             节点连接信息                      │"
  echo "  ├─────────────────────────────────────────────┤"
  echo "  │  地址:        ${ip}"
  echo "  │  端口:        ${XRAY_PORT}"
  echo "  │  协议:        VLESS + XTLS-Vision + REALITY"
  echo "  │  UUID:        ${UUID}"
  echo "  │  PublicKey:   ${pub}"
  echo "  │  ShortId:     ${sid}"
  echo "  │  回落域名:    ${FALLBACK_DOMAIN}"
  echo "  │  节点后端:    :${NODE_BACKEND_PORT}"
  echo "  │  节点密钥:    ${sec}"
  echo "  └─────────────────────────────────────────────┘"
  echo ""
  echo "  服务管理命令:"
  echo "    systemctl status xray         查看 Xray 状态"
  echo "    systemctl restart xray        重启 Xray"
  echo "    systemctl status huxiao-node  查看节点后端状态"
  echo "    systemctl restart huxiao-node 重启节点后端"
  echo "    systemctl status acme-renewal.timer  查看 SSL 续期状态"
  echo ""

  if [[ -n "$DOMAIN_NAME" ]]; then
    echo "  节点后端 API: https://${DOMAIN_NAME}:${NODE_BACKEND_PORT}/api/node/health"
  else
    echo "  节点后端 API: http://${ip}:${NODE_BACKEND_PORT}/api/node/health"
  fi
  echo ""
  echo "  在主后端 ServerConfig 中添加此节点:"
  echo "    nodeBackendUrl: http://${ip}:${NODE_BACKEND_PORT}"
  echo "    useXrayNode: true"
  echo "    nodeSecret: ${sec}"
  echo ""

  save_node_info
}

# ============================================================================
#  安装流程
# ============================================================================
do_install() {
  echo ""
  echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"
  echo -e "${MAG}          虎啸VPN 节点 — 全新安装${RESET}"
  echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"

  # 自定义安装参数
  echo ""
  echo -e "  ${CYAN}安装参数配置${NC}"
  echo -e "  ${DIM}（直接按 Enter 使用默认值）${NC}"
  echo ""

  echo -n "  Xray 监听端口 [${XRAY_PORT}]: "
  read -r input_port
  if [[ -n "$input_port" ]]; then
    if ! [[ "$input_port" =~ ^[0-9]+$ ]] || [[ "$input_port" -lt 1 || "$input_port" -gt 65535 ]]; then
      error "无效端口号，使用默认值 443"
      XRAY_PORT=443
    else
      XRAY_PORT=$input_port
    fi
  fi

  echo -n "  REALITY 回落域名 [${FALLBACK_DOMAIN}]: "
  read -r input_domain
  if [[ -n "$input_domain" ]]; then
    FALLBACK_DOMAIN=$input_domain
  fi

  info "端口: ${XRAY_PORT}, 回落域名: ${FALLBACK_DOMAIN}"
  echo ""

  local ver
  ver=$(get_latest_xray_version)
  check_env
  enable_bbr
  install_xray "$ver"
  generate_xray_config
  setup_xray_service
  install_java
  setup_node_backend
  setup_ssl
  setup_firewall
  print_result
}

# ============================================================================
#  更新流程
# ============================================================================
do_update() {
  echo ""
  echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"
  echo -e "${MAG}          虎啸VPN 节点 — 更新服务${RESET}"
  echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"

  check_env

  # --- 更新 Xray-core ---
  title "检查 Xray 更新"
  local current_ver latest_ver
  current_ver=$(get_installed_xray_version)
  info "当前版本: $current_ver"
  latest_ver=$(get_latest_xray_version)
  info "最新版本: v${latest_ver}"

  read -r -p "是否更新 Xray-core? [y/N]: " up_xray
  if [[ "$up_xray" =~ ^[Yy]$ ]]; then
    install_xray "$latest_ver"
    if [[ -f "$XRAY_DIR/config.json" ]]; then
      if "$XRAY_BIN" run -test -config "$XRAY_DIR/config.json" 2>&1; then
        ok "现有配置与新版本兼容"
      else
        warn "现有配置与新版本不兼容，如需重新生成配置请全新安装"
      fi
    fi
    systemctl restart xray
    if systemctl is-active --quiet xray; then
      ok "Xray 已更新至 v${latest_ver} 并重启"
    else
      warn "Xray 重启失败: journalctl -u xray -n 30"
    fi
  fi

  # --- 更新节点后端 JAR ---
  title "检查节点后端更新"
  local jar_dst="$INSTALL_DIR/node-backend-1.1.3.jar"
  local jar_src=""
  for p in "./node-backend-1.1.3.jar" "$_SCRIPT_DIR/node-backend-1.1.3.jar" "/root/node-backend-1.1.3.jar"; do
    if [[ -f "$p" ]]; then
      jar_src="$p"
      break
    fi
  done

  if [[ -n "$jar_src" ]]; then
    if [[ ! -f "$jar_dst" ]] || [[ "$(stat -c%s "$jar_src" 2>/dev/null || echo 0)" -ne "$(stat -c%s "$jar_dst" 2>/dev/null || echo 0)" ]]; then
      cp "$jar_src" "$jar_dst"
      systemctl restart huxiao-node
      ok "节点后端 JAR 已更新并重启"
    else
      info "节点后端 JAR 无变化，跳过"
    fi
  else
    info "未找到新 JAR 包，跳过节点后端更新"
  fi

  # --- 更新 SSL 证书 ---
  title "检查 SSL 证书"
  if [[ -f /root/.acme.sh/acme.sh ]]; then
    read -r -p "是否强制续签 SSL 证书? [y/N]: " re_ssl
    if [[ "$re_ssl" =~ ^[Yy]$ ]]; then
      /root/.acme.sh/acme.sh --cron --force 2>&1 && ok "证书续签完成" || warn "证书续签失败"
    fi
  fi
  if [[ -f /etc/systemd/system/acme-renewal.timer ]]; then
    systemctl start acme-renewal.service 2>/dev/null || true
    ok "acme.sh 续期定时器正常运行中"
  fi

  ok "更新完成！"
}

# ============================================================================
#  卸载流程
# ============================================================================
do_uninstall() {
  echo ""
  echo -e "${RED}══════════════════════════════════════════════════════════${RESET}"
  echo -e "${RED}          虎啸VPN 节点 — 卸载${RESET}"
  echo -e "${RED}══════════════════════════════════════════════════════════${RESET}"
  echo ""
  warn "此操作将删除以下内容:"
  echo "  • Xray-core 可执行文件 + 配置目录"
  echo "  • 节点后端程序 + 配置目录"
  echo "  • 所有日志文件"
  echo "  • systemd 服务（xray, huxiao-node, acme-renewal）"
  echo "  • SSL 证书文件"
  echo "  • 防火墙规则"
  echo ""
  read -r -p "确认卸载? 输入 YES 确认: " confirm
  if [[ "$confirm" != "YES" ]]; then
    info "取消卸载"
    return 0
  fi

  title "停止并删除服务"
  for svc in huxiao-node xray acme-renewal.timer acme-renewal; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  done
  rm -f /etc/systemd/system/xray.service
  rm -f /etc/systemd/system/huxiao-node.service
  rm -f /etc/systemd/system/acme-renewal.service
  rm -f /etc/systemd/system/acme-renewal.timer
  systemctl daemon-reload
  ok "服务已删除"

  title "删除文件"
  rm -f "$XRAY_BIN"
  rm -rf "$XRAY_DIR" "$INSTALL_DIR" "$LOG_DIR" /etc/ssl/huxiao
  ok "文件已删除"

  title "清理防火墙规则"
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw delete allow ${XRAY_PORT}/tcp 2>/dev/null || true
    ufw delete allow 80/tcp 2>/dev/null || true
    ufw delete allow "$NODE_BACKEND_PORT"/tcp 2>/dev/null || true
    ok "UFW 规则已清理"
  elif command -v firewall-cmd &>/dev/null; then
    for p in ${XRAY_PORT} 80 "$NODE_BACKEND_PORT"; do
      firewall-cmd --permanent --remove-port="$p"/tcp 2>/dev/null || true
    done
    firewall-cmd --reload 2>/dev/null || true
    ok "Firewalld 规则已清理"
  fi

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${GREEN}  虎啸VPN 节点已完全卸载${RESET}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  info "如需重新安装，直接再次运行此脚本即可"
}

# ============================================================================
#  hx 快捷命令 — 查看节点状态
# ============================================================================
do_hx() {
  echo ""
  echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"
  echo -e "${MAG}          虎啸VPN 节点状态${RESET}"
  echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"
  echo ""

  # Xray 状态
  if systemctl is-active --quiet xray 2>/dev/null; then
    echo -e "  ${GREEN}●${RESET} Xray:        运行中"
  else
    echo -e "  ${RED}●${RESET} Xray:        未运行"
  fi

  # 节点后端状态
  if systemctl is-active --quiet huxiao-node 2>/dev/null; then
    echo -e "  ${GREEN}●${RESET} 节点后端:    运行中 (端口 $NODE_BACKEND_PORT)"
  else
    echo -e "  ${RED}●${RESET} 节点后端:    未运行"
  fi

  # BBR 状态
  local bbr_status
  bbr_status=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "未知")
  if [[ "$bbr_status" == "bbr" ]]; then
    echo -e "  ${GREEN}●${RESET} BBR 加速:    已启用"
  else
    echo -e "  ${YELLOW}●${RESET} BBR 加速:    未启用 ($bbr_status)"
  fi

  # SSL 证书状态
  if [[ -f /etc/ssl/huxiao/cert.pem ]]; then
    local cert_expire
    cert_expire=$(openssl x509 -enddate -noout -in /etc/ssl/huxiao/cert.pem 2>/dev/null | cut -d= -f2 || echo "未知")
    echo -e "  ${GREEN}●${RESET} SSL 证书:    已安装 (到期: $cert_expire)"
  else
    echo -e "  ${YELLOW}●${RESET} SSL 证书:    未安装"
  fi

  # 节点信息
  if [[ -f "$INSTALL_DIR/node-info.txt" ]]; then
    local ip
    ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "获取IP失败")
    echo ""
    echo "  服务器 IP: $ip"
    echo "  配置文件: $XRAY_DIR/config.json"
    echo "  节点信息: $INSTALL_DIR/node-info.txt"
  fi

  echo ""
  echo "  快捷操作:"
  echo "    systemctl restart xray         重启 Xray"
  echo "    systemctl restart huxiao-node  重启节点后端"
  echo ""
}

# ============================================================================
#  xray 命令 — 管理 Xray 服务
# ============================================================================
do_xray() {
  local action="${1:-status}"

  case "$action" in
    start)
      echo -e "${GREEN}启动 Xray 服务...${RESET}"
      systemctl start xray
      sleep 1
      if systemctl is-active --quiet xray; then
        echo -e "${GREEN}●${RESET} Xray 已启动"
      else
        echo -e "${RED}●${RESET} Xray 启动失败"
        journalctl -u xray -n 10 --no-pager
      fi
      ;;
    stop)
      echo -e "${YELLOW}停止 Xray 服务...${RESET}"
      systemctl stop xray
      echo -e "${GREEN}●${RESET} Xray 已停止"
      ;;
    restart)
      echo -e "${YELLOW}重启 Xray 服务...${RESET}"
      systemctl restart xray
      sleep 1
      if systemctl is-active --quiet xray; then
        echo -e "${GREEN}●${RESET} Xray 已重启"
      else
        echo -e "${RED}●${RESET} Xray 重启失败"
        journalctl -u xray -n 10 --no-pager
      fi
      ;;
    status)
      echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"
      echo -e "${MAG}          Xray 服务状态${RESET}"
      echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"
      echo ""
      systemctl status xray --no-pager 2>/dev/null || echo "Xray 服务未安装"
      echo ""
      if [[ -f "$XRAY_DIR/config.json" ]]; then
        echo "  配置文件: $XRAY_DIR/config.json"
        local installed
        installed=$(get_installed_xray_version)
        echo "  Xray 版本: $installed"
      else
        echo -e "  ${YELLOW}未找到 Xray 配置，请先安装${RESET}"
      fi
      ;;
    *)
      echo "用法: bash install-xray-node.sh xray [start|stop|restart|status]"
      echo ""
      echo "  start   - 启动 Xray"
      echo "  stop    - 停止 Xray"
      echo "  restart - 重启 Xray"
      echo "  status  - 查看状态（默认）"
      ;;
  esac
}

# ============================================================================
#  addnode 命令 — 显示当前节点信息
# ============================================================================
do_addnode() {
  echo ""
  echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"
  echo -e "${MAG}          虎啸VPN 节点信息${RESET}"
  echo -e "${MAG}══════════════════════════════════════════════════════════${RESET}"
  echo ""

  if [[ ! -f "$INSTALL_DIR/node-info.txt" ]]; then
    echo -e "  ${YELLOW}未找到节点信息，请先安装节点${RESET}"
    echo ""
    return 1
  fi

  local ip uuid pubkey short_id secret
  ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "获取IP失败")

  # 从 node-info.txt 提取信息
  uuid=$(grep "UUID:" "$INSTALL_DIR/node-info.txt" 2>/dev/null | awk '{print $NF}' || echo "")
  pubkey=$(grep "PublicKey:" "$INSTALL_DIR/node-info.txt" 2>/dev/null | awk '{print $NF}' || echo "")
  short_id=$(grep "ShortId:" "$INSTALL_DIR/node-info.txt" 2>/dev/null | awk '{print $NF}' || echo "")
  secret=$(grep "节点密钥:" "$INSTALL_DIR/node-info.txt" 2>/dev/null | awk '{print $NF}' || echo "")

  echo "  ┌─────────────────────────────────────────────┐"
  echo "  │             节点连接信息                      │"
  echo "  ├─────────────────────────────────────────────┤"
  echo "  │  地址:        $ip"
  echo "  │  端口:        ${XRAY_PORT}"
  echo "  │  协议:        VLESS + XTLS-Vision + REALITY"
  echo "  │  UUID:        $uuid"
  echo "  │  PublicKey:   $pubkey"
  echo "  │  ShortId:     $short_id"
  echo "  │  回落域名:    $FALLBACK_DOMAIN"
  echo "  │  节点后端:    :$NODE_BACKEND_PORT"
  echo "  │  节点密钥:    $secret"
  echo "  └─────────────────────────────────────────────┘"
  echo ""
  echo "  安装时间: $(grep "生成时间:" "$INSTALL_DIR/node-info.txt" 2>/dev/null | sed 's/.*生成时间: //' || echo "未知")"
  echo ""
}

# ============================================================================
#  主菜单
# ============================================================================
show_menu() {
  while true; do
    clear 2>/dev/null || true
    echo ""
    echo -e "${MAG}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${MAG}║             虎啸VPN 节点服务器管理脚本                   ║${RESET}"
    echo -e "${MAG}╠══════════════════════════════════════════════════════════╣${RESET}"
    printf "${MAG}║${RESET}  Xray-core: 自动获取最新版本 %28s${MAG}║${RESET}\n" ""
    local iv; iv=$(get_installed_xray_version)
    printf "${MAG}║${RESET}  已安装: %-44s${MAG}║${RESET}\n" "Xray ${iv}"
    echo -e "${MAG}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo "  请选择操作（需 root 权限）:"
    echo ""
    echo -e "    ${GREEN}1${RESET}) 全新安装  — 安装 Xray + 节点后端 + SSL 证书"
    echo -e "    ${YELLOW}2${RESET}) 更新服务  — 升级 Xray / 节点后端 / 续签证书"
    echo -e "    ${RED}3${RESET}) 卸载删除  — 停止服务并清除所有文件"
    echo -e "    ${CYAN}4${RESET}) 退出"
    echo ""
    read -r -p "  请输入数字 [1-4]: " choice
    echo ""
    case "$choice" in
      1)
        do_install
        pause
        ;;
      2)
        do_update
        pause
        ;;
      3)
        do_uninstall
        pause
        ;;
      4)
        info "再见！"
        echo ""
        exit 0
        ;;
      *)
        warn "无效选择，请输入 1-4"
        sleep 1
        ;;
    esac
  done
}

# ============================================================================
#  启动入口（支持 hx / xray 参数快速操作）
# ============================================================================
  case "${1:-}" in
  hx)
    do_hx
    exit 0
    ;;
  xray)
    do_xray "${2:-status}"
    exit 0
    ;;
  addnode)
    do_addnode
    exit 0
    ;;
esac
show_menu