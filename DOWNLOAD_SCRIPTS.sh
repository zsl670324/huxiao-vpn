#!/bin/bash

# 虎啸VPN下载脚本
# 用于快速下载VPN安装脚本

set -e

echo "🚀 虎啸VPN 安装脚本下载工具"
echo "=================================="

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 默认GitHub用户名（请替换为你的实际用户名）
GITHUB_USER="你的GitHub用户名"
GITHUB_REPO="huxiao-vpn"
BRANCH="vpn"

# 下载函数
download_file() {
    local file="$1"
    local url="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/${file}"
    
    echo -e "${YELLOW}下载 ${file}...${NC}"
    
    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$file" || {
            echo -e "${RED}❌ 下载失败: $url${NC}"
            return 1
        }
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$file" || {
            echo -e "${RED}❌ 下载失败: $url${NC}"
            return 1
        }
    else
        echo -e "${RED}❌ 错误: 需要 curl 或 wget${NC}"
        return 1
    fi
    
    chmod +x "$file"
    echo -e "${GREEN}✅ ${file} 下载完成${NC}"
}

# 检查GitHub用户名
if [ "$GITHUB_USER" = "你的GitHub用户名" ]; then
    echo -e "${YELLOW}⚠️  请修改脚本中的 GITHUB_USER 变量为你的GitHub用户名${NC}"
    echo -e "${YELLOW}或者直接运行下面的命令下载：${NC}"
    echo ""
    echo "curl -fsSL https://raw.githubusercontent.com/你的用户名/huxiao-vpn/vpn/install-backend-fixed.sh -O"
    echo "curl -fsSL https://raw.githubusercontent.com/你的用户名/huxiao-vpn/vpn/install-xray-node.sh -O"
    echo ""
    read -p "是否继续使用默认配置? (y/N): " continue_choice
    if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
        echo "请先编辑脚本中的 GITHUB_USER 变量"
        exit 1
    fi
fi

# 创建下载目录
DOWNLOAD_DIR="${PWD}/huxiao-vpn-scripts"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

echo -e "${GREEN}📁 下载目录: $DOWNLOAD_DIR${NC}"
echo ""

# 选择下载模式
echo "请选择下载模式:"
echo "1) 仅下载核心安装脚本"
echo "2) 下载所有文档和脚本"
echo "3) 自定义选择文件"
echo "4) 显示下载链接"
echo ""
read -p "请选择 [1-4]: " choice

case $choice in
    1)
        echo -e "${GREEN}📦 下载核心安装脚本...${NC}"
        download_file "install-backend-fixed.sh"
        download_file "install-backend.sh"
        download_file "install-xray-node.sh"
        download_file "update-node.sh"
        ;;
    2)
        echo -e "${GREEN}📦 下载完整包...${NC}"
        download_file "install-backend-fixed.sh"
        download_file "install-backend.sh"
        download_file "install-xray-node.sh"
        download_file "update-node.sh"
        download_file "README.md"
        download_file "INSTALL.md"
        download_file "CHANGELOG.md"
        download_file "LICENSE"
        ;;
    3)
        echo -e "${YELLOW}可用文件列表:${NC}"
        echo "1) install-backend-fixed.sh (推荐)"
        echo "2) install-backend.sh"
        echo "3) install-xray-node.sh"
        echo "4) update-node.sh"
        echo "5) README.md"
        echo "6) INSTALL.md"
        echo "7) CHANGELOG.md"
        echo "8) LICENSE"
        echo ""
        
        read -p "请输入要下载的文件编号 (多文件用空格分隔): " file_numbers
        
        for num in $file_numbers; do
            case $num in
                1) download_file "install-backend-fixed.sh" ;;
                2) download_file "install-backend.sh" ;;
                3) download_file "install-xray-node.sh" ;;
                4) download_file "update-node.sh" ;;
                5) download_file "README.md" ;;
                6) download_file "INSTALL.md" ;;
                7) download_file "CHANGELOG.md" ;;
                8) download_file "LICENSE" ;;
                *) echo -e "${RED}❌ 无效编号: $num${NC}" ;;
            esac
        done
        ;;
    4)
        echo -e "${YELLOW}🔗 下载链接:${NC}"
        echo ""
        echo "核心安装脚本:"
        echo "  install-backend-fixed.sh: https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/install-backend-fixed.sh"
        echo "  install-backend.sh: https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/install-backend.sh"
        echo "  install-xray-node.sh: https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/install-xray-node.sh"
        echo "  update-node.sh: https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/update-node.sh"
        echo ""
        echo "文档:"
        echo "  README.md: https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/README.md"
        echo "  INSTALL.md: https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/INSTALL.md"
        echo "  CHANGELOG.md: https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/CHANGELOG.md"
        echo "  LICENSE: https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/LICENSE"
        echo ""
        echo "完整仓库克隆:"
        echo "  git clone -b vpn https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
        ;;
    *)
        echo -e "${RED}❌ 无效选择${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}🎉 下载完成!${NC}"
echo ""
echo -e "${YELLOW}使用说明:${NC}"
echo "1. 进入下载目录: cd $DOWNLOAD_DIR"
echo "2. 给脚本执行权限: chmod +x *.sh"
echo "3. 运行安装脚本: sudo bash install-backend-fixed.sh"
echo ""
echo -e "${YELLOW}📖 更多信息请查看 README.md 和 INSTALL.md${NC}"
echo ""
echo -e "${CYAN}项目地址: https://github.com/${GITHUB_USER}/${GITHUB_REPO}/tree/${BRANCH}${NC}"