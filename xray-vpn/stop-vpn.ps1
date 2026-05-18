# Xray VPN 一键停止脚本
# 使用方法: .\stop-vpn.ps1

Set-Location $PSScriptRoot

Write-Host "停止 Xray VPN 服务..." -ForegroundColor Cyan
docker compose down

Write-Host "Xray VPN 服务器已停止" -ForegroundColor Yellow
