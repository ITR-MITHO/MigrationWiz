Import-Module ActiveDirectory
$ImportPath = "$Home\Desktop\ADUserExport.csv"
$OutputPath = "$Home\Desktop\NewUsersWithPasswords.csv"

## Change these to ensure the correct OU is chosen and the correct domain is used when creating! ##
$OU = "OU=users,DC=contoso,DC=local"
$Domain = "itm8exchangetest.dk"

# Generate random 16 character password
function New-RandomPassword {
    param ([int]$Length = 16)
    if ($Length -lt 4) {
        throw "Password length must be at least 4"
    }
    $lower   = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $numbers = '0123456789'.ToCharArray()
    $symbols = '!@#$%^&*()_-+=[]{}'.ToCharArray()

    $passwordChars = @(
        $lower   | Get-Random
        $upper   | Get-Random
        $numbers | Get-Random
        $symbols | Get-Random
    )

    $allChars = $lower + $upper + $numbers + $symbols
    $remaining = $Length - $passwordChars.Count
    if ($remaining -gt 0) {
        $passwordChars += 1..$remaining | ForEach-Object {
            $allChars | Get-Random
        }
    }
    $passwordChars = $passwordChars | Sort-Object { Get-Random }
    return -join $passwordChars
}

$Users = Import-Csv $ImportPath
$Output = @()

# --- PASS 1: CREATE USERS ---
foreach ($User in $Users) {

    $PasswordPlain = New-RandomPassword
    $SecurePassword = ConvertTo-SecureString $PasswordPlain -AsPlainText -Force

        New-ADUser `
            -SamAccountName $User.SamAccountName `
            -UserPrincipalName ($User.SamAccountName + "@$Domain") `
            -Name $User.DisplayName `
            -DisplayName $User.DisplayName `
            -Description $User.Description `
            -Enabled ([System.Convert]::ToBoolean($User.Enabled)) `
            -Title $User.Title `
            -Department $User.Department `
            -OfficePhone $User.TelephoneNumber `
            -MobilePhone $User.Mobile `
            -AccountPassword $SecurePassword `
            -ChangePasswordAtLogon $true `
            -Path $OU

        $Output += [PSCustomObject]@{
            SamAccountName = $User.SamAccountName
            DisplayName    = $User.DisplayName
            Password       = $PasswordPlain

    }
    
}

# --- PASS 2: SET REMAINING ATTRIBUTES ---
foreach ($User in $Users) {

    try {
        $ADUser = Get-ADUser -Identity $User.SamAccountName

        if ($User.PasswordNeverExpires -eq "True") {
            Set-ADUser -Identity $ADUser -PasswordNeverExpires $true
        }

        if ($User.Manager) {
            $ManagerObj = Get-ADUser -Filter "SamAccountName -eq '$($User.Manager)'"
            if ($ManagerObj) {
                Set-ADUser -Identity $ADUser -Manager $ManagerObj.DistinguishedName
            }
        }

    }
    catch {
        Write-Host "Failed to update user: $($User.SamAccountName)" -ForegroundColor Yellow
    }
}

# Export passwords
$Output | Export-Csv $OutputPath -NoTypeInformation -Encoding UNICODE
Write-Host "Output file: $OutputPath" -ForegroundColor Green
