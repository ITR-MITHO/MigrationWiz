<#
.SYNOPSIS
Bulk Active Directory User Import.
.DESCRIPTION
    Validates CSV, checks for existing accounts, and provisions users in a single pass while outputting randomized credentials.
#>

Import-Module ActiveDirectory

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------
$ImportPath  = "$Home\Desktop\ADUserExport.csv"
$OutputPath  = "$Home\Desktop\NewUsersWithPasswords.csv"
$ConflictLog = "$Home\Desktop\USERNAME-CONFLICT.csv"
$OU          = "OU=users,DC=contoso,DC=local"
$Domain      = "itm8exchangetest.dk"

# ---------------------------------------------------------
# PASSWORD GENERATION - Length can be adjusted.
# ---------------------------------------------------------
function New-RandomPassword {
    param ([int]$Length = 16)
    
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
        $passwordChars += 1..$remaining | ForEach-Object { $allChars | Get-Random }
    }
    
    return -join ($passwordChars | Sort-Object { Get-Random })
}

# ---------------------------------------------------------
# VALIDATION & CSV GUARDRAILS
# ---------------------------------------------------------
if (-not (Test-Path $ImportPath)) {
    Write-Error "Source import CSV file not found at $ImportPath"
    return
}

# Read header row
$RequiredHeaders = @('SamAccountName', 'DisplayName', 'Enabled')
$CsvHeaders = (Get-Content $ImportPath -First 1) -split ',' | ForEach-Object { $_.Trim('"').Trim("'") }

foreach ($Header in $RequiredHeaders) {
    if ($Header -notin $CsvHeaders) {
        Write-Error "CRITICAL: Missing mandatory structural CSV header column: [$Header]. Aborting script execution."
        return
    }
}

# ---------------------------------------------------------
# IMPORT
# ---------------------------------------------------------
Write-Host "Importing users..." -ForegroundColor Yellow
$Users = Import-Csv $ImportPath

Write-Host "Caching existing directory entries..." -ForegroundColor Cyan
$ExistingUsers = @{}
Get-ADUser -Filter * | ForEach-Object { $ExistingUsers[$_.SamAccountName.ToLower()] = $true }
$ManagerQueue = New-Object System.Collections.Generic.List[PSCustomObject]

$PasswordOutput = foreach ($User in $Users) {
    $SamAccountName = $User.SamAccountName.Trim()
    
    # Checking if username is already taken.
    if ($ExistingUsers.ContainsKey($SamAccountName.ToLower())) {
        [PSCustomObject]@{ SamAccountName = $SamAccountName; Status = "Already Exists" } | Export-Csv $ConflictLog -Append -NoTypeInformation
        Write-Warning "User $SamAccountName already exists. Logged to conflict manifest."
        continue # Drop out of this iteration immediately
    }

    $IsEnabled = $false
    if ($User.Enabled -match 'True|1|Yes') { $IsEnabled = $true }
    $PasswordPlain  = New-RandomPassword
    $SecurePassword = ConvertTo-SecureString $PasswordPlain -AsPlainText -Force

    $UserParams = @{
        SamAccountName        = $SamAccountName
        UserPrincipalName     = "$SamAccountName@$Domain"
        Name                  = $User.DisplayName
        DisplayName           = $User.DisplayName
        Description           = $User.Description
        Enabled               = $IsEnabled
        Title                 = $User.Title
        Department            = $User.Department
        OfficePhone           = $User.TelephoneNumber
        MobilePhone           = $User.Mobile
        AccountPassword       = $SecurePassword
        ChangePasswordAtLogon = ($User.PasswordNeverExpires -ne "True") # Force unless NeverExpires is explicitly flag-true
        Path                  = $OU
        ErrorAction           = 'Stop'
    }

    try {
        New-ADUser @UserParams
        Write-Host "Successfully provisioned user account: $SamAccountName" -ForegroundColor Green
        if ($User.PasswordNeverExpires -eq "True") {
            Set-ADUser -Identity $SamAccountName -PasswordNeverExpires $true
        }
        if ($User.Manager) {
            $ManagerQueue.Add([PSCustomObject]@{ User = $SamAccountName; Manager = $User.Manager })
        }

        [PSCustomObject]@{
            SamAccountName = $SamAccountName
            DisplayName    = $User.DisplayName
            Password       = $PasswordPlain
        }
    }
    catch {
        Write-Error "Failed to provision user $SamAccountName. Exception Details: $_"
    }
}

# ---------------------------------------------------------
# MANAGER HANDLING
# ---------------------------------------------------------
if ($ManagerQueue.Count -gt 0) {
    Write-Host "Resolving nested manager dependencies..." -ForegroundColor Yellow
    foreach ($Item in $ManagerQueue) {
        try {
            $MgrObj = Get-ADUser -Filter "SamAccountName -eq '$($Item.Manager)'" -ErrorAction SilentlyContinue
            if ($MgrObj) {
                Set-ADUser -Identity $Item.User -Manager $MgrObj.DistinguishedName -ErrorAction Stop
            } else {
                Write-Warning "Manager reference '$($Item.Manager)' wasn't found in Active Directory for user $($Item.User)."
            }
        }
        catch {
            Write-Warning "Failed binding hierarchy linkage between $($Item.User) and manager reference."
        }
    }
}

# ---------------------------------------------------------
# EXPORT CREDENTIAL MANIFEST
# ---------------------------------------------------------
if ($PasswordOutput) {
    $PasswordOutput | Export-Csv $OutputPath -NoTypeInformation -Encoding UNICODE
    Write-Host "Script completed. Credentials exported here: $OutputPath" -ForegroundColor Green
}
