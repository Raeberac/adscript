Import-Module ActiveDirectory

$LogFile = "C:\ADScriptLog.txt"
$DomainName = (Get-ADDomain).DNSRoot

function Write-Log {
    param($Message)
    try {
        $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        # Security: Passwords are never passed to this function.
        "$Time - $Message" | Out-File -FilePath $LogFile -Append -ErrorAction SilentlyContinue
    } catch {}
}

function Get-RandomPassword {
    $uppers = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lowers = "abcdefghijkmnopqrstuvwxyz"
    $nums   = "23456789"
    $specs  = "!@#$%"
    $password = ""
    $password += $uppers[(Get-Random -Maximum $uppers.Length)]
    $password += $lowers[(Get-Random -Maximum $lowers.Length)]
    $password += $nums[(Get-Random -Maximum $nums.Length)]
    $password += $specs[(Get-Random -Maximum $specs.Length)]
    $all = $uppers + $lowers + $nums + $specs
    for ($i = 1; $i -le 6; $i++) { $password += $all[(Get-Random -Maximum $all.Length)] }
    return (-join ($password.ToCharArray() | Get-Random -Count $password.Length))
}

function Select-OU {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName | Sort-Object Name
    Write-Host "`n--- Available Organizational Units ---" -ForegroundColor Cyan
    for ($i = 0; $i -lt $ous.Count; $i++) {
        Write-Host "[$($i+1)] " -NoNewline -ForegroundColor Gray
        Write-Host "$($ous[$i].Name)"
    }
    $selection = Read-Host "`nSelect OU number"
    if ($selection -match '^\d+$' -and $selection -gt 0 -and $selection -le $ous.Count) {
        return $ous[$selection-1].DistinguishedName
    }
    Write-Host "!! Invalid Selection !!" -ForegroundColor Red
    return $null
}

while ($true) {
    Clear-Host
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "         ACTIVE DIRECTORY MANAGEMENT CONSOLE         " -ForegroundColor White -BackgroundColor Blue
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host " [USER]           [OU]             [SYSTEM]          " -ForegroundColor Gray
    Write-Host " reset            createou         listuser          " -ForegroundColor White
    Write-Host " enable           listou           bulkimport        " -ForegroundColor White
    Write-Host " disable                           userinfo          " -ForegroundColor White
    Write-Host " setou                             exit              " -ForegroundColor White
    Write-Host " createuser                                          " -ForegroundColor White
    Write-Host " deleteuser                                          " -ForegroundColor White
    Write-Host "-----------------------------------------------------" -ForegroundColor Cyan

    $action = Read-Host "Enter command"
    if ($action -eq "exit") { break }

    switch ($action) {
        "reset" {
            $name = Read-Host "Enter username"
            try {
                $tempPass = Get-RandomPassword
                $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force
                Set-ADAccountPassword -Identity $name -Reset -NewPassword $securePass
                Set-ADUser -Identity $name -ChangePasswordAtLogon $true
                Write-Host "SUCCESS: Password reset." -ForegroundColor Green
                Write-Host "TEMP PASSWORD: $tempPass" -ForegroundColor Yellow
                Write-Log "SUCCESS: Password reset for $name."
            } catch {
                Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "ERROR: Password reset failed for $name."
            }
        }

        "createuser" {
            $name = Read-Host "Enter SamAccountName"
            $first = Read-Host "First Name"
            $last = Read-Host "Last Name"
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($first)) {
                Write-Host "ERROR: Username and First Name are required!" -ForegroundColor Red
                break
            }
            $ou = Select-OU
            if ($ou) {
                try {
                    $tempPass = Get-RandomPassword
                    $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force
                    New-ADUser -SamAccountName $name -UserPrincipalName "$name@$DomainName" `
                               -Name "$first $last" -GivenName $first -Surname $last `
                               -Enabled $true -AccountPassword $securePass -ChangePasswordAtLogon $true -Path $ou
                    Write-Host "User Created Successfully." -ForegroundColor Green
                    Write-Host "TEMP PASSWORD: $tempPass" -ForegroundColor Yellow
                    Write-Log "SUCCESS: Created user $name in $ou."
                } catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }

        "deleteuser" {
            $name = Read-Host "Username to PERMANENTLY DELETE"
            Write-Host "WARNING: This cannot be undone!" -ForegroundColor Red
            $confirm = Read-Host "Confirm deletion? (y/n)"
            if ($confirm -eq 'y') {
                try {
                    Remove-ADUser -Identity $name -Confirm:$false
                    Write-Host "User $name purged." -ForegroundColor Green
                    Write-Log "SUCCESS: Deleted user $name."
                } catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }

        "setou" {
            $name = Read-Host "Username to move"
            $targetOU = Select-OU
            if ($targetOU) {
                try {
                    Move-ADObject -Identity (Get-ADUser $name).DistinguishedName -TargetPath $targetOU
                    Write-Host "Move Successful." -ForegroundColor Green
                    Write-Log "SUCCESS: Moved $name to $targetOU"
                } catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }

        "bulkimport" {
            $path = Read-Host "Enter CSV path (Headers: SamAccountName,FirstName,LastName)"
            if (Test-Path $path) {
                $users = Import-Csv $path
                $ou = Select-OU
                if ($ou) {
                    foreach ($u in $users) {
                        try {
                            $tempPass = Get-RandomPassword
                            $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force
                            New-ADUser -SamAccountName $u.SamAccountName -UserPrincipalName "$($u.SamAccountName)@$DomainName" `
                                       -Name "$($u.FirstName) $($u.LastName)" -GivenName $u.FirstName -Surname $u.LastName `
                                       -Enabled $true -AccountPassword $securePass -ChangePasswordAtLogon $true -Path $ou
                            Write-Host "Created $($u.SamAccountName) - Temp Pass: $tempPass" -ForegroundColor Green
                            Write-Log "BULK: Created $($u.SamAccountName)"
                        } catch { Write-Host "Failed $($u.SamAccountName): $($_.Exception.Message)" -ForegroundColor Red }
                    }
                }
            } else { Write-Host "File not found!" -ForegroundColor Red }
        }

        "enable" {
            $name = Read-Host "Username to enable"
            try {
                Enable-ADAccount -Identity $name
                Write-Host "Account $name enabled." -ForegroundColor Green
                Write-Log "SUCCESS: Enabled $name"
            } catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
        }

        "disable" {
            $name = Read-Host "Username to disable"
            try {
                Disable-ADAccount -Identity $name
                Write-Host "Account $name disabled." -ForegroundColor Yellow
                Write-Log "SUCCESS: Disabled $name"
            } catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
        }

        "createou" {
            $ouName = Read-Host "New OU Name"
            try {
                $domainDN = (Get-ADDomain).DistinguishedName
                New-ADOrganizationalUnit -Name $ouName -Path $domainDN
                Write-Host "OU '$ouName' created." -ForegroundColor Green
                Write-Log "SUCCESS: Created OU $ouName"
            } catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
        }

        "listuser" {
            Get-ADUser -Filter * -ResultSetSize 100 | Select Name, SamAccountName | Sort-Object Name | Format-Table
            Write-Host "(Showing first 100 users)" -ForegroundColor Gray
        }

        "listou" {
            Get-ADOrganizationalUnit -Filter * | Select Name, DistinguishedName | Sort-Object Name | Format-Table
        }

        "userinfo" {
            $name = Read-Host "Enter username"
            try {
                Write-Host "`n--- User Details: $name ---" -ForegroundColor Cyan
                Get-ADUser $name -Properties DisplayName,Enabled,LastLogonDate,PasswordLastSet,LockedOut,DistinguishedName |
                Select-Object DisplayName, SamAccountName, Enabled, LastLogonDate, PasswordLastSet, LockedOut, DistinguishedName |
                Format-List
            } catch { Write-Host "User not found." -ForegroundColor Red }
        }

        default { Write-Host "Unknown command." -ForegroundColor Yellow }
    }
    Write-Host "`n[Press Enter to return to menu]" -ForegroundColor Gray
    Read-Host
}
