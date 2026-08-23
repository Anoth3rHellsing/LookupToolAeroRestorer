#Requires -Version 5.1
<#
.SYNOPSIS
    Restablece como predeterminados en Windows 11 los recursos Frutiger Aero
    rescatados por AeroScan.ps1: fondo, sonidos, cursores, protector y tema.

.DESCRIPTION
    Aplica UNICAMENTE cambios seguros y reversibles, casi todos bajo HKCU
    (tu perfil de usuario). Nunca reemplaza ni parchea archivos del sistema:
    Windows 11 protege sus binarios con WRP y firmas digitales, y sustituirlos
    rompe el sistema en la siguiente actualizacion. Lo que SI se puede devolver
    de forma nativa:

      -Wallpaper      Fondo de escritorio de Vista/7 (img0.jpg de Windows 7,
                      o el mejor fondo disponible en la boveda).
      -Sounds         Esquema de sonidos completo de Windows 7 (registrado como
                      esquema "Frutiger Aero" en el panel de sonidos).
      -Cursors        Esquema de cursores Windows Aero (los .cur/.ani vidriosos
                      de Vista, que Windows 11 aun incluye).
      -Screensaver    Protector de pantalla de la era (Burbujas por defecto;
                      Aurora.scr de Vista si esta en la boveda).
      -SampleMedia    Devuelve Sample Pictures / Sample Music / Sample Videos
                      a C:\Users\Public.
      -StartupSound   Reactiva el sonido de inicio y programa el "Windows Logon
                      Sound" de Vista/7 al iniciar sesion (tarea programada del
                      usuario; el chime nativo de Win11 vive dentro de una DLL
                      firmada y no se toca).
      -Theme          Genera y aplica un archivo .theme "Frutiger Aero
                      (Recuperado)" que ata todo lo anterior, con presentacion
                      de fondos si hay varios.
      -All            Todo lo anterior.

    Lo que NO hace (y por que): el estilo visual Aero Glass real (msstyles con
    cristal y DWM con blur) requiere parchear la verificacion de firmas del
    sistema con software de terceros. Eso queda fuera de esta herramienta por
    estabilidad y seguridad; ver README.

    Soporta -WhatIf para previsualizar cada cambio sin aplicarlo.

.PARAMETER Vault
    Carpeta AeroVault generada por AeroScan.ps1.

.PARAMETER Revert
    Deshace los cambios aplicados anteriormente, devolviendo el fondo, los
    cursores, el esquema de sonidos y el protector de pantalla a los valores
    que tenian ANTES de la primera ejecucion. Esos valores se guardan de forma
    automatica en %LOCALAPPDATA%\FrutigerAero\backup.json la primera vez que se
    aplica algo, y ese respaldo original nunca se sobrescribe.

.EXAMPLE
    .\AeroRestore.ps1 -Vault .\AeroVault -All -WhatIf
    Muestra todo lo que haria sin tocar nada.

.EXAMPLE
    .\AeroRestore.ps1 -Vault .\AeroVault -Wallpaper -Sounds -Cursors -Theme

.EXAMPLE
    .\AeroRestore.ps1 -Revert
    Devuelve el sistema al aspecto que tenia antes.
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Aplicar')]
param(
    [Parameter(ParameterSetName = 'Aplicar', Mandatory = $true)]
    [string]$Vault,
    [Parameter(ParameterSetName = 'Aplicar')] [switch]$Wallpaper,
    [Parameter(ParameterSetName = 'Aplicar')] [switch]$Sounds,
    [Parameter(ParameterSetName = 'Aplicar')] [switch]$Cursors,
    [Parameter(ParameterSetName = 'Aplicar')] [switch]$Screensaver,
    [Parameter(ParameterSetName = 'Aplicar')] [switch]$SampleMedia,
    [Parameter(ParameterSetName = 'Aplicar')] [switch]$StartupSound,
    [Parameter(ParameterSetName = 'Aplicar')] [switch]$Theme,
    [Parameter(ParameterSetName = 'Aplicar')] [switch]$All,

    [Parameter(ParameterSetName = 'Revertir', Mandatory = $true)]
    [switch]$Revert
)

if ($env:OS -ne 'Windows_NT') {
    throw 'AeroRestore.ps1 solo funciona en Windows.'
}

$stage = Join-Path $env:LOCALAPPDATA 'FrutigerAero'
$backupPath = Join-Path $stage 'backup.json'

# Eventos de sonido que este script toca (usado al aplicar y al revertir)
$soundMap = @(
    @{ App = '.Default'; Event = '.Default';             Wav = 'Windows Ding.wav' },
    @{ App = '.Default'; Event = 'SystemAsterisk';       Wav = 'Windows Ding.wav' },
    @{ App = '.Default'; Event = 'SystemExclamation';    Wav = 'Windows Exclamation.wav' },
    @{ App = '.Default'; Event = 'SystemHand';           Wav = 'Windows Critical Stop.wav' },
    @{ App = '.Default'; Event = 'SystemNotification';   Wav = 'Windows Notify.wav' },
    @{ App = '.Default'; Event = 'Notification.Default'; Wav = 'Windows Notify.wav' },
    @{ App = '.Default'; Event = 'DeviceConnect';        Wav = 'Windows Hardware Insert.wav' },
    @{ App = '.Default'; Event = 'DeviceDisconnect';     Wav = 'Windows Hardware Remove.wav' },
    @{ App = '.Default'; Event = 'DeviceFail';           Wav = 'Windows Hardware Fail.wav' },
    @{ App = '.Default'; Event = 'LowBatteryAlarm';      Wav = 'Windows Battery Low.wav' },
    @{ App = '.Default'; Event = 'CriticalBatteryAlarm'; Wav = 'Windows Battery Critical.wav' },
    @{ App = '.Default'; Event = 'PrintComplete';        Wav = 'Windows Print complete.wav' },
    @{ App = '.Default'; Event = 'WindowsUAC';           Wav = 'Windows User Account Control.wav' },
    @{ App = '.Default'; Event = 'WindowsLogon';         Wav = 'Windows Logon Sound.wav' },
    @{ App = '.Default'; Event = 'WindowsLogoff';        Wav = 'Windows Logoff Sound.wav' },
    @{ App = '.Default'; Event = 'SystemExit';           Wav = 'Windows Shutdown.wav' },
    @{ App = '.Default'; Event = 'MailBeep';             Wav = 'Windows Notify.wav' },
    @{ App = '.Default'; Event = 'FaxBeep';              Wav = 'Windows Notify.wav' },
    @{ App = '.Default'; Event = 'MenuCommand';          Wav = '' },
    @{ App = 'Explorer'; Event = 'Navigating';           Wav = 'Windows Navigation Start.wav' },
    @{ App = 'Explorer'; Event = 'EmptyRecycleBin';      Wav = 'Windows Recycle.wav' },
    @{ App = 'Explorer'; Event = 'BlockedPopup';         Wav = 'Windows Pop-up Blocked.wav' }
)

$cursorRegNames = @('Arrow','Help','AppStarting','Wait','NWPen','No','SizeNS','SizeWE',
                    'SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Crosshair','IBeam')

Add-Type -Namespace AeroTools -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool SystemParametersInfoW(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
'@

$SPI_SETDESKWALLPAPER = 0x0014
$SPI_SETCURSORS       = 0x0057
$SPIF_UPDATE_SEND     = 0x0003

function Get-RegValue {
    param([string]$Key, [string]$Name)
    try {
        $item = Get-ItemProperty -Path $Key -Name $Name -ErrorAction Stop
        return [string]$item.$Name
    } catch { return $null }
}

function Save-OriginalState {
    # Guarda el estado previo UNA sola vez, para que revertir siempre devuelva
    # el aspecto original y no un estado Aero intermedio.
    if (Test-Path -LiteralPath $backupPath) { return }
    if (-not (Test-Path -LiteralPath $stage)) {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
    }
    $desktop = @{}
    foreach ($n in @('Wallpaper','WallpaperStyle','TileWallpaper','SCRNSAVE.EXE',
                     'ScreenSaveActive','ScreenSaveTimeOut')) {
        $desktop[$n] = Get-RegValue -Key 'HKCU:\Control Panel\Desktop' -Name $n
    }
    $cur = @{}
    foreach ($n in $cursorRegNames) {
        $cur[$n] = Get-RegValue -Key 'HKCU:\Control Panel\Cursors' -Name $n
    }
    $cur['(default)'] = Get-RegValue -Key 'HKCU:\Control Panel\Cursors' -Name '(default)'

    $snd = @{}
    foreach ($m in $soundMap) {
        $k = "HKCU:\AppEvents\Schemes\Apps\$($m.App)\$($m.Event)\.Current"
        $snd["$($m.App)|$($m.Event)"] = Get-RegValue -Key $k -Name '(default)'
    }

    $backup = [ordered]@{
        Fecha       = (Get-Date).ToString('o')
        Desktop     = $desktop
        Cursors     = $cur
        SoundScheme = (Get-RegValue -Key 'HKCU:\AppEvents\Schemes' -Name '(default)')
        Sounds      = $snd
    }
    $backup | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $backupPath -Encoding UTF8
    Write-Host "Estado original guardado en $backupPath" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Modo revertir
# ---------------------------------------------------------------------------
if ($Revert) {
    Write-Host ''
    Write-Host '=== AeroRestore: deshaciendo los cambios ===' -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Write-Warning "No hay respaldo en ${backupPath}: no se aplico nunca nada desde esta cuenta, o se borro."
        Write-Host 'Puedes volver al aspecto original manualmente en Configuracion > Personalizacion > Temas > "Windows (claro)".'
        return
    }
    $b = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json
    $deshecho = New-Object System.Collections.Generic.List[string]

    if ($PSCmdlet.ShouldProcess('HKCU:\Control Panel\Desktop', 'Restaurar fondo y protector originales')) {
        foreach ($p in $b.Desktop.PSObject.Properties) {
            if ($null -eq $p.Value) { continue }
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name $p.Name -Value $p.Value
        }
        if ($b.Desktop.Wallpaper) {
            [AeroTools.Native]::SystemParametersInfoW($SPI_SETDESKWALLPAPER, 0, $b.Desktop.Wallpaper, $SPIF_UPDATE_SEND) | Out-Null
        }
        $deshecho.Add('Fondo de escritorio y protector de pantalla originales')
    }

    if ($PSCmdlet.ShouldProcess('HKCU:\Control Panel\Cursors', 'Restaurar cursores originales')) {
        foreach ($p in $b.Cursors.PSObject.Properties) {
            if ($null -eq $p.Value) { continue }
            Set-ItemProperty -Path 'HKCU:\Control Panel\Cursors' -Name $p.Name -Value $p.Value -Type ExpandString
        }
        [AeroTools.Native]::SystemParametersInfoW($SPI_SETCURSORS, 0, $null, $SPIF_UPDATE_SEND) | Out-Null
        $deshecho.Add('Esquema de cursores original')
    }

    if ($PSCmdlet.ShouldProcess('HKCU:\AppEvents', 'Restaurar esquema de sonidos original')) {
        foreach ($p in $b.Sounds.PSObject.Properties) {
            if ($null -eq $p.Value) { continue }
            $parts = $p.Name -split '\|', 2
            $k = "HKCU:\AppEvents\Schemes\Apps\$($parts[0])\$($parts[1])\.Current"
            if (Test-Path $k) { Set-ItemProperty -Path $k -Name '(default)' -Value $p.Value }
        }
        $esquema = $b.SoundScheme
        if (-not $esquema) { $esquema = '.Default' }
        Set-ItemProperty -Path 'HKCU:\AppEvents\Schemes' -Name '(default)' -Value $esquema
        $nombresKey = 'HKCU:\AppEvents\Schemes\Names\FrutigerAero'
        if (Test-Path $nombresKey) { Remove-Item -Path $nombresKey -Recurse -Force }
        $deshecho.Add("Esquema de sonidos devuelto a '$esquema'")
    }

    $tarea = Get-ScheduledTask -TaskName 'FrutigerAero-LogonSound' -ErrorAction SilentlyContinue
    if ($tarea -and $PSCmdlet.ShouldProcess('FrutigerAero-LogonSound', 'Eliminar tarea programada')) {
        try {
            Unregister-ScheduledTask -TaskName 'FrutigerAero-LogonSound' -Confirm:$false
            $deshecho.Add('Tarea del sonido de inicio de sesion eliminada')
        } catch {
            Write-Warning "No se pudo eliminar la tarea programada: $($_.Exception.Message)"
        }
    }

    $themePath = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes\FrutigerAero.theme'
    if ((Test-Path -LiteralPath $themePath) -and
        $PSCmdlet.ShouldProcess($themePath, 'Eliminar tema Frutiger Aero')) {
        Remove-Item -LiteralPath $themePath -Force -ErrorAction SilentlyContinue
        $deshecho.Add('Tema "Frutiger Aero (Recuperado)" eliminado')
    }

    Write-Host ''
    Write-Host '=== Cambios deshechos ===' -ForegroundColor Cyan
    foreach ($d in $deshecho) { Write-Host "  [OK] $d" -ForegroundColor Green }
    Write-Host ''
    Write-Host "Los archivos rescatados siguen intactos en $stage (borralos a mano si no los quieres)." -ForegroundColor DarkGray
    Write-Host 'Cierra sesion y vuelve a entrar para que todo se refresque por completo.' -ForegroundColor DarkGray
    return
}

# ---------------------------------------------------------------------------
# Modo aplicar
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Vault)) {
    throw "No existe la boveda: $Vault"
}
$Vault = (Resolve-Path -LiteralPath $Vault).Path
if ($All) {
    $Wallpaper = $Sounds = $Cursors = $Screensaver = $SampleMedia = $StartupSound = $Theme = $true
}
if (-not ($Wallpaper -or $Sounds -or $Cursors -or $Screensaver -or $SampleMedia -or $StartupSound -or $Theme)) {
    Write-Host 'Nada que hacer: indica -All o alguno de -Wallpaper -Sounds -Cursors -Screensaver -SampleMedia -StartupSound -Theme'
    return
}

# ---------------------------------------------------------------------------
# Preparacion
# ---------------------------------------------------------------------------

# Antes de tocar nada, conservar el aspecto actual para poder revertir despues.
if (-not $WhatIfPreference) { Save-OriginalState }

# Indice de la boveda por nombre de archivo (prefiere Win7 sobre Vista sobre Superviviente)
$eraRank = @{ 'Win7' = 0; 'Vista' = 1; 'Superviviente' = 2 }
$vaultIndex = @{}
Get-ChildItem -LiteralPath $Vault -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $key = $_.Name.ToLowerInvariant()
    $parts = @($_.FullName.Substring($Vault.Length) -split '[\\/]' | Where-Object { $_ })
    $era = if ($parts.Count -gt 0) { $parts[0] } else { '' }
    $rank = 9
    if ($eraRank.ContainsKey($era)) { $rank = $eraRank[$era] }
    if (-not $vaultIndex.ContainsKey($key) -or $rank -lt $vaultIndex[$key].Rank) {
        $vaultIndex[$key] = [pscustomobject]@{ Path = $_.FullName; Rank = $rank }
    }
}

function Find-Asset {
    # Busca por nombre en la boveda; si no esta, prueba las rutas del sistema.
    param([string[]]$Names, [string[]]$SystemFallbacks = @())
    foreach ($n in $Names) {
        $k = $n.ToLowerInvariant()
        if ($vaultIndex.ContainsKey($k)) { return $vaultIndex[$k].Path }
    }
    foreach ($f in $SystemFallbacks) {
        $expanded = [Environment]::ExpandEnvironmentVariables($f)
        if (Test-Path -LiteralPath $expanded) { return $expanded }
    }
    return $null
}

function Stage-Asset {
    # Copia un recurso a %LOCALAPPDATA%\FrutigerAero para que el tema no dependa
    # de que la boveda (quiza un disco externo) siga conectada.
    param([string]$Source, [string]$SubDir)
    if (-not $Source) { return $null }
    $dir = Join-Path $stage $SubDir
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dest = Join-Path $dir ([System.IO.Path]::GetFileName($Source))
    Copy-Item -LiteralPath $Source -Destination $dest -Force
    return $dest
}

$applied = New-Object System.Collections.Generic.List[string]
$themeWallpaper = $null
$themeSlideshowDir = $null

Write-Host ''
Write-Host '=== AeroRestore: devolviendo la era Frutiger Aero a Windows 11 ===' -ForegroundColor Cyan
Write-Host "Boveda: $Vault"
Write-Host ''

# ---------------------------------------------------------------------------
# Fondo de pantalla
# ---------------------------------------------------------------------------
if ($Wallpaper -or $Theme) {
    $fondos = @(Get-ChildItem -LiteralPath $Vault -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in @('.jpg', '.jpeg', '.png', '.bmp') -and
            $_.FullName -match '[\\/](Fondos|Regionales|OOBE)[\\/]'
        })
    if ($fondos.Count -eq 0) {
        Write-Warning 'La boveda no contiene fondos de pantalla.'
    } else {
        # img0.jpg es el fondo "Armonia" por defecto de Windows 7
        $principal = $fondos | Where-Object { $_.Name -ieq 'img0.jpg' } | Select-Object -First 1
        if (-not $principal) {
            $principal = $fondos | Sort-Object Length -Descending | Select-Object -First 1
        }
        $slideDir = Join-Path $stage 'Wallpaper'
        foreach ($f in $fondos) { Stage-Asset -Source $f.FullName -SubDir 'Wallpaper' | Out-Null }
        $themeWallpaper = Join-Path $slideDir $principal.Name
        if ($fondos.Count -gt 1) { $themeSlideshowDir = $slideDir }

        if ($Wallpaper -and $PSCmdlet.ShouldProcess($themeWallpaper, 'Establecer como fondo de escritorio')) {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $themeWallpaper
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'
            [AeroTools.Native]::SystemParametersInfoW($SPI_SETDESKWALLPAPER, 0, $themeWallpaper, $SPIF_UPDATE_SEND) | Out-Null
            $applied.Add("Fondo de escritorio: $($principal.Name) ($($fondos.Count) fondos preparados)")
        }
    }
}

# ---------------------------------------------------------------------------
# Sonidos
# ---------------------------------------------------------------------------

# $soundMap (evento -> wav del esquema por defecto de Windows 7) se define arriba,
# porque el modo -Revert tambien lo necesita.

if ($Sounds) {
    $schemeId = 'FrutigerAero'
    $schemeName = 'Frutiger Aero (Windows 7)'
    $count = 0
    if ($PSCmdlet.ShouldProcess('HKCU:\AppEvents', "Registrar y activar esquema de sonidos '$schemeName'")) {
        $namesKey = "HKCU:\AppEvents\Schemes\Names\$schemeId"
        if (-not (Test-Path $namesKey)) { New-Item -Path $namesKey -Force | Out-Null }
        Set-ItemProperty -Path $namesKey -Name '(default)' -Value $schemeName

        foreach ($m in $soundMap) {
            $wavPath = ''
            if ($m.Wav) {
                $src = Find-Asset -Names @($m.Wav) -SystemFallbacks @("%SystemRoot%\Media\$($m.Wav)")
                if (-not $src) { continue }
                $wavPath = Stage-Asset -Source $src -SubDir 'Sounds'
            }
            $eventKey = "HKCU:\AppEvents\Schemes\Apps\$($m.App)\$($m.Event)"
            if (-not (Test-Path $eventKey)) { New-Item -Path $eventKey -Force | Out-Null }
            foreach ($sub in @($schemeId, '.Current')) {
                $k = Join-Path $eventKey $sub
                if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
                Set-ItemProperty -Path $k -Name '(default)' -Value $wavPath
            }
            if ($m.Wav) { $count++ }
        }
        Set-ItemProperty -Path 'HKCU:\AppEvents\Schemes' -Name '(default)' -Value $schemeId
        $applied.Add("Esquema de sonidos '$schemeName' activado ($count eventos)")
    }
}

# ---------------------------------------------------------------------------
# Sonido de inicio (el "pearl" de Vista/7)
# ---------------------------------------------------------------------------
if ($StartupSound) {
    $logonWav = Find-Asset -Names @('Windows Logon Sound.wav', 'Windows Logon.wav') `
        -SystemFallbacks @('%SystemRoot%\Media\Windows Logon Sound.wav', '%SystemRoot%\Media\Windows Logon.wav')
    if (-not $logonWav) {
        Write-Warning 'No se encontro "Windows Logon Sound.wav" ni en la boveda ni en el sistema.'
    } else {
        $staged = Stage-Asset -Source $logonWav -SubDir 'Sounds'

        # 1) Reactivar el sonido de inicio del sistema (requiere administrador)
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $bootKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation'
        if ($isAdmin) {
            if ($PSCmdlet.ShouldProcess($bootKey, 'DisableStartupSound = 0')) {
                if (-not (Test-Path $bootKey)) { New-Item -Path $bootKey -Force | Out-Null }
                Set-ItemProperty -Path $bootKey -Name DisableStartupSound -Value 0 -Type DWord
                $applied.Add('Sonido de inicio del sistema reactivado (DisableStartupSound=0)')
            }
        } else {
            Write-Warning 'Sin permisos de administrador: no se pudo reactivar el sonido de inicio global (DisableStartupSound). El chime nativo de Win11 seguira apagado.'
        }

        # 2) Tarea al iniciar sesion que reproduce el logon de Vista/7
        if ($PSCmdlet.ShouldProcess('Tarea programada FrutigerAero-LogonSound', "Reproducir '$staged' al iniciar sesion")) {
            try {
                $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
                    "-NoProfile -WindowStyle Hidden -Command `"(New-Object Media.SoundPlayer '$staged').PlaySync()`"")
                $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
                Register-ScheduledTask -TaskName 'FrutigerAero-LogonSound' -Action $action `
                    -Trigger $trigger -Description 'Reproduce el Windows Logon Sound de Vista/7 al iniciar sesion' `
                    -Force | Out-Null
                $applied.Add('Sonido de inicio de sesion de Vista/7 programado (tarea FrutigerAero-LogonSound)')
            } catch {
                Write-Warning "No se pudo registrar la tarea de inicio de sesion: $($_.Exception.Message)"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Cursores Aero
# ---------------------------------------------------------------------------

$cursorMap = @(
    @{ Reg = 'Arrow';       File = 'aero_arrow.cur' },
    @{ Reg = 'Help';        File = 'aero_helpsel.cur' },
    @{ Reg = 'AppStarting'; File = 'aero_working.ani' },
    @{ Reg = 'Wait';        File = 'aero_busy.ani' },
    @{ Reg = 'NWPen';       File = 'aero_pen.cur' },
    @{ Reg = 'No';          File = 'aero_unavail.cur' },
    @{ Reg = 'SizeNS';      File = 'aero_ns.cur' },
    @{ Reg = 'SizeWE';      File = 'aero_ew.cur' },
    @{ Reg = 'SizeNWSE';    File = 'aero_nwse.cur' },
    @{ Reg = 'SizeNESW';    File = 'aero_nesw.cur' },
    @{ Reg = 'SizeAll';     File = 'aero_move.cur' },
    @{ Reg = 'UpArrow';     File = 'aero_up.cur' },
    @{ Reg = 'Hand';        File = 'aero_link.cur' },
    @{ Reg = 'Crosshair';   File = '' },
    @{ Reg = 'IBeam';       File = '' }
)

$cursorPaths = @{}
foreach ($c in $cursorMap) {
    if (-not $c.File) { $cursorPaths[$c.Reg] = ''; continue }
    $src = Find-Asset -Names @($c.File) -SystemFallbacks @("%SystemRoot%\Cursors\$($c.File)")
    if ($src) {
        if ($src.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $cursorPaths[$c.Reg] = $src   # ya vive en el sistema: usar tal cual
        } else {
            $cursorPaths[$c.Reg] = Stage-Asset -Source $src -SubDir 'Cursors'
        }
    }
}

if ($Cursors) {
    if ($cursorPaths.Count -le 2) {
        Write-Warning 'No se encontraron cursores aero_*.'
    } elseif ($PSCmdlet.ShouldProcess('HKCU:\Control Panel\Cursors', 'Aplicar esquema de cursores Windows Aero (Recuperado)')) {
        $key = 'HKCU:\Control Panel\Cursors'
        foreach ($entry in $cursorPaths.GetEnumerator()) {
            Set-ItemProperty -Path $key -Name $entry.Key -Value $entry.Value -Type ExpandString
        }
        Set-ItemProperty -Path $key -Name '(default)' -Value 'Windows Aero (Recuperado)'
        Set-ItemProperty -Path $key -Name 'Scheme Source' -Value 1 -Type DWord
        [AeroTools.Native]::SystemParametersInfoW($SPI_SETCURSORS, 0, $null, $SPIF_UPDATE_SEND) | Out-Null
        $applied.Add("Esquema de cursores Aero aplicado ($($cursorPaths.Count) punteros)")
    }
}

# ---------------------------------------------------------------------------
# Protector de pantalla
# ---------------------------------------------------------------------------
if ($Screensaver) {
    $scr = $null
    $aurora = Find-Asset -Names @('Aurora.scr')
    if ($aurora) {
        $scr = Stage-Asset -Source $aurora -SubDir 'Screensaver'
        Write-Host 'Nota: Aurora.scr procede de Vista; si no arranca en Win11, se puede volver a Burbujas.' -ForegroundColor DarkYellow
    } else {
        $scr = Find-Asset -Names @('Bubbles.scr', 'Ribbons.scr', 'Mystify.scr') -SystemFallbacks @(
            '%SystemRoot%\System32\Bubbles.scr', '%SystemRoot%\System32\Ribbons.scr', '%SystemRoot%\System32\Mystify.scr')
    }
    if (-not $scr) {
        Write-Warning 'No hay protectores de pantalla disponibles.'
    } elseif ($PSCmdlet.ShouldProcess($scr, 'Establecer como protector de pantalla (10 min)')) {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'SCRNSAVE.EXE' -Value $scr
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name ScreenSaveActive -Value '1'
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name ScreenSaveTimeOut -Value '600'
        $applied.Add("Protector de pantalla: $([System.IO.Path]::GetFileName($scr))")
    }
}

# ---------------------------------------------------------------------------
# Medios de muestra en carpetas publicas
# ---------------------------------------------------------------------------
if ($SampleMedia) {
    $muestras = @(Get-ChildItem -LiteralPath $Vault -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]Muestras[\\/]' })
    if ($muestras.Count -eq 0) {
        Write-Warning 'La boveda no contiene medios de muestra (Muestras).'
    } else {
        $destMap = @{
            '.jpg' = 'Pictures\Sample Pictures'; '.jpeg' = 'Pictures\Sample Pictures'
            '.mp3' = 'Music\Sample Music';       '.wma'  = 'Music\Sample Music'
            '.wmv' = 'Videos\Sample Videos'
        }
        $n = 0
        foreach ($f in $muestras) {
            $sub = $destMap[$f.Extension.ToLowerInvariant()]
            if (-not $sub) { continue }
            $destDir = Join-Path $env:PUBLIC $sub
            if ($PSCmdlet.ShouldProcess((Join-Path $destDir $f.Name), 'Restaurar medio de muestra')) {
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destDir $f.Name) -Force
                $n++
            }
        }
        if ($n -gt 0) { $applied.Add("$n medios de muestra devueltos a $env:PUBLIC") }
    }
}

# ---------------------------------------------------------------------------
# Tema .theme que ata todo
# ---------------------------------------------------------------------------
if ($Theme) {
    $themesDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes'
    if (-not (Test-Path -LiteralPath $themesDir)) {
        New-Item -ItemType Directory -Path $themesDir -Force | Out-Null
    }
    $themePath = Join-Path $themesDir 'FrutigerAero.theme'

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('; Tema generado por AeroRestore.ps1 - LookupToolAeroRestorer')
    $lines.Add('[Theme]')
    $lines.Add('DisplayName=Frutiger Aero (Recuperado)')
    $lines.Add('')
    $lines.Add('[Control Panel\Desktop]')
    if ($themeWallpaper) { $lines.Add("Wallpaper=$themeWallpaper") }
    $lines.Add('TileWallpaper=0')
    $lines.Add('WallpaperStyle=10')
    $lines.Add('')
    if ($themeSlideshowDir) {
        $lines.Add('[Slideshow]')
        $lines.Add("ImagesRootPath=$themeSlideshowDir")
        $lines.Add('Interval=1800000')
        $lines.Add('Shuffle=1')
        $lines.Add('')
    }
    $lines.Add('[VisualStyles]')
    $lines.Add('Path=%SystemRoot%\resources\themes\Aero\Aero.msstyles')
    $lines.Add('ColorStyle=NormalColor')
    $lines.Add('Size=NormalSize')
    # Color de acento por defecto de Windows 7 ("cielo" azul translucido)
    $lines.Add('ColorizationColor=0X6B74B8FC')
    $lines.Add('Transparency=1')
    $lines.Add('')
    if ($cursorPaths.Count -gt 2) {
        $lines.Add('[Control Panel\Cursors]')
        foreach ($entry in $cursorPaths.GetEnumerator()) {
            if ($entry.Value) { $lines.Add("$($entry.Key)=$($entry.Value)") }
        }
        $lines.Add('DefaultValue=Windows Aero (Recuperado)')
        $lines.Add('')
    }
    $lines.Add('[MasterThemeSelector]')
    $lines.Add('MTSM=DABJDKT')

    if ($PSCmdlet.ShouldProcess($themePath, 'Generar y aplicar tema')) {
        Set-Content -LiteralPath $themePath -Value $lines -Encoding Unicode
        $applied.Add("Tema generado: $themePath")
        # Abrir el .theme lo aplica y abre Configuracion > Personalizacion
        Start-Process -FilePath $themePath
    }
}

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Cambios aplicados ===' -ForegroundColor Cyan
if ($applied.Count -eq 0) {
    Write-Host '  (ninguno)'
} else {
    foreach ($a in $applied) { Write-Host "  [OK] $a" -ForegroundColor Green }
}
Write-Host ''
Write-Host 'Para revertir: Configuracion > Personalizacion > Temas > "Windows (claro)".' -ForegroundColor DarkGray
Write-Host 'La tarea FrutigerAero-LogonSound se elimina con: Unregister-ScheduledTask FrutigerAero-LogonSound' -ForegroundColor DarkGray
