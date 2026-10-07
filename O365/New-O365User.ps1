<#
.SYNOPSIS
    Creates a Microsoft 365 user and assigns a license when a seat is available.

.DESCRIPTION
    Creates an enabled Entra ID user using the supplied display name, email
    address, and phone number. The email address is used as the user principal
    name. The script generates a temporary password, requires it to be changed
    at first sign-in, and displays it once after the user is created.

    The operator selects a SKU from the tenant's subscribed SKUs. If that SKU
    has no available seats, the user is still created without a license; the
    operator must obtain a seat through the CSP and assign it separately.

.PARAMETER DisplayName
    The new user's display name.

.PARAMETER Email
    The new user's email address and user principal name.

.PARAMETER MobilePhone
    The new user's mobile phone number.

.NOTES
    Requires Microsoft.Graph.Authentication, Microsoft.Graph.Users,
    Microsoft.Graph.Identity.DirectoryManagement, and
    Microsoft.Graph.Users.Actions. Delegated permissions:
    User.ReadWrite.All, Organization.Read.All, and
    LicenseAssignment.ReadWrite.All.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$Email,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$MobilePhone
)

#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users.Actions

$ErrorActionPreference = 'Stop'
$connected = $false

try {
    Connect-MgGraph -Scopes @(
        'User.ReadWrite.All',
        'Organization.Read.All',
        'LicenseAssignment.ReadWrite.All'
    ) -NoWelcome
    $connected = $true

    $skus = @(Get-MgSubscribedSku -All | Sort-Object SkuPartNumber)
    $selectedSku = $null

    if ($skus.Count -gt 0) {
        Write-Host 'Tenant licenses (available seats = enabled seats - consumed seats):'
        for ($i = 0; $i -lt $skus.Count; $i++) {
            $sku = $skus[$i]
            $enabledSeats = [int]$sku.PrepaidUnits.Enabled
            $consumedSeats = [int]$sku.ConsumedUnits
            $availableSeats = [Math]::Max(0, $enabledSeats - $consumedSeats)
            Write-Host ('[{0}] {1} - {2} available ({3})' -f
                ($i + 1), $sku.SkuPartNumber, $availableSeats, $sku.CapabilityStatus)
        }

        $selection = Read-Host 'Select a SKU number, or press Enter to create the user without a license'
        if (-not [string]::IsNullOrWhiteSpace($selection)) {
            $selectionNumber = 0
            if (-not [int]::TryParse($selection, [ref]$selectionNumber) -or
                $selectionNumber -lt 1 -or $selectionNumber -gt $skus.Count) {
                throw "Invalid SKU selection: $selection"
            }
            $selectedSku = $skus[$selectionNumber - 1]
        }
    }
    else {
        Write-Warning 'No subscribed SKUs were returned. The user will be created without a license.'
    }

    $mailNickname = ($Email.Split('@')[0] -replace '[^a-zA-Z0-9._-]', '')
    if ([string]::IsNullOrWhiteSpace($mailNickname)) {
        throw "Could not derive a mail nickname from '$Email'."
    }

    # A GUID is generated from a cryptographically strong random source.
    $initialPassword = ([guid]::NewGuid().ToString('N')) + 'aA1!'
    $passwordProfile = @{
        Password                      = $initialPassword
        ForceChangePasswordNextSignIn = $true
    }
    $userBody = @{
        AccountEnabled    = $true
        DisplayName       = $DisplayName
        MailNickname      = $mailNickname
        UserPrincipalName = $Email
        MobilePhone       = $MobilePhone
        UsageLocation     = 'US'
        PasswordProfile   = $passwordProfile
    }

    $user = $null
    if ($PSCmdlet.ShouldProcess($Email, 'Create Microsoft 365 user')) {
        $user = New-MgUser -BodyParameter $userBody -ErrorAction Stop
        Write-Host "Created user: $($user.UserPrincipalName)"
        Write-Host "Temporary password (shown once): $initialPassword" -ForegroundColor Yellow
        Write-Host 'The user must change this password at first sign-in.'
    }
    elseif (-not $WhatIfPreference) {
        return
    }

    if ($null -eq $selectedSku) {
        if ($null -ne $user) {
            Write-Host 'No license selected. Assign a license separately when ready.'
        }
        return
    }

    $enabledSeats = [int]$selectedSku.PrepaidUnits.Enabled
    $consumedSeats = [int]$selectedSku.ConsumedUnits
    $availableSeats = [Math]::Max(0, $enabledSeats - $consumedSeats)
    if ($selectedSku.CapabilityStatus -ne 'Enabled' -or $availableSeats -lt 1) {
        $creationMessage = if ($null -ne $user) {
            'The user was created without a license.'
        }
        else {
            'The user would be created without a license.'
        }
        Write-Warning "No available seat for $($selectedSku.SkuPartNumber). $creationMessage Obtain the SKU through the CSP, then assign it to the user."
        return
    }

    if ($PSCmdlet.ShouldProcess($Email, "Assign license $($selectedSku.SkuPartNumber)")) {
        if ($null -eq $user) {
            return
        }

        Set-MgUserLicense `
            -UserId $user.Id `
            -AddLicenses @(@{ SkuId = $selectedSku.SkuId }) `
            -RemoveLicenses @() `
            -ErrorAction Stop | Out-Null
        Write-Host "Assigned license: $($selectedSku.SkuPartNumber)"
    }
}
finally {
    if ($connected) {
        Disconnect-MgGraph | Out-Null
    }
}
