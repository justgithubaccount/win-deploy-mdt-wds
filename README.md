# mdt + wds

> Вся инфра Майков строиться вокруг AD. Обьекты наполняют ее.

- AutoMDTDeployment.ps1 from https://github.com/Tenaka/
- Import-MDTApps.ps1 from https://github.com/DeploymentBunny/

AutoMDTDeployment.ps1 when finished will:

- Install DHCP and WDS
- Install WDS
- Configure DHCP  
- Install ADK, ADKPE and MDT
- Deploy MDT Share with correct permissions and Service account
- Create Boot media and a generic Windows 10 Task Sequence