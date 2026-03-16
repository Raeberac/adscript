Import-Module ActiveDirectory

$LogFile = "C:\ADScriptLog.txt"
$DomainName = (Get-ADDomain).DNSRoot

function Write-Log {
    param($Message)
    try {
        $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$Time - $Message" | Out-File -FilePath $LogFile -Append -ErrorAction SilentlyContinue
    } catch {}
}

function Select-OU {
    $ous = Get-ADOrganizationalUnit -Filter * | Sort-Object Name
    Write-Host "`n--- Available Organizational Units ---" -ForegroundColor Cyan
    $i = 1
    foreach ($ou in $ous) {
        Write-Host "[$i] " -NoNewline -ForegroundColor Gray
        Write-Host "$($ou.Name)" -ForegroundColor White
        $i++
    }
    Write-Host ""
    $selection = Read-Host "Select OU number"
    if ($selection -match '^\d+$' -and $selection -gt 0 -and $selection -le $ous.Count) {
        return $ous[$selection-1].DistinguishedName
    }
    else {
        Write-Host "!! Invalid selection !!" -ForegroundColor Red
        return $null
    }
}

function Get-RandomPassword {
    # Ensures complexity: 1 Upper, 1 Lower, 1 Num, 1 Special + randoms
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
    for ($i = 1; $i -le 6; $i++) {
        $password += $all[(Get-Random -Maximum $all.Length)]
    }
    
    # Scramble the result
    return (-join ($password.ToCharArray() | Get-Random -Count $password.Length))
}

while ($true) {
    Clear-Host
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "         ACTIVE DIRECTORY MANAGEMENT CONSOLE         " -ForegroundColor White -BackgroundColor Blue
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host " [USER]           [OU]             [SYSTEM]          " -ForegroundColor Gray
    Write-Host " reset            createou         listuser          " -ForegroundColor White
    Write-Host " enable           listou           userinfo          " -ForegroundColor White
    Write-Host " disable                           exit              " -ForegroundColor White
    Write-Host " setou                                               " -ForegroundColor White
    Write-Host " createuser                                          " -ForegroundColor White
    Write-Host " deleteuser                                          " -ForegroundColor White
    Write-Host "-----------------------------------------------------" -ForegroundColor Cyan

    $action = Read-Host "Enter command"
    if ($action -eq "exit") { break }

    switch ($action) {
        "reset" {
            $name = Read-Host "Enter username to reset"
            try {
                $tempPass = Get-RandomPassword
                $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force
                Set-ADAccountPassword -Identity $name -Reset -NewPassword $securePass
                Set-ADUser -Identity $name -ChangePasswordAtLogon $true
                
                Write-Host "`n[SUCCESS] Password reset for $name" -ForegroundColor Green
                Write-Host "NEW TEMPORARY PASSWORD: " -NoNewline
                Write-Host $tempPass -ForegroundColor Yellow -BackgroundColor Black
                Write-Log "SUCCESS: Password reset for $name. (Temp: $tempPass)"
            } catch {
                Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "ERROR: Failed password reset for $name : $($_.Exception.Message)"
            }
        }

        "createuser" {
            $name = Read-Host "Enter SamAccountName (e.g. jdoe)"
            $firstname = Read-Host "First Name"
            $lastname = Read-Host "Last Name"
            $tempPass = Get-RandomPassword
            $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force

            $ou = Select-OU
            if ($null -ne $ou) {
                try {
                    New-ADUser -SamAccountName $name -UserPrincipalName "$name@$DomainName" `
                               -Name "$firstname $lastname" -GivenName $firstname -Surname $lastname `
                               -Enabled $true -AccountPassword $securePass -ChangePasswordAtLogon $true -Path $ou
                    
                    Write-Host "`n[CREATED] User $name added to $ou" -ForegroundColor Green
                    Write-Host "TEMPORARY PASSWORD: " -NoNewline
                    Write-Host $tempPass -ForegroundColor Yellow
                    Write-Log "SUCCESS: Created user $name in $ou. (Temp: $tempPass)"
                } catch {
                    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Log "ERROR: Failed to create user $name : $($_.Exception.Message)"
                }
            }
        }

        "enable" {
            $name = Read-Host "Username to enable"
            try {
                Enable-ADAccount -Identity $name
                Write-Host "Account $name enabled." -ForegroundColor Green
                Write-Log "SUCCESS: Enabled account $name"
            } catch { 
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "ERROR: Could not enable $name : $($_.Exception.Message)"
            }
        }

        "disable" {
            $name = Read-Host "Username to disable"
            try {
                Disable-ADAccount -Identity $name
                Write-Host "Account $name disabled." -ForegroundColor Yellow
                Write-Log "SUCCESS: Disabled account $name"
            } catch { 
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "ERROR: Could not disable $name : $($_.Exception.Message)"
            }
        }

        "setou" {
            $name = Read-Host "Username to move"
            $targetOU = Select-OU
            if ($null -ne $targetOU) {
                try {
                    Move-ADObject -Identity (Get-ADUser $name).DistinguishedName -TargetPath $targetOU
                    Write-Host "Move Successful." -ForegroundColor Green
                    Write-Log "SUCCESS: Moved $name to $targetOU"
                } catch { 
                    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red 
                    Write-Log "ERROR: Failed to move $name : $($_.Exception.Message)"
                }
            }
        }

        "deleteuser" {
            $name = Read-Host "Username to PERMANENTLY DELETE"
            Write-Host "WARNING: This action cannot be undone!" -ForegroundColor Red
            $confirm = Read-Host "Confirm deletion? (y/n)"
            if ($confirm -eq 'y') {
                try {
                    Remove-ADUser -Identity $name -Confirm:$false
                    Write-Host "User $name purged." -ForegroundColor Green
                    Write-Log "SUCCESS: Deleted user $name"
                } catch { 
                    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red 
                    Write-Log "ERROR: Failed to delete $name : $($_.Exception.Message)"
                }
            }
        }

        "createou" {
            $ouName = Read-Host "New OU Name"
            try {
                $domainDN = (Get-ADDomain).DistinguishedName
                New-ADOrganizationalUnit -Name $ouName -Path $domainDN
                Write-Host "OU '$ouName' created at root." -ForegroundColor Green
                Write-Log "SUCCESS: Created OU $ouName"
            } catch { 
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red 
                Write-Log "ERROR: Failed to create OU $ouName : $($_.Exception.Message)"
            }
        }

        "listuser" {
            Get-ADUser -Filter * | Select Name, SamAccountName | Sort-Object Name | Format-Table
            Write-Log "INFO: Listed all users"
        }

        "listou" {
            Get-ADOrganizationalUnit -Filter * | Select Name, DistinguishedName | Sort-Object Name | Format-Table
            Write-Log "INFO: Listed all OUs"
        }

        "userinfo" {
            $name = Read-Host "Enter username"
            try {
                Write-Host "`n--- User Details: $name ---" -ForegroundColor Cyan
                Get-ADUser $name -Properties DisplayName,Enabled,LastLogonDate,PasswordLastSet,LockedOut,DistinguishedName |
                Select-Object DisplayName, SamAccountName, Enabled, LastLogonDate, PasswordLastSet, LockedOut, DistinguishedName |
                Format-List
                Write-Log "INFO: Viewed user info for $name"
            } catch { 
                Write-Host "User not found." -ForegroundColor Red 
                Write-Log "ERROR: Userinfo lookup failed for $name"
            }
        }

        default { Write-Host "Unknown command." -ForegroundColor Yellow }
    }
    Write-Host "`n[Press Enter to return to menu]" -ForegroundColor Gray
    Read-Host
}
