# mdt + wds

> Вся инфра Майков строиться вокруг AD. Обьекты наполняют ее.

- AutoMDTDeployment.ps1 from https://github.com/Tenaka/
- Import-MDTApps.ps1 from https://github.com/DeploymentBunny/

## Usage

1. Prepare the server by placing required installation media under `C:\Media` as described in the script comments.
2. Run `AutoMDTDeployment.ps1` from an elevated PowerShell prompt. Network settings can be supplied as parameters, for example:

   ```powershell
   .\AutoMDTDeployment.ps1 -IPAddress 192.0.2.5 -DefGate 192.0.2.1 -dnsServer 192.0.2.53
   ```

3. Import applications after deployment with:

   ```powershell
   .\Import-MDTApps.ps1 -ImportFolder C:\Media\Apps -MDTFolder D:\DeploymentShare
   ```

AutoMDTDeployment.ps1 when finished will:

- Install DHCP and WDS
- Install WDS
- Configure DHCP
- Install ADK, ADKPE and MDT
- Deploy MDT Share with correct permissions and Service account
- Create Boot media and a generic Windows 10 Task Sequence

