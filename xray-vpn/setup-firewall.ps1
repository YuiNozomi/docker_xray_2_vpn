# Xray VPN 防火墙配置脚本
# 使用方法: 以管理员身份运行 .\setup-firewall.ps1

Write-Host "配置 Windows 防火墙规则..." -ForegroundColor Cyan

$port = 10086
$ruleName = "Xray VPN Port"

# 检查是否已存在规则
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($existingRule) {
    Write-Host "防火墙规则已存在，跳过创建" -ForegroundColor Yellow
} else {
    # 添加入站规则
    New-NetFirewallRule -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $port `
        -Action Allow `
        -Profile Any

    Write-Host "防火墙规则已创建: 允许 TCP 端口 $port 入站连接" -ForegroundColor Green
}

# 显示当前规则
Write-Host "`n当前防火墙规则:" -ForegroundColor Cyan
Get-NetFirewallRule -DisplayName $ruleName | Select-Object DisplayName, Enabled, Direction, Action, Profile
