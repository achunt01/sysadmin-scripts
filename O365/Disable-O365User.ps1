<#
.SYNOPSIS
    Offboards a Microsoft 365 user.

.DESCRIPTION
    Revokes the user's sign-in sessions, blocks sign-in, converts the Exchange
    Online mailbox to a shared mailbox, removes the user from removable direct
    group memberships, and removes directly assigned licenses.

    Dynamic and on-premises-synchronized group memberships cannot be removed
    through this script and are reported for manual follow-up. Group-based
    licenses are released when their group membership is removed; any that
    remain assigned are reported. Mailbox conversion must succeed before
    licenses are removed. If the mailbox is over 50 GB, has an archive, or is
    on hold, the script stops before group and license removal so the required
    Exchange license is not inadvertently removed.

.PARAMETER Email
    The user's email address or user principal name.

.NOTES
    Requires ExchangeOnlineManagement and Microsoft.Graph modules.
    Graph delegated permissions: User.ReadWrite.All, User.RevokeSessions.All,
    LicenseAssignment.ReadWrite.All, Group.Read.All, GroupMember.ReadWrite.All,
    and RoleManagement.ReadWrite.Directory. Exchange Online requires permission
    to manage recipients/mailboxes.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$Email
)

#Requires -Version 5.1
#Requires -Modules ExchangeOnlineManagement, Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Users.Actions, Microsoft.Graph.Groups

$ErrorActionPreference = 'Stop'
$graphConnected = $false
$exchangeConnected = $false
$groupIssues = [System.Collections.Generic.List[string]]::new()
$actionIssues = [System.Collections.Generic.List[string]]::new()

try {
    Connect-MgGraph -Scopes @(
        'User.ReadWrite.All',
        'User.RevokeSessions.All',
        'LicenseAssignment.ReadWrite.All',
        'Group.Read.All',
        'GroupMember.ReadWrite.All',
        'RoleManagement.ReadWrite.Directory'
    ) -NoWelcome
    $graphConnected = $true

    Connect-ExchangeOnline -ShowBanner:$false
    $exchangeConnected = $true

    $user = Get-MgUser `
        -UserId $Email `
        -Property 'Id,DisplayName,UserPrincipalName,AccountEnabled,AssignedLicenses,LicenseAssignmentStates' `
        -ErrorAction Stop
    $mailbox = Get-Mailbox -Identity $Email -ErrorAction Stop

    if ($PSCmdlet.ShouldProcess($Email, 'Revoke Microsoft 365 sign-in sessions')) {
        try {
            Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop | Out-Null
            Write-Host 'Revoked sign-in sessions.'
        }
        catch {
            $actionIssues.Add("Session revocation failed: $($_.Exception.Message)")
        }
    }

    if ($user.AccountEnabled -and $PSCmdlet.ShouldProcess($Email, 'Block sign-in')) {
        try {
            Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop | Out-Null
            Write-Host 'Blocked sign-in.'
        }
        catch {
            $actionIssues.Add("Blocking sign-in failed: $($_.Exception.Message)")
        }
    }
    elseif (-not $user.AccountEnabled) {
        Write-Host 'Sign-in was already blocked.'
    }

    $mailboxIsShared = $mailbox.RecipientTypeDetails -eq 'SharedMailbox'
    if (-not $mailboxIsShared) {
        if ($PSCmdlet.ShouldProcess($Email, 'Convert mailbox to shared')) {
            Set-Mailbox -Identity $Email -Type Shared -ErrorAction Stop
            Write-Host 'Converted mailbox to shared.'
        }
        elseif (-not $WhatIfPreference) {
            return
        }
    }
    else {
        Write-Host 'Mailbox is already shared.'
    }

    $mailboxStatistics = Get-MailboxStatistics -Identity $Email -ErrorAction Stop
    try {
        $mailboxSizeBytes = [long]$mailboxStatistics.TotalItemSize.Value.ToBytes()
    }
    catch {
        throw "Could not verify mailbox size; no group memberships or licenses were removed. $($_.Exception.Message)"
    }

    $licenseRetentionReasons = [System.Collections.Generic.List[string]]::new()
    if ($mailboxSizeBytes -gt 50GB) {
        $licenseRetentionReasons.Add('mailbox is over 50 GB')
    }
    if ($mailbox.ArchiveStatus -eq 'Active') {
        $licenseRetentionReasons.Add('online archive is enabled')
    }
    if ($mailbox.LitigationHoldEnabled -or
        $mailbox.DelayHoldApplied -or
        $mailbox.DelayReleaseHoldApplied -or
        @($mailbox.InPlaceHolds).Count -gt 0) {
        $licenseRetentionReasons.Add('mailbox is on hold')
    }

    if ($licenseRetentionReasons.Count -gt 0) {
        $retentionMessage = "Mailbox requires license review ($($licenseRetentionReasons -join ', ')). Sign-in is blocked and the mailbox is shared, but group memberships and licenses were left unchanged."
        if ($WhatIfPreference) {
            Write-Warning $retentionMessage
            return
        }
        throw $retentionMessage
    }

    $groups = @(Get-MgUserMemberOfAsGroup -UserId $user.Id -All -ErrorAction Stop)
    foreach ($group in $groups) {
        if ($group.GroupTypes -contains 'DynamicMembership') {
            $groupIssues.Add("$($group.DisplayName): dynamic membership; cannot remove directly.")
            continue
        }

        if ($group.OnPremisesSyncEnabled) {
            $groupIssues.Add("$($group.DisplayName): synchronized from on-premises; remove it at the source.")
            continue
        }

        if ($PSCmdlet.ShouldProcess($Email, "Remove membership in group '$($group.DisplayName)'")) {
            try {
                Remove-MgGroupMemberByRef `
                    -GroupId $group.Id `
                    -DirectoryObjectId $user.Id `
                    -ErrorAction Stop
                Write-Host "Removed from group: $($group.DisplayName)"
            }
            catch {
                $groupIssues.Add("$($group.DisplayName): $($_.Exception.Message)")
            }
        }
    }

    $user = Get-MgUser `
        -UserId $user.Id `
        -Property 'Id,AssignedLicenses,LicenseAssignmentStates' `
        -ErrorAction Stop

    $directSkuIds = @(
        $user.LicenseAssignmentStates |
            Where-Object { [string]::IsNullOrEmpty($_.AssignedByGroup) } |
            Select-Object -ExpandProperty SkuId -Unique
    )
    if ($directSkuIds.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess($Email, "Remove $($directSkuIds.Count) directly assigned license(s)")) {
            Set-MgUserLicense `
                -UserId $user.Id `
                -AddLicenses @() `
                -RemoveLicenses $directSkuIds `
                -ErrorAction Stop | Out-Null
            Write-Host "Removed $($directSkuIds.Count) directly assigned license(s)."
        }
    }
    else {
        Write-Host 'No directly assigned licenses were found.'
    }

    $remainingGroupLicenses = @(
        $user.LicenseAssignmentStates |
            Where-Object { -not [string]::IsNullOrEmpty($_.AssignedByGroup) }
    )
    if ($remainingGroupLicenses.Count -gt 0) {
        foreach ($license in $remainingGroupLicenses) {
            $groupIssues.Add("License $($license.SkuId) is still group-assigned through group $($license.AssignedByGroup).")
        }
    }

    if ($groupIssues.Count -gt 0) {
        Write-Warning 'Some group memberships or group-based licenses need manual follow-up:'
        foreach ($issue in $groupIssues) {
            Write-Warning " - $issue"
        }
    }

    if ($actionIssues.Count -gt 0) {
        Write-Warning 'Some offboarding actions failed:'
        foreach ($issue in $actionIssues) {
            Write-Warning " - $issue"
        }
    }

    if ($actionIssues.Count -gt 0 -or $groupIssues.Count -gt 0) {
        if ($WhatIfPreference) {
            Write-Host 'WhatIf completed; review the reported follow-up items.'
        }
        else {
            throw 'Offboarding did not complete cleanly; review the warnings and resolve the reported items.'
        }
    }
    elseif ($WhatIfPreference) {
        Write-Host 'WhatIf completed; no changes were made.'
    }
    else {
        Write-Host "Offboarding actions completed for $Email."
    }
}
finally {
    if ($exchangeConnected) {
        Disconnect-ExchangeOnline -Confirm:$false
    }
    if ($graphConnected) {
        Disconnect-MgGraph | Out-Null
    }
}
