@echo off
setlocal EnableExtensions

cd /d "%~dp0"
set "PORT=8060"
set "GAME_FILE=Kurenai_Bancho_School_Wars.html"
set "GAME_URL=http://127.0.0.1:%PORT%/%GAME_FILE%"
set "LAN_IP="
set "PYTHON_EXE="

call :check_export
if errorlevel 1 exit /b 1

call :find_python
if defined PYTHON_EXE goto start_server

echo Python nao foi encontrado.
echo Ele e necessario para abrir o export Web sem o erro "Failed to fetch".
echo.

where winget >nul 2>nul
if errorlevel 1 (
	echo O instalador winget tambem nao foi encontrado.
	echo Instale o Python em https://www.python.org/downloads/
	echo e execute este arquivo novamente.
	echo.
	pause
	exit /b 1
)

choice /c SN /n /m "Deseja instalar o Python automaticamente agora? [S/N] "
if errorlevel 2 exit /b 1

echo.
echo Instalando Python pelo winget...
winget install --id Python.Python.3.13 --exact --scope user --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
	echo.
	echo Nao foi possivel instalar o Python automaticamente.
	echo Tente instalar manualmente em https://www.python.org/downloads/
	echo.
	pause
	exit /b 1
)

call :find_python
if not defined PYTHON_EXE (
	echo.
	echo O Python foi instalado, mas ainda nao esta disponivel nesta sessao.
	echo Feche esta janela e execute o BAT novamente.
	echo.
	pause
	exit /b 1
)

:start_server
echo Iniciando servidor local...
start "Kurenai Web Server" /min "%PYTHON_EXE%" %PYTHON_ARGS% -m http.server %PORT% --bind 0.0.0.0

call :wait_for_server
if errorlevel 1 (
	echo.
	echo O servidor nao respondeu na porta %PORT%.
	echo Verifique se outro programa ja esta usando essa porta.
	echo.
	pause
	exit /b 1
)

start "" "%GAME_URL%"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$ip = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceOperationalStatus -eq 'Up' } | Sort-Object InterfaceMetric | Select-Object -First 1 -ExpandProperty IPAddress; if ($ip) { $ip }"`) do set "LAN_IP=%%I"
echo.
echo Jogo aberto em:
echo %GAME_URL%
if defined LAN_IP (
	echo.
	echo No celular conectado ao mesmo Wi-Fi, abra:
	echo http://%LAN_IP%:%PORT%/%GAME_FILE%
	echo.
	echo Se o Windows perguntar, permita o acesso na rede privada.
)
echo.
echo Para encerrar o servidor, feche a janela "Kurenai Web Server".
timeout /t 4 /nobreak >nul
exit /b 0

:check_export
set "MISSING_FILE="
for %%F in (
	"%GAME_FILE%"
	"Kurenai_Bancho_School_Wars.js"
	"Kurenai_Bancho_School_Wars.wasm"
	"Kurenai_Bancho_School_Wars.pck"
) do (
	if not exist "%%~F" (
		echo Arquivo ausente: %%~F
		set "MISSING_FILE=1"
	)
)

if defined MISSING_FILE (
	echo.
	echo Exporte o projeto para Web pelo Godot antes de executar este BAT.
	echo.
	pause
	exit /b 1
)
exit /b 0

:find_python
for /f "delims=" %%P in ('where py 2^>nul') do (
	if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
)
if defined PYTHON_EXE (
	set "PYTHON_ARGS=-3"
	"%PYTHON_EXE%" -3 -c "import sys" >nul 2>nul
	if errorlevel 1 set "PYTHON_EXE="
)
if defined PYTHON_EXE (
	exit /b 0
)

for /f "delims=" %%P in ('where python 2^>nul') do (
	if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
)
if defined PYTHON_EXE (
	set "PYTHON_ARGS="
	"%PYTHON_EXE%" -c "import sys" >nul 2>nul
	if errorlevel 1 set "PYTHON_EXE="
)
if defined PYTHON_EXE (
	exit /b 0
)

for %%P in (
	"%LocalAppData%\Programs\Python\Python313\python.exe"
	"%LocalAppData%\Programs\Python\Python312\python.exe"
	"C:\Python313\python.exe"
	"C:\Python312\python.exe"
) do (
	if not defined PYTHON_EXE if exist "%%~P" set "PYTHON_EXE=%%~P"
)
set "PYTHON_ARGS="
if defined PYTHON_EXE (
	"%PYTHON_EXE%" -c "import sys" >nul 2>nul
	if errorlevel 1 set "PYTHON_EXE="
)
exit /b 0

:wait_for_server
for /l %%I in (1,1,15) do (
	powershell -NoProfile -Command "try { $r = Invoke-WebRequest -UseBasicParsing '%GAME_URL%' -TimeoutSec 1; if ($r.StatusCode -eq 200) { exit 0 } } catch {}; exit 1" >nul 2>nul
	if not errorlevel 1 exit /b 0
	timeout /t 1 /nobreak >nul
)
exit /b 1
