param(
    [Parameter(Mandatory = $true)]
    [string] $Version
)

$innoSetupDir = "C:\Program Files (x86)\Inno Setup 6"

# Inno Setup should already be installed by the CI workflow
if (!(Test-Path "$innoSetupDir\ISCC.exe")) {
    Write-Error "Inno Setup not found at $innoSetupDir. Please ensure it's installed."
    exit 1
}

Remove-Item "D:\inno" -Force  -Recurse -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "D:\inno"

# unzip signed zip file
Expand-Archive -Path "build\windows\app.zip" -DestinationPath "D:\inno"

Remove-Item "D:\inno-result" -Force  -Recurse -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "D:\inno-result"

# Chinese language files are vendored in repo and referenced by the .iss.
& "$innoSetupDir\ISCC.exe" `
  "/DMyAppVersion=""$Version""" `
  "/DStagingDir=""D:\inno""" `
  "/DInstallerOutputDir=""D:\inno-result""" `
  ".\scripts\compile_windows_setup-inno.iss"

Copy-Item "D:\inno-result\app.exe" "build\windows\unsigned\app.exe"

Write-Output 'Generated Windows exe installer!'

