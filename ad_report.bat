@echo OFF
:: ******************************
:: Active Directory Report Batch
:: ******************************
SETLOCAL ENABLEDELAYEDEXPANSION
:: CONSTANTES
set LOGDIR=%temp%\AD_LOG
set VERSION=04
set OUTPUTZIP=%~n0_v%VERSION%_output.zip
:: ** VARIABLES *****************
set COUNT_LOG=00
:: ** MAIN **********************
echo %~nx0 v.%VERSION%
dcdiag > nul 2>&1
if "%errorlevel%" EQU "9009" (
	echo  *** SUPPORT TOOLS NOT FOUND ***
	echo  please install from
	echo  Windows_2003_CD\SUPPORT\TOOLS\SUPTOOLS.MSI
	goto :exit
)
mkdir %LOGDIR% > nul 2>&1
del %temp%\%OUTPUTZIP% /q > nul 2>&1
del %LOGDIR%\*.* /q > nul 2>&1
echo.
echo  Running ...
echo   - dcdiag /v ...
dcdiag /v /f:%LOGDIR%\dcdiag.log > nul 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - repadmin /showrepl ...
repadmin /showrepl > %LOGDIR%\showrepl.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - repadmin /ReplSummary ...
repadmin /ReplSummary > %LOGDIR%\ReplSummary.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - dnscmd /info ...
dnscmd /info > %LOGDIR%\dnscmd_info.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - dnscmd /EnumZones ...
dnscmd /EnumZones > %LOGDIR%\dnscmd_zones.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - nltest /dclist:%USERDNSDOMAIN% ...
nltest /dclist:%USERDNSDOMAIN% > %LOGDIR%\nltest_dc_list.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - nltest /dnsgetdc:%USERDNSDOMAIN% ...
nltest /dnsgetdc:%USERDNSDOMAIN% > %LOGDIR%\nltest_get_dc.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - netdom query fsmo ...
netdom query fsmo > %LOGDIR%\netdom_fsmo.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - dsquery ou domainroot -scope onelevel ...
dsquery ou domainroot -scope onelevel > %LOGDIR%\dsquery_ou.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - dsquery site ...
dsquery site > %LOGDIR%\dsquery_site.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - dsquery server ...
dsquery server > %LOGDIR%\dsquery_server.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - dsquery partition ...
dsquery partition > %LOGDIR%\dsquery_part.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - dsquery * for AD Level and Schema version ...
for /f %%i in ('dsquery partition') do (
	dsquery * %%i -scope base -attr msDS-Behavior-Version >> %LOGDIR%\dsquery_forest_level.log 2>&1
	set /a COUNT_LOG=%COUNT_LOG%+1
	dsquery * %%i -scope base -attr msDS-Behavior-Version ntMixedDomain >> %LOGDIR%\dsquery_domain_level.log 2>&1
	set /a COUNT_LOG=%COUNT_LOG%+1
	dsquery * %%i -scope base -attr objectVersion >> %LOGDIR%\dsquery_schema_version.log 2>&1
	set /a COUNT_LOG=%COUNT_LOG%+1
)
echo   - w32tm /monitor ...
w32tm /monitor >> %LOGDIR%\w32tm_monitor.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - net time /querysntp ...
net time /querysntp >> %LOGDIR%\net_time_sntp.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - ipconfig /all ...
ipconfig /all >> %LOGDIR%\ipconfig_all.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - systeminfo ...
systeminfo >> %LOGDIR%\systeminfo.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - gpresult /z ...
gpresult /z >> %LOGDIR%\gpresult_z.log 2>&1
set /a COUNT_LOG=%COUNT_LOG%+1
echo   - SYSVOL Share
For /f %%i IN ('dsquery server -o rdn') do (
		echo %%i >> %LOGDIR%\SYSVOL.log 2>&1
		net view \\%%i | find "SYSVOL" >> %LOGDIR%\SYSVOL.log 2>&1
		set /a COUNT_LOG=!COUNT_LOG!+1
)
echo   - DFSR
if exist %windir%\system32\wbem\wmico.exe (
	For /f %%i IN ('dsquery server -o rdn') do (
		
		wmic /node:"%%i" /output:"%LOGDIR%\DFSR_1_%%i.log" /namespace:\\root\microsoftdfs path dfsrreplicatedfolderinfo WHERE replicatedfoldername='SYSVOL share' get replicationgroupname,replicatedfoldername,state
		set /a COUNT_LOG=!COUNT_LOG!+1

		wmic /node:"%%i" /output:"%LOGDIR%\DFSR_2_%%i.log" /namespace:\\root\microsoftdfs path DfsrMachineConfig get MaxOfflineTimeInDays
		set /a COUNT_LOG=!COUNT_LOG!+1
	)
) else (
rem Windows 2025 do not support wmic
rem Instead we use Powershell
	For /f %%i IN ('dsquery server -o rdn') do (
		powershell -command "Get-CimInstance -Namespace "root\microsoftdfs" -ClassName "DfsrReplicatedFolderInfo" -computername %%i | Select-Object ReplicatedFolderName, MemberName, ReplicationGroupName, State | fl" >> %LOGDIR%\DFSR_1_%%i.log 2>&1
		set /a COUNT_LOG=!COUNT_LOG!+1
		powershell -command "Get-CimInstance -Namespace "root\microsoftdfs" -ClassName "DfsrMachineConfig" -computername %%i | select-object MaxOfflineTimeInDays | fl" >> %LOGDIR%\DFSR_2_%%i.log 2>&1
		set /a COUNT_LOG=!COUNT_LOG!+1
	)
)


echo.
for /r  %LOGDIR% %%i in (*.*) do (
	set /a i=!i!+1
) 
echo  %i% log files in  %LOGDIR%
if %i% LSS %COUNT_LOG% (
	set /a diff=%COUNT_LOG%-%i%
	echo  *** !diff! log^(s^) missed ^(%COUNT_LOG% logs expected^) ***
)
echo.
echo  Compressing : %LOGDIR%\*.log
echo  To : %temp%\%OUTPUTZIP%	
echo  ...
echo.
call :CREATE_ZIP_FILE
dir /b %temp%\%OUTPUTZIP% > nul
	if "%errorlevel%" EQU "0" (
		echo  Zip file %temp%\%OUTPUTZIP% available 
		explorer %temp%
	) ELSE (
		echo  *** Zip file %temp%\%OUTPUTZIP% not present... ***
	)
rmdir /s /q %LOGDIR%
:EXIT
exit /b 0
:CREATE_ZIP_FILE
echo Set objArgs = WScript.Arguments > %temp%\_zipIt.vbs
echo InputFolder = objArgs(0) >> %temp%\_zipIt.vbs
echo ZipFile = objArgs(1) >> %temp%\_zipIt.vbs
echo CreateObject("Scripting.FileSystemObject").CreateTextFile(ZipFile, True).Write "PK" ^& Chr(5) ^& Chr(6) ^& String(18, vbNullChar) >> %temp%\_zipIt.vbs
echo Set objShell = CreateObject("Shell.Application") >> %temp%\_zipIt.vbs
echo Set source = objShell.NameSpace(InputFolder).Items >> %temp%\_zipIt.vbs
echo objShell.NameSpace(ZipFile).CopyHere(source) >> %temp%\_zipIt.vbs
echo wScript.Sleep 2000 >> %temp%\_zipIt.vbs
CScript  //NOLOGO %temp%\_zipIt.vbs  %LOGDIR%  %temp%\%OUTPUTZIP%
DEL %temp%\_zipIt.vbs
goto :eof

