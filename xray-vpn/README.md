# Xray VPN 部署文档

基于 Docker + Xray + v2rayN 的内网/外网代理解决方案

## 📋 目录

- [快速开始](#快速开始)
- [架构说明](#架构说明)
- [配置说明](#配置说明)
- [客户端配置](#客户端配置)
- [常见问题](#常见问题)
- [文件结构](#文件结构)

---
## 配置
### v2rayN下载链接：https://github.com/2dust/v2rayN/releases

## 快速开始

### 1. 生成 UUID

```powershell
# 生成用户 ID（每个用户一个）
[guid]::NewGuid().ToString()
```

### 2. 生成 TLS 证书（可选，内网测试可跳过）

```powershell
docker run --rm -v E:\docs\xray-vpn\certs:/certs alpine/openssl `
  req -new -x509 -days 3650 `
  -key /certs/server.key `
  -out /certs/server.crt `
  -subj "/C=CN/ST=Beijing/L=Beijing/O=XrayVPN/CN=vpn.example.com"
```

### 3. 配置 Xray

编辑 `config/config.json`，修改 UUID 为你的用户 ID。

### 4. 启动服务

```powershell
cd E:\docs\xray-vpn
docker compose up -d

# 查看状态
docker compose ps

# 查看日志
docker compose logs -f
```

### 5. 配置防火墙

```powershell
# 允许 10086 端口
New-NetFirewallRule -DisplayName "Xray VPN Port" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 10086 `
  -Action Allow
```

### 6. 配置路由器（外网访问需要）

登录路由器管理界面，添加端口转发：
- 外部端口：`10086`
- 内部 IP：`192.168.1.203`
- 内部端口：`10086`
- 协议：`TCP`

### 7. 配置客户端

下载 v2rayN，添加节点配置（见[客户端配置](#客户端配置)）。

---

## 架构说明

### 内网测试架构

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  客户端电脑 1  │      │  客户端电脑 2  │      │  客户端电脑 3  │
│   v2rayN    │      │   v2rayN    │      │   v2rayN    │
└──────┬───────┘      └──────┬───────┘      └──────┬───────┘
       │                     │                     │
       └─────────────────────┴─────────────────────┘
                             │
                      同一局域网 (WiFi)
                             │
                             ▼
                    ┌─────────────────┐
                    │  Windows 服务器  │
                    │  192.168.1.203  │
                    │   端口：10086   │
                    │   Docker Xray   │
                    └────────┬────────┘
                             │
                             ▼
                       国内网络/互联网
```

### 外网访问架构

```
┌──────────────┐
│  外网客户端   │
│   v2rayN    │
└──────┬───────┘
       │
       │ 公网 IP: 119.122.88.43:10086
       ▼
┌─────────────────┐
│    路由器       │
│  端口转发 10086  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Windows 服务器  │
│  192.168.1.203  │
│   Docker Xray   │
└────────┬────────┘
         │
         ▼
    互联网访问
```

---

## 配置说明

### config.json 核心配置

#### 1. 多用户配置

```json
"inbounds": [
  {
    "port": 10086,
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "用户 1-UUID",
          "email": "user1"
        },
        {
          "id": "用户 2-UUID",
          "email": "user2"
        }
      ]
    }
  }
]
```

**说明**：
- 每个 `client` 是一个独立用户
- 所有用户共享同一个端口（10086）
- 通过不同的 UUID 区分用户

#### 2. 传输配置（streamSettings）

**内网测试（当前配置）**：
```json
"streamSettings": {
  "network": "ws",
  "wsSettings": {
    "path": "/ray"
  }
}
```

**外网部署（推荐配置）**：
```json
"streamSettings": {
  "network": "ws",
  "security": "tls",
  "tlsSettings": {
    "certificates": [
      {
        "certificateFile": "/etc/xray/certs/server.crt",
        "keyFile": "/etc/xray/certs/server.key"
      }
    ]
  },
  "wsSettings": {
    "path": "/ray",
    "headers": {
      "Host": "你的域名.com"
    }
  }
}
```

**为什么需要 TLS？**
- 内网测试：不需要，简化配置
- 外网部署：**必须**，否则流量会被识别和封锁


---

## 客户端配置

### v2rayN 配置参数

#### 内网测试配置

| 参数 | 值 | 说明 |
|------|-----|------|
| 协议 | VLESS | 选择 VLESS 协议 |
| 地址 | `192.168.1.203` | **内网 IP**（同一 WiFi） |
| 端口 | `10086` | Xray 监听端口 |
| UUID | `你的用户 ID` | config.json 中配置的 ID |
| 传输 | WebSocket | 与服务器配置一致 |
| 路径 | `/ray` | 与服务器配置一致 |
| Host | 留空 | 内网测试不需要 |
| TLS | 关闭 | 内网测试不需要 |
| 流控 | 无 | TCP 直连不需要 |

#### 外网访问配置

| 参数 | 值 | 说明 |
|------|-----|------|
| 协议 | VLESS | 选择 VLESS 协议 |
| 地址 | `119.122.88.43` | **公网 IP**（或域名） |
| 端口 | `10086` | Xray 监听端口 |
| UUID | `你的用户 ID` | config.json 中配置的 ID |
| 传输 | WebSocket | 与服务器配置一致 |
| 路径 | `/ray` | 与服务器配置一致 |
| Host | `你的域名.com` | 与 TLS 证书域名一致 |
| TLS | ✓ 开启 | 外网必须开启 |
| 流控 | 无 | |

### 添加节点步骤

1. 下载 v2rayN：https://github.com/2dust/v2rayN/releases
2. 解压运行 `v2rayN.exe`
3. 右键托盘图标 → **添加 [VLESS] 服务器**
4. 填写上述配置参数
5. 保存
6. 右键节点 → **测试服务器延迟**
7. 显示延迟值（如 15ms）表示成功

### 代理模式说明

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| **绕过大陆** | 国内网站直连，国外走代理 | ✅ 推荐（日常使用） |
| **全局代理** | 所有流量走代理 | 测试/特殊需求 |
| **直连** | 不使用代理 | 临时关闭代理 |

---

## 常见问题

### Q1: 延迟显示 -1 或连接失败

**原因**：
1. 地址填写错误（内网填了公网 IP）
2. 防火墙阻止
3. 路由器未配置端口转发（外网访问时）
4. UUID 不匹配

**解决**：
```powershell
# 检查端口监听
netstat -ano | findstr :10086

# 检查防火墙
Get-NetFirewallRule -DisplayName "Xray VPN Port"

# 检查容器状态
docker compose ps
```

### Q2: 全局代理无法访问网站

**原因**：DNS 解析问题

**解决**：
1. v2rayN 设置 → 启用本地 DNS
2. DNS 服务器填写：`114.114.114.114`
3. 勾选"DNS 流量不经过代理"
4. 使用"绕过大陆"模式（推荐）

### Q3: 公网 IP 无法访问

**原因**：路由器未配置端口转发

**解决**：
1. 登录路由器管理界面（通常是 `192.168.1.1`）
2. 找到"端口转发"或"虚拟服务器"
3. 添加规则：外部 10086 → 内部 192.168.1.203:10086
4. 保存并重启路由器

### Q4: 配置文件修改后不生效

**解决**：
```powershell
# 重启容器
cd E:\docs\xray-vpn
docker compose restart

# 或重新部署
docker compose down
docker compose up -d
```

### Q5: 多用户如何配置？

**答案**：
1. 在 `config.json` 的 `clients` 数组中添加多个用户
2. 每个用户分配不同的 UUID
3. 每个用户用各自的 UUID 配置 v2rayN
4. 所有用户共享同一个端口（10086）

---

## 运维管理

### 常用命令

```powershell
# 启动服务
docker compose up -d

# 停止服务
docker compose down

# 重启服务
docker compose restart

# 查看状态
docker compose ps

# 查看日志
docker compose logs -f
docker compose logs --tail=50

# 更新镜像
docker compose pull
docker compose up -d

# 查看资源使用
docker stats xray-vpn
```
---

## 文件结构

```
E:\docs\xray-vpn/
├── docker-compose.yml          # Docker Compose 配置
├── config/
│   └── config.json             # Xray 配置文件 ⭐
├── certs/
│   ├── server.crt              # TLS 证书（公网部署需要）
│   └── server.key              # TLS 私钥
├── logs/
│   ├── access.log              # 访问日志
│   └── error.log               # 错误日志
├── start-vpn.ps1               # 启动脚本
├── stop-vpn.ps1                # 停止脚本
├── setup-firewall.ps1          # 防火墙配置脚本
└── README.md                   # 本文档
```

---

**测试环境**: Windows 10 + Docker Desktop
