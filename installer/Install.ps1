# Automated Install script by Midonei
$Host.UI.RawUI.WindowTitle = "Installing MagiskOnWSA..."
function Test-Administrator {
    [OutputType([bool])]
    param()
    process {
        [Security.Principal.WindowsPrincipal]$user = [Security.Principal.WindowsIdentity]::GetCurrent();
        return $user.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator);
    }
}

function Get-InstalledDependencyVersion {
    param (
        [string]$Name,
        [string]$ProcessorArchitecture
    )
    process {
        return Get-AppxPackage -Name $Name | ForEach-Object { if ($_.Architecture -eq $ProcessorArchitecture) { $_ } } | Sort-Object -Property Version | Select-Object -ExpandProperty Version -Last 1;
    }
}

function DownloadWinHttpDLL {
        Invoke-WebRequest -Uri https://github.com/cinit/WSAPatch/blob/main/original.dll.win11.22h2/x86_64/winhttp.dll?raw=true -OutFile .\WSAClient\winhttp.dll
        $hash = Get-FileHash ".\WSAClient\winhttp.dll" | Select-Object Hash
        if ($hash -ne "373A742B37DCF3DD18E895F33816AEF1FC238D128B3BF2AA528F6838AB1DC304") 
        {
            DownloadWinHttpDLL
        }
}

function DownloadWSAPatchDLL {
        Invoke-WebRequest -Uri https://github.com/YT-Advanced/WSA-Script/blob/main/DLL/WsaPatch.dll?raw=true -OutFile .\WSAClient\WsaPatch.dll
        $hash = Get-FileHash ".\WSAClient\WsaPatch.dll" | Select-Object Hash
        if ($hash -ne "e15a619f91891419c2be09264d4a8e1ccbead002a895902f721d59ebc63a4b89") 
        {
            DownloadWSAPatchDLL
        }
}

function DownloadIcuDLL {
        Invoke-WebRequest -Uri https://github.com/YT-Advanced/WSA-Script/blob/main/DLL/icu.dll?raw=true -OutFile .\WSAClient\icu.dll
        $hash = Get-FileHash ".\WSAClient\icu.dll" | Select-Object Hash
        if ($hash -ne "46eae8b730995198d24f1bc9bbbac6d05be5829acddc056536c024ecc927bd03") 
        {
            DownloadIcuDLL
        }
}
function Finish {
    Clear-Host
    Start-Process "wsa://com.topjohnwu.magisk"
    Start-Process "wsa://com.android.vending"
}

If (-Not (Test-Administrator)) {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
    $proc = Start-Process -PassThru -WindowStyle Hidden -Verb RunAs ConHost.exe -Args "powershell -ExecutionPolicy Bypass -Command Set-Location '$PSScriptRoot'; &'$PSCommandPath' EVAL"
    $proc.WaitForExit()
    If ($proc.ExitCode -Ne 0) {
        Clear-Host
        Write-Warning "Failed to launch start as Administrator`r`nPress any key to exit"
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    }
    exit
}
ElseIf (($args.Count -Eq 1) -And ($args[0] -Eq "EVAL")) {
    Start-Process ConHost.exe -Args "powershell -ExecutionPolicy Bypass -Command Set-Location '$PSScriptRoot'; &'$PSCommandPath'"
    exit
}

$FileList = Get-Content -Path .\filelist.txt
If (((Test-Path -Path $FileList) -Eq $false).Count) {
    Write-Error "Some files are missing in the folder. Please try to build again. Press any key to exist"
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"

If ($(Get-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform').State -Ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -NoRestart -FeatureName 'VirtualMachinePlatform'
    Clear-Host
    Write-Warning "Need restart to enable virtual machine platform`r`nPress y to restart or press any key to exit"
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    If ("y" -Eq $key.Character) {
        Restart-Computer -Confirm
    }
    Else {
        exit 1
    }
}

[xml]$Xml = Get-Content ".\AppxManifest.xml";
$Name = $Xml.Package.Identity.Name;
$ProcessorArchitecture = $Xml.Package.Identity.ProcessorArchitecture;
$Dependencies = $Xml.Package.Dependencies.PackageDependency;
$Dependencies | ForEach-Object {
    If ($_.Name -Eq "Microsoft.VCLibs.140.00.UWPDesktop") {
        $HighestInstalledVCLibsVersion = Get-InstalledDependencyVersion -Name $_.Name -ProcessorArchitecture $ProcessorArchitecture;
        If ( $HighestInstalledVCLibsVersion -Lt $_.MinVersion ) {
            Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Path "Microsoft.VCLibs.$ProcessorArchitecture.14.00.Desktop.appx"
        }
    }
    ElseIf ($_.Name -Match "Microsoft.UI.Xaml") {
        $HighestInstalledXamlVersion = Get-InstalledDependencyVersion -Name $_.Name -ProcessorArchitecture $ProcessorArchitecture;
        If ( $HighestInstalledXamlVersion -Lt $_.MinVersion ) {
            Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Path "Microsoft.UI.Xaml_$ProcessorArchitecture.appx"
        }
    }
}

$Installed = $null
$Installed = Get-AppxPackage -Name $Name

If (($null -Ne $Installed) -And (-Not ($Installed.IsDevelopmentMode))) {
    Clear-Host
    Write-Warning "There is already one installed WSA. Please uninstall it first.`r`nPress y to uninstall existing WSA or press any key to exit"
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    If ("y" -Eq $key.Character) {
        Remove-AppxPackage -Package $Installed.PackageFullName
    }
    Else {
        exit 1
    }
}

Stop-Process -Name "WsaClient" -ErrorAction SilentlyContinue
$winver = (Get-WmiObject -class Win32_OperatingSystem).Caption
if ($winver.Contains("10")) {
    if ((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId -eq 2009)
    {
        Clear-Host
        Write-Host "Patching Windows 10 AppxManifest file..."
        $xml = [xml](Get-Content '.\AppxManifest.xml')
        $nsm = New-Object Xml.XmlNamespaceManager($xml.NameTable)
        $nsm.AddNamespace('rescap', "http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities")
        $nsm.AddNamespace('desktop6', "http://schemas.microsoft.com/appx/manifest/desktop/windows10/6")
        $node = $xml.Package.Capabilities.SelectSingleNode("rescap:Capability[@Name='customInstallActions']", $nsm)
        $xml.Package.Capabilities.RemoveChild($node) | Out-Null
        $node = $xml.Package.Extensions.SelectSingleNode("desktop6:Extension[@Category='windows.customInstall']", $nsm)
        $xml.Package.Extensions.RemoveChild($node) | Out-Null
        $xml.Package.Dependencies.TargetDeviceFamily.MinVersion = "10.0.19045.2311"
        $xml.Save(".\AppxManifest.xml")

        Clear-Host
        Write-Host "Downloading modifided DLL file..."
        DownloadWinHttpDLL
        DownloadWsaPatchDLL
        DownloadIcuDLL
    }
    else {
    Clear-Host
    Write-Warning "Your Windows Version is lower than 10.0.19045.2311, please upgrade your Windows to be at least 10.0.19045.2311"
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
    }
}

Clear-Host
Write-Host "Installing MagiskOnWSA..."
Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Register .\AppxManifest.xml
If ($?) {
    Finish
}
ElseIf ($null -Ne $Installed) {
    Clear-Host
    Write-Error "Failed to update.`r`nPress any key to uninstall existing installation while preserving user data.`r`nTake in mind that this will remove the Android apps' icon from the start menu.`r`nIf you want to cancel, close this window now."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Remove-AppxPackage -PreserveApplicationData -Package $Installed.PackageFullName
    Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Register .\AppxManifest.xml
    If ($?) {
        Finish
    }
}
Write-Host "All Done!`r`nPress any key to exit"
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
