# Xray + Docker + v2rayN 完整部署实施指南

**版本**: 2026-05-19  
**适用场景**: 国内内网学习测试（纯内网，不访问外网）  
**最终目标**: 让多台客户端电脑通过一台 Windows 服务器共享网络

---

## 一、整体架构概览

### 1.1 部署架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        客户端设备区域                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  客户端电脑1  │  │  客户端电脑2  │  │  客户端电脑3  │          │
│  │   v2rayN    │  │   v2rayN    │  │   v2rayN    │          │
│  │  ID: user1  │  │  ID: user2  │  │  ID: user3  │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                    │
│         └─────────────────┴─────────────────┘                    │
│                           │                                      │
│                      同一局域网                                   │
│                    (WiFi/交换机)                                  │
└───────────────────────────┼──────────────────────────────────────┘
                            │
                    连接到 192.168.1.203:10086
                            │
┌───────────────────────────▼──────────────────────────────────────┐
│                    Windows 服务器区域                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    Windows 主机                             │  │
│  │  内网 IP: 192.168.1.203                                    │  │
│  │  公网 IP: 119.122.88.43 (动态，暂不使用)                     │  │
│  │                                                            │  │
│  │  ┌──────────────────────────────────────────────────────┐ │  │
│  │  │              Docker Desktop                          │ │  │
│  │  │  ┌────────────────────────────────────────────────┐  │ │  │
│  │  │  │          Xray 容器 (teddysun/xray:latest)      │  │ │  │
│  │  │  │                                                │  │ │  │
│  │  │  │  入站 (Inbound):                               │  │ │  │
│  │  │  │  - 端口：10086                                 │  │ │  │
│  │  │  │  - 协议：VLESS                                 │  │ │  │
│  │  │  │  - 认证：clients 列表 (3 个用户 ID)               │  │ │  │
│  │  │  │  - 传输：TCP (内网测试简化版)                   │  │ │  │
│  │  │  │                                                │  │ │  │
│  │  │  │  出站 (Outbound):                              │  │ │  │
│  │  │  │  - 协议：freedom (直接连接)                     │  │ │  │
│  │  │  │  - 目标：国内网站/内网资源                       │  │ │  │
│  │  │  └────────────────────────────────────────────────┘  │ │  │
│  │  └──────────────────────────────────────────────────────┘ │  │
│  │                                                            │  │
│  │  ┌──────────────────────────────────────────────────────┐ │  │
│  │  │              Windows 防火墙                           │ │  │
│  │  │  规则：允许 TCP 10086 端口入站                         │ │  │
│  │  └──────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │   国内网络     │
                    │  (百度/内网)   │
                    └───────────────┘
```

### 1.2 数据流向说明

```
客户端 v2rayN
    ↓ (VLESS 协议，携带用户 ID)
Windows 防火墙 (端口 10086)
    ↓ (验证通过)
Docker Xray 容器
    ↓ (核对 clients 列表中的 ID)
验证成功 → 转发流量到目标网站
验证失败 → 拒绝连接
```

### 1.3 核心概念解释

#### 为什么需要配置 ID (UUID)？

| 组件 | 作用 | 比喻 |
|------|------|------|
| **config.json 中的 `clients`** | 服务器端的"白名单" | 大楼的门禁系统名单 |
| **v2rayN 中的 ID** | 客户端的"身份凭证" | 你手里的门禁卡 |
| **匹配过程** | 服务器核对 ID 是否在名单上 | 门卫检查你的卡是否有效 |

**重要**：
- 3 个客户端可以使用**同一个 ID**（共享一张门禁卡）
- 也可以使用**不同的 ID**（每人一张卡，便于管理）
- 但 v2rayN 里的 ID **必须**在 config.json 的 `clients` 列表里

---

## 二、详细部署步骤

### 步骤 1: 生成 UUID（用户身份标识）

#### 作用
UUID 是客户端连接服务器的"身份证"。每个 UUID 代表一个独立用户。

#### 操作命令
```powershell
# 生成一个 UUID
[guid]::NewGuid().ToString()

# 示例输出
# 9db5d1b8-8463-4e62-8f1f-f065a1b456d3

# 生成 3 个 UUID（给 3 个用户用）
[guid]::NewGuid().ToString()
[guid]::NewGuid().ToString()
[guid]::NewGuid().ToString()
```

#### 注意事项
- ✅ **记录所有生成的 UUID**，后续配置要用
- ✅ **UUID 格式**: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
- ⚠️ **不要使用示例中的 UUID**，自己生成新的（安全考虑）

---

### 步骤 2: 生成 TLS 证书（加密传输）

#### 作用
TLS 证书用于加密客户端和服务器之间的通信，防止数据被窃听。

#### 操作命令
```powershell
# 创建证书目录
New-Item -ItemType Directory -Force -Path "E:\docs\xray-vpn\certs"

# 生成证书（使用 Docker 运行 OpenSSL）
docker run --rm -v E:\docs\xray-vpn\certs:/certs alpine/openssl `
  req -new -x509 -days 3650 `
  -key /certs/server.key `
  -out /certs/server.crt `
  -subj "/C=CN/ST=Beijing/L=Beijing/O=XrayVPN/CN=vpn.example.com"
```

#### 生成的文件
- `server.key`: 私钥（保密，不要给别人）
- `server.crt`: 公钥证书（客户端会验证）

#### 注意事项
- ✅ **内网测试可以不用 TLS**（简化配置）
- ✅ **公网部署必须使用 TLS**（否则会被防火墙识别）
- ⚠️ **自签名证书**: 客户端需要勾选"允许不安全连接"

---

### 步骤 3: 配置 config.json（核心配置文件）

#### 作用
这是 Xray 服务器的"大脑"，定义了：
- 监听哪个端口
- 允许哪些用户连接
- 使用什么传输协议
- 流量如何转发

#### 当前配置（内网测试简化版）

```json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10086,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "9db5d1b8-8463-4e62-8f1f-f065a1b456d3",
            "level": 0,
            "email": "user1@xrayvpn"
          },
          {
            "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "level": 0,
            "email": "user2@xrayvpn"
          },
          {
            "id": "12345678-1234-1234-1234-123456789012",
            "level": 0,
            "email": "user3@xrayvpn"
          }
        ],
        "decryption": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
```

#### ⚠️ 关键说明：为什么去掉了 `streamSettings`？

**当前配置（内网测试）**:
```json
// 没有 streamSettings
```

**原因**:
1. **简化配置**: 内网测试不需要复杂的传输伪装
2. **TCP 直连**: VLESS 协议默认使用 TCP 直连，最稳定
3. **快速排查**: 减少配置项，便于定位问题
4. **内网环境**: 内网没有防火墙，不需要伪装成 HTTPS 流量

**后续公网部署需要补上**:
```json
{
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "/ray"
    }
  }
}
```

**补上的好处？**:
1. **防封锁**: WebSocket 可以伪装成普通网页流量
2. **穿透防火墙**: 某些网络环境会封锁纯 TCP 流量
3. **CDN 支持**: 可以配合 CDN 隐藏真实 IP
4. **HTTPS 伪装**: 看起来像访问网站，不像代理
**但其实，不加应该也没什么问题，加上也不需要填host**
#### 配置项详解

| 配置项 | 值 | 作用 |
|--------|-----|------|
| `port` | `10086` | 监听端口，客户端要连接这个端口 |
| `listen` | `0.0.0.0` | 监听所有网卡（内网 + 外网） |
| `protocol` | `vless` | 使用 VLESS 协议（比 VMess 更快） |
| `clients[].id` | UUID | 允许连接的用户 ID 列表 |
| `clients[].level` | `0` | 用户等级（0 是普通用户） |
| `clients[].email` | 自定义 | 用户标识，方便看日志 |
| `decryption` | `"none"` | VLESS 必须配置，表示不加密 |
| `protocol` (outbound) | `freedom` | 直接连接目标网站 |

#### 注意事项
- ✅ **UUID 必须与步骤 1 生成的一致**
- ✅ **端口不要和其他服务冲突**（如 IIS 占用 80）
- ⚠️ **VLESS 协议必须配置 `"decryption": "none"`**，否则启动失败
- ⚠️ **JSON 格式要严格正确**，逗号、括号不能少

---

### 步骤 4: 配置 docker-compose.yml

#### 作用
Docker Compose 用于一键启动和管理 Xray 容器。

#### 配置文件

```yaml
services:
  xray:
    image: teddysun/xray:latest
    container_name: xray-vpn
    restart: always
    ports:
      - "10086:10086"
    volumes:
      - ./config/config.json:/etc/xray/config.json:ro
      - ./certs:/etc/xray/certs:ro
      - ./logs:/var/log/xray
    environment:
      - TZ=Asia/Shanghai
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - xray-net

networks:
  xray-net:
    driver: bridge
```

#### 配置项详解

| 配置项 | 作用 | 为什么需要 |
|--------|------|------------|
| `image` | 使用 teddysun/xray 镜像 | 这是 Xray 的官方镜像 |
| `container_name` | 容器名为 xray-vpn | 方便管理和查看日志 |
| `restart: always` | 开机自动启动 | 服务器重启后自动运行 |
| `ports` | 端口映射 10086:10086 | 让外部能访问容器端口 |
| `volumes` | 挂载配置文件 | 修改 config.json 不用重建容器 |
| `environment` | 设置时区 | 日志时间显示为北京时间 |
| `extra_hosts` | 允许容器访问宿主机 | 用于后续配置上游代理 |

#### 注意事项
- ✅ **版本已移除**: Docker Compose v2+ 不再需要 `version: '3.8'`
- ✅ **路径使用相对路径**: `./config` 表示当前目录下的 config 文件夹
- ⚠️ **`:ro` 后缀**: 表示只读挂载，防止容器修改配置文件

---

### 步骤 5: 启动 Docker 服务

#### 操作命令

```powershell
# 进入项目目录
cd E:\docs\xray-vpn

# 启动服务（后台运行）
docker compose up -d

# 查看运行状态
docker compose ps

# 查看日志（确认启动成功）
docker compose logs --tail=20

# 持续查看日志（实时）
docker compose logs -f
```

#### 预期输出

**成功启动的标志**:
```
✔ Container xray-vpn  Started
Xray 26.5.9 (Xray, Penetrates Everything.)
A unified platform for anti-censorship.
[Info] infra/conf/serial: Reading config: &{Name:/etc/xray/config.json Format:json}
```

**失败的情况**:
```
Failed to start: main: failed to load config files
```
- 原因：config.json 格式错误
- 解决：检查 JSON 语法，确保 `"decryption": "none"` 存在

#### 验证服务运行

```powershell
# 检查端口是否监听
netstat -ano | findstr :10086

# 应该看到
# TCP    0.0.0.0:10086          0.0.0.0:0              LISTENING
```

#### 注意事项
- ✅ **Docker Desktop 必须运行**: 如果 Docker 没启动，命令会失败
- ⚠️ **端口冲突**: 如果 10086 被占用，修改 config.json 和 docker-compose.yml 中的端口
- ✅ **日志无 ERROR**: 如果有错误，根据日志排查

---

### 步骤 6: 配置 Windows 防火墙

#### 作用
Windows 防火墙默认阻止外部连接，需要开放 10086 端口。

#### 操作命令

```powershell
# 创建防火墙规则（允许入站）
New-NetFirewallRule -DisplayName "Xray VPN Port" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 10086 `
  -Action Allow `
  -Profile Any

# 验证规则
Get-NetFirewallRule -DisplayName "Xray VPN Port" | `
  Select-Object DisplayName, Enabled, Direction, Action, Profile
```

#### 预期输出

```
DisplayName : Xray VPN Port
Enabled     : True
Direction   : Inbound
Action      : Allow
Profile     : Any
```

#### 注意事项
- ✅ **以管理员身份运行 PowerShell**: 否则没有权限创建规则
- ⚠️ **公共网络慎用**: 如果服务器在公网，建议限制访问 IP
- ✅ **测试后可以删除**: `Remove-NetFirewallRule -DisplayName "Xray VPN Port"`

---

### 步骤 7: 路由器端口转发配置（公网访问必需）

#### ⚠️ 内网测试跳过此步骤

**如果你只在内网使用**（手机和电脑都在同一 WiFi），**不需要配置路由器**。

#### 作用（公网访问时）
让外网设备能够通过公网 IP 访问内网的 Xray 服务器。

#### 配置步骤

1. **登录路由器管理界面**
   - 浏览器打开：`http://192.168.1.1`（或路由器背面标签上的地址）
   - 输入管理员账号密码

2. **找到端口转发设置**
   - 菜单名称可能是：
     - "端口转发"
     - "虚拟服务器"
     - "NAT 设置"
     - "高级 NAT"

3. **添加转发规则**

| 设置项 | 值 | 说明 |
|--------|-----|------|
| 服务名称 | `Xray-VPN` | 自定义，方便识别 |
| 外部端口/WAN 端口 | `10086` | 外网访问的端口 |
| 内部 IP/服务器 IP | `192.168.1.203` | Windows 服务器的内网 IP |
| 内部端口/LAN 端口 | `10086` | Xray 监听的端口 |
| 协议类型 | `TCP` | Xray 使用 TCP 协议 |
| 状态 | `启用` | 激活规则 |

4. **保存并重启路由器**

5. **验证端口转发**

在外网环境（如手机 4G/5G）测试：
```powershell
Test-NetConnection -ComputerName 119.122.88.43 -Port 10086
```

#### 注意事项
- ⚠️ **动态公网 IP**: 你的公网 IP 可能会变，重启路由器后可能变化
- ⚠️ **运营商封锁**: 某些运营商封锁常见端口（如 80, 443, 8080）
- ✅ **使用不常见端口**: 如 10086, 10443 等
- ⚠️ **NAT 回环**: 部分路由器不支持从内网访问自己的公网 IP

---

### 步骤 8: 下载并配置 v2rayN 客户端

#### 下载 v2rayN

1. **下载地址**:
   - GitHub: https://github.com/2dust/v2rayN/releases
   - 选择 `v2rayN-windows-64.zip`（Windows 64 位）

2. **解压运行**:
   - 解压到任意目录（如 `D:\v2rayN`）
   - 运行 `v2rayN.exe`

#### 配置客户端参数

1. **添加服务器**:
   - 右键托盘图标 → **添加 [VLESS] 服务器**

2. **填写配置信息**:

| 参数 | 值 | 说明 |
|------|-----|------|
| 地址 (Address) | `192.168.1.203` | 内网 IP（公网访问填公网 IP） |
| 端口 (Port) | `10086` | Xray 监听的端口 |
| 用户 ID (UUID) | `9db5d1b8-8463-4e62-8f1f-f065a1b456d3` | 步骤 1 生成的 UUID |
| 传输协议 | `TCP` | 当前简化配置使用 TCP |
| 流控 (Flow) | 无 | TCP 直连不需要流控 |
| 加密方式 | `none` | VLESS 默认不加密 |

3. **测试连接**:
   - 选择添加的服务器
   - 右键 → **测试服务器延迟**
   - 显示具体数值（如 15ms）表示成功

4. **启用代理**:
   - 选择服务器
   - 按 `Ctrl+Shift+A` 或点击"启用代理"
   - 设置系统代理模式为"全局代理"或"规则代理"

#### 多用户配置示例

如果你有 3 个用户，可以配置 3 个节点（或共享 1 个节点）：

**方案 A: 多用户共享 1 个节点**（推荐）
- 所有客户端使用同一个 UUID
- 优点：配置简单
- 缺点：无法区分哪个用户在使用

**方案 B: 多用户多 ID**
- 用户 1: UUID = `9db5d1b8-8463-4e62-8f1f-f065a1b456d3`
- 用户 2: UUID = `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
- 用户 3: UUID = `12345678-1234-1234-1234-123456789012`
- 优点：可以在日志中区分用户
- 缺点：配置稍复杂

#### 注意事项
- ✅ **地址填内网 IP**: 内网测试时填 `192.168.1.203`
- ⚠️ **UUID 必须匹配**: 必须和 config.json 中的一致
- ⚠️ **传输协议**: 当前配置是 TCP，不要选 WebSocket
- ✅ **允许不安全**: 如果使用 TLS，勾选"允许不安全连接"

---

## 三、测试验证流程

### 3.1 内网测试（当前阶段）

#### 测试 1: 服务器自身测试

```powershell
# 1. 检查端口监听
netstat -ano | findstr :10086
# 应该显示：LISTENING

# 2. 本地连接测试
Test-NetConnection -ComputerName 127.0.0.1 -Port 10086
# 应该显示：TcpTestSucceeded : True
```

#### 测试 2: 局域网内其他设备测试

在**同一 WiFi 的另一台电脑/手机**上：

```powershell
# 1. 测试端口连通性
Test-NetConnection -ComputerName 192.168.1.203 -Port 10086
# 应该显示：TcpTestSucceeded : True

# 2. 配置 v2rayN 并测试延迟
# 应该显示具体数值（如 10-50ms）
```



### 3.2 公网测试（后续阶段）

完成路由器端口转发后：

1. **在外网环境**（如手机 4G/5G）
2. **配置 v2rayN 地址为公网 IP**: `119.122.88.43`
3. **测试延迟和访问**

---

## 四、常见问题排查

### 问题 1: 容器启动失败

**错误信息**:
```
Failed to start: main: failed to load config files
```

**解决方案**:
1. 检查 config.json 格式（使用 JSON 验证工具）
2. 确保 `"decryption": "none"` 存在
3. 查看完整日志：`docker compose logs`

### 问题 2: 客户端连接失败/延迟 -1

**可能原因**:
1. Windows 防火墙阻止
2. 路由器未配置端口转发（公网访问时）
3. UUID 不匹配

**排查步骤**:
```powershell
# 1. 检查防火墙规则
Get-NetFirewallRule -DisplayName "Xray VPN Port"

# 2. 检查端口监听
netstat -ano | findstr :10086

# 3. 检查容器状态
docker compose ps
```

### 问题 3: 能连接但无法访问网站

**可能原因**:
1. DNS 配置问题
2. 路由配置问题

**解决方案**:
在 v2rayN 设置中：
- 启用"本地 DNS"
- 或使用"规则模式"而非"全局模式"

### 问题 4: 公网 IP 无法访问

**原因**: 路由器未配置端口转发

**解决方案**: 按照步骤 7 配置路由器端口转发

---

## 五、后续优化建议

### 5.1 公网部署时的配置修改

1. **添加 streamSettings（我感觉不是必须，可以看看前面）**（防封锁）:
```json
"streamSettings": {
  "network": "ws",
  "wsSettings": {
    "path": "/ray"
  }
}
```

2. **启用 TLS**（加密传输）:
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
  }
}
```

3. **v2rayN 配置调整**:
   - 传输协议：WebSocket
   - 路径：`/ray`
   - TLS：开启


### 5.3 监控和维护

```powershell
# 查看实时日志
docker compose logs -f

# 查看资源使用
docker stats xray-vpn

# 重启服务
docker compose restart

# 更新镜像
docker compose pull
docker compose up -d
```

---

## 六、总结

### 已完成的工作 ✅

1. ✅ 生成 UUID（用户身份标识）
2. ✅ 生成 TLS 证书（加密传输）
3. ✅ 配置 Xray 服务器（内网简化版）
4. ✅ 配置 Docker Compose
5. ✅ 启动服务并验证
6. ✅ 配置 Windows 防火墙
7. ⏳ 配置路由器端口转发（公网访问时需要）
8. ✅ 配置 v2rayN 客户端

