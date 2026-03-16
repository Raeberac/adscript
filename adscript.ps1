Import-Module ActiveDirectory

# Log file location
$LogFile = "$env:TEMP\ADScriptLog.txt"

# Set Console Colors for that "Terminal" look
function Set-ConsoleColors {
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "Gray"
    Clear-Host 
}

# Dynamic Domain Info
$ADDomain = Get-ADDomain
$DomainName = $ADDomain.DNSRoot
$NetBIOSName = $ADDomain.NetBIOSName

function Write-Log {
    param($Message)
    try {
        $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$Time - $Message" | Out-File -FilePath $LogFile -Append -ErrorAction SilentlyContinue
    } catch {}
}

function Get-RandomPassword {
    $uppers = "ABCDEFGHJKLMNPQRSTUVWXYZ"; $lowers = "abcdefghijkmnopqrstuvwxyz"
    $nums = "23456789"; $specs = "!@#$%"
    $password = $uppers[(Get-Random -Maximum 24)] + $lowers[(Get-Random -Maximum 25)] + $nums[(Get-Random -Maximum 8)] + $specs[(Get-Random -Maximum 5)]
    $all = $uppers + $lowers + $nums + $specs
    for ($i = 1; $i -le 6; $i++) { $password += $all[(Get-Random -Maximum $all.Length)] }
    return (-join ($password.ToCharArray() | Get-Random -Count $password.Length))
}

function Select-OU {
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName | Sort-Object Name
    Write-Host "`n[ AD STRUCTURE ]" -ForegroundColor Green
    for ($i = 0; $i -lt $ous.Count; $i++) {
        Write-Host " ($($i+1)) " -NoNewline -ForegroundColor Green
        Write-Host "$($ous[$i].Name)" -ForegroundColor White
    }
    $selection = Read-Host "`nSelect OU Number"
    if ($selection -match '^\d+$' -and $selection -gt 0 -and $selection -le $ous.Count) {
        return $ous[$selection-1].DistinguishedName
    }
    Write-Host "!! INVALID SELECTION !!" -ForegroundColor Red
    return $null
}

# Initialize UI
Set-ConsoleColors

while ($true) {
    Clear-Host
    Write-Host " _____________________________________________________ " -ForegroundColor Green
    Write-Host "|                                                     |" -ForegroundColor Green
    Write-Host "|         ACTIVE DIRECTORY MANAGEMENT CONSOLE         |" -ForegroundColor White
    Write-Host "|_____________________________________________________|" -ForegroundColor Green
    Write-Host "  [USER OPS]        [OU OPS]         [SYSTEM OPS]      " -ForegroundColor Green
    Write-Host "  reset             createou         listuser          " -ForegroundColor White
    Write-Host "  enable            listou           bulkimport        " -ForegroundColor White
    Write-Host "  disable                            userinfo          " -ForegroundColor White
    Write-Host "  setou                              viewlog           " -ForegroundColor White
    Write-Host "  createuser                         exit              " -ForegroundColor White
    Write-Host "  deleteuser                                           " -ForegroundColor White
    Write-Host " ----------------------------------------------------- " -ForegroundColor Green

    $action = Read-Host "Command"
    if ($action -eq "exit") { break }

    switch ($action) {
        "reset" {
            $name = Read-Host "Target Username"
            try {
                $tempPass = Get-RandomPassword
                $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force
                Set-ADAccountPassword -Identity $name -Reset -NewPassword $securePass
                Set-ADUser -Identity $name -ChangePasswordAtLogon $true
                Write-Host "`n[ SUCCESS ]" -ForegroundColor Green
                Write-Host "TEMP PASSWORD: $tempPass" -ForegroundColor Green -BackgroundColor DarkGreen
                Write-Log "SUCCESS: Reset $name"
            } catch {
                Write-Host "`n[ ERROR ] $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        "createuser" {
            $name = Read-Host "SamAccountName"; $first = Read-Host "First Name"; $last = Read-Host "Last Name"
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($first)) {
                Write-Host "!! REQUIRED FIELDS MISSING !!" -ForegroundColor Red; break
            }
            
            Write-Host "Default UPN Suffix: @$DomainName" -ForegroundColor Gray
            $suffixInput = Read-Host "Press Enter for default, or type new suffix"
            $upnSuffix = if ([string]::IsNullOrWhiteSpace($suffixInput)) { $DomainName } else { $suffixInput.Replace("@","") }

            $ou = Select-OU
            if ($ou) {
                try {
                    $tempPass = Get-RandomPassword
                    $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force
                    New-ADUser -SamAccountName $name -UserPrincipalName "$name@$upnSuffix" -Name "$first $last" `
                               -GivenName $first -Surname $last -Enabled $true -AccountPassword $securePass -ChangePasswordAtLogon $true -Path $ou
                    
                    Write-Host "`n[ USER CREATED ]" -ForegroundColor Green
                    Write-Host "Legacy Logon:  $NetBIOSName\$name" -ForegroundColor White
                    Write-Host "UPN/Email:     $name@$upnSuffix" -ForegroundColor White
                    Write-Host "TEMP PASSWORD: $tempPass" -ForegroundColor Green -BackgroundColor DarkGreen
                    Write-Log "SUCCESS: Created $name ($name@$upnSuffix)"
                } catch { Write-Host "!! ERROR: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }

        "setou" {
            $name = Read-Host "Username to move"
            $targetOU = Select-OU
            if ($targetOU) {
                try {
                    Move-ADObject -Identity (Get-ADUser $name).DistinguishedName -TargetPath $targetOU
                    Write-Host "[ MOVED ] $name successfully." -ForegroundColor Green
                    Write-Log "SUCCESS: Moved $name to $targetOU"
                } catch { Write-Host "!! ERROR: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }

        "bulkimport" {
            $path = Read-Host "CSV Path"
            if (Test-Path $path) {
                $users = Import-Csv $path; $ou = Select-OU
                if ($ou) {
                    foreach ($u in $users) {
                        try {
                            $tempPass = Get-RandomPassword
                            $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force
                            New-ADUser -SamAccountName $u.SamAccountName -UserPrincipalName "$($u.SamAccountName)@$DomainName" `
                                       -Name "$($u.FirstName) $($u.LastName)" -GivenName $u.FirstName -Surname $u.LastName `
                                       -Enabled $true -AccountPassword $securePass -ChangePasswordAtLogon $true -Path $ou
                            Write-Host "PROCESSED: $($u.SamAccountName) | Pass: $tempPass" -ForegroundColor Green
                        } catch { Write-Host "FAILED: $($u.SamAccountName)" -ForegroundColor Red }
                    }
                }
            } else { Write-Host "!! FILE NOT FOUND !!" -ForegroundColor Red }
        }

        "listuser" {
            Get-ADUser -Filter * -ResultSetSize 50 | Select Name, SamAccountName | Sort-Object Name | Format-Table
            Write-Host "(Limit: 50 objects)" -ForegroundColor Gray
        }

        "listou" {
            Get-ADOrganizationalUnit -Filter * | Select Name, DistinguishedName | Sort-Object Name | Format-Table
        }

        "userinfo" {
            $name = Read-Host "Target Username"
            try {
                Write-Host "`n[ EXTENDED USER REPORT ]" -ForegroundColor Green
                Get-ADUser $name -Properties UserPrincipalName, Enabled, LastLogonDate, LockedOut, PasswordLastSet, DistinguishedName | 
                Select-Object @{N="Display Name";E={$_.Name}}, 
                              SamAccountName, 
                              UserPrincipalName, 
                              Enabled, 
                              LockedOut, 
                              PasswordLastSet, 
                              LastLogonDate, 
                              DistinguishedName | Format-List
                Write-Log "INFO: Viewed userinfo for $name"
            } catch { Write-Host "!! USER NOT FOUND !!" -ForegroundColor Red }
        }

        "enable" { 
            try { 
                $u = Read-Host "User"
                Enable-ADAccount -Identity $u
                Write-Host "[ ENABLED ]" -ForegroundColor Green
                Write-Log "SUCCESS: Enabled $u"
            } catch { Write-Host "!! ERROR !!" -ForegroundColor Red } 
        }

        "disable" { 
            try { 
                $u = Read-Host "User"
                Disable-ADAccount -Identity $u
                Write-Host "[ DISABLED ]" -ForegroundColor Red
                Write-Log "SUCCESS: Disabled $u"
            } catch { Write-Host "!! ERROR !!" -ForegroundColor Red } 
        }

        "deleteuser" {
            $name = Read-Host "Username to PURGE"
            Write-Host "!! WARNING: IRREVERSIBLE ACTION !!" -ForegroundColor Red
            if ((Read-Host "Confirm (y/n)") -eq 'y') {
                try {
                    Remove-ADUser -Identity $name -Confirm:$false
                    Write-Host "[ PURGED ] $name" -ForegroundColor Green
                    Write-Log "SUCCESS: Deleted $name"
                } catch { Write-Host "!! ERROR: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }

        "createou" {
            $ouName = Read-Host "New OU Name"
            try {
                New-ADOrganizationalUnit -Name $ouName -Path $ADDomain.DistinguishedName
                Write-Host "OU '$ouName' created." -ForegroundColor Green
                Write-Log "SUCCESS: Created OU $ouName"
            } catch { Write-Host "!! ERROR: $($_.Exception.Message)" -ForegroundColor Red }
        }

        "viewlog" { if (Test-Path $LogFile) { notepad $LogFile } }

        default { Write-Host "!! UNKNOWN COMMAND !!" -ForegroundColor Red }
    }
    Write-Host "`n[ ENTER TO RETURN ]" -ForegroundColor Green
    Read-Host
}
