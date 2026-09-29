param(
  [string]$Avd,
  [string]$SdkRoot,
  [ValidateSet('Debug', 'Release')]
  [string]$Config = 'Debug',
  [int]$TimeoutSeconds = 600,
  # run the suites unattended and fetch the log (Debug only: run-as)
  [switch]$Run
)

$ErrorActionPreference = 'Stop'
try {
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# DCC_ExeOutput of test_runner_android.dproj, then the deployment's own layout
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $projectDir '..\..\..')).Path
$apk = Join-Path $repoRoot "bin\d13\test_runner_android\Android64\$Config\test_runner_android\bin\test_runner_android.apk"
$package = 'org.mormot.pdf.tests'
$activity = 'com.embarcadero.firemonkey.FMXNativeActivity'

if (-not (Test-Path -LiteralPath $apk)) {
  throw "APK not found: $apk. Run build.cmd $Config first, or deploy from the IDE."
}
if ($TimeoutSeconds -lt 1) {
  throw 'TimeoutSeconds must be greater than zero.'
}

$sdkCandidates = @($SdkRoot, $env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
if ($env:LOCALAPPDATA) {
  $sdkCandidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
}
$sdk = $null
foreach ($candidate in $sdkCandidates) {
  if ($candidate -and
      (Test-Path -LiteralPath (Join-Path $candidate 'emulator\emulator.exe')) -and
      (Test-Path -LiteralPath (Join-Path $candidate 'platform-tools\adb.exe'))) {
    $sdk = (Resolve-Path -LiteralPath $candidate).Path
    break
  }
}
if (-not $sdk) {
  throw 'Android SDK with emulator.exe and adb.exe not found. Pass -SdkRoot or set ANDROID_SDK_ROOT.'
}
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  & $adb start-server *> $null
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not start the ADB server.'
  }
} finally {
  $ErrorActionPreference = $savedErrorActionPreference
}

$avds = @(& $emulator -list-avds 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) {
  throw "Could not list Android virtual devices with $emulator."
}
if (-not $avds.Count) {
  throw 'No AVD exists. In Android Studio, open Device Manager and create a virtual device with an ARM64-compatible system image (API 23 or newer).'
}
if (-not $Avd) {
  if ($avds.Count -ne 1) {
    throw "Choose an AVD with -Avd. Available: $($avds -join ', ')"
  }
  $Avd = $avds[0]
}
if ($avds -cnotcontains $Avd) {
  throw "AVD '$Avd' was not found. Available: $($avds -join ', ')"
}

function Get-RunningEmulatorSerial {
  $deviceLines = @(& $adb devices 2>$null)
  foreach ($line in $deviceLines) {
    if ($line -match '^(emulator-\d+)\s+device\b') {
      $serial = $Matches[1]
      $nameLines = @(& $adb -s $serial emu avd name 2>$null)
      if ($LASTEXITCODE -eq 0 -and ($nameLines -ccontains $Avd)) {
        return $serial
      }
    }
  }
  return $null
}

$serial = Get-RunningEmulatorSerial
if (-not $serial) {
  Write-Host "Starting Android Studio AVD: $Avd"
  $emulatorProcess = Start-Process -FilePath $emulator -ArgumentList ('-avd "{0}"' -f $Avd) -WorkingDirectory (Split-Path $emulator) -PassThru
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
  if (-not $serial) {
    $serial = Get-RunningEmulatorSerial
  }
  if ($serial) {
    $bootCompleted = (& $adb -s $serial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $bootCompleted -eq '1') {
      break
    }
  }
  if ($emulatorProcess -and $emulatorProcess.HasExited) {
    throw "The Android emulator exited with code $($emulatorProcess.ExitCode)."
  }
  Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)

if (-not $serial -or $bootCompleted -ne '1') {
  throw "AVD '$Avd' did not finish booting within $TimeoutSeconds seconds."
}

$guestAbis = (& $adb -s $serial shell getprop ro.product.cpu.abilist 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or ($guestAbis -split ',') -notcontains 'arm64-v8a') {
  throw "AVD '$Avd' reports ABIs '$guestAbis'. This APK needs arm64-v8a. Select a compatible system image in Android Studio Device Manager."
}

Write-Host "Installing APK on $serial ($Avd)..."
& $adb -s $serial install -r $apk
if ($LASTEXITCODE -ne 0) {
  throw 'APK installation failed.'
}
if (-not $Run) {
  & $adb -s $serial shell am start -n "$package/$activity"
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not start the test runner.'
  }
  Write-Host 'App started. Tap "Run tests" in the emulator to begin.'
  exit 0
}

# -Run: start the suites unattended, wait for the log's RESULT line, keep a
# copy under logs\ and pass the verdict on as the exit code
$remoteLog = 'files/test_runner_android.log' # TPath.GetDocumentsPath
& $adb -s $serial shell am force-stop $package
# the app deletes it too, but only once started: the first poll could come
# earlier and read the previous run's result
& $adb -s $serial shell run-as $package rm -f $remoteLog
& $adb -s $serial shell am start -n "$package/$activity" --ez autorun true
if ($LASTEXITCODE -ne 0) {
  throw 'Could not start the test runner.'
}
Write-Host 'Tests started, waiting for the result...'
$log = ''
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
  Start-Sleep -Seconds 2
  # run-as needs a debuggable APK, i.e. the Debug configuration
  $log = (& $adb -s $serial exec-out run-as $package cat $remoteLog 2>$null | Out-String)
  if ($log -match '(?m)^RESULT: ') {
    break
  }
  $alive = (& $adb -s $serial shell pidof $package 2>$null | Out-String).Trim()
  if (-not $alive) {
    throw 'The test runner exited before writing its result - see adb logcat -s pdf-tests'
  }
} while ((Get-Date) -lt $deadline)
if ($log -notmatch '(?m)^RESULT: ') {
  throw "No result within $TimeoutSeconds seconds."
}
$logDir = Join-Path $projectDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$localLog = Join-Path $logDir ('test_runner_android-{0}-{1}.log' -f $Config, (Get-Date -Format 'yyyyMMdd-HHmmss'))
[IO.File]::WriteAllText($localLog, $log)
Write-Host "Log: $localLog"
$failures = @($log -split "`r?`n" | Where-Object { $_ -match '^(- .+: |! )' -and $_ -notmatch '^! (All|Some) tests' })
if ($failures.Count) {
  Write-Host 'Failures:'
  $failures | ForEach-Object { Write-Host "  $_" }
}
$result = ($log -split "`r?`n" | Where-Object { $_ -match '^RESULT: ' } | Select-Object -Last 1)
Write-Host $result
if ($result -match '^RESULT: true') { exit 0 } else { exit 1 }
} catch {
  [Console]::Error.WriteLine('ERROR: ' + $_.Exception.Message)
  exit 2
}
