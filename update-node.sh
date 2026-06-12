#!/bin/bash
# 节点服务更新脚本 - 在服务器上运行
# 用法: 将 node-backend-1.1.1.jar 放到同目录后执行: sudo bash update-node.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAR_NAME="node-backend-1.1.3.jar"
INSTALL_DIR="/opt/huxiao-node"
BACKUP_DIR="/opt/huxiao-node/backup"
SERVICE_NAME="huxiao-node"

echo "===== 虎啸VPN 节点服务更新 ====="
echo ""

# 查找本地 JAR（优先级：同目录 > /home/ubuntu/ > /root/）
echo "[1/6] 查找新版本 JAR..."
SRC_JAR=""
if [ -f "${SCRIPT_DIR}/${JAR_NAME}" ]; then
    SRC_JAR="${SCRIPT_DIR}/${JAR_NAME}"
    echo "找到: ${SRC_JAR}"
elif [ -f "/home/ubuntu/${JAR_NAME}" ]; then
    SRC_JAR="/home/ubuntu/${JAR_NAME}"
    echo "找到: ${SRC_JAR}"
elif [ -f "/root/${JAR_NAME}" ]; then
    SRC_JAR="/root/${JAR_NAME}"
    echo "找到: ${SRC_JAR}"
fi

if [ -z "${SRC_JAR}" ]; then
    echo "错误: 未找到 ${JAR_NAME}，请将 JAR 文件放到以下任一位置："
    echo "  1. 脚本同目录 (${SCRIPT_DIR}/)"
    echo "  2. /home/ubuntu/"
    echo "  3. /root/"
    exit 1
fi

# 停止服务
echo ""
echo "[2/6] 停止服务..."
if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
    systemctl stop ${SERVICE_NAME}
    echo "服务已停止"
else
    echo "服务未运行，跳过停止"
fi

# 备份旧 JAR
echo ""
echo "[3/6] 备份旧版本..."
mkdir -p "${BACKUP_DIR}"
if [ -f "${INSTALL_DIR}/${JAR_NAME}" ] || [ -f "${INSTALL_DIR}"/node-backend-*.jar ]; then
    OLD_JAR=$(ls -t "${INSTALL_DIR}"/node-backend-*.jar 2>/dev/null | head -1)
    if [ -n "${OLD_JAR}" ]; then
        BACKUP_FILE="${BACKUP_DIR}/$(basename "${OLD_JAR}").$(date +%Y%m%d%H%M%S)"
        cp "${OLD_JAR}" "${BACKUP_FILE}"
        if [ -f "${BACKUP_FILE}" ]; then
            echo "备份完成 -> ${BACKUP_FILE}"
        else
            echo "错误: 备份失败"
            exit 1
        fi
    else
        echo "未找到旧版本，跳过备份"
    fi
else
    echo "未找到旧版本，跳过备份"
fi

# 替换 JAR
echo ""
echo "[4/6] 安装新版本..."
mkdir -p "${INSTALL_DIR}"
cp "${SRC_JAR}" "${INSTALL_DIR}/${JAR_NAME}"
chmod 640 "${INSTALL_DIR}/${JAR_NAME}"
echo "安装完成: ${INSTALL_DIR}/${JAR_NAME}"

# 启动服务
echo ""
echo "[5/6] 启动服务..."
systemctl start "${SERVICE_NAME}"
sleep 3

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "服务启动成功!"
else
    echo "警告: 服务启动失败，请检查日志:"
    echo "  journalctl -u ${SERVICE_NAME} -n 30"
fi

# 清理
echo ""
echo "[6/6] 完成"
echo "===== 更新完成 ====="
