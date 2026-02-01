#!/bin/bash
#
# Copyright (c) 2024 Huang Qinjin
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

. "${0%/*}/test.sh"

host=x64
if [ "$(uname -m)" = "aarch64" ]; then
    host=arm64
fi

BASE=$(. "${BIN}msvcenv.sh" && echo $BASE)
ARCH=$(. "${BIN}msvcenv.sh" && echo $ARCH)

if [ "$host" = "$ARCH" ]; then
    vcvars_arch=${ARCH}
else
    vcvars_arch=${host}_${ARCH}
fi

cat >test-$vcvars_arch.bat <<EOF
@echo off

set "CWD=%CD%"

set VSCMD_START_DIR=
call $BASE\VC\Auxiliary\Build\vcvarsall.bat $vcvars_arch
if %errorlevel% neq 0 exit /B %errorlevel%

if not "%CWD%"=="%CD%" (
    echo ERROR: vcvarsall.bat changed CWD to %CD%.
    exit /B 2
)

set "WindowsSDKVersion=%WindowsSDKVersion:\=%"

call :SaveVar VSINSTALLDIR
call :SaveVar VCToolsInstallDir
call :SaveVar WindowsSdkDir
call :SaveVar WindowsSDKVersion
call :SaveVar UniversalCRTSdkDir
call :SaveVar UCRTVersion
call :SearchInPath cl.exe
call :SearchInPath rc.exe
call :SearchInPath MSBuild.exe
exit /B 0

:SearchInPath
set "f=%1"
set "f=%f:.=_%"
for %%P in ("%PATH:;=" "%") do (
    if not "%%~P"=="" if exist "%%~P\\%1" (
        set "%f%=%%~P\\%1"
        call :SaveVar %f%
        exit /B 0
    )
)
exit /B 1

:SaveVar
setlocal EnableDelayedExpansion
set "v=!%1!"
if "%v:~-1%"=="\" set "v=%v:~0,-1%"
echo %1=!v!>> $vcvars_arch-env.txt
exit /B 0
EOF


TestVariable() {
    if [ "${!1}" != "$2" ]; then
        echo "ERROR: $1=\"${!1}\""
        return 1
    fi
    return 0
}

TestRealPath() {
    if [ "$(readlink -f "${!1}")" != "$(readlink -f "$2")" ]; then
        echo "ERROR: $1=\"${!1}\""
        return 1
    fi
    return 0
}

EXEC "" WINEDEBUG=-all $(command -v wine64 || command -v wine) cmd /c test-$vcvars_arch.bat || EXIT
tr -d '\r' <$vcvars_arch-env.txt >$vcvars_arch-env

get_var() {
    local name=$1
    local line
    line=$(grep -m1 "^${name}=" "$vcvars_arch-env" || true)
    printf '%s' "${line#*=}"
}

VSINSTALLDIR=$(get_var VSINSTALLDIR)
VCToolsInstallDir=$(get_var VCToolsInstallDir)
WindowsSdkDir=$(get_var WindowsSdkDir)
WindowsSDKVersion=$(get_var WindowsSDKVersion)
UniversalCRTSdkDir=$(get_var UniversalCRTSdkDir)
UCRTVersion=$(get_var UCRTVersion)
cl_exe=$(get_var cl_exe)
rc_exe=$(get_var rc_exe)
MSBuild_exe=$(get_var MSBuild_exe)

to_unix_path() {
    if [ -n "${!1}" ]; then
        local val
        val=$(WINEDEBUG=-all $(command -v wine64 || command -v wine) winepath -u "${!1}")
        if [ -n "$val" ]; then
            printf -v "$1" '%s' "$val"
        fi
    fi
}

to_unix_path VSINSTALLDIR
to_unix_path VCToolsInstallDir
to_unix_path WindowsSdkDir
to_unix_path UniversalCRTSdkDir
to_unix_path cl_exe
to_unix_path rc_exe
to_unix_path MSBuild_exe

SDKBASE=$(. "${BIN}msvcenv.sh" && echo $SDKBASE)
SDKBASE=${SDKBASE//\\//}
SDKBASE=${SDKBASE#z:}

MSVCDIR=$(. "${BIN}msvcenv.sh" && echo $MSVCDIR)
MSVCDIR=${MSVCDIR//\\//}
MSVCDIR=${MSVCDIR#z:}

EXEC "" TestRealPath VSINSTALLDIR       $(. "${BIN}msvcenv.sh" && echo $BASE_UNIX)
EXEC "" TestRealPath VCToolsInstallDir  $MSVCDIR
EXEC "" TestRealPath WindowsSdkDir      $SDKBASE
EXEC "" TestVariable WindowsSDKVersion  $(. "${BIN}msvcenv.sh" && echo $SDKVER)
EXEC "" TestRealPath UniversalCRTSdkDir $SDKBASE
EXEC "" TestVariable UCRTVersion        $(. "${BIN}msvcenv.sh" && echo $SDKVER)

if WINEDEBUG=-all $(command -v wine64 || command -v wine) cmd /c where /? >/dev/null 2>&1; then
    EXEC "" TestRealPath cl_exe             $(. "${BIN}msvcenv.sh" && echo $BINDIR)/cl.exe
    EXEC "" TestRealPath rc_exe             $(. "${BIN}msvcenv.sh" && echo $SDKBINDIR)/rc.exe
    EXEC "" TestRealPath MSBuild_exe        $(. "${BIN}msvcenv.sh" && echo $MSBUILDBINDIR)/MSBuild.exe
else
    echo "Skipping where.exe checks; not available in this Wine."
fi

EXIT
