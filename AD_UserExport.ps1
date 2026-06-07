# ---------------------------------------------------------
# CONFIGURATION & RECIPIENT TYPE MAPPING
# ---------------------------------------------------------
$CSVPATH = "$Home\Desktop\ADUserExport.csv"
$RequiredProperties = @(
    'DisplayName', 'Description', 'PasswordNeverExpires', 'Enabled', 
    'msExchRecipientTypeDetails', 'Title', 'Department', 'Manager', 
    'TelephoneNumber', 'Mobile', 'ProxyAddresses'
)
$MailboxTypeMap = @{
    1           = "UserMailbox"
    2           = "LinkedMailbox"
    4           = "SharedMailbox"
    16          = "RoomMailbox"
    32          = "EquipmentMailbox"
    128         = "MailUser"
    2147483648  = "RemoteUserMailbox"
    8589934592  = "RemoteRoomMailbox"
    17179869184 = "RemoteEquipmentMailbox"
    34359738368 = "RemoteSharedMailbox"
}

# ---------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------
Import-Module ActiveDirectory

Write-Host "Fetching targeted Active Directory user data..." -ForegroundColor Yellow
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$UserList = Get-ADUser -Filter * -Properties $RequiredProperties
$TotalCount = $UserList.Count

Write-Host "Processing $TotalCount users..." -ForegroundColor Yellow
$ExportList = foreach ($User in $UserList) {

    $MailboxValue = $null
    if ($User.msExchRecipientTypeDetails) {
        $MailboxValue = $MailboxTypeMap[[long]$User.msExchRecipientTypeDetails]
    }
    if (-not $MailboxValue) { $MailboxValue = "" }

    $OU = $null
    if ($User.DistinguishedName -match '(?<=,)(?:OU|CN)=.+') {
        $OU = $Matches[0]
    }

    $ManagerSam = ""
    if ($User.Manager -and $User.Manager -match '^CN=(?<sam>[^,]+)') {
        $ManagerSam = $Matches['sam']
    }
    [PSCustomObject]@{
        DisplayName          = $User.DisplayName
        SamAccountName       = $User.SamAccountName
        Description          = $User.Description
        PasswordNeverExpires = $User.PasswordNeverExpires
        Enabled              = $User.Enabled
        MailType             = $MailboxValue
        Title                = $User.Title
        Department           = $User.Department
        Manager              = $ManagerSam
        TelephoneNumber      = $User.TelephoneNumber
        Mobile               = $User.Mobile
        OU                   = $OU
        Proxy                = ($User.ProxyAddresses -join ";")
    }
}

# ---------------------------------------------------------
# EXPORT
# ---------------------------------------------------------
Write-Host "Exporting to CSV..." -ForegroundColor Yellow
$ExportList | Export-Csv $CSVPATH -NoTypeInformation -Encoding Unicode

$Stopwatch.Stop()
Write-Host "Script completed in $($Stopwatch.Elapsed.TotalSeconds.ToString('F2')) seconds. Find your export here: $CSVPATH" -ForegroundColor Green
