$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
If (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
Write-Host "Start PowerShell as an Administrator" -ForegroundColor Red
Break
}

Import-Module ActiveDirectory
$UserList = Get-ADuser -filter * -Properties *
$ExportList = @()

foreach ($User in $UserList) {
    switch ($User.msExchRecipientTypeDetails) {
        1 {$MailboxValue = "UserMailbox"}
        2 {$MailboxValue = "LinkedMailbox"}
        4 {$MailboxValue = "SharedMailbox"}
        16 {$MailboxValue = "RoomMailbox"}
        32 {$MailboxValue = "EquipmentMailbox"}
        128 {$MailboxValue = "MailUser"}
        2147483648 {$MailboxValue = "RemoteUserMailbox"}
        8589934592 {$MailboxValue = "RemoteRoomMailbox"}
        17179869184 {$MailboxValue = "RemoteEquipmentMailbox"}
        34359738368 {$MailboxValue = "RemoteSharedMailbox"}
        default {$MailboxValue = ""}

      }

$OU = $User | Select @{n='OU';e={$_.DistinguishedName -replace '^.+?,(CN|OU.+)','$1'}} -ErrorAction SilentlyContinue
$Collection = New-Object PSObject -Property @{

DisplayName = ($User).DisplayName
SamAccountName = ($User).SamAccountName
Description = ($User).Description
PasswordNeverExpires = ($User).PasswordNeverExpires
Enabled = ($User).Enabled
MailType = $MailboxValue
Title = ($User).Title
Department = ($User).Department
Manager = if ($User.Manager) {(Get-ADUser -Identity $User.Manager -Properties SamAccountName).SamAccountName} else {""}
TelephoneNumber = ($User).TelephoneNumber
Mobile = ($User).Mobile
OU = $OU.OU
Proxy = ($User.ProxyAddresses -join ";")


}
$ExportList += $Collection
}

# Select fields in specific order rather than random.
$ExportList | Select DisplayName, SamAccountName, Description, PasswordNeverExpires, Enabled, MailType, Title, Department, Manager, TelephoneNumber, Mobile, OU, Proxy  | 
Export-csv $Home\Desktop\ADUserExport.csv -NoTypeInformation -Encoding Unicode
Write-Host "Script completed. Find your export here: $Home\Desktop\ADUserExport.csv" -ForegroundColor Green
