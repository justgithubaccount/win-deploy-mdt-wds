
<#
.Synopsis

Automate the installation and configuration of MDT, ADK, DHCP and WDS to allow PXE and deployment of OEM Windows 10.

For support visit https://www.tenaka.net/mdt-scripted-install

.DESCRIPTION

Server Spec:
VM or Physical Server
    C:\ 60Gb min
    D:\ 60Gb 
    2048Mb RAM, 4096 is prefered
    2 * Cores

Windows Server 2019

Media Required copying to the the following locations:
    ADK                              saved to C:\Media\ADK
    ADKPE                            saved to C:\Media\ADKPE
    MDTx64                           saved to C:\Media\MDT
    Windows 10 iso                   saved to c:\Media\Win10
    SXS from Server Install media    saved to C:\Media\sxs 

ADK and ADK PE
https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install

MDT 
https://www.microsoft.com/en-us/download/details.aspx?id=54259

There are limitations with drivers in its current configuration, if Windows 10 doesn't naively support
the network adapter and mass storage devices, the deployment will fail. Follow MDT part 6 to resolve any driver issues.


.VERSION
210716.01 - created 


#>

param(
    [Parameter()]
    [string]$IPAddress = "192.0.2.5",

    [Parameter()]
    [string]$DefGate = "192.0.2.1",

    [Parameter()]
    [string]$dnsServer = "192.0.2.53",

    [Parameter()]
    [string]$scopeName = "MDT Client Deployment Scope",

    [Parameter()]
    [string]$DHCPStart = "192.0.2.230",

    [Parameter()]
    [string]$DHCPEnd = "192.0.2.240",

    [Parameter()]
    [string]$DHCPSub = "255.255.255.0",

    [Parameter()]
    [string]$dnsName = "corp.example.com"
)

if (-not([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{ Write-Host "An elevated administrator account is required to run this script." -ForegroundColor Red }

else {
    # Confirm that software is present and saved to the correct paths
    $swADK = "C:\Media\ADK\adksetup.exe"
    $swPE = "C:\Media\ADKPE\adkwinpesetup.exe"
    $swMDT = "C:\Media\MDT\MicrosoftDeploymentToolkit_x64.msi"
    $swSXS = "C:\Media\sxs"
    $swWin10 = "C:\Media\Win10"

    # Language settings (Administrators/Администраторы)

    $lngAdmin = "Administrators"

    $swPaths = $swADK, $swPE, $swMDT, $swSXS, $swWin10 

    Write-Host "" -ForegroundColor Green

    foreach ($software in $swPaths) {
        $tpSoft = Test-Path $software
        if ($tpSoft -eq $true)
        { Write-Host "$software is present" -ForegroundColor Green }
        else {
            Write-Host "$software is missing" -ForegroundColor Red
            Read-Host -Prompt "Required software missing. Press Enter to exit"
            exit 1
        }
    }
    #Hostname
    $hostn = Hostname

    #get the current network information
    $gNetAdp = Get-NetAdapter | Where-Object { $_.Status -eq "up" }
    $intAlias = $gNetAdp.InterfaceAlias

    $gNetIPC = Get-NetIPConfiguration -InterfaceAlias $gNetAdp.Name
    

    $gNetIPC | Remove-NetIPAddress -Confirm:$false
    $gNetIPC.IPv4DefaultGateway | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    #Set Static IP
    Write-Host "Setting static IP" -ForegroundColor Green
    New-NetIPAddress -InterfaceAlias $gNetAdp.Name `
        -IPAddress $IPAddress `
        -AddressFamily IPv4 `
        -PrefixLength 24 `
        -DefaultGateway $DefGate
    #Set DNS Server                 
    Set-DnsClientServerAddress -ServerAddresses $dnsServer -InterfaceAlias $intAlias

    ############################################################################################
    ##########################  INSTALL WINDOWS FEATURES, MDT AND ADK  #########################
    ############################################################################################

    #Install DHCP and WDS Features
    Write-Host "Installing Windows Features WDS and DHCP" -ForegroundColor Green
    Install-WindowsFeature -Name DHCP, RSAT-DHCP, WDS, WDS-AdminPack

    #Install .Net Framework - required for SQL Databased
    Write-Host "Installing .Net for SQL if required later" -ForegroundColor Green
    Install-WindowsFeature -Name NET-Framework-Core -Source C:\media\sxs

    #Identify data drive and select the first listed
    $psDataDrv = Get-PSDrive | Where-Object { $_.Provider -like "*File*" -and $_.name -ne "C" -and $_.Free -ne "0" -and $_.Free -ne $null }[0]

    #Set Data Drive Letter as variable
    $drv = ($psDataDrv).Name + ":"
    $tpDrv = Test-Path $drv

    #Set installation path for ADK and MDT
    if ($tpDrv -eq $true)
    { $installPath = "$drv" + "\Program Files\Windows Kits" }
    else 
    { $installPath = "C:\Program Files\Windows Kits" }

    #Install ADK
    Write-Host "Installing ADK" -ForegroundColor Green
    cmd.exe /c C:\Media\ADK\adksetup.exe /Quiet /InstallPath $installPath /Features OptionId.DeploymentTools OptionID.UserStateMigrationTool OptionId.ImagingAndConfigurationDesigner OptionId.ICDConfigurationDesigner
    
    #Install ADK PE
    Write-Host "Installing ADK PE" -ForegroundColor Green
    cmd.exe /c C:\Media\ADKPE\adkwinpesetup.exe /features + /q 

    #Install MDT
    Write-Host "Installing MDT" -ForegroundColor Green
    cmd.exe /c msiexec.exe /i C:\Media\MDT\MicrosoftDeploymentToolkit_x64.msi /l C:\Media\MDT_Setup.log /q

    ############################################################################################
    #################################  DEPLOY DHCP SERVER  #####################################
    ############################################################################################

    #Creates DHCP Scope
    Write-Host "Adding DHCP Scope and Options" -ForegroundColor Green
    Add-DhcpServerv4Scope -ComputerName $hostn `
        -Name $scopeName `
        -StartRange $DHCPStart `
        -EndRange $DHCPEnd `
        -SubnetMask $DHCPSub `
        -Description "MDT Client Deployment Scope" `
        -State Active 

    $scopeID = Get-DhcpServerv4Scope -ComputerName $hostn | Where-Object { $_.name -eq $scopeName } | Select-Object Scopeid

    #Adds Scope options 
    Set-DhcpServerv4OptionValue -ComputerName $hostn -OptionId 001 -Value 0x2 -ScopeId $scopeID.ScopeId -Force
    Set-DhcpServerv4OptionValue -ComputerName $hostn -OptionId 003 -value $DefGate -ScopeId $scopeID.ScopeId
    Set-DhcpServerv4OptionValue -ComputerName $hostn -OptionId 006 -value $dnsServer -ScopeId $scopeID.ScopeId -Force
    Set-DhcpServerv4OptionValue -ComputerName $hostn -OptionId 015 -value $dnsName -ScopeId $scopeID.ScopeId -Force
    Set-DhcpServerv4Optionvalue -ComputerName $hostn -OptionId 066 -Value $IPAddress -ScopeId $scopeID.ScopeId
    Set-DhcpServerv4Optionvalue -ComputerName $hostn -OptionId 067 -Value "boot\x64\bootmgfw.efi" -ScopeId $scopeID.ScopeId

    ############################################################################################
    ######################  CREATE MDT SERVICE ACCOUNT AND SET UP SHARES  ######################
    ############################################################################################

    #Generate Random Password for MDTUser Service Account
    Write-Host "Creates MDT User with complex password" -ForegroundColor Green
    $mdtUser = "MDTUser"
    $pwl = 14
    $sysWeb = Add-Type -AssemblyName system.web
    #ranPass is the clear text password - used in customsettings and bootstrat
    $randPass = [System.Web.Security.Membership]::GeneratePassword($pwl, 3)

    $svcPass = ConvertTo-SecureString $randPass -AsPlainText -Force 

    New-LocalUser    -Name $mdtUser `
        -Description "MDT Service Account" `
        -FullName $mdtUser `
        -Password $svcPass `
        -AccountNeverExpires `
        -PasswordNeverExpires

    #Paths and Shares
    Write-Host "Creates MDT Shares" -ForegroundColor Green
    if ($drv -eq ":") { $drv = "c:" }
    $mdtRoot = "$drv" + "\DeploymentShare"
    $mdtLogs = "$mdtRoot\Logs"
    $mdtCap = "$mdtRoot\Captures"
    $mdtDes = "MDT Deployment Share"

    $mdtShRoot = "DeploymentShare$"
    $mdtShLogs = "Logs$"
    $mdtShCap = "Captures$"

    $mdtShRtDes = "MDT Deployment Share"

    #MDT Root grants Svc Read access
    New-Item -Path $mdtRoot -ItemType directory 
    New-SmbShare -ReadAccess $mdtuser -Path $mdtRoot -Name $mdtShRoot -Description $mdtShRtDes

    #MDT Root requires Admin modify access to create\update unattend.xml
    Grant-FileShareAccess -Name $mdtShRoot -AccountName $lngAdmin -AccessRight Modify

    #Add MDT Module and create new MDT Root
    Add-PSSnapin Microsoft.BDD.PSSnapin
    New-PSDrive -Name 'DS001' `
        -PSProvider "MDTProvider" `
        -Root $mdtRoot `
        -Description 'MDT Deployment Share' `
        -Networkpath "\\$hostn\$mdtShRoot" | Add-MDTPersistentDrive

    #Logging Share grants svc Modify access
    New-Item -Path $mdtLogs -ItemType directory 
    New-SmbShare -Path $mdtLogs -Name $mdtShLogs -Description "Logs Share" -ChangeAccess $mdtUser

    #Capture share grants svc Modify access to upload deployed captures
    New-SmbShare -Path $mdtCap -Name $mdtShCap -Description "Capture Share" -ChangeAccess $mdtUser

    Write-Host "Sets MDT Share NTFS Permissions" -ForegroundColor Green
    #Inheritence 
    $inherNone = [System.Security.AccessControl.InheritanceFlags]::None
    $propNone = [System.Security.AccessControl.PropagationFlags]::None
    $inherCnIn = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
    $propInOn = [System.Security.AccessControl.PropagationFlags]::InheritOnly
    $inherObIn = [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propNoPr = [System.Security.AccessControl.PropagationFlags]::NoPropagateInherit

    #Sets MDTUser permission over MDTRoot
    $aclMdtRoot = Get-Acl $MdtRoot
    $arMdtRoot = New-Object System.Security.AccessControl.FileSystemAccessRule("$mdtUser", "READ", "$inherCnIn,$inherObIn", "None", "Allow")
    $aclMdtRoot.SetAccessRule($arMdtRoot)
    Set-Acl $MdtRoot $aclMdtRoot

    #Creates Root\Logs
    New-Item -Path $mdtLogs -ItemType Directory -Force

    #Removes Inherit
    $aclmdtLogs = get-acl $mdtLogs
    $aclmdtLogs.SetAccessRuleProtection($true, $true)
    Set-Acl $mdtLogs $aclmdtLogs

    #MDTUser gets modify permissons 
    $aclMDTLogs = Get-Acl $mdtLogs
    $arMDTLogs = New-Object System.Security.AccessControl.FileSystemAccessRule("$mdtUser", "MODIFY", "$inherCnIn,$inherObIn", "None", "Allow")
    $aclMDTLogs.SetAccessRule($arMDTLogs)
    Set-Acl $mdtLogs $aclMDTLogs

    #Removes Inherit
    $aclmdtCap = get-acl $mdtCap
    $aclmdtCap.SetAccessRuleProtection($true, $true)
    Set-Acl $mdtCap $aclmdtCap

    #Sets Modify permission over Captures Folder
    $aclmdtCap = Get-Acl $mdtCap
    $armdtCap = New-Object System.Security.AccessControl.FileSystemAccessRule("$mdtUser", "MODIFY", "$inherCnIn,$inherObIn", "None", "Allow")
    $aclmdtCap.SetAccessRule($armdtCap)
    Set-Acl $mdtCap $aclmdtCap

    ############################################################################################
    ################################  CONFIG MDT SETTINGS  #####################################
    ############################################################################################
    
    #Import MDT Powershell Module
    Import-Module "C:\Program Files\Microsoft Deployment Toolkit\Bin\MicrosoftDeploymentToolkit.psd1"

    #Enable MDT Monitoring
    Enable-MDTMonitorService -EventPort 9800 -DataPort 9801 

    #Win10-Drivers Profiles created
    Write-Host "Creates Win10-Drivers Selection Profile" -ForegroundColor Green
    New-PSDrive -Name "DS002" -PSProvider MDTProvider -Root $mdtRoot
    New-Item -path "DS002:\Selection Profiles" -enable "True" -Name "Win10-Drivers" -Comments "Only add Network and Storage drivers to this profile" -Definition "<SelectionProfile />" -ReadOnly "False" -Verbose

    ############################################################################################
    ############################  IMPORT WINDOWS 10 MEDIA  #####################################
    ############################################################################################

    #Mount Windows ISO
    Write-Host "Mounts Windows 10 ISO" -ForegroundColor Green
    Mount-DiskImage -ImagePath (Get-ChildItem C:\Media\Win10 -Filter *.iso).FullName

    $psISO = (Get-PSDrive | Where-Object { $_.Free -eq "0" }).Name[0]

    #New Folder for Windows 10 Images

    #New-PSDrive -Name "DS001" -PSProvider MDTProvider -Root "$mdtRoot"
    New-Item -path "DS002:\Operating Systems" -enable "True" -Name "Windows 10" -Comments "" -ItemType "folder" -Verbose

    Write-Host "Imports Windows 10 Media into MDT" -ForegroundColor Green
    #Import Windows 10 into MDT
    Import-MDTOperatingSystem -path "DS002:\Operating Systems\Windows 10" -SourceFile "$psISO`:\sources\install.wim" -DestinationFolder "Windows 10" -Verbose

    #New Folder for Gold Image Task Sequences
    New-Item -path "DS002:\Task Sequences" -enable "True" -Name "Windows 10 Default Image" -Comments "" -ItemType "folder" -Verbose

    #List avaiable Windows 10 versions in wim file - Select Pro or Enterprise 
    $gcOSImage = (Get-Content "$mdtRoot\Control\OperatingSystems.xml" -Delimiter / | Select-String "<ImageName>") -replace ("</", "") -replace ("ImageIndex><ImageName>", "")

    $tsID = "Win10-Default-001"

    Write-Host "Creates Task Sequence" -ForegroundColor Green
    if ($gcOSImage -match "Windows 10 Enterprise" ) { 
        #New Task Sequence for Windows 10 Enterprise
        Import-MDTTaskSequence -path "DS002:\Task Sequences\Windows 10 Default Image" -Name "Windows 10 Enterprise Default Image" -Template "Client.xml" -Comments "" -ID $tsID -Version "1.0" -OperatingSystemPath "DS002:\Operating Systems\Windows 10\Windows 10 Enterprise in Windows 10 install.wim" -FullName "Windows User" -OrgName "Contoso" -HomePage "about:blank" -Verbose
    }
    else { 
        #New Task Sequence for Windows 10 Pro
        Import-MDTTaskSequence -path "DS002:\Task Sequences\Windows 10 Default Image" -Name "Windows 10 Pro Default Image" -Template "Client.xml" -Comments "" -ID $tsID -Version "1.0" -OperatingSystemPath "DS002:\Operating Systems\Windows 10\Windows 10 Pro in Windows 10 install.wim" -FullName "Windows User" -OrgName "Contoso" -HomePage "about:blank" -Verbose
    }

    ############################################################################################
    #########################  SET CUSTOMSETTINGS AND BOOTSTRAP  ###############################
    ############################################################################################

    #Set custom settings
    Write-Host "Update CustomSettings.ini to drive deployment wizard at boot" -ForegroundColor Green 
    $cuSet = "$mdtRoot\Control\CustomSettings.ini"

    Set-Content -Path $cuSet -Value "[Settings]"
    Add-Content -Path $cuSet -Value "Priority=DefaultGateway,Default"
    Add-Content -Path $cuSet -Value "Properties=MyCustomProperty"
    Add-Content -Path $cuSet -Value "[DefaultGateway]"
    Add-Content -Path $cuSet -Value "$DefGate=MSK"
    Add-Content -Path $cuSet -Value " "
    Add-Content -Path $cuSet -Value "[MSK]"
    Add-Content -Path $cuSet -Value "TimeZoneName=Moscow Standard Time"
    Add-Content -Path $cuSet -Value "UILanguage=ru-RU"
    Add-Content -Path $cuSet -Value "UserLocale=ru-RU"
    Add-Content -Path $cuSet -Value "SystemLocale=ru-RU"
    Add-Content -Path $cuSet -Value "KeyboardLocale=ru-RU;en-US"
    Add-Content -Path $cuSet -Value "KeyboardLocalePE=ru-RU;en-US"
    Add-Content -Path $cuSet -Value " "
    Add-Content -Path $cuSet -Value "[Default]"
    Add-Content -Path $cuSet -Value "_SMSTSOrgName=RS: %TaskSequenceID%"
    Add-Content -Path $cuSet -Value " " 
    Add-Content -Path $cuSet -Value "'// Setting up page skipping (Wizard Pages)"
    Add-Content -Path $cuSet -Value "SkipWizard=NO"
    Add-Content -Path $cuSet -Value "SkipAppsOnUpgrade=YES"
    Add-Content -Path $cuSet -Value "SkipDeploymentType=YES"
    Add-Content -Path $cuSet -Value "SkipCapture=NO"
    Add-Content -Path $cuSet -Value "SkipComputerName=NO"
    Add-Content -Path $cuSet -Value "SkipDomainMembership=YES"
    Add-Content -Path $cuSet -Value "SkipUserData=YES"
    Add-Content -Path $cuSet -Value "SkipComputerBackup=YES"
    Add-Content -Path $cuSet -Value "SkipTaskSequence=NO"
    Add-Content -Path $cuSet -Value "SkipProductKey=YES"
    Add-Content -Path $cuSet -Value "SkipPackageDisplay=YES"
    Add-Content -Path $cuSet -Value "SkipLocaleSelection=YES"
    Add-Content -Path $cuSet -Value "SkipTimeZone=YES"
    Add-Content -Path $cuSet -Value "SkipApplications=YES"
    Add-Content -Path $cuSet -Value "SkipAdminPassword=YES"
    Add-Content -Path $cuSet -Value "SkipBitLocker=YES"
    Add-Content -Path $cuSet -Value "SkipSummary=YES"
    Add-Content -Path $cuSet -Value "SkipFinalSummary=YES"
    Add-Content -Path $cuSet -Value "SkipCredentials=YES"
    Add-Content -Path $cuSet -Value "SkipRoles=YES"
    Add-Content -Path $cuSet -Value " "
    Add-Content -Path $cuSet -Value "'// Build Settings - MDT Image Engineering"
    Add-Content -Path $cuSet -Value "OSInstall=Y"
    Add-Content -Path $cuSet -Value "SLShare=\\$IPAddress\Logs$"
    Add-Content -Path $cuSet -Value "DeploymentType=NEWCOMPUTER"
    Add-Content -Path $cuSet -Value "'//JoinWorkgroup=WORKGroup"
    Add-Content -Path $cuSet -Value 'BackupFile = %TaskSequenceID%-#day(date)&"-"&month(date)&"-"&year(date)#.wim'
    Add-Content -Path $cuSet -Value "ComputerBackupLocation=\\$IPAddress\Captures$"
    Add-Content -Path $cuSet -Value "DoCapture=NO"
    Add-Content -Path $cuSet -Value "HideShell=NO"
    Add-Content -Path $cuSet -Value "TaskSequenceID=$tsID"
    Add-Content -Path $cuSet -Value "FinishAction=REBOOT"
    Add-Content -Path $cuSet -Value " "
    Add-Content -Path $cuSet -Value "OrgName=RS"
    Add-Content -Path $cuSet -Value "AdminPassword=PASSWORD"
    <#
    Add-Content -Path $cuSet -Value "AreaCode=020"
    Add-Content -Path $cuSet -Value "CountryCode=7"
    Add-Content -Path $cuSet -Value "Dialing=TONE"
    Add-Content -Path $cuSet -Value "LongDistanceAccess=1"
    Add-Content -Path $cuSet -Value "BitsPerPel=32"
    Add-Content -Path $cuSet -Value "VRefresh=60"
    Add-Content -Path $cuSet -Value "XResolution=1"
    Add-Content -Path $cuSet -Value "YResolution=1"
    #>
    Add-Content -Path $cuSet -Value " "
    Add-Content -Path $cuSet -Value "'//Capture Credentials"
    Add-Content -Path $cuSet -Value "'//UserID=Domain\$mdtUser"
    Add-Content -Path $cuSet -Value " "
    Add-Content -Path $cuSet -Value "UserID=$mdtUser"
    Add-Content -Path $cuSet -Value "UserPassword=$randPass"
    Add-Content -Path $cuSet -Value " " 
    Add-Content -Path $cuSet -Value "'//MDT Monitoring and Update Server"
    Add-Content -Path $cuSet -Value "EventService=http://$IPAddress:9800"
    Add-Content -Path $cuSet -Value "'//WSUSServer=http://192.0.2.3:8530"
    Add-Content -Path $cuSet -Value " "

    #Update BootStrap.ini
    $bootStrap = "$mdtRoot\Control\Bootstrap.ini"

    Set-Content -Path $bootStrap -Value "[Settings]"
    Add-Content -Path $bootStrap -Value "Priority=Default"
    Add-Content -Path $bootStrap -Value " "
    Add-Content -Path $bootStrap -Value "[Default]"
    Add-Content -Path $bootStrap -Value "SkipBDDWelcome=YES"
    Add-Content -Path $bootStrap -Value "DeployRoot=\\$IPAddress\$mdtShRoot"
    Add-Content -Path $bootStrap -Value "UserDomain=."
    Add-Content -Path $bootStrap -Value "UserID=$mdtUser"
    Add-Content -Path $bootStrap -Value "UserPassword=$randPass"

    ############################################################################################
    ############################  SET BOOT MEDIA SETTINGS ######################################
    ############################################################################################

    function Update-SettingsXml {
        param([string]$Path, [string]$HostName)
        $content = Get-Content $Path
        $content = $content.Replace('Boot.x64.ScratchSpace>32</Boot.x64.ScratchSpace', 'Boot.x64.ScratchSpace>512</Boot.x64.ScratchSpace')
        $content = $content.Replace('Boot.x64.GenerateGenericWIM>False</Boot.x64.GenerateGenericWIM', 'Boot.x64.GenerateGenericWIM>True</Boot.x64.GenerateGenericWIM')
        $content = $content.Replace('Boot.x64.SelectionProfile>All Drivers and Packages</Boot.x64.SelectionProfile', 'Boot.x64.SelectionProfile>Win10-Drivers</Boot.x64.SelectionProfile')
        $content = $content.Replace('<MonitorHost>', "`<MonitorHost>$HostName")
        $content | Set-Content $Path -Force
    }

    Write-Host "Update the configuraton settings in the workbench" -ForegroundColor Green
    $mdtSetSrc = "C:\Program Files\Microsoft Deployment Toolkit\Templates\"
    Copy-Item $mdtSetSrc\Settings.xml $mdtSetSrc\Settings-backup.xml -Force
    Copy-Item $mdtRoot\Control\Settings.xml $mdtRoot\Control\Settings-backup.xml -Force
    Update-SettingsXml -Path "$mdtSetSrc\Settings.xml" -HostName $hostn
    Update-SettingsXml -Path "$mdtRoot\Control\Settings.xml" -HostName $hostn

    ############################################################################################
    ########################  CREATE BOOT MEDIA, IMPORT AND INIT WDS  ##########################
    ############################################################################################
    Write-Host "Generate boot image and initialize WDS" -ForegroundColor Green
    Write-Host "This step takes a while to complete - Coffee time" -ForegroundColor Green
    #Generate boot media
    #New-PSDrive -Name "DS001" -PSProvider MDTProvider -Root "$mdtRoot"
    Update-MDTDeploymentShare -path "DS002:" -Force -Verbose

    #init WDS
    Start-Sleep 5
    $remDir = $mdtRoot.Split(":")[0]
    $wdsDrv = "$remDir`:\RemoteInstall"
    cmd.exe /c wdsutil.exe /Initialize-Server /Server:$hostn /reminst:$wdsDrv /standalone

    Start-Sleep 5
    Start-Service WDSServer

    #Import WDS Boot image generated by MDT
    Write-Host "Imports the MDT generated boot image into WDS" -ForegroundColor Green
    Import-WdsBootImage -NewImageName "Lite Touch Windows PE (x64)" -NewFileName "LiteTouchPE_x64.wim" -Path $mdtRoot\boot\LiteTouchPE_x64.wim 

    Write-Host "" -ForegroundColor Green
    Write-Host "Add addtional drivers and add to a selection profile, update Boot media and add to Task Sequence - if there is not native support for Windows 10" -ForegroundColor Red
    Write-Host "" -ForegroundColor Green
    Write-Host "" -ForegroundColor Green
    Write-Host "FINISHED" -ForegroundColor Green


    ############################################################################################
    ######################################  THE END  ###########################################
    ############################################################################################
}