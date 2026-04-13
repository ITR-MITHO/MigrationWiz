<# The script can be used in both on-premises Exchange and in Exchange Online. 
2 files are exported once the scripts completes: 

Groups: Contains all group information for bulk creation
GroupMembership: Contains all membership information

Use Connect-ExchangeOnline if you need to access the ExchangeOnline cmdlets
#>

Add-PSSnapin *EXC*
Import-Module ActiveDirectory

$Groups = Get-DistributionGroup | Select SamAccountName, Alias, DisplayName, PrimarySMTPAddress, RecipientType, {$_.EmailAddresses}, Description
$Groups | Export-csv $home\desktop\Groups.csv -NoTypeInformation -Encoding Unicode
$Data = Import-Csv $home\desktop\Groups.csv
$Results = @()


Foreach ($D in $Data)
{
$GroupName = $D.Alias
$GroupDes = $D.Description
$User = Get-DistributionGroupMember -Identity $GroupName | Select SamAccountName, DisplayName, PrimarySMTPAddress

Foreach ($U in $User)

{

$Results += [PSCustomObject]@{
                Group = $GroupName
                User = $U.SamAccountName               
                UserDisplay = $U.DisplayName
                UserEmail = $U.PrimarySMTPAddress

}
    }
        }
$Results | Export-csv $home\desktop\GroupMembership.csv -NoTypeInformation -Encoding Unicode
