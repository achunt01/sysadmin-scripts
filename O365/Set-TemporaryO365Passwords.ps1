Write-Host "Checking for MSGraph module..."

$Module = Get-Module -Name "Microsoft.Graph.Users.Actionst" -ListAvailable

if ($Module -eq $null) {
    
        Write-Host "MSGraph module not found, installing MSGraph"
        Install-Module -name Microsoft.Graph.Users.Actions
    
    }
Connect-MgGraph

#Enter Admin credentials

############# Define CSV path of Users and Group ##################

$users = Import-Csv "C:\passwordchange.csv"

$users | ForEach-Object {
    $passwordProfile = @{
        Password = $_.Password
        ForceChangePasswordNextSignIn = $true
    }

    Write-Host "Updating $($_.UserPrincipalName)..." -ForegroundColor Yellow

    Update-MgUser -UserId $_.UserPrincipalName -PasswordProfile $passwordProfile
}
