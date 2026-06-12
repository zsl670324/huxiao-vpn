# GitHub 上传指南

## 📋 准备工作

### 1. 安装 Git
```bash
# Windows
winget install Git.Git

# Linux (Ubuntu/Debian)
sudo apt-get install git

# Linux (CentOS/RHEL)
sudo yum install git
```

### 2. 配置 Git
```bash
# 设置用户名和邮箱
git config --global user.name "你的GitHub用户名"
git config --global user.email "你的GitHub邮箱"

# 设置默认分支名
git config --global init.defaultBranch main
```

## 🚀 上传步骤

### 1. 初始化 Git 仓库
```bash
cd D:\huxiao-vpn-node
git init
```

### 2. 添加文件到暂存区
```bash
git add .
```

### 3. 创建第一次提交
```bash
git commit -m "feat: 初始版本 - 虎啸VPN完整部署包

- 包含后端安装脚本 (v3.1 和 v3.2修复版)
- 包含Xray节点安装脚本
- 包含VPN应用程序 (notification-server和node-backend)
- 添加完整的文档和许可证
- 支持一键部署和SSL证书管理"
```

### 4. 关联远程仓库
```bash
# 创建GitHub仓库后，替换下面的URL
git remote add origin https://github.com/你的用户名/huxiao-vpn.git
```

### 5. 创建并切换到VPN分支
```bash
git checkout -b vpn
```

### 6. 推送到GitHub
```bash
git push -u origin vpn
```

## 🔧 完整命令序列

```bash
# 1. 进入目录
cd D:\huxiao-vpn-node

# 2. 初始化仓库
git init

# 3. 添加文件
git add .

# 4. 提交
git commit -m "feat: 初始版本 - 虎啸VPN完整部署包

- 包含后端安装脚本 (v3.1 和 v3.2修复版)
- 包含Xray节点安装脚本
- 包含VPN应用程序 (notification-server和node-backend)
- 添加完整的文档和许可证
- 支持一键部署和SSL证书管理"

# 5. 添加远程仓库（替换为你的GitHub仓库URL）
git remote add origin https://github.com/你的用户名/huxiao-vpn.git

# 6. 创建VPN分支并推送
git checkout -b vpn
git push -u origin vpn
```

## 📁 包含的文件

### 安装脚本
- `install-backend.sh` - 后端安装脚本 v3.1
- `install-backend-fixed.sh` - 后端安装脚本 v3.2 (修复版)
- `install-xray-node.sh` - Xray节点安装脚本
- `update-node.sh` - 节点更新脚本

### 应用程序
- `notification-server-1.3.6.jar` - VPN后端服务器
- `node-backend-1.1.3.jar` - 节点管理后端
- `mimo.exe` - VPN客户端

### 文档
- `README.md` - 项目说明
- `INSTALL.md` - 安装指南
- `CHANGELOG.md` - 更新日志
- `LICENSE` - 许可证
- `GIT_UPLOAD_GUIDE.md` - 上传指南

### 其他
- `.gitignore` - Git忽略文件配置
- `脚本使用报告.txt` - 脚本使用说明
- `节点信息.txt` - 节点配置信息
- `huxiao-vpn-backend-full-backup-20260610171857.tar.gz` - 备份文件

## 🌐 GitHub仓库创建步骤

### 1. 登录GitHub
访问 https://github.com 并登录你的账户。

### 2. 创建新仓库
- 点击右上角的 "+" 号
- 选择 "New repository"
- 填写仓库信息：
  - Repository name: `huxiao-vpn`
  - Description: `虎啸VPN完整部署包`
  - 选择 Public/Private
  - 不要勾选 "Add a README file"
  - 不要勾选 "Add .gitignore"
  - 不要勾选 "Add a license"

### 3. 复制仓库URL
创建完成后，复制仓库的URL：
```
https://github.com/你的用户名/huxiao-vpn.git
```

## 🔐 认证方式

### HTTPS 方式（推荐）
```bash
git remote add origin https://github.com/你的用户名/huxiao-vpn.git
```
首次推送时需要输入GitHub用户名和密码。

### SSH 方式
```bash
git remote add origin git@github.com:你的用户名/huxiao-vpn.git
```
需要配置SSH密钥。

## 📋 推送后的操作

### 1. 查看GitHub仓库
访问你的GitHub仓库，确认文件已成功上传。

### 2. 设置分支保护
- 进入仓库的 "Settings" > "Branches"
- 点击 "Add branch protection rule"
- Branch name pattern: `vpn`
- 勾选 "Require pull request reviews before merging"
- 勾选 "Require status checks to pass before merging"

### 3. 创建Release
- 进入仓库的 "Releases"
- 点击 "Create a new release"
- Tag version: `v3.2`
- Title: `虎啸VPN v3.2 (修复版)`
- Description: 描述修复内容和新增功能

## 🚨 注意事项

1. **隐私保护**: 确保不包含任何敏感信息（如密码、密钥等）
2. **文件大小**: 注意GitHub的文件大小限制（单个文件最大100MB）
3. **许可证**: 确保包含适当的许可证文件
4. **文档**: 保持文档的更新和维护

## 🔄 更新维护

### 添加新文件
```bash
git add .
git commit -m "feat: 添加新功能"
git push origin vpn
```

### 创建新版本
```bash
# 创建新分支
git checkout -b feature/new-feature

# 开发完成后合并
git checkout vpn
git merge feature/new-feature
git push origin vpn
```

---

**提示**: 如果在推送过程中遇到问题，请检查：
1. 网络连接
2. GitHub账户权限
3. 仓库URL是否正确
4. 是否有未解决的冲突