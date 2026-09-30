@echo off
rem Build and package the Android64 test runner as an APK:
rem   build.cmd [Debug|Release]
rem Output: bin\d13\test_runner_android\Android64\<Config>\test_runner_android\bin\
rem Then run-emulator.cmd [-Avd name] [-Config Release] installs and starts it.
setlocal EnableExtensions
set "CONFIG=%~1"
if not defined CONFIG set "CONFIG=Debug"
if /I not "%CONFIG%"=="Debug" if /I not "%CONFIG%"=="Release" (
  echo usage: %~nx0 [Debug^|Release]
  exit /b 2
)
if not exist "%~dp0libfreetype.so" (
  echo libfreetype.so for arm64-v8a is missing in "%~dp0"
  exit /b 2
)
if not defined BDS (
  if exist "%ProgramFiles(x86)%\Embarcadero\Studio\37.0\bin\rsvars.bat" (
    call "%ProgramFiles(x86)%\Embarcadero\Studio\37.0\bin\rsvars.bat"
  ) else (
    echo rsvars.bat of Delphi 13 not found - run from a RAD Studio command prompt
    exit /b 2
  )
)
pushd "%~dp0"
msbuild test_runner_android.dproj /nologo /v:minimal /t:Build /p:Config=%CONFIG%;Platform=Android64
if errorlevel 1 goto failed
msbuild test_runner_android.dproj /nologo /v:minimal /t:Deploy /p:Config=%CONFIG%;Platform=Android64
if errorlevel 1 goto failed
popd
exit /b 0

:failed
popd
echo Android64 build or packaging failed.
exit /b 1
