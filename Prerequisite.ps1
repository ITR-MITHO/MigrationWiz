<#
.SYNOPSIS
    Verifies that the MOERA address is present on Exchange objects. 
    If missing, it attempts to add it. 
    Logs both successful modifications and failures (e.g., DirSynced mailboxes) to separate CSV files.
#>

$Customer = Read-Host "Enter customer name (e.g. itm8)"

# Define Log File Paths
$SuccessLogPath = "C:\temp\Successful_MOERA_Fixes.csv"
$FailedLogPath  = "C:\temp\Failed_MOERA_Fixes.csv"

# Initialize lists to hold log entries
$SuccessMailboxes = [System.Collections.Generic.List[PSObject]]::new()
$FailedMailboxes  = [System.Collections.Generic.List[PSObject]]::new()

# Get the primary onmicrosoft.com domain as a string
$MOERA = (Get-AcceptedDomain | Where-Object { $_.Name -like "*onmicrosoft.com" } | Select-Object -First 1).DomainName.Address

# Fetch all mailboxes
$Mailboxes = Get-Mailbox -ResultSize Unlimited

foreach ($M in $Mailboxes) {
    # Check if any listed email address matches the onmicrosoft.com domain
    if (-not ($M.EmailAddresses -like "*$MOERA")) {
        
        # Define address to add
        $NewAddress = "smtp:$($M.Alias)+$Customer@$MOERA"
        
        try {
            # -ErrorAction Stop ensures DirSync write-failures hit the Catch block
            Set-Mailbox -Identity $M.Identity -EmailAddresses @{Add = $NewAddress } -ErrorAction Stop
            
            Write-Host "Successfully added $NewAddress to $($M.PrimarySmtpAddress)" -ForegroundColor Green
            
            # Log successful modification
            $SuccessMailboxes.Add([PSCustomObject]@{
                PrimarySmtpAddress = $M.PrimarySmtpAddress.ToString()
                UserPrincipalName  = $M.UserPrincipalName
                Alias              = $M.Alias
                AddedAddress       = $NewAddress
                Timestamp          = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            })
        }
        catch {
            Write-Warning "Failed to update $($M.PrimarySmtpAddress): $_"
            
            # Log failed modification
            $FailedMailboxes.Add([PSCustomObject]@{
                PrimarySmtpAddress = $M.PrimarySmtpAddress.ToString()
                UserPrincipalName  = $M.UserPrincipalName
                Alias              = $M.Alias
                AttemptedAddress   = $NewAddress
                ErrorMessage       = $_.Exception.Message
                Timestamp          = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            })
        }
    }
}

# Export Success Logs if entries exist
if ($SuccessMailboxes.Count -gt 0) {
    $SuccessMailboxes | Export-Csv -Path $SuccessLogPath -NoTypeInformation -Encoding utf8
    Write-Host "Exported $($SuccessMailboxes.Count) successful changes to $SuccessLogPath" -ForegroundColor Green
} else {
    Write-Host "No successful changes were made." -ForegroundColor Gray
}

# Export Failure Logs if entries exist
if ($FailedMailboxes.Count -gt 0) {
    $FailedMailboxes | Export-Csv -Path $FailedLogPath -NoTypeInformation -Encoding utf8
    Write-Host "Exported $($FailedMailboxes.Count) failed objects to $FailedLogPath" -ForegroundColor Yellow
} else {
    Write-Host "No failed modifications encountered." -ForegroundColor Gray
}
