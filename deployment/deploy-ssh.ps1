$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

$installer_url = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v8.9.1.0p1-Beta/OpenSSH-Win64.zip"
$installer_archive = "OpenSSH-Win64.zip"
$installer_search_path = @("c:\ci",
                           $PWD,
                           (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path)

foreach ($p in $installer_search_path){
    "Searching installer in $p"

    if (Test-Path -PathType Leaf -Path "$p\$installer_archive"){
        $installer_path = "$p\$installer_archive"
        break
    }
}

foreach ($p in $installer_search_path){
    "Searching custom sshd_config in $p"

    if (Test-Path -PathType Leaf -Path "$p\sshd_config"){
        $config_path = "$p\sshd_config"
        break
    }
}

if ($installer_path -eq "" -or $installer_path -eq $null){
    "Trying to download installer"
    try {
        Invoke-WebRequest -Uri $installer_url -OutFile $installer_archive
        $installer_path = "$pwd\$installer_archive"
    } catch {
        WriteError -ErrorAction Stop -Message "Unable to download installer: $_"
    }
}

"Trying to install from $installer_path"

try{
    if (Get-Command Expand-Archive -errorAction SilentlyContinue -CommandType Cmdlet){
        Expand-Archive $installer_path "C:\Program Files\" -Force
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem ; [System.IO.Compression.ZipFile]::ExtractToDirectory($installer_path, "c:\Program Files\")
    }

    New-Item "C:\Program Files\OpenSSH" -ItemType Directory -Force
    Copy-Item "C:\Program Files\OpenSSH-Win64\*" "C:\Program Files\OpenSSH"

    if ($config_path -ne "" -and $config_path -ne $null){
        Copy-Item $config_path "C:\Program Files\OpenSSH\sshd_config_default"
    }
} catch {
    WriteError -ErrorAction Stop -Message "Unable to extract OpenSSH: $_"
}

powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files\OpenSSH\install-sshd.ps1"

netsh advfirewall firewall del rule name=sshd
netsh advfirewall firewall add rule name=sshd dir=in action=allow protocol=TCP localport=22
net start sshd
Set-Service sshd -StartupType Automatic

"Setting default shell to Powershell"
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShellCommandOption -Value "/c" -PropertyType String -Force
