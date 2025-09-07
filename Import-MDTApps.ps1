#Import Apps
Param(
    [parameter(mandatory = $True, HelpMessage = 'Name of Appfolder')] 
    $ImportFolder = "C:\Media\Apps",

    [parameter(mandatory = $True, HelpMessage = 'Name of MDTfolder')] 
    $MDTFolder = "D:\DeploymentShare"
)

#Load the MDT PS Module
try {
    Import-Module "C:\Program Files\Microsoft Deployment Toolkit\bin\MicrosoftDeploymentToolkit.psd1"
}
catch {
    Write-Error 'The MDT PS module could not be loaded correctly, exit'
    Exit
}

if (!(test-path DS001:)) {
    New-PSDrive -Name "DS001" -PSProvider MDTProvider -Root $MDTFolder
}

Function Import-MDTAppBulk {
    Import-MDTApplication -path "DS001:\Applications" `
        -Enable "True"  `
        -Name $InstallLongAppName  `
        -ShortName $InstallLongAppName  `
        -Version ""  `
        -Publisher ""  `
        -Language ""  `
        -CommandLine $CommandLine  `
        -WorkingDirectory ".\Applications\$InstallLongAppName"  `
        -ApplicationSourcePath $InstallFolder  `
        -DestinationFolder $InstallLongAppName
}

$SearchFolders = Get-ChildItem -Path $ImportFolder
Foreach ($SearchFolder in $SearchFolders) {
    foreach ($InstallFile in Get-ChildItem -Path $SearchFolder.FullName -File) {
        $Install = $InstallFile.Name
        $InstallFolder = $InstallFile.DirectoryName
        $InstallLongAppName = $InstallFolder | Split-Path -Leaf
        $CommandLine = switch ($InstallFile.Extension.ToLower()) {
            '.wsf' { "cscript.exe $Install" }
            '.exe' { "$Install /q" }
            '.msi' { "msiexec.exe /i $Install /qn" }
            '.msu' { "wusa.exe $Install /Quiet /NoRestart" }
            '.ps1' { "PowerShell.exe -ExecutionPolicy ByPass -File $Install" }
            default { continue }
        }
        Write-Verbose "Installer is $Install"
        Write-Verbose "InstallFolder is $InstallFolder"
        Write-Verbose "InstallLongAppName is $InstallLongAppName"
        Write-Verbose "InstallCommand is $CommandLine"
        Write-Verbose ""
        . Import-MDTAppBulk
    }
}