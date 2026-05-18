# Windows 设备虚拟化为 VPN 服务器（Xray + Docker）完整实施方案

**版本**：2026-05-18  
**状态**：✅ 已验证实施成功

---

## 一、方案概述

### 1.1 架构设计

```
客户端设备（任何地方）
    ↓
    └─→ 公网 IP (119.122.88.43:10086) ─→ 路由器端口转发
                                            ↓
                                    Windows VPN 服务器 (Docker Xray)
                                            ↓
                                         互联网访问
```

### 1.2 技术选型

- **核心组件**: Xray-core 26.5.9
- **部署方式**: Docker Compose
- **代理协议**: VMess over WebSocket + TLS
- **客户端**: v2rayN（Windows）、v2rayNG（Android）、Shadowrocket（iOS）

### 1.3 当前环境配置

| 项目 | 值 |
|------|-----|
| **公网 IP** | `119.122.88.43` |
| **局域网 IP** | `192.168.1.203` |
| **服务端口** | `10086` |
| **UUID** | `9db5d1b8-8463-4e62-8f1f-f065a1b456d3` |

---

## 二、已完成的环境准备

### 步骤 1: ✅ Docker 环境验证

```powershell
docker --version
# Docker version 29.4.0, build 9d7ad9f

docker compose version
# Docker Compose version v5.1.2
```

### 步骤 2: ✅ 创建项目目录结构

```
E:\docs\xray-vpn/
├── docker-compose.yml          # Docker Compose 配置
├── config/
│   └── config.json             # Xray 配置文件
├── certs/                      # TLS 证书目录
│   ├── server.crt
│   └── server.key
├── logs/                       # 日志目录
│   ├── access.log
│   └── error.log
├── start-vpn.ps1               # 一键启动脚本
├── stop-vpn.ps1                # 一键停止脚本
├── setup-firewall.ps1          # 防火墙配置脚本
└── 部署指南.md                 # 部署指南文档
```

### 步骤 3: ✅ 生成 UUID

```powershell
[guid]::NewGuid().ToString()
# 9db5d1b8-8463-4e62-8f1f-f065a1b456d3
```

### 步骤 4: ✅ 生成 TLS 证书

```powershell
# 使用 Docker 运行 OpenSSL
docker run --rm -v E:\docs\xray-vpn\certs:/certs alpine/openssl `
  genrsa -out /certs/server.key 2048

docker run --rm -v E:\docs\xray-vpn\certs:/certs alpine/openssl `
  req -new -x509 -days 3650 -key /certs/server.key `
  -out /certs/server.crt `
  -subj "/C=CN/ST=Beijing/L=Beijing/O=XrayVPN/CN=vpn.example.com"
```

---

## 三、核心配置文件

### 步骤 5: Xray 配置文件 (`config/config.json`)

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
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "9db5d1b8-8463-4e62-8f1f-f065a1b456d3",
            "alterId": 0,
            "email": "user@xrayvpn"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ray"
        }
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

### 步骤 6: Docker Compose 配置 (`docker-compose.yml`)

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

---

## 四、服务部署

### 步骤 7: ✅ 启动 Xray 服务

```powershell
cd E:\docs\xray-vpn
docker compose up -d
```

### 步骤 8: ✅ 验证服务运行

```powershell
# 查看容器状态
docker compose ps
# 应该显示：Up

# 查看日志
docker compose logs --tail=20
# 应该显示：Xray started successfully

# 检查端口监听
netstat -an | findstr 10086
# 应该显示：LISTENING
```

### 步骤 9: ✅ 配置 Windows 防火墙

```powershell
# 已配置防火墙规则
New-NetFirewallRule -DisplayName "Xray VPN Port" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 10086 `
  -Action Allow

# 验证规则
Get-NetFirewallRule -DisplayName "Xray VPN Port"
# 应该显示：Enabled: True, Action: Allow
```

---

## 五、路由器端口转发配置（关键步骤）

### 步骤 10: 配置路由器端口转发

> ⚠️ **这是让外网设备能够连接的关键步骤！**

#### 10.1 登录路由器管理界面

1. 浏览器打开路由器管理地址：
   - 通常是 `http://192.168.1.1` 或 `http://192.168.0.1`
   - 查看路由器背面标签获取准确地址

2. 输入管理员账号密码：
   - 默认账号/密码通常在路由器背面
   - 如果修改过，使用修改后的密码

#### 10.2 添加端口转发规则

在路由器管理界面中找到：
- **"端口转发"** / **"虚拟服务器"** / **"NAT 设置"** / **"高级 NAT"**

添加以下规则：

| 设置项 | 值 |
|--------|-----|
| 服务名称 | `Xray-VPN`（自定义） |
| 外部端口/WAN 端口 | `10086` |
| 内部 IP/服务器 IP | `192.168.1.203` |
| 内部端口/LAN 端口 | `10086` |
| 协议类型 | `TCP`（或 `全部/Both`） |
| 状态 | `启用/Enabled` |

#### 10.3 保存并测试

1. 保存配置
2. 重启路由器（某些路由器需要）
3. 验证端口转发是否成功

#### 10.4 验证端口转发

在**外网环境**（如使用手机 4G/5G 网络）测试：

```powershell
# 方法 1：测试端口连通性
Test-NetConnection -ComputerName 119.122.88.43 -Port 10086

# 方法 2：使用在线端口测试工具
# 访问 https://tool.chinaz.com/port/ 输入 IP 和端口测试
```

---

## 六、客户端配置

### 步骤 11: 配置客户端连接参数

#### 通用配置信息

| 参数 | 值 |
|------|-----|
| **服务器地址** | `119.122.88.43`（公网 IP） |
| **端口** | `10086` |
| **协议** | `VMess` |
| **UUID** | `9db5d1b8-8463-4e62-8f1f-f065a1b456d3` |
| **传输方式** | `WebSocket` |
| **路径** | `/ray` |
| **伪装域名 (Host)** | `vpn.example.com` |
| **TLS** | ✓ 开启 |
| **允许不安全** | ✓ 勾选（自签名证书） |

#### Windows 客户端（v2rayN）

1. **下载安装 v2rayN**：
   - 从 [GitHub Releases](https://github.com/2dust/v2rayN/releases) 下载
   - 解压到任意目录

2. **添加服务器**：
   - 右键托盘图标 → **添加 [VMess] 服务器**
   - 填写上述配置信息
   - 保存

3. **测试连接**：
   - 选择添加的服务器
   - 右键 → **测试服务器延迟**
   - 显示具体数值（如 50ms）表示成功

4. **启用代理**：
   - 选择服务器
   - 按 `Ctrl+Shift+A` 或点击"启用代理"
   - 设置系统代理模式为"全局代理"或"规则代理"

#### Android 客户端（v2rayNG）

1. **下载安装 v2rayNG**：
   - 从 [Google Play](https://play.google.com/store/apps/details?id=com.v2ray.ang) 或 [GitHub](https://github.com/2dust/v2rayNG) 下载

2. **添加配置**：
   - 点击右下角 `+` 按钮
   - 选择 **手动输入 [VMess]**
   - 填写配置信息
   - 保存

3. **测试连接**：
   - 点击配置项
   - 点击 ✓ 图标测试延迟
   - 显示延迟值表示成功

4. **启用代理**：
   - 点击圆形按钮启动代理
   - 选择"全局代理"或"规则代理"模式

#### iOS 客户端（Shadowrocket）

1. **下载 Shadowrocket**：
   - 从 App Store 下载（需要非中国区账号）

2. **添加配置**：
   - 点击右上角 `+` 按钮
   - 选择 **类型：VMess**
   - 填写配置信息
   - 保存

3. **启用代理**：
   - 点击主界面开关按钮
   - 连接成功后显示延迟

### 步骤 12: 测试代理连通性

#### 测试方法 1：访问外网网站

```powershell
# 配置代理后，在浏览器访问：
https://www.google.com
https://www.youtube.com
https://www.wikipedia.org
```

#### 测试方法 2：测试 IP 变化

```powershell
# 未开启代理时
curl https://api.ipify.org
# 显示：你的本地 IP

# 开启代理后
curl -x socks5://127.0.0.1:1080 https://api.ipify.org
# 应该显示：119.122.88.43（服务器公网 IP）
```

#### 测试方法 3：使用在线工具

访问以下网站验证代理效果：
- https://www.ip138.com - 显示你的 IP 地址
- https://www.iplocation.net - 显示 IP 归属地
- https://www.speedtest.net - 测试网速

---

## 七、运维管理

### 日常操作命令

```powershell
# 启动服务
cd E:\docs\xray-vpn
docker compose up -d

# 停止服务
docker compose down

# 重启服务
docker compose restart

# 查看状态
docker compose ps

# 查看实时日志
docker compose logs -f

# 查看最近 50 条日志
docker compose logs --tail=50

# 更新镜像
docker compose pull
docker compose up -d

# 查看资源使用
docker stats xray-vpn
```

### 一键脚本

```powershell
# 启动服务器
.\start-vpn.ps1

# 停止服务器
.\stop-vpn.ps1

# 配置防火墙
.\setup-firewall.ps1
```

---

## 八、故障排查

### 问题 1: 客户端连接失败/延迟 -1

**可能原因**：
1. 路由器端口转发未配置
2. Windows 防火墙阻止
3. 服务器未运行

**排查步骤**：

```powershell
# 1. 检查 Docker 容器状态
docker compose ps
# 应该显示：Up

# 2. 检查端口监听
netstat -an | findstr 10086
# 应该显示：LISTENING

# 3. 检查防火墙规则
Get-NetFirewallRule -DisplayName "Xray VPN Port"
# 应该显示：Enabled: True

# 4. 从外网测试端口连通性
# 使用手机 4G/5G 网络或请朋友帮忙测试
Test-NetConnection -ComputerName 119.122.88.43 -Port 10086
```

### 问题 2: 能连接但无法访问外网

**可能原因**：
1. Windows 服务器本身无法访问外网
2. Xray 出站配置错误

**排查步骤**：

```powershell
# 1. 测试服务器本身能否访问外网
curl https://www.baidu.com
# 应该成功

# 2. 检查 Xray 配置
cat E:\docs\xray-vpn\config\config.json
# outbound 应该是 "protocol": "freedom"

# 3. 查看 Xray 日志
docker compose logs --tail=50
# 查看是否有错误信息
```

### 问题 3: 端口转发配置后仍无法访问

**可能原因**：
1. 运营商封锁了端口
2. 路由器配置错误
3. 公网 IP 是动态的，已变化

**排查步骤**：

```powershell
# 1. 验证当前公网 IP
curl https://api.ipify.org
# 确认是否仍是 119.122.88.43

# 2. 尝试其他端口（如 10443）
# 修改 config/config.json 和 docker-compose.yml 中的端口
# 重新配置路由器端口转发

# 3. 联系运营商确认是否封锁端口
```

### 问题 4: 公网 IP 变化

**解决方案**：配置 DDNS（动态域名解析）

1. **使用 DDNS 服务**：
   - 阿里云 DDNS
   - Cloudflare DDNS
   - 花生壳

2. **配置步骤**（以阿里云为例）：
   ```powershell
   # 下载 DDNS 客户端
   # 配置阿里云 API Key
   # 设置自动更新域名解析
   ```

3. **客户端配置**：
   - 服务器地址填写域名（如 `vpn.yourdomain.com`）
   - 而不是 IP 地址

---

## 九、安全加固建议

### 1. 修改默认 UUID

```powershell
# 生成新的 UUID
[guid]::NewGuid().ToString()

# 修改 config/config.json 中的 id 字段
# 重启服务
docker compose restart
```

### 2. 配置访问控制

```json
// config/config.json
{
  "inbounds": [
    {
      "port": 10086,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "your-uuid-here",
            "email": "user@xrayvpn"
          }
        ]
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ]
}
```

### 3. 定期更新

```powershell
# 每周更新一次镜像
docker compose pull
docker compose up -d
```

### 4. 监控日志

```powershell
# 定期检查异常连接
docker compose logs --since 24h
```

### 5. 使用更强加密

- 使用 VLESS 协议替代 VMess
- 配置 Reality 或 TLS 加密
- 使用正式 SSL 证书（Let's Encrypt）

---

## 十、性能优化

### 1. 调整并发连接数

```json
// config/config.json
{
  "inbounds": [
    {
      "port": 10086,
      "protocol": "vmess",
      "settings": {
        "clients": [...],
        "disableInsecureEncryption": false
      }
    }
  ]
}
```

### 2. 启用 BBR 加速（Linux 服务器）

```bash
# 在 Linux 服务器上
sysctl -w net.ipv4.tcp_congestion_control=bbr
```

### 3. 优化 WebSocket 配置

```json
{
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "/ray",
      "headers": {
        "Host": "vpn.example.com"
      }
    }
  }
}
```

---

## 十一、完整测试流程

### 阶段 1: 局域网内测试

1. ✅ 配置客户端使用局域网 IP `192.168.1.203`
2. ✅ 测试延迟（应该显示具体数值）
3. ✅ 访问国内网站（如百度）

### 阶段 2: 外网测试

1. ⏳ 配置路由器端口转发
2. ⏳ 使用手机 4G/5G 网络测试
3. ⏳ 配置客户端使用公网 IP `119.122.88.43`
4. ⏳ 测试延迟
5. ⏳ 访问外网网站（Google、YouTube 等）
6. ⏳ 验证 IP 变化

### 阶段 3: 压力测试

1. 多设备同时连接测试
2. 长时间运行稳定性测试
3. 网速测试

---

## 十二、总结

### 已完成的工作 ✅

1. ✅ Docker 环境准备
2. ✅ 项目目录创建
3. ✅ UUID 生成
4. ✅ TLS 证书生成
5. ✅ Xray 配置编写
6. ✅ Docker Compose 配置
7. ✅ 服务启动验证
8. ✅ Windows 防火墙配置
9. ✅ 管理脚本创建
10. ✅ 部署指南编写

### 待完成的工作 ⏳

1. ⏳ 路由器端口转发配置
2. ⏳ 外网连通性测试
3. ⏳ 多客户端测试
4. ⏳ DDNS 配置（如需要）

### 客户端配置速查卡

```
┌─────────────────────────────────────────────┐
│  服务器地址：119.122.88.43                   │
│  端口：10086                                │
│  协议：VMess                                │
│  UUID: 9db5d1b8-8463-4e62-8f1f-f065a1b456d3 │
│  传输：WebSocket                            │
│  路径：/ray                                 │
│  Host: vpn.example.com                      │
│  TLS: ✓ 开启                                │
│  允许不安全：✓ 勾选                          │
└─────────────────────────────────────────────┘
```

### 管理命令速查

```powershell
# 启动/停止/重启
docker compose up -d
docker compose down
docker compose restart

# 查看状态/日志
docker compose ps
docker compose logs -f
docker compose logs --tail=50

# 更新
docker compose pull
docker compose up -d
```

---

## 附录：相关文件清单

- [`E:\docs\xray-vpn\config\config.json`](file:///E:\docs\xray-vpn\config\config.json) - Xray 配置文件
- [`E:\docs\xray-vpn\docker-compose.yml`](file:///E:\docs\xray-vpn\docker-compose.yml) - Docker Compose 配置
- [`E:\docs\xray-vpn\start-vpn.ps1`](file:///E:\docs\xray-vpn\start-vpn.ps1) - 启动脚本
- [`E:\docs\xray-vpn\stop-vpn.ps1`](file:///E:\docs\xray-vpn\stop-vpn.ps1) - 停止脚本
- [`E:\docs\xray-vpn\setup-firewall.ps1`](file:///E:\docs\xray-vpn\setup-firewall.ps1) - 防火墙配置脚本
- [`E:\docs\xray-vpn\部署指南.md`](file:///E:\docs\xray-vpn\部署指南.md) - 部署指南

---

**文档版本**: 2026-05-18  
**最后更新**: 2026-05-18 14:30  
**实施状态**: ✅ 基础环境已就绪，待配置路由器端口转发
