#!/bin/bash
# ============================================================
#  hx - 虎啸VPN 节点管理命令
#  用法: hx <命令> [选项]
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

XRAY_SERVICE="xray"
NODE_SERVICE="huxiao-node"
XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/usr/local/etc/xray"
NODE_DIR="/opt/huxiao-node"

show_status() {
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}           虎啸VPN 节点状态${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    
    printf "  Xray 服务:     "
    if systemctl is-active --quiet "$XRAY_SERVICE" 2>/dev/null; then
        echo -e "${GREEN}运行中${NC}"
    else
        echo -e "${RED}已停止${NC}"
    fi
    
    printf "  节点后端:      "
    if systemctl is-active --quiet "$NODE_SERVICE" 2>/dev/null; then
        echo -e "${GREEN}运行中${NC}"
    else
        echo -e "${RED}已停止${NC}"
    fi
    
    printf "  BBR 加速:      "
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    if [[ "$cc" == "bbr" ]]; then
        echo -e "${GREEN}已启用${NC}"
    else
        echo -e "${YELLOW}未启用 ($cc)${NC}"
    fi
    
    if [[ -f "$XRAY_BIN" ]]; then
        local ver=$("$XRAY_BIN" version 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1)
        echo "  Xray 版本:     v${ver:-未知}"
    fi
    
    echo ""
    echo -e "${CYAN}  监听端口:${NC}"
    ss -tlnp 2>/dev/null | grep -E ":(443|80|9080) " | awk '{print "    "$4}' | sed 's/.*://' | sort -u | while read port; do
        echo "    端口: $port"
    done
    
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

show_usage() {
    echo -e "${CYAN}虎啸VPN 节点管理命令${NC}"
    echo ""
    echo "用法: hx <命令> [选项]"
    echo ""
    echo "服务管理:"
    echo "  start          启动所有服务"
    echo "  stop           停止所有服务"
    echo "  restart        重启所有服务"
    echo "  status         查看服务状态"
    echo "  logs [服务]    查看日志 (xray|node)"
    echo ""
    echo "Xray 管理:"
    echo "  xray start     启动 Xray"
    echo "  xray stop      停止 Xray"
    echo "  xray restart   重启 Xray"
    echo "  xray status    查看 Xray 状态"
    echo "  xray test      测试配置文件"
    echo "  xray config    编辑配置文件"
    echo ""
    echo "节点后端管理:"
    echo "  node start     启动节点后端"
    echo "  node stop      停止节点后端"
    echo "  node restart   重启节点后端"
    echo "  node status    查看节点后端状态"
    echo "  node logs      查看节点后端日志"
    echo ""
    echo "流量统计:"
    echo "  traffic        查看所有用户流量"
    echo "  traffic <邮箱> 查看指定用户流量"
    echo ""
    echo "系统管理:"
    echo "  update         更新服务"
    echo "  uninstall      卸载服务"
    echo "  bbr            查看 BBR 状态"
    echo "  config         查看配置信息"
    echo "  help           显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  hx status      # 查看服务状态"
    echo "  hx restart     # 重启所有服务"
    echo "  hx logs node   # 查看节点后端日志"
    echo "  hx traffic     # 查看流量统计"
}

start_services() {
    echo -e "${GREEN}启动所有服务...${NC}"
    systemctl start "$XRAY_SERVICE" 2>/dev/null && echo "  ✓ Xray 已启动" || echo "  ✗ Xray 启动失败"
    systemctl start "$NODE_SERVICE" 2>/dev/null && echo "  ✓ 节点后端已启动" || echo "  ✗ 节点后端启动失败"
}

stop_services() {
    echo -e "${YELLOW}停止所有服务...${NC}"
    systemctl stop "$NODE_SERVICE" 2>/dev/null && echo "  ✓ 节点后端已停止" || echo "  ✗ 节点后端停止失败"
    systemctl stop "$XRAY_SERVICE" 2>/dev/null && echo "  ✓ Xray 已停止" || echo "  ✗ Xray 停止失败"
}

restart_services() {
    echo -e "${GREEN}重启所有服务...${NC}"
    systemctl restart "$XRAY_SERVICE" 2>/dev/null && echo "  ✓ Xray 已重启" || echo "  ✗ Xray 重启失败"
    systemctl restart "$NODE_SERVICE" 2>/dev/null && echo "  ✓ 节点后端已重启" || echo "  ✗ 节点后端重启失败"
}

show_logs() {
    local service="${1:-xray}"
    case "$service" in
        xray|Xray)
            echo -e "${CYAN}Xray 日志 (最近50行):${NC}"
            journalctl -u "$XRAY_SERVICE" -n 50 --no-pager 2>/dev/null || echo "无法获取日志"
            ;;
        node|Node|huxiao-node)
            echo -e "${CYAN}节点后端日志 (最近50行):${NC}"
            journalctl -u "$NODE_SERVICE" -n 50 --no-pager 2>/dev/null || echo "无法获取日志"
            ;;
        *)
            echo "未知服务: $service"
            echo "可用服务: xray, node"
            ;;
    esac
}

xray_command() {
    local cmd="${1:-status}"
    case "$cmd" in
        start)
            systemctl start "$XRAY_SERVICE" && echo "✓ Xray 已启动" || echo "✗ 启动失败"
            ;;
        stop)
            systemctl stop "$XRAY_SERVICE" && echo "✓ Xray 已停止" || echo "✗ 停止失败"
            ;;
        restart)
            systemctl restart "$XRAY_SERVICE" && echo "✓ Xray 已重启" || echo "✗ 重启失败"
            ;;
        status)
            systemctl status "$XRAY_SERVICE" --no-pager
            ;;
        test)
            echo "测试配置文件..."
            "$XRAY_BIN" run -test -config "$XRAY_DIR/config.json" && echo "✓ 配置文件正确" || echo "✗ 配置文件错误"
            ;;
        config)
            if [[ -f "$XRAY_DIR/config.json" ]]; then
                ${EDITOR:-nano} "$XRAY_DIR/config.json"
            else
                echo "配置文件不存在: $XRAY_DIR/config.json"
            fi
            ;;
        *)
            echo "用法: hx xray {start|stop|restart|status|test|config}"
            ;;
    esac
}

node_command() {
    local cmd="${1:-status}"
    case "$cmd" in
        start)
            systemctl start "$NODE_SERVICE" && echo "✓ 节点后端已启动" || echo "✗ 启动失败"
            ;;
        stop)
            systemctl stop "$NODE_SERVICE" && echo "✓ 节点后端已停止" || echo "✗ 停止失败"
            ;;
        restart)
            systemctl restart "$NODE_SERVICE" && echo "✓ 节点后端已重启" || echo "✗ 重启失败"
            ;;
        status)
            systemctl status "$NODE_SERVICE" --no-pager
            ;;
        logs|log)
            journalctl -u "$NODE_SERVICE" -n 50 --no-pager
            ;;
        *)
            echo "用法: hx node {start|stop|restart|status|logs}"
            ;;
    esac
}

show_traffic() {
    local email="${1}"
    local port=$(grep -oP 'port:\s*\K\d+' "$NODE_DIR/application.yml" 2>/dev/null || echo "9080")
    
    if [[ -n "$email" ]]; then
        echo -e "${CYAN}用户流量统计: $email${NC}"
        curl -s "http://localhost:$port/api/node/traffic/get?email=$email" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "无法获取数据"
    else
        echo -e "${CYAN}所有用户流量统计:${NC}"
        curl -s "http://localhost:$port/api/node/traffic/all" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "无法获取数据"
    fi
}

show_config() {
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}           节点配置信息${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    
    if [[ -f "$NODE_DIR/node-info.txt" ]]; then
        cat "$NODE_DIR/node-info.txt"
    else
        echo "节点信息文件不存在"
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

show_bbr() {
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}           BBR TCP 加速状态${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    
    echo ""
    echo "  拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '未知')"
    echo "  队列调度算法: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo '未知')"
    echo ""
    
    if [[ -f /etc/sysctl.d/99-huxiao-bbr.conf ]]; then
        echo -e "  ${GREEN}BBR 配置文件: 已存在${NC}"
    else
        echo -e "  ${YELLOW}BBR 配置文件: 不存在${NC}"
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

do_update() {
    echo -e "${CYAN}正在检查更新...${NC}"
    echo ""
    echo "  选项:"
    echo "    1) 更新 Xray-core"
    echo "    2) 更新节点后端 JAR"
    echo "    3) 续签 SSL 证书"
    echo "    4) 配置 BBR 加速"
    echo "    5) 更新所有"
    echo ""
    read -r -p "  请选择 [1-5]: " choice
    
    case "$choice" in
        1|2|5)
            if [[ -f "/root/install-xray-node.sh" ]]; then
                bash /root/install-xray-node.sh
            else
                echo "未找到安装脚本"
            fi
            ;;
        3)
            if [[ -f "/root/.acme.sh/acme.sh" ]]; then
                /root/.acme.sh/acme.sh --cron --force
            else
                echo "未安装 acme.sh"
            fi
            ;;
        4)
            sysctl -p /etc/sysctl.d/99-huxiao-bbr.conf 2>/dev/null
            echo "BBR 配置已更新"
            ;;
        *)
            echo "无效选择"
            ;;
    esac
}

do_uninstall() {
    echo -e "${RED}警告: 此操作将完全卸载虎啸VPN节点!${NC}"
    echo ""
    echo "  将删除以下内容:"
    echo "    - Xray-core 可执行文件 + 配置"
    echo "    - 节点后端程序 + 配置"
    echo "    - systemd 服务"
    echo "    - SSL 证书"
    echo "    - 防火墙规则"
    echo "    - BBR 配置"
    echo "    - hx 管理命令"
    echo "    - huxiao-node 用户"
    echo ""
    read -r -p "  确认卸载? (输入 YES): " confirm
    if [[ "$confirm" != "YES" ]]; then
        echo "取消卸载"
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}开始卸载...${NC}"
    
    systemctl stop huxiao-node 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true
    systemctl disable huxiao-node 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    
    rm -f /etc/systemd/system/xray.service
    rm -f /etc/systemd/system/huxiao-node.service
    rm -f /etc/systemd/system/acme-renewal.service
    rm -f /etc/systemd/system/acme-renewal.timer
    systemctl daemon-reload
    
    rm -f /usr/local/bin/xray
    rm -rf /usr/local/etc/xray
    rm -rf /opt/huxiao-node
    rm -rf /var/log/huxiao
    rm -f /usr/local/bin/hx
    rm -f /etc/sysctl.d/99-huxiao-bbr.conf
    rm -rf /etc/ssl/huxiao
    
    userdel -r huxiao-node 2>/dev/null || true
    rm -f /etc/sudoers.d/huxiao-node
    
    sysctl -w net.ipv4.tcp_congestion_control=cubic 2>/dev/null || true
    sysctl -w net.core.default_qdisc=pfifo_fast 2>/dev/null || true
    
    if command -v ufw &>/dev/null; then
        ufw delete allow 443/tcp 2>/dev/null || true
        ufw delete allow 80/tcp 2>/dev/null || true
        ufw delete allow 9080/tcp 2>/dev/null || true
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --remove-port=443/tcp 2>/dev/null || true
        firewall-cmd --permanent --remove-port=80/tcp 2>/dev/null || true
        firewall-cmd --permanent --remove-port=9080/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    fi
    
    rm -rf /root/.acme.sh
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  虎啸VPN 节点已完全卸载${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

case "${1:-help}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status|st)
        show_status
        ;;
    logs|log)
        show_logs "$2"
        ;;
    xray)
        xray_command "$2"
        ;;
    node)
        node_command "$2"
        ;;
    traffic|tr)
        show_traffic "$2"
        ;;
    config|conf)
        show_config
        ;;
    bbr)
        show_bbr
        ;;
    update|up)
        do_update
        ;;
    uninstall|rm)
        do_uninstall
        ;;
    help|--help|-h|"")
        show_usage
        ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        echo "使用 'hx help' 查看帮助"
        exit 1
        ;;
esac
