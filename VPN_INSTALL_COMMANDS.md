# 虎啸VPN 一键安装命令

## 🚀 快速下载安装脚本

### 方法1：使用提供的下载脚本（推荐）
```bash
# 下载安装脚本
wget https://raw.githubusercontent.com/你的用户名/huxiao-vpn/vpn/DOWNLOAD_SCRIPTS.sh -O DOWNLOAD_SCRIPTS.sh
chmod +x DOWNLOAD_SCRIPTS.sh
./DOWNLOAD_SCRIPTS.sh

# 或者直接运行
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/huxiao-vpn/vpn/DOWNLOAD_SCRIPTS.sh)
```

### 方法2：直接下载单个脚本
```bash
# 下载修复版后端安装脚本（推荐）
wget https://raw.githubusercontent.com/你的用户名/huxiao-vpn/vpn/install-backend-fixed.sh -O install-backend-fixed.sh
chmod +x install-backend-fixed.sh

# 下载原版后端安装脚本
wget https://raw.githubusercontent.com/你的用户名/huxiao-vpn/vpn/install-backend.sh -O install-backend.sh
chmod +x install-backend.sh

# 下载Xray节点安装脚本
wget https://raw.githubusercontent.com/你的用户名/huxiao-vpn/vpn/install-xray-node.sh -O install-xray-node.sh
chmod +x install-xray-node.sh
```

### 方法3：克隆完整项目
```bash
# 克隆VPN分支
git clone -b vpn https://github.com/你的用户名/huxiao-vpn.git
cd huxiao-vpn
```

## 🛠️ 安装步骤

### 1. 后端服务器安装（推荐修复版）
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

## 📋 常用命令

### 服务管理
```bash
# 查看服务状态
systemctl status notification-server
systemctl status xray-node

# 启动/停止/重启服务
systemctl start notification-server
systemctl stop notification-server
systemctl restart notification-server

systemctl start xray-node
systemctl stop xray-node
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

# 域名更换
sudo bash install-backend.sh --domain
```

### 备份和恢复
```bash
# 备份系统
sudo bash install-backend.sh --backup
```

## 🔍 故障排除

### 检查服务状态
```bash
# 查看服务日志
journalctl -u notification-server -f
journalctl -u xray-node -f

# 查看应用日志
tail -f /opt/notification-server/logs/application.log
```

### 检查端口占用
```bash
# 查看端口占用
netstat -tlnp | grep :443
netstat -tlnp | grep :8082
netstat -tlnp | grep :80

# 查看进程
ps aux | grep java
ps aux | grep xray
```

### 数据库连接测试
```bash
# 测试MySQL连接
mysql -u root -p
mysql -u admin -p notification_db

# 检查MySQL状态
systemctl status mysql
systemctl status mariadb
```

## 🌐 访问地址

### 后端管理界面
安装完成后可通过以下地址访问：

- **HTTP模式**: `http://服务器IP:8082/admin`
- **HTTPS模式**: `https://域名/admin`

### VPN客户端
- 客户端程序: `mimo.exe`
- 需要从 `/opt/notification-server/` 或下载目录获取

## 📊 系统监控

### 资源使用
```bash
# 查看CPU和内存使用
top
htop

# 查看磁盘使用
df -h

# 查看网络流量
iftop
nethogs
```

### 日志监控
```bash
# 实时查看日志
tail -f /var/log/syslog
tail -f /opt/notification-server/logs/application.log
tail -f /var/log/xray/access.log
tail -f /var/log/xray/error.log
```

## 🔧 性能优化

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
# 备份当前版本
cp /opt/notification-server/notification-server.jar /opt/notification-server/notification-server.jar.backup

# 下载新版本
wget https://github.com/你的用户名/huxiao-vpn/releases/latest/download/notification-server.jar -O /opt/notification-server/notification-server.jar

# 重启服务
systemctl restart notification-server
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

**注意**: 请在使用前确保：
1. 系统满足最低要求 (Ubuntu 18.04+, CentOS 7+, Debian 9+)
2. 有足够的权限 (root或sudo)
3. 网络连接正常
4. 端口80、443、8082未被占用

**重要**: 本项目仅供学习和研究使用，请遵守当地法律法规。