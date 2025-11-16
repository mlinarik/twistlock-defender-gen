<#
Interactive installer for Prisma Cloud Defender on Windows (PowerShell)
Uses Docker (Docker Desktop / Docker Engine) to run a single-container Defender.
#>
param()

function Confirm-YN([string]$Prompt, [string]$Default='Y'){
    $defaultPrompt = if ($Default -match '^[Yy]') { 'Y' } else { 'N' }
    $resp = Read-Host "$Prompt [$defaultPrompt]"
    if ([string]::IsNullOrWhiteSpace($resp)) { $resp = $Default }
    return $resp.Trim().ToLower() -in @('y','yes')
}

Write-Host '----------------------------------------'
Write-Host 'Prisma Cloud Defender - Interactive Installer (PowerShell)'
Write-Host '----------------------------------------'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'docker not found in PATH. Install Docker Desktop or Docker Engine and re-run.'
    exit 1
}

$image = Read-Host 'Defender container image URI (example: registry.prismacloud.io/defender:latest)'
if ([string]::IsNullOrWhiteSpace($image)) { Write-Error 'Image URI is required.'; exit 1 }

$name = Read-Host 'Container name [tw-defender]'
if ([string]::IsNullOrWhiteSpace($name)) { $name = 'tw-defender' }

$token = Read-Host 'Prisma access / registration token (leave empty to set later)'

if (Confirm-YN 'Do you need to login to a private registry? (y/n)' 'n') {
    $regUser = Read-Host 'Registry username'
    $regPass = Read-Host 'Registry password'
    $sec = ConvertTo-SecureString $regPass -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ($regUser, $sec)
    docker login --username $regUser --password-stdin <<< $regPass | Out-Null
}

$opts = @()
if (Confirm-YN 'Run container with --privileged? (y/n)' 'y') { $opts += '--privileged' }
if (Confirm-YN 'Use host networking (--network host)? (y/n)' 'y') { $opts += '--network host' }

$vols = @()
while (Confirm-YN 'Add a bind mount (host path -> container path)?' 'n') {
    $hp = Read-Host 'Host path'
    $cp = Read-Host 'Container path'
    $vols += "-v $hp`: $cp"
}

$envs = @()
if (-not [string]::IsNullOrWhiteSpace($token)) { $envs += "-e DEFENDER_TOKEN=$token" }
while (Confirm-YN 'Add another environment variable (KEY=VALUE)?' 'n') {
    $kv = Read-Host 'Env (KEY=VALUE)'
    $envs += "-e $kv"
}

$restart = Read-Host 'Restart policy (default: unless-stopped)'
if ([string]::IsNullOrWhiteSpace($restart)) { $restart = 'unless-stopped' }

$cmd = @('docker','run','-d','--name',$name,'--restart',$restart) + $opts + $vols + $envs + @($image)

Write-Host "`n--- Generated docker run command ---"
Write-Host ($cmd -join ' ')

if (Confirm-YN 'Execute the above command now?' 'y') {
    try {
        & docker run -d --name $name --restart $restart @($opts) @($vols) @($envs) $image
        Write-Host 'Container started.'
    } catch {
        Write-Error "docker run failed: $_"
        exit 1
    }
} else {
    Write-Host 'Skipping execution. Run the printed command manually.'
}

Write-Host 'Done. If Defender requires additional registration steps, complete them in the Prisma Cloud UI.'
