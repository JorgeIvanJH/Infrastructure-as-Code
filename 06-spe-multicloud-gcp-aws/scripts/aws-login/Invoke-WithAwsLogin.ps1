[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$CommandArguments,

    [string]$AwsProfile = "default"
)

$pythonExecutable = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonExecutable) {
    throw "Python was not found. Open a new PowerShell window after installing it."
}

$commandExecutable = (Get-Command $Command -ErrorAction SilentlyContinue).Source
if (-not $commandExecutable -and $Command -eq "aws") {
    $allUsersAws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    if (Test-Path -LiteralPath $allUsersAws) {
        $commandExecutable = $allUsersAws
    }
}
if (-not $commandExecutable) {
    throw "Command '$Command' was not found. Open a new PowerShell window after installing it."
}

$serverScript = Join-Path $PSScriptRoot "aws-login-credential-server.py"
$authorizationToken = [Guid]::NewGuid().ToString("N")

$portFinder = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Loopback,
    0
)
$portFinder.Start()
$credentialPort = $portFinder.LocalEndpoint.Port
$portFinder.Stop()

$serverArguments = @(
    ('"{0}"' -f $serverScript)
    "--port"
    $credentialPort
    "--profile"
    ('"{0}"' -f $AwsProfile)
    "--token"
    $authorizationToken
) -join " "

$environmentNames = @(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_SESSION_TOKEN"
    "AWS_CONTAINER_CREDENTIALS_FULL_URI"
    "AWS_CONTAINER_AUTHORIZATION_TOKEN"
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable(
        $name,
        "Process"
    )
    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
}

$credentialServer = Start-Process `
    -FilePath $pythonExecutable `
    -ArgumentList $serverArguments `
    -PassThru `
    -WindowStyle Hidden

try {
    Start-Sleep -Milliseconds 750
    if ($credentialServer.HasExited) {
        throw "The local AWS credential bridge could not start."
    }

    $env:AWS_CONTAINER_CREDENTIALS_FULL_URI = (
        "http://127.0.0.1:{0}/credentials" -f $credentialPort
    )
    $env:AWS_CONTAINER_AUTHORIZATION_TOKEN = $authorizationToken

    Write-Host "Using refreshable AWS CLI login credentials from localhost."
    & $commandExecutable @CommandArguments
    $commandExitCode = $LASTEXITCODE

    if ($commandExitCode -ne 0) {
        throw "'$Command' finished with exit code $commandExitCode."
    }
}
finally {
    if ($credentialServer -and -not $credentialServer.HasExited) {
        Stop-Process -Id $credentialServer.Id -Force
        $credentialServer.WaitForExit()
    }

    foreach ($name in $environmentNames) {
        $previousValue = $previousEnvironment[$name]
        if ($null -eq $previousValue) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable(
                $name,
                $previousValue,
                "Process"
            )
        }
    }
}
