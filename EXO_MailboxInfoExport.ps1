<#
.SYNOPSIS
    Exchange Online Mailbox Information Export.
.DESCRIPTION
    Uses high-performance modern Exchange Online V3 cmdlets to retrieve 
    mailbox statistics, archive data, and directory status via bulk operations.
#>

$CSVPATH = "$Home\Desktop\MailboxExport.csv"

Write-Host "Starting data retrieval. Processing in bulk pipelines..." -ForegroundColor Yellow
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Fetch only the exact properties needed via fast V3 cmdlet.
# We explicitly request 'EmailAddresses' to avoid loading unneeded structural properties.
Write-Host "Fetching basic mailbox structures..." -ForegroundColor Cyan
$Mailboxes = Get-EXOMailbox -ResultSize Unlimited -Property EmailAddresses, RetentionPolicy, ForwardingAddress, IsDirSynced `
    | Where-Object { $_.RecipientTypeDetails -ne "DiscoveryMailbox" }

$TotalCount = $Mailboxes.Count
Write-Host "Found $TotalCount mailboxes. Building tables..." -ForegroundColor Cyan

$StatsTable   = @{}
$ArchiveTable = @{}

Write-Host "Retrieving primary mailbox statistics in bulk..." -ForegroundColor Cyan
Get-EXOMailboxStatistics -ResultSize Unlimited | ForEach-Object {
    $StatsTable[$_.ExternalDirectoryObjectId] = $_.TotalItemSize.Value.ToBytes()
}

Write-Host "Retrieving archive mailbox statistics in bulk..." -ForegroundColor Cyan
Get-EXOMailboxStatistics -ResultSize Unlimited -Archive | ForEach-Object {
    $ArchiveTable[$_.ExternalDirectoryObjectId] = $_.TotalItemSize.Value.ToBytes()
}

Write-Host "Processing attributes and calculating sizes..." -ForegroundColor Cyan
$Results = foreach ($Mailbox in $Mailboxes) {
    $PrimaryBytes = $StatsTable[$Mailbox.ExternalDirectoryObjectId]
    $ArchiveBytes = $ArchiveTable[$Mailbox.ExternalDirectoryObjectId]
    $SizeInMB    = $PrimaryBytes ? [math]::Round($PrimaryBytes / 1MB, 3) : 0
    $ArchiveInMB = $ArchiveBytes ? [math]::Round($ArchiveBytes / 1MB, 3) : "No Archive"
    $DirSync = $Mailbox.IsDirSynced -eq $true ? "Yes" : "No"
    $MoeraAddress = ($Mailbox.EmailAddresses | Where-Object { $_ -like "*onmicrosoft.com" }) -join ";"

    [PSCustomObject]@{
        Username       = $Mailbox.Alias
        Name           = $Mailbox.DisplayName
        Email          = $Mailbox.PrimarySmtpAddress
        Type           = $Mailbox.RecipientTypeDetails
        MailboxSizeMB  = $SizeInMB
        ArchiveSizeMB  = $ArchiveInMB
        Retention      = $Mailbox.RetentionPolicy
        Forward        = $Mailbox.ForwardingAddress
        DirSync        = $DirSync
        MOERA          = $MoeraAddress
        Proxy          = ($Mailbox.EmailAddresses -join ';')
    }
}


Write-Host "Exporting to CSV..." -ForegroundColor Cyan
$Results | Export-Csv $CSVPATH -NoTypeInformation -Encoding Unicode

$Stopwatch.Stop()
Clear-Host
Write-Host "Find your .csv-file here: $CSVPATH" -ForegroundColor Green
Write-Host "Execution finished in $($Stopwatch.Elapsed.TotalMinutes.ToString('F2')) minutes for $TotalCount mailboxes." -ForegroundColor Gray
