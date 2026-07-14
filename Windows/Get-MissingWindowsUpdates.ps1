Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# talking directly to Windows Update Agent instead of PSWindowsUpdate
# avoids the ArgumentException that hits when update metadata is malformed
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$searcher.ServerSelection = 2  # 2 = Microsoft Update, pulls driver/app updates too

$results = $searcher.Search("IsInstalled=0")

# build the update list and stuff it into the Ninja custom field
$c = ""
foreach ($update in $results.Updates) {
    $c = $update.Title + "`r`n" + $c
}

Ninja-Property-Set missingUpdates $c

Write-Output "Found $($results.Updates.Count) pending updates and wrote them to missingUpdates field."
