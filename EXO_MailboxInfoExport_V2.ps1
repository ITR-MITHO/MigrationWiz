<#
.SYNOPSIS
    Exchange Online Mailbox Information Export.
.DESCRIPTION
    Uses high-performance modern Exchange Online V3 cmdlets to retrieve 
    mailbox statistics, archive data, and directory status via bulk operations.
#>

$CSVPATH = "$Home\Desktop\MailboxExport.csv"
$Customer = Read-Host "Enter customer name (e.g. itm8)"
$Destination = Read-Host "Enter target MOERA domain (e.g. itm8exchangetest.onmicrosoft.com)"

Write-Host "Starting data retrieval. Processing in bulk pipelines..." -ForegroundColor Yellow
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "Fetching basic mailbox structures..." -ForegroundColor Cyan

$Mailboxes = Get-EXOMailbox -ResultSize Unlimited -Properties ExchangeGuid, EmailAddresses, RetentionPolicy, ForwardingAddress, IsDirSynced, ArchiveStatus `
    | Where-Object { $_.RecipientTypeDetails -ne "DiscoveryMailbox" }

$TotalCount = $Mailboxes.Count
Write-Host "Found $TotalCount mailboxes. Building tables..." -ForegroundColor Cyan

if ($TotalCount -eq 0) {
    Write-Warning "No mailboxes retrieved. Exiting script."
    return
}

$StatsTable   = @{}
$ArchiveTable = @{}

Write-Host "Retrieving primary mailbox statistics in bulk..." -ForegroundColor Cyan
$Mailboxes | Get-EXOMailboxStatistics | ForEach-Object {
    $StatsTable[[string]$_.MailboxGuid] = $_.TotalItemSize.Value.ToBytes()
}

Write-Host "Retrieving archive mailbox statistics in bulk..." -ForegroundColor Cyan
$Mailboxes | Where-Object { $_.ArchiveStatus -eq "Active" } | Get-EXOMailboxStatistics -Archive | ForEach-Object {
    $ArchiveTable[[string]$_.MailboxGuid] = $_.TotalItemSize.Value.ToBytes()
}

Write-Host "Processing attributes and calculating sizes..." -ForegroundColor Cyan
$Results = foreach ($Mailbox in $Mailboxes) {
    $GuidString   = [string]$Mailbox.ExchangeGuid
    $PrimaryBytes = $StatsTable[$GuidString]
    $ArchiveBytes = $ArchiveTable[$GuidString]
    
    $SizeInMB    = if ($PrimaryBytes) { [math]::Round($PrimaryBytes / 1MB, 0) } else { 0 }
    $ArchiveInMB = if ($ArchiveBytes) { [math]::Round($ArchiveBytes / 1MB, 0) } else { "No Archive" }
    
    $DirSync = if ($Mailbox.IsDirSynced -eq $true) { "Yes" } else { "No" }
    
    $MoeraRaw = ($Mailbox.EmailAddresses | Where-Object { $_ -like "*onmicrosoft.com" } | Select-Object -First 1) -replace '(?i)^smtp:', ''
    $MoeraAddress = if ($MoeraRaw) { $MoeraRaw } else { "MISSING FIX IT MANUALLY" }

    $DestinationEmail = if ($Mailbox.Alias -and $Destination) { "$($Mailbox.Alias)@$Destination" } else { "" }

    [PSCustomObject]@{
        Username               = $Mailbox.Alias
        Name                   = $Mailbox.DisplayName
        Email                  = $Mailbox.PrimarySmtpAddress
        Type                   = $Mailbox.RecipientTypeDetails
        MailboxSizeMB          = $SizeInMB
        ArchiveSizeMB          = $ArchiveInMB
        Retention              = $Mailbox.RetentionPolicy
        Forward                = $Mailbox.ForwardingAddress
        DirSync                = $DirSync
        MOERA                  = $MoeraAddress
        Proxy                  = ($Mailbox.EmailAddresses -join ';')
        "Source Email"         = $MoeraAddress
        "Source Login Name"    = ""
        "Source Password"      = ""
        "Destination Email"    = $DestinationEmail
        "Destination Login Name" = ""
        "Destination Password" = ""
        Flags                  = ""
    }
}

Write-Host "Exporting to CSV..." -ForegroundColor Cyan
$Results | Export-Csv $CSVPATH -NoTypeInformation -Encoding Unicode -UseCulture

$Stopwatch.Stop()
Clear-Host
Write-Host "Find your .csv-file here: $CSVPATH" -ForegroundColor Green
Write-Host "Execution finished in $($Stopwatch.Elapsed.TotalMinutes.ToString('F2')) minutes for $TotalCount mailboxes." -ForegroundColor Gray
