# 虎啸VPN (HuxiaoVPN)

虎啸VPN是一个完整的VPN解决方案，包含后端服务器节点和客户端管理工具。

## 🌟 特性

- 🚀 **高性能**: 基于Xray和Node.js的高性能VPN服务器
- 🔒 **安全**: 多层加密保护，支持多种协议
- 🌍 **全球节点**: 支持全球多个服务器节点
- 📱 **多平台**: 支持Android、Windows等平台
- 🎯 **易部署**: 一键部署脚本，简化安装流程

## 📦 包含内容

### 安装脚本
- `install-backend.sh` - 后端服务器安装脚本 (v3.2)
- `install-xray-node.sh` - Xray节点安装脚本
- `update-node.sh` - 节点更新脚本

### 应用程序
- `notification-server-1.3.6.jar` - VPN后端服务器主程序
- `node-backend-1.1.3.jar` - VPN节点管理后端
- `mimo.exe` - VPN客户端程序

### 配置文件
- `脚本使用报告.txt` - 脚本使用说明
- `节点信息.txt` - 节点配置信息

## 🛠️ 快速开始

### 1. 下载最新版本

```bash
# 下载脚本
wget -O install-backend.sh https://raw.githubusercontent.com/yourusername/huxiao-vpn/vpn/install-backend.sh
wget -O install-xray-node.sh https://raw.githubusercontent.com/yourusername/huxiao-vpn/vpn/install-xray-node.sh
```

### 2. 安装后端服务器

```bash
# 给脚本执行权限
chmod +x install-backend.sh install-backend-fixed.sh install-xray-node.sh

# 安装后端服务器 
sudo bash install-backend.sh
```

### 3. 安装Xray节点

```bash
# 安装Xray节点
sudo bash install-xray-node.sh
```

## 📋 安装脚本使用说明

### 后端服务器安装脚本

```bash
# 全新安装
sudo bash install-backend.sh

# SSL证书管理
sudo bash install-backend.sh --ssl

# 域名替换
sudo bash install-backend.sh --domain

# 备份系统
sudo bash install-backend.sh --backup

# 查看证书信息
sudo bash install-backend.sh --cert-info
```

### Xray节点安装脚本

```bash
# 安装Xray节点
sudo bash install-xray-node.sh

# 更新Xray节点
sudo bash update-node.sh
```

## 🔧 系统要求

- **操作系统**: Ubuntu 18.04+, CentOS 7+, Debian 9+
- **内存**: 最少 512MB，推荐 2GB+
- **存储**: 最少 1GB 可用空间
- **网络**: 需要稳定的互联网连接

## 📁 项目结构

```
huxiao-vpn/
├── README.md                    # 项目说明
├── install-backend.sh            # 后端安装脚本 (v3.2)
├── install-xray-node.sh         # Xray节点安装脚本
├── update-node.sh               # 节点更新脚本
├── notification-server-1.3.6.jar # 后端服务器程序
├── node-backend-1.1.3.jar       # 节点管理程序
├── mimo.exe                     # VPN客户端
├── 脚本使用报告.txt              # 使用说明
└── 节点信息.txt                  # 节点配置
```

## 🛡️ 安全性

- 所有脚本都包含安全检查和错误处理
- 支持SSL证书配置 (Let's Encrypt/自签名)
- 密码和密钥的安全处理
- 自动清理临时文件和敏感信息

## 🚨 注意事项

1. **权限要求**: 安装脚本需要root权限
2. **端口冲突**: 确保端口80、443、8082等未被占用
3. **防火墙**: 需要开放相应的端口
4. **域名**: 使用Let's Encrypt需要域名解析

## 📞 支持

如果遇到问题，请检查：

1. 系统日志: `journalctl -u notification-server`
2. 应用日志: `/opt/notification-server/logs/application.log`
3. 脚本输出: 查看安装过程中的错误信息

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 🔄 版本历史

- **v3.2**: 原始版本，功能完整但存在一些兼容性问题

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📝 更新日志

### 修复版 v3.2 (2026-06-12)
- ✅ 修复MySQL连接超时问题
- ✅ 改进临时文件安全性
- ✅ 修复Java路径硬编码问题
- ✅ 增加包管理器兼容性 (dnf、pacman)
- ✅ 添加网络操作重试机制
- ✅ 优化变量作用域，避免污染
- ✅ 实现配置文件生成原子性
- ✅ 增加详细错误诊断信息
- ✅ 实现安装回滚机制

---

**注意**: 本项目仅供学习和研究使用，请遵守当地法律法规。
