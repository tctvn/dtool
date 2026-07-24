# dtool

## Main Features
- Automatically requests Administrator privileges.
- Fast, single-key UI navigation (no `Enter` required).
- Toggle Windows Test Mode (testsigning).
- Toggle BitLocker on selected drives.
- Toggle Volume Write Protection (Read-Only) using diskpart (prevents locking system volumes).
- Reboot directly to UEFI/BIOS firmware settings.

## Quick Installation Guide

**Method 1: Using Windows PowerShell**
Just open Windows PowerShell (run as Administrator if needed) and copy/paste the following command:

```powershell
irm https://raw.githubusercontent.com/tctvn/dtool/main/dtool.ps1 | iex
```

**Method 2: Using the Run Dialog (Win + R)**
Press `Windows + R` on your keyboard, paste the following command, and hit Enter:

```powershell
powershell -nop -c "irm https://raw.githubusercontent.com/tctvn/dtool/main/dtool.ps1 | iex"
```

> **Note:** The `irm` (Invoke-RestMethod) command downloads the file content, and `iex` (Invoke-Expression) executes that content immediately.

## Disclaimer
This tool is intended solely to assist with Windows licensing operations. The author is not responsible for any misuse or illegal use of this tool. We strongly encourage users to purchase a genuine Windows license to support the developers.
