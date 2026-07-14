# Listening Ports vs Staged Inbound Rules
# Run this locally with admin rights
# Output saved to C:\Support\Firewall_Audit_<hostname>.txt

$outputDir  = "C:\Support"
$outputFile = "$outputDir\Firewall_Audit_$($env:COMPUTERNAME).txt"

# Make sure the output folder exists
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Pipe everything into the file - width 300 prevents column truncation
& {
    Write-Output "=== HOSTNAME ==="
    Write-Output $env:COMPUTERNAME
    Write-Output ""

    Write-Output "=== LISTENING TCP PORTS ==="
    Get-NetTCPConnection -State Listen |
        Where-Object { $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::1' } |
        Select-Object LocalAddress, LocalPort,
            @{N='Process'; E={ (Get-Process -Id $_.OwningProcess -EA SilentlyContinue).Name }},
            @{N='PID'; E={ $_.OwningProcess }} |
        Sort-Object LocalPort |
        Format-Table -AutoSize

    Write-Output "=== LISTENING UDP PORTS ==="
    Get-NetUDPEndpoint |
        Where-Object { $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::1' } |
        Select-Object LocalAddress, LocalPort,
            @{N='Process'; E={ (Get-Process -Id $_.OwningProcess -EA SilentlyContinue).Name }},
            @{N='PID'; E={ $_.OwningProcess }} |
        Sort-Object LocalPort |
        Format-Table -AutoSize

    Write-Output "=== INBOUND FIREWALL RULES (Domain Profile, Enabled) ==="
    Get-NetFirewallRule -Direction Inbound -Enabled True |
        Where-Object { $_.Profile -match 'Domain|Any' } |
        ForEach-Object {
            $rule       = $_
            $portFilter = $rule | Get-NetFirewallPortFilter
            $appFilter  = $rule | Get-NetFirewallApplicationFilter
            [PSCustomObject]@{
                Name      = $rule.DisplayName
                Protocol  = $portFilter.Protocol
                LocalPort = $portFilter.LocalPort
                Program   = $appFilter.Program
                Profile   = $rule.Profile
                Action    = $rule.Action
            }
        } |
        Sort-Object LocalPort |
        Format-Table -AutoSize

    Write-Output "=== ACTIVE ESTABLISHED CONNECTIONS ==="
    Get-NetTCPConnection -State Established |
        Where-Object { $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::1' } |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort,
            @{N='Process'; E={ (Get-Process -Id $_.OwningProcess -EA SilentlyContinue).Name }} |
        Sort-Object LocalPort |
        Format-Table -AutoSize

} | Out-File -FilePath $outputFile -Width 300 -Encoding UTF8

Write-Host "Audit saved to $outputFile" -ForegroundColor Green
