# 虎啸VPN 安装指南

## 📥 下载脚本

### 方法一：直接下载
```bash
# 下载安装脚本
wget -O install-backend.sh https://raw.githubusercontent.com/yourusername/huxiao-vpn/vpn/install-backend.sh
wget -O install-backend-fixed.sh https://raw.githubusercontent.com/yourusername/huxiao-vpn/vpn/install-backend-fixed.sh
wget -O install-xray-node.sh https://raw.githubusercontent.com/yourusername/huxiao-vpn/vpn/install-xray-node.sh
```

### 方法二：克隆整个项目
```bash
# 克隆VPN分支
git clone -b vpn https://github.com/yourusername/huxiao-vpn.git
cd huxiao-vpn
```

## 🚀 快速安装

### 1. 后端服务器安装 (推荐修复版)

```bash
# 赋予执行权限
chmod +x install-backend-fixed.sh

# 运行安装脚本
sudo bash install-backend-fixed.sh
```

**安装选项：**
- 数据库配置 (MySQL/MariaDB)
- 管理员账号设置
- SSL证书选择 (Let's Encrypt/自签名/HTTP)
- 加密密钥生成

### 2. Xray节点安装

```bash
# 赋予执行权限
chmod +x install-xray-node.sh

# 运行安装脚本
sudo bash install-xray-node.sh
```

## 📋 安装流程详解

### 后端服务器安装步骤

1. **系统依赖检查**
   - 自动检查和安装必需工具
   - 检查Java环境 (Java 17+)
   - 检查数据库服务

2. **配置收集**
   - 数据库用户名和密码
   - 管理员账号信息
   - SSL证书配置
   - 加密密钥设置

3. **文件部署**
   - 复制JAR文件到安装目录
   - 生成配置文件
   - 设置SSL证书

4. **数据库初始化**
   - 创建数据库和表结构
   - 配置用户权限
   - 初始化管理员账号

5. **服务安装**
   - 创建systemd服务
   - 启动并验证服务
   - 开放防火墙端口

### Xray节点安装步骤

1. **环境准备**
   - 安装基础依赖
   - 配置系统参数

2. **Xray安装**
   - 下载Xray程序
   - 配置节点信息
   - 生成配置文件

3. **服务配置**
   - 创建systemd服务
   - 启动并验证
   - 配置防火墙

## 🔧 配置说明

### 后端服务器配置

主要配置文件位置：
- `/opt/notification-server/application.yml` - 主配置文件
- `/opt/notification-server/env.conf` - 环境变量
- `/opt/notification-server/keystore.p12` - SSL证书

### Xray节点配置

配置文件位置：
- `/etc/xray/config.json` - Xray配置
- `/opt/xray-node/config.json` - 节点配置

## 🌐 访问地址

安装完成后可通过以下地址访问：

### 后端管理界面
- **HTTP模式**: `http://服务器IP:8082/admin`
- **HTTPS模式**: `https://域名/admin`

### 服务状态检查
```bash
# 查看服务状态
systemctl status notification-server
systemctl status xray-node

# 查看服务日志
journalctl -u notification-server -f
journalctl -u xray-node -f
```

## 🛠️ 常用命令

### 服务管理
```bash
# 启动服务
systemctl start notification-server
systemctl start xray-node

# 停止服务
systemctl stop notification-server
systemctl stop xray-node

# 重启服务
systemctl restart notification-server
systemctl restart xray-node

# 开机自启
systemctl enable notification-server
systemctl enable xray-node
```

### SSL证书管理
```bash
# 重新申请SSL证书
sudo bash install-backend.sh --ssl

# 查看证书信息
sudo bash install-backend.sh --cert-info
```

### 备份和恢复
```bash
# 备份系统
sudo bash install-backend.sh --backup

# 域名更换
sudo bash install-backend.sh --domain
```

## 🔍 故障排除

### 常见问题

1. **服务无法启动**
   ```bash
   # 检查日志
   journalctl -u notification-server -n 50
   tail -f /opt/notification-server/logs/application.log
   ```

2. **数据库连接失败**
   ```bash
   # 检查MySQL状态
   systemctl status mysql
   systemctl status mariadb
   
   # 测试连接
   mysql -u root -p
   ```

3. **端口被占用**
   ```bash
   # 检查端口占用
   netstat -tlnp | grep :443
   netstat -tlnp | grep :8082
   
   # 查看服务状态
   ps aux | grep java
   ```

4. **SSL证书问题**
   ```bash
   # 检查证书文件
   ls -la /opt/notification-server/keystore.p12
   
   # 验证证书
   openssl pkcs12 -in keystore.p12 -nokeys -info
   ```

### 日志文件位置

- **应用日志**: `/opt/notification-server/logs/application.log`
- **系统日志**: `/var/log/syslog`
- **Xray日志**: `/var/log/xray/access.log` 和 `/var/log/xray/error.log`

## 📊 性能优化

### 系统优化
```bash
# 增加文件描述符限制
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# 优化内核参数
echo "net.core.somaxconn = 65536" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65536" >> /etc/sysctl.conf
sysctl -p
```

### JVM优化
```yaml
# 在application.yml中调整JVM参数
server:
  tomcat:
    max-threads: 200
    accept-count: 100
```

## 🔄 更新和维护

### 更新程序
```bash
# 更新后端程序
sudo cp new-notification-server.jar /opt/notification-server/
systemctl restart notification-server

# 更新Xray
sudo bash update-node.sh
```

### 定期维护
```bash
# 清理日志
find /var/log -name "*.log" -mtime +7 -delete

# 备份数据库
mysqldump -u root -p notification_db > backup.sql

# 更新证书 (Let's Encrypt)
certbot renew
```

---

**注意**: 安装和使用前请确保符合当地法律法规，仅供学习和研究使用。