$FreeCadInstallUri = "https://github.com/FreeCAD/FreeCAD/releases/download/0.19.1/FreeCAD-0.19.1.a88db11-WIN-x64-installer-1.exe"
$FreeCadLocalInstaller = ".\FreeCadInstaller.exe"

$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -UseBasicParsing -Uri $FreeCadInstallUri -OutFile $FreeCadLocalInstaller
$ProgressPreference = 'Continue'

if (-not (Test-Path -Path $FreeCadLocalInstaller) ) {
    throw "Download of FreeCAD installer failed."
}

Unblock-File -Path $FreeCadLocalInstaller

Start-Process -Wait -PassThru -Verb runAs -FilePath $FreeCadLocalInstaller -ArgumentList "/S"
