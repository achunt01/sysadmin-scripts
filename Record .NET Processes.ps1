$targetPath = "Microsoft.NETCore.App\6.*"

# Get all processes with a path (filter out some system ones)
$processes = Get-Process | Where-Object { $_.Path -ne $null }
Write-host ".NET 6 Processes:"
foreach ($proc in $processes) {
    try {
        $modules = $proc.Modules
        foreach ($mod in $modules) {
            if ($mod.FileName -like "*$targetPath*") {
                Write-Host "`nProcess: $($proc.ProcessName) (PID: $($proc.Id))"
                Write-Host "Loaded .NET module: $($mod.FileName)"
                break
            }
        }
    } catch {
        # Access denied or system process – skip it
    }
}




$dotNetVersions = @("2.*", "3.*", "4.*", "5.*", "6.*", "7.*","9.*","8.*")

$targetPaths = @(
    "C:\Program Files\dotnet\shared\Microsoft.NETCore.App",
    "C:\Program Files (x86)\dotnet\shared\Microsoft.NETCore.App"
)

$processes = Get-Process | Where-Object { $_.Path }

foreach ($version in $dotNetVersions) {
    Write-Host "`n.NET $version Processes:"
    foreach ($proc in $processes) {
        try {
            foreach ($mod in $proc.Modules) {
                foreach ($path in $targetPaths) {
                    if ($mod.FileName -like "$path\$version*") {
                        Write-Host "`nProcess: $($proc.ProcessName) (PID: $($proc.Id))"
                        Write-Host "Loaded .NET module: $($mod.FileName)"
                        break
                    }
                }
            }
        } catch {
            # Access denied or protected process
        }
    }
}
