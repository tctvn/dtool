# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        Start-Process powershell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath) -Verb RunAs
    } else {
        Start-Process powershell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "irm https://raw.githubusercontent.com/tctvn/dtool/main/dtool.ps1 | iex") -Verb RunAs
    }
    exit
}

function Read-MenuChoice {
    param([string]$Prompt = "Select an option")
    Write-Host "$($Prompt): " -NoNewline -ForegroundColor Green
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    Write-Host $key -ForegroundColor White
    Write-Host ""
    return [string]$key
}

function Pause {
    Write-Host "Press any key to continue..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}

function Toggle-TestMode {
    Write-Host "`n--- Toggle Test Mode ---" -ForegroundColor Cyan
    # Get current bcdedit info
    $bcdeditOutput = bcdedit
    
    $success = $false
    
    # Check if testsigning is ON or OFF and perform toggle
    if ($bcdeditOutput -match "testsigning\s+Yes") {
        Write-Host "Test Mode is currently ON. Turning it OFF..."
        $resultStr = bcdedit /set testsigning off 2>&1
        if ($?) {
            Write-Host "Success!" -ForegroundColor Green
            $success = $true
        } else {
            Write-Host "An error occurred while turning off Test Mode:" -ForegroundColor Red
            Write-Host $resultStr -ForegroundColor Red
            if ($resultStr -match "Secure Boot") {
                Write-Host "`n[!] It looks like Secure Boot is enabled. You must disable Secure Boot in your BIOS/UEFI settings to change this policy." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Test Mode is currently OFF. Turning it ON..."
        $resultStr = bcdedit /set testsigning on 2>&1
        if ($?) {
            Write-Host "Success!" -ForegroundColor Green
            $success = $true
        } else {
            Write-Host "An error occurred while turning on Test Mode:" -ForegroundColor Red
            Write-Host $resultStr -ForegroundColor Red
            if ($resultStr -match "Secure Boot") {
                Write-Host "`n[!] It looks like Secure Boot is enabled. You must disable Secure Boot in your BIOS/UEFI settings to change this policy." -ForegroundColor Yellow
            }
        }
    }
    
    if ($success) {
        $choice = Read-MenuChoice "Do you want to restart your computer now to apply the changes? (Y/N)"
        if ($choice -match "^[Yy]") {
            Write-Host "Restarting computer..."
            Restart-Computer -Force
        } else {
            Write-Host "Please restart your computer later for the changes to take effect."
        }
    }
    Pause
}

function Toggle-BitLocker {
    Write-Host "`n--- Toggle BitLocker ---" -ForegroundColor Cyan
    # Get available drives
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -ne $null } | Sort-Object DriveLetter
    Write-Host "Available drives:"
    foreach ($vol in $volumes) {
        Write-Host "  $($vol.DriveLetter): - $($vol.FileSystemLabel)"
    }
    
    $driveLetter = Read-MenuChoice "Enter the Drive Letter you want to toggle (e.g. C, D) or 'q' to quit"
    if ($driveLetter -eq 'q' -or [string]::IsNullOrWhiteSpace($driveLetter)) { return }
    
    # Ensure format is like "C:"
    $drive = $driveLetter.Trim().ToUpper().Replace(":", "") + ":"
    Write-Host "Checking BitLocker status for drive $drive..."
    
    try {
        $volume = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
        if ($volume.ProtectionStatus -eq "On" -or $volume.VolumeStatus -eq "EncryptionInProgress") {
            Write-Host "BitLocker is currently ON (or encrypting). Turning it OFF..."
            Disable-BitLocker -MountPoint $drive
            Write-Host "Decryption started successfully! It may take a while to complete." -ForegroundColor Green
            Write-Host "You can check the status anytime with 'manage-bde -status $drive'" -ForegroundColor Yellow
        } else {
            Write-Host "BitLocker is currently OFF. Turning it ON..."
            # Turn on BitLocker
            Enable-BitLocker -MountPoint $drive -UsedSpaceOnly -RecoveryPasswordProtector
            Write-Host "Encryption started successfully! A recovery password protector was added." -ForegroundColor Green
            Write-Host "IMPORTANT: Please backup your recovery key using 'manage-bde -protectors -get $drive'" -ForegroundColor Red
            Write-Host "You can check the status anytime with 'manage-bde -status $drive'" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "An error occurred while toggling BitLocker on ${drive}:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Note: BitLocker is not supported on Windows Home editions, or the drive might not exist." -ForegroundColor Yellow
    }
    Pause
}

function Toggle-VolumeWriteProtection {
    Write-Host "`n--- Toggle Volume Write Protection ---" -ForegroundColor Cyan
    Write-Host "Getting list of available volumes..."
    
    # Run diskpart to list volumes
    $diskpartOutput = "list volume" | diskpart
    $listVolumes = $diskpartOutput | Select-String "Volume [0-9]"
    
    if (-not $listVolumes) {
        Write-Host "Could not retrieve volume list." -ForegroundColor Red
        return
    }
    
    foreach ($line in $listVolumes) {
        Write-Host $line.ToString().Trim()
    }
    
    Write-Host ""
    $volNum = Read-MenuChoice "Enter the Volume number you want to toggle (e.g. 0, 1) or 'q' to quit"
    if ($volNum -eq 'q' -or [string]::IsNullOrWhiteSpace($volNum)) { return }
    
    # Check if the user selected the system volume
    $selectedLine = $listVolumes | Where-Object { $_ -match "Volume\s+$volNum\s+" }
    if ($selectedLine) {
        $lineStr = $selectedLine.ToString()
        $sysDriveLetter = $env:SystemDrive.Substring(0,1)
        if ($lineStr -match "\bBoot\b" -or $lineStr -match "\bSystem\b" -or $lineStr -match "\b$sysDriveLetter\b") {
            Write-Host "Error: You cannot write-protect the System/Boot volume or the OS drive ($env:SystemDrive)!" -ForegroundColor Red
            return
        }
    }
    
    Write-Host "Checking current read-only status for Volume $volNum..."
    # Check current status
    $detailVol = "select volume $volNum`ndetail volume" | diskpart
    $isReadOnly = $false
    
    foreach ($line in $detailVol) {
        if ($line -match "Read-only\s*:\s*Yes") {
            $isReadOnly = $true
            break
        }
    }
    
    if ($isReadOnly) {
        Write-Host "Volume $volNum is currently READ-ONLY (Write Protected). Turning it OFF..."
        $output = "select volume $volNum`nattributes volume clear readonly" | diskpart
        if ($output -match "successfully") {
            Write-Host "Success! Volume $volNum is now writable." -ForegroundColor Green
        } else {
            Write-Host "Failed to clear read-only attribute. Output:" -ForegroundColor Red
            Write-Host ($output | Out-String)
        }
    } else {
        Write-Host "Volume $volNum is currently WRITABLE. Turning it to READ-ONLY (Write Protected)..."
        $output = "select volume $volNum`nattributes volume set readonly" | diskpart
        if ($output -match "successfully") {
            Write-Host "Success! Volume $volNum is now write-protected." -ForegroundColor Green
        } else {
            Write-Host "Failed to set read-only attribute. Output:" -ForegroundColor Red
            Write-Host ($output | Out-String)
        }
    }
    Pause
}

function Show-RebootMenu {
    while ($true) {
        Clear-Host
        Write-Host "`n--- Reboot Options ---" -ForegroundColor Cyan
        Write-Host "1. Reboot to UEFI BIOS"
        Write-Host "2. Reboot to Recovery (Advanced Startup)"
        Write-Host "3. Normal Reboot"
        Write-Host "4. Back to Main Menu"
        
        $choice = Read-MenuChoice "Select an option"
        
        switch ($choice) {
            '1' {
                $confirm = Read-MenuChoice "Reboot to UEFI: Ensure all work is saved. Proceed? (Y/N)"
                if ($confirm -match "^[Yy]") {
                    Write-Host "Rebooting to UEFI..."
                    shutdown /r /fw /t 0
                }
            }
            '2' {
                $confirm = Read-MenuChoice "Reboot to Recovery: Ensure all work is saved. Proceed? (Y/N)"
                if ($confirm -match "^[Yy]") {
                    Write-Host "Rebooting to Recovery..."
                    shutdown /r /o /t 0
                }
            }
            '3' {
                $confirm = Read-MenuChoice "Normal Reboot: Ensure all work is saved. Proceed? (Y/N)"
                if ($confirm -match "^[Yy]") {
                    Write-Host "Rebooting..."
                    shutdown /r /t 0
                }
            }
            '4' { return }
            default { Write-Host "Invalid option. Please try again." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

function Check-WindowsLicense {
    Write-Host "`n--- Check Windows License ---" -ForegroundColor Cyan
    Write-Host "Downloading and executing winlic script..."
    try {
        irm https://raw.githubusercontent.com/tctvn/winlic/main/winlic.ps1 | iex
    } catch {
        Write-Host "Failed to execute script: $_" -ForegroundColor Red
    }
}

function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host "`n========================" -ForegroundColor Cyan
        Write-Host "      dtool Menu        " -ForegroundColor Cyan
        Write-Host "========================" -ForegroundColor Cyan
        Write-Host "1. Toggle Test Mode"
        Write-Host "2. Toggle BitLocker (Select Drive)"
        Write-Host "3. Toggle Volume Write Protection (diskpart)"
        Write-Host "4. Reboot Options..."
        Write-Host "5. Check Windows License (winlic)"
        Write-Host "6. Exit"
        Write-Host "========================" -ForegroundColor Cyan
        
        $choice = Read-MenuChoice "Select an option"
        
        switch ($choice) {
            '1' { Toggle-TestMode }
            '2' { Toggle-BitLocker }
            '3' { Toggle-VolumeWriteProtection }
            '4' { Show-RebootMenu }
            '5' { Check-WindowsLicense }
            '6' { Write-Host "Exiting..."; exit }
            default { Write-Host "Invalid option. Please try again." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

Show-Menu
