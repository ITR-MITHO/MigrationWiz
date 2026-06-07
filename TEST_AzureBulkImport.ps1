<#
.SYNOPSIS
    Bulk Microsoft Entra ID (Azure AD) User Import.
.DESCRIPTION
    Validates CSV headers, caches existing cloud accounts to prevent collisions,
    and bulk-provisions Entra ID users using Microsoft Graph.

    MS Graph PowerShell is MANDATORY: Install-Module Microsoft.Graph.Users -Scope CurrentUser
#>

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------
$ImportPath  = "$Home\Desktop\ADUserExport.csv"
$OutputPath  = "$Home\Desktop\EntraUsersWithPasswords.csv"
$ConflictLog = "$Home\Desktop\Entra-USERNAME-CONFLICT.csv"
$Domain      = "itm8exchangetest.dk"
$UsageLocation = "DK" # Required for assigning licenses later if needed (e.g., ISO 2-letter code)

# ---------------------------------------------------------
# PASSWORD GENERATOR - Length can be changed
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
# VALIDATION & CONNECT
# ---------------------------------------------------------
if (-not (Test-Path $ImportPath)) {
    Write-Error "Source import CSV file not found at $ImportPath"
    return
}

$RequiredHeaders = @('SamAccountName', 'DisplayName', 'Enabled')
$CsvHeaders = (Get-Content $ImportPath -First 1) -split ',' | ForEach-Object { $_.Trim('"').Trim("'") }

foreach ($Header in $RequiredHeaders) {
    if ($Header -notin $CsvHeaders) {
        Write-Error "CRITICAL: Missing mandatory structural CSV header column: [$Header]. Aborting script execution."
        return
    }
}

Import-Module Microsoft.Graph.Users

# Connect to Graph API (Prompts for login if no active context exists)
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "User.ReadWrite.All"

# ---------------------------------------------------------
# CACHE EXISTING CLOUD ACCOUNTS
# ---------------------------------------------------------
Write-Host "Caching existing cloud directory entries..." -ForegroundColor Cyan
$ExistingUsers = @{}
# Pulling only UserPrincipalName to optimize network payload
$CloudUsers = Get-MgUser -All -Property UserPrincipalName -ErrorAction Stop
foreach ($CU in $CloudUsers) {
    $ExistingUsers[$CU.UserPrincipalName.ToLower()] = $true
}

$ManagerQueue = New-Object System.Collections.Generic.List[PSCustomObject]

# ---------------------------------------------------------
# IMPORT
# ---------------------------------------------------------
Write-Host "Importing users to Entra ID..." -ForegroundColor Yellow
$Users = Import-Csv $ImportPath

$PasswordOutput = foreach ($User in $Users) {
    $SamAccountName = $User.SamAccountName.Trim()
    $UPN = "$SamAccountName@$Domain"
    
    if ($ExistingUsers.ContainsKey($UPN.ToLower())) {
        [PSCustomObject]@{ UserPrincipalName = $UPN; Status = "Already Exists" } | Export-Csv $ConflictLog -Append -NoTypeInformation
        Write-Warning "User $UPN already exists in Entra ID. Logged to conflict manifest."
        continue 
    }

    $AccountEnabled = $false
    if ($User.Enabled -match 'True|1|Yes') { $AccountEnabled = $true }

    $PasswordPlain = New-RandomPassword
    $PasswordProfile = @{
        Password = $PasswordPlain
        ForceChangePasswordNextSignIn = $true
    }

    $UserParams = @{
        AccountEnabled    = $AccountEnabled
        DisplayName       = $User.DisplayName
        UserPrincipalName = $UPN
        MailNickname      = $SamAccountName
        PasswordProfile   = $PasswordProfile
        JobTitle          = $User.Title
        Department        = $User.Department
        OfficePhone       = $User.TelephoneNumber
        MobilePhone       = $User.Mobile
        UsageLocation     = $UsageLocation
        ErrorAction       = 'Stop'
    }

    try {
        $NewUser = New-MgUser @UserParams
        Write-Host "Successfully provisioned cloud account: $UPN" -ForegroundColor Green

        if ($User.Manager) {
            $ManagerQueue.Add([PSCustomObject]@{ UserUPN = $UPN; ManagerSam = $User.Manager })
        }
        [PSCustomObject]@{
            UserPrincipalName = $UPN
            DisplayName       = $User.DisplayName
            Password          = $PasswordPlain
        }
    }
    catch {
        Write-Error "Failed to provision $UPN. Exception Details: $_"
    }
}

# ---------------------------------------------------------
# MANAGER HANDLING
# ---------------------------------------------------------
if ($ManagerQueue.Count -gt 0) {
    Write-Host "Resolving Entra ID manager linkages..." -ForegroundColor Yellow
    foreach ($Item in $ManagerQueue) {
        try {
            # Find both the user and manager object IDs to construct the Graph reference payload
            $TargetUser = Get-MgUser -UserId $Item.UserUPN -ErrorAction SilentlyContinue
            $ManagerUPN = "$($Item.ManagerSam)@$Domain"
            $TargetMgr  = Get-MgUser -UserId $ManagerUPN -ErrorAction SilentlyContinue

            if ($TargetUser -and $TargetMgr) {
                # Graph handles managers via navigation properties ($links)
                Set-MgUserManagerByRef -UserId $TargetUser.Id -OdataId "https://graph.microsoft.com/v1.0/users/$($TargetMgr.Id)" -ErrorAction Stop
            } else {
                Write-Warning "Could not resolve cloud accounts to bind manager hierarchy for $($Item.UserUPN)"
            }
        }
        catch {
            Write-Warning "Failed binding cloud manager linkage for user $($Item.UserUPN). Error: $_"
        }
    }
}

# ---------------------------------------------------------
# EXPORT CREDENTIAlS
# ---------------------------------------------------------
if ($PasswordOutput) {
    $PasswordOutput | Export-Csv $OutputPath -NoTypeInformation -Encoding UNICODE
    Write-Host "Execution finalized. Provisioning matrix saved to: $OutputPath" -ForegroundColor Green
}

# Disconnect from Graph session
Disconnect-MgGraph
