#Requires -Version 5.1
<#
.SYNOPSIS
    Menú interactivo que guía paso a paso todo el proceso de rescate y
    restauración de la estética Frutiger Aero (Windows Vista / Windows 7).

.DESCRIPTION
    Es el punto de entrada recomendado del proyecto. No hace falta recordar
    ningún parámetro: se ejecuta, aparece un menú y la herramienta va
    preguntando. Cubre todo el flujo:

      - Comprobación del sistema (versión de PowerShell, permisos, DISM...).
      - Escaneo de la instalación actual, de otro disco, de una carpeta,
        de una ISO (se monta y desmonta sola) o de un install.wim de Vista/7.
      - Extracción de los recursos incrustados en las DLL del sistema.
      - Restauración en Windows 11, con vista previa obligatoria antes de
        aplicar nada.
      - Deshacer los cambios y volver al aspecto original.

    Todos los errores se capturan y se explican en castellano, con una
    sugerencia concreta de qué hacer a continuación.

.PARAMETER Vault
    Carpeta de la bóveda a usar por defecto. Si se omite, se usa .\AeroVault
    junto al script.

.EXAMPLE
    .\AeroTool.ps1

.EXAMPLE
    .\AeroTool.ps1 -Vault D:\PreservacionAero
#>
[CmdletBinding()]
param(
    [string]$Vault
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Que cualquier fallo de un cmdlet sea una excepcion capturable: asi Invoke-Paso
# puede explicarlo en castellano en vez de dejar el trabajo a medias en silencio.
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Estado global
# ---------------------------------------------------------------------------

$script:Raiz = $PSScriptRoot
if (-not $script:Raiz) { $script:Raiz = (Get-Location).Path }

if ($Vault) { $script:Boveda = $Vault }
else { $script:Boveda = Join-Path $script:Raiz 'AeroVault' }

$script:Origen    = $null                                     # última raíz escaneada
$script:Montajes  = New-Object System.Collections.Generic.List[object]
$script:EsWindows = ($env:OS -eq 'Windows_NT')
$script:EsAdmin   = $false
if ($script:EsWindows) {
    try {
        $script:EsAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }
}

$script:ScriptScan    = Join-Path $script:Raiz 'AeroScan.ps1'
$script:ScriptExtract = Join-Path $script:Raiz 'AeroExtract.ps1'
$script:ScriptRestore = Join-Path $script:Raiz 'AeroRestore.ps1'

# ---------------------------------------------------------------------------
# Presentación
# ---------------------------------------------------------------------------

function Write-Regla {
    param([ConsoleColor]$Color = 'DarkCyan')
    Write-Host ('  ' + ('-' * 68)) -ForegroundColor $Color
}

function Show-Cabecera {
    Clear-Host
    Write-Host ''
    Write-Host '   ================================================================' -ForegroundColor Cyan
    Write-Host '        F R U T I G E R   A E R O   ' -NoNewline -ForegroundColor Cyan
    Write-Host '-  rescate y restauración' -ForegroundColor White
    Write-Host '        Windows Vista / 7  ->  Windows 11' -ForegroundColor DarkCyan
    Write-Host '   ================================================================' -ForegroundColor Cyan
    Write-Host ''
    $estadoBoveda = 'sin crear'
    $colorBoveda = 'DarkYellow'
    if ($script:Boveda -and (Test-Path -LiteralPath $script:Boveda -ErrorAction SilentlyContinue)) {
        $n = @(Get-ChildItem -LiteralPath $script:Boveda -File -Recurse -ErrorAction SilentlyContinue).Count
        $estadoBoveda = "$n archivo(s)"
        $colorBoveda = 'Green'
    }
    Write-Host '   Bóveda: ' -NoNewline -ForegroundColor DarkGray
    Write-Host $script:Boveda -NoNewline -ForegroundColor Gray
    Write-Host "  [$estadoBoveda]" -ForegroundColor $colorBoveda
    if ($script:Montajes.Count -gt 0) {
        Write-Host "   Montajes activos: $($script:Montajes.Count) (se desmontarán al salir)" -ForegroundColor DarkYellow
    }
    Write-Host ''
}

function Write-Paso {
    param([string]$Texto)
    Write-Host ''
    Write-Host "  >> $Texto" -ForegroundColor White
    Write-Regla
}

function Write-Info  { param([string]$T) Write-Host "     $T" -ForegroundColor Gray }
function Write-Exito { param([string]$T) Write-Host "  [OK]  $T" -ForegroundColor Green }
function Write-Aviso { param([string]$T) Write-Host "  [!]   $T" -ForegroundColor Yellow }
function Write-Fallo { param([string]$T) Write-Host "  [X]   $T" -ForegroundColor Red }

function Pausar {
    param([string]$Texto = 'Pulsa ENTER para continuar...')
    Write-Host ''
    Read-Host "  $Texto" | Out-Null
}

# ---------------------------------------------------------------------------
# Entrada del usuario
# ---------------------------------------------------------------------------

function Read-Opcion {
    <#  Muestra opciones numeradas y devuelve la clave elegida.
        $Opciones es una lista de @{ Clave='1'; Texto='...'; Nota='...' } #>
    param(
        [string]$Titulo,
        [array]$Opciones,
        [string]$Ayuda
    )
    while ($true) {
        Write-Host ''
        if ($Titulo) {
            Write-Host "  $Titulo" -ForegroundColor White
            Write-Regla
        }
        foreach ($o in $Opciones) {
            Write-Host '    ' -NoNewline
            Write-Host $o.Clave.PadRight(3) -NoNewline -ForegroundColor Cyan
            Write-Host $o.Texto -ForegroundColor Gray
            if ($o.Nota) { Write-Host ('        ' + $o.Nota) -ForegroundColor DarkGray }
        }
        if ($Ayuda) {
            Write-Host ''
            Write-Host "  $Ayuda" -ForegroundColor DarkGray
        }
        Write-Host ''
        $r = (Read-Host '  Elige una opción').Trim()
        $match = $Opciones | Where-Object { $_.Clave -ieq $r } | Select-Object -First 1
        if ($match) { return $match.Clave }
        Write-Fallo "'$r' no es una opción válida. Escribe uno de: $(($Opciones | ForEach-Object { $_.Clave }) -join ', ')"
    }
}

function Confirmar {
    param([string]$Pregunta, [bool]$PorDefecto = $false)
    $sufijo = if ($PorDefecto) { '[S/n]' } else { '[s/N]' }
    while ($true) {
        $r = (Read-Host "  $Pregunta $sufijo").Trim().ToLowerInvariant()
        if ($r -eq '') { return $PorDefecto }
        if ($r -in @('s','si','sí','y','yes')) { return $true }
        if ($r -in @('n','no'))                { return $false }
        Write-Fallo "Responde 's' (sí) o 'n' (no)."
    }
}

function Read-Ruta {
    <# Pide una ruta y la valida. Devuelve $null si el usuario cancela. #>
    param(
        [string]$Pregunta,
        [ValidateSet('Carpeta', 'Archivo', 'Cualquiera')] [string]$Tipo = 'Cualquiera',
        [string]$PorDefecto
    )
    while ($true) {
        $prompt = "  $Pregunta"
        if ($PorDefecto) { $prompt += " [$PorDefecto]" }
        $r = (Read-Host $prompt).Trim().Trim('"')
        if ($r -eq '' -and $PorDefecto) { $r = $PorDefecto }
        if ($r -eq '') { Write-Fallo 'No has escrito nada. Escribe una ruta, o "x" para cancelar.'; continue }
        if ($r -ieq 'x') { return $null }

        if (-not (Test-Path -LiteralPath $r)) {
            Write-Fallo "No existe la ruta: $r"
            Write-Info  'Comprueba que la unidad está conectada y que la ruta está bien escrita.'
            Write-Info  'Consejo: puedes arrastrar la carpeta o el archivo a esta ventana para pegar su ruta.'
            Write-Info  'Escribe "x" para cancelar y volver al menú.'
            continue
        }
        $item = Get-Item -LiteralPath $r -Force
        $esCarpeta = $item.PSIsContainer
        if ($Tipo -eq 'Carpeta' -and -not $esCarpeta) {
            Write-Fallo 'Esa ruta es un archivo, y aquí hace falta una carpeta.'; continue
        }
        if ($Tipo -eq 'Archivo' -and $esCarpeta) {
            Write-Fallo 'Esa ruta es una carpeta, y aquí hace falta un archivo.'; continue
        }
        return $item.FullName
    }
}

# ---------------------------------------------------------------------------
# Ejecución con errores explicados
# ---------------------------------------------------------------------------

function Get-Consejo {
    <# Traduce una excepción a un consejo accionable. #>
    param([System.Management.Automation.ErrorRecord]$Err)
    $msg = $Err.Exception.Message
    $tipo = $Err.Exception.GetType().Name

    if ($tipo -eq 'UnauthorizedAccessException' -or $msg -match 'denegado|denied|Access is denied') {
        if (-not $script:EsAdmin) {
            return 'Windows ha denegado el acceso. Vuelve a abrir la herramienta como administrador (opción 8 del menú principal).'
        }
        return 'Windows ha denegado el acceso aunque eres administrador: el archivo puede estar en uso o protegido por el sistema. Se puede omitir sin problema.'
    }
    if ($msg -match 'manifiesto esta vacio|manifiesto está vacío') {
        return 'El escaneo anterior no llegó a escribir nada. Vuelve a escanear (opción 2 o 3) para regenerar el manifiesto.'
    }
    if ($tipo -match 'FileNotFound|DirectoryNotFound|ItemNotFound') {
        return 'La ruta ha dejado de existir. Si es una unidad extraíble o una ISO, comprueba que sigue conectada o montada.'
    }
    if ($msg -match 'no está reconocido|not recognized|CommandNotFound') {
        return 'Falta un comando del sistema. Mount-DiskImage y Mount-WindowsImage vienen con Windows 10/11; en ediciones recortadas pueden no estar.'
    }
    if ($msg -match 'espacio|space') {
        return 'No queda espacio en el disco de destino. Elige otra carpeta para la bóveda (opción 9) o libera espacio.'
    }
    if ($msg -match 'en uso|being used|in use') {
        return 'Otro programa está usando el archivo. Cierra el Explorador de archivos o el reproductor que lo tenga abierto e inténtalo otra vez.'
    }
    return 'Si el problema se repite, anota este mensaje: es lo que hace falta para diagnosticarlo.'
}

function Invoke-Paso {
    <# Ejecuta un bloque capturando errores y explicándolos. Devuelve $true/$false. #>
    param(
        [string]$Descripcion,
        [scriptblock]$Accion,
        [string]$Consejo
    )
    try {
        & $Accion
        return $true
    } catch {
        Write-Host ''
        Write-Fallo "$Descripcion no se pudo completar."
        Write-Host "        Motivo: $($_.Exception.Message)" -ForegroundColor DarkRed
        $c = $Consejo
        if (-not $c) { $c = Get-Consejo -Err $_ }
        Write-Host "        Qué hacer: $c" -ForegroundColor Yellow
        return $false
    }
}

function Get-Manifiesto {
    <#  Lee un manifest.json y devuelve SIEMPRE un array de entradas.
        Windows PowerShell 5.1 serializa algunas colecciones envueltas en un
        objeto con una propiedad 'value', asi que se desenvuelve antes de usarlas. #>
    param([string]$Ruta)
    $crudo = Get-Content -LiteralPath $Ruta -Raw
    if (-not $crudo -or $crudo.Trim().Length -eq 0) {
        throw "El manifiesto esta vacio: $Ruta"
    }
    $datos = $crudo | ConvertFrom-Json
    if ($null -eq $datos) { return @() }
    if (-not ($datos -is [System.Collections.IEnumerable]) -or ($datos -is [string])) {
        $nombres = @($datos.PSObject.Properties.Name)
        foreach ($envoltorio in @('value', 'Value')) {
            if ($nombres -contains $envoltorio) { return @($datos.$envoltorio) }
        }
    }
    return @($datos)
}

function Test-Scripts {
    <# Comprueba que los tres scripts acompañan al launcher. #>
    $faltan = @()
    foreach ($s in @($script:ScriptScan, $script:ScriptExtract, $script:ScriptRestore)) {
        if (-not (Test-Path -LiteralPath $s)) { $faltan += [System.IO.Path]::GetFileName($s) }
    }
    if ($faltan.Count -gt 0) {
        Write-Fallo "Faltan estos archivos junto a AeroTool.ps1: $($faltan -join ', ')"
        Write-Info 'Descarga el proyecto completo y mantén los cuatro .ps1 en la misma carpeta.'
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# Montajes: ISO, WIM, VHD
# ---------------------------------------------------------------------------

function Get-LetraDeImagen {
    param([string]$RutaImagen)
    for ($i = 0; $i -lt 20; $i++) {
        $vol = Get-DiskImage -ImagePath $RutaImagen -ErrorAction SilentlyContinue |
               Get-Volume -ErrorAction SilentlyContinue
        if ($vol -and $vol.DriveLetter) { return "$($vol.DriveLetter):\" }
        Start-Sleep -Milliseconds 400
    }
    return $null
}

function Mount-ImagenDisco {
    <# Monta una ISO/VHD y devuelve la raíz montada, o $null. #>
    param([string]$Ruta)
    Write-Info "Montando $([System.IO.Path]::GetFileName($Ruta))..."
    $ok = Invoke-Paso -Descripcion 'El montaje de la imagen' -Accion {
        Mount-DiskImage -ImagePath $Ruta -ErrorAction Stop | Out-Null
    } -Consejo 'Si la imagen ya está montada, ciérrala desde el Explorador y reinténtalo. Si es un .iso descargado, comprueba que no esté dañado ni bloqueado (clic derecho > Propiedades > Desbloquear).'
    if (-not $ok) { return $null }

    $letra = Get-LetraDeImagen -RutaImagen $Ruta
    if (-not $letra) {
        Write-Fallo 'La imagen se montó pero Windows no le asignó ninguna letra de unidad.'
        Write-Info  'Abre el Explorador para ver si aparece, o usa Administración de discos para asignarle una letra.'
        try { Dismount-DiskImage -ImagePath $Ruta -ErrorAction SilentlyContinue | Out-Null } catch { }
        return $null
    }
    $script:Montajes.Add([pscustomobject]@{ Tipo = 'Imagen'; Ruta = $Ruta; Punto = $letra })
    Write-Exito "Imagen montada en $letra"
    return $letra
}

function Mount-ImagenWindows {
    <# Monta un install.wim en modo solo lectura. Devuelve la carpeta, o $null. #>
    param([string]$RutaWim)

    if ([System.IO.Path]::GetExtension($RutaWim) -ieq '.esd') {
        Write-Aviso 'Es un archivo .esd (comprimido), y Windows no puede montarlo directamente.'
        Write-Info  'Conviértelo antes a .wim con este comando (tarda unos minutos):'
        Write-Host  "        Export-WindowsImage -SourceImagePath '$RutaWim' -SourceIndex 1 -DestinationImagePath 'C:\install.wim' -CompressionType Max" -ForegroundColor Cyan
        return $null
    }
    if (-not $script:EsAdmin) {
        Write-Fallo 'Montar un install.wim requiere permisos de administrador.'
        Write-Info  'Cierra esta ventana y vuelve a abrir la herramienta como administrador (opción 8 del menú principal).'
        return $null
    }

    $imagenes = $null
    $ok = Invoke-Paso -Descripcion 'La lectura del archivo WIM' -Accion {
        $script:TmpImagenes = Get-WindowsImage -ImagePath $RutaWim -ErrorAction Stop
    } -Consejo 'Comprueba que el archivo es un .wim válido y que no está en un medio de solo lectura con errores.'
    if (-not $ok) { return $null }
    $imagenes = $script:TmpImagenes

    if (-not $imagenes -or @($imagenes).Count -eq 0) {
        Write-Fallo 'El WIM no contiene ninguna imagen.'
        return $null
    }

    Write-Info 'Ediciones encontradas dentro del WIM:'
    $opciones = @()
    foreach ($img in $imagenes) {
        Write-Host ('       ' + ([string]$img.ImageIndex).PadRight(3) + $img.ImageName) -ForegroundColor Gray
        $opciones += @{ Clave = [string]$img.ImageIndex; Texto = $img.ImageName }
    }
    $opciones += @{ Clave = 'x'; Texto = 'Cancelar' }
    $idx = Read-Opcion -Titulo 'Elige la edición a montar (cualquiera sirve: los recursos estéticos son los mismos)' -Opciones $opciones
    if ($idx -ieq 'x') { return $null }

    $destino = Join-Path $env:TEMP ('AeroWim_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $destino -Force | Out-Null

    Write-Info 'Montando la imagen en modo solo lectura (puede tardar 1-3 minutos)...'
    $ok = Invoke-Paso -Descripcion 'El montaje del WIM' -Accion {
        Mount-WindowsImage -ImagePath $RutaWim -Index ([int]$idx) -Path $destino -ReadOnly -ErrorAction Stop | Out-Null
    } -Consejo 'Si falla, ejecuta "Dismount-WindowsImage -Path <carpeta> -Discard" sobre montajes anteriores que hayan quedado colgados, o reinicia el equipo.'
    if (-not $ok) {
        Remove-Item -LiteralPath $destino -Force -Recurse -ErrorAction SilentlyContinue
        return $null
    }
    $script:Montajes.Add([pscustomobject]@{ Tipo = 'Wim'; Ruta = $RutaWim; Punto = $destino })
    Write-Exito "WIM montado en $destino"
    return $destino
}

function Dismount-Todo {
    if ($script:Montajes.Count -eq 0) { return }
    Write-Paso 'Desmontando lo que hemos montado'
    foreach ($m in @($script:Montajes)) {
        if ($m.Tipo -eq 'Wim') {
            Invoke-Paso -Descripcion "El desmontaje de $($m.Punto)" -Accion {
                Dismount-WindowsImage -Path $m.Punto -Discard -ErrorAction Stop | Out-Null
                Remove-Item -LiteralPath $m.Punto -Force -Recurse -ErrorAction SilentlyContinue
            } -Consejo 'Cierra cualquier ventana del Explorador abierta en esa carpeta y vuelve a intentarlo.' | Out-Null
        } else {
            Invoke-Paso -Descripcion "El desmontaje de $($m.Ruta)" -Accion {
                Dismount-DiskImage -ImagePath $m.Ruta -ErrorAction Stop | Out-Null
            } -Consejo 'Cierra el Explorador si tiene abierta esa unidad.' | Out-Null
        }
        Write-Exito "Desmontado: $($m.Punto)"
    }
    $script:Montajes.Clear()
}

# ---------------------------------------------------------------------------
# Elección de origen
# ---------------------------------------------------------------------------

function Select-Origen {
    <# Devuelve la raíz a escanear (letra de unidad o carpeta), o $null. #>
    $opciones = @(
        @{ Clave = '1'; Texto = 'Esta instalación de Windows'; Nota = "Escanea $env:SystemDrive\ , incluido Windows.old si existe" }
        @{ Clave = '2'; Texto = 'Otra unidad o carpeta ya accesible'; Nota = 'Un disco antiguo, un USB, un backup... (D:\, E:\, C:\Copias\Win7...)' }
        @{ Clave = '3'; Texto = 'Un archivo ISO'; Nota = 'Lo monto y lo desmonto por ti al terminar' }
        @{ Clave = '4'; Texto = 'Un install.wim de un disco de Vista/7'; Nota = 'La fuente más completa. Requiere administrador' }
        @{ Clave = '5'; Texto = 'Un disco virtual VHD/VHDX'; Nota = 'De una máquina virtual con Vista o 7' }
        @{ Clave = 'x'; Texto = 'Volver al menú' }
    )
    $sel = Read-Opcion -Titulo '¿De dónde quieres rescatar los archivos?' -Opciones $opciones `
        -Ayuda 'Lo ideal es escanear primero esta instalación y luego, si tienes, un disco o ISO de Vista/7: todo se acumula en la misma bóveda.'

    switch ($sel) {
        '1' { return "$env:SystemDrive\" }
        '2' {
            Write-Host ''
            Write-Info 'Escribe la letra de la unidad (por ejemplo D:\) o la ruta de una carpeta.'
            return Read-Ruta -Pregunta 'Ruta a escanear' -Tipo 'Carpeta'
        }
        '3' {
            if (-not $script:EsWindows) { Write-Fallo 'Montar ISOs solo funciona en Windows.'; return $null }
            Write-Host ''
            $iso = Read-Ruta -Pregunta 'Ruta del archivo .iso' -Tipo 'Archivo'
            if (-not $iso) { return $null }
            $raiz = Mount-ImagenDisco -Ruta $iso
            if (-not $raiz) { return $null }

            # En un disco de Vista/7 lo valioso está dentro de sources\install.wim
            $wim = Join-Path $raiz 'sources\install.wim'
            $esd = Join-Path $raiz 'sources\install.esd'
            if (Test-Path -LiteralPath $wim) {
                Write-Host ''
                Write-Aviso 'He encontrado sources\install.wim dentro de la ISO.'
                Write-Info  'La raíz de la ISO casi no tiene recursos estéticos: están todos dentro del WIM.'
                if (Confirmar -Pregunta '¿Monto el install.wim para rescatarlo todo? (recomendado)' -PorDefecto $true) {
                    $m = Mount-ImagenWindows -RutaWim $wim
                    if ($m) { return $m }
                    Write-Aviso 'Sigo con la raíz de la ISO, aunque encontraré mucho menos.'
                }
            } elseif (Test-Path -LiteralPath $esd) {
                Write-Host ''
                Mount-ImagenWindows -RutaWim $esd | Out-Null
                Write-Aviso 'Sigo con la raíz de la ISO.'
            }
            return $raiz
        }
        '4' {
            if (-not $script:EsWindows) { Write-Fallo 'Montar imágenes WIM solo funciona en Windows.'; return $null }
            Write-Host ''
            $wim = Read-Ruta -Pregunta 'Ruta del archivo .wim (normalmente sources\install.wim)' -Tipo 'Archivo'
            if (-not $wim) { return $null }
            return Mount-ImagenWindows -RutaWim $wim
        }
        '5' {
            if (-not $script:EsWindows) { Write-Fallo 'Montar discos virtuales solo funciona en Windows.'; return $null }
            Write-Host ''
            $vhd = Read-Ruta -Pregunta 'Ruta del archivo .vhd o .vhdx' -Tipo 'Archivo'
            if (-not $vhd) { return $null }
            return Mount-ImagenDisco -Ruta $vhd
        }
        default { return $null }
    }
}

# ---------------------------------------------------------------------------
# Acciones del menú
# ---------------------------------------------------------------------------

function Do-Escanear {
    param([string]$RaizForzada, [switch]$SinPausa)

    if (-not (Test-Scripts)) { Pausar; return $false }

    $raiz = $RaizForzada
    if (-not $raiz) { $raiz = Select-Origen }
    if (-not $raiz) { return $false }

    Write-Paso "Preparando el escaneo de: $raiz"

    if (-not (Test-Path -LiteralPath (Join-Path $raiz 'Windows'))) {
        Write-Aviso "No veo una carpeta 'Windows' dentro de $raiz."
        Write-Info  'El escaneo funcionará igual, pero seguramente no encuentre nada.'
        Write-Info  'Si es una ISO de instalación, lo que buscas está dentro de sources\install.wim (opción 4 del menú de origen).'
        if (-not (Confirmar -Pregunta '¿Sigo de todas formas?' -PorDefecto $false)) { return $false }
    }

    $winsxs = $false
    Write-Host ''
    Write-Info 'WinSxS es el almacén de componentes de Windows. Si actualizaste desde 7,'
    Write-Info 'guarda miles de restos de esa época... pero escanearlo tarda varios minutos.'
    $winsxs = Confirmar -Pregunta '¿Incluir WinSxS? (más completo, más lento)' -PorDefecto $false

    Write-Paso 'Escaneando'
    Write-Info 'Puedes interrumpir en cualquier momento con Ctrl+C; lo ya copiado se conserva.'
    Write-Host ''

    $parametros = @{ Root = $raiz; OutputDir = $script:Boveda }
    if ($winsxs) { $parametros['IncludeWinSxS'] = $true }

    $ok = Invoke-Paso -Descripcion 'El escaneo' -Accion {
        & $script:ScriptScan @parametros
    } -Consejo 'Si el error menciona permisos, vuelve a abrir la herramienta como administrador. Si menciona espacio, elige otra carpeta de bóveda (opción 9).'

    if ($ok) {
        $script:Origen = $raiz
        Write-Host ''
        Write-Exito "Escaneo terminado. Bóveda: $script:Boveda"
    }
    if (-not $SinPausa) { Pausar }
    return $ok
}

function Do-Extraer {
    param([switch]$SinPausa)

    if (-not (Test-Scripts)) { Pausar; return $false }
    if (-not $script:EsWindows) {
        Write-Fallo 'La extracción de recursos usa la API de Windows y solo funciona en Windows.'
        if (-not $SinPausa) { Pausar }
        return $false
    }
    $manifiesto = Join-Path $script:Boveda 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifiesto)) {
        Write-Fallo "No encuentro el manifiesto: $manifiesto"
        Write-Info  'Ejecuta primero un escaneo (opción 2 o 3 del menú principal).'
        if (-not $SinPausa) { Pausar }
        return $false
    }

    Write-Paso 'Extrayendo los recursos incrustados en las DLL'
    Write-Info 'Muchos iconos y texturas Aero no son archivos sueltos: viven dentro de'
    Write-Info 'imageres.dll, shell32.dll o aero.msstyles. Esto los saca como PNG, ICO y WAV.'
    Write-Host ''

    $destino = Join-Path $script:Raiz 'AeroExtracted'
    $ok = Invoke-Paso -Descripcion 'La extracción' -Accion {
        & $script:ScriptExtract -FromManifest $manifiesto -OutputDir $destino
    } -Consejo 'Si ninguna DLL se pudo abrir, comprueba que el escaneo marcó candidatos (categoría CandidatoExtraccion en el manifiesto).'

    if ($ok) { Write-Exito "Recursos extraídos en $destino" }
    if (-not $SinPausa) { Pausar }
    return $ok
}

function Do-Restaurar {
    param([switch]$SinPausa)

    if (-not (Test-Scripts)) { Pausar; return $false }
    if (-not $script:EsWindows) {
        Write-Fallo 'La restauración solo funciona sobre un Windows en marcha.'
        if (-not $SinPausa) { Pausar }
        return $false
    }
    if (-not (Test-Path -LiteralPath $script:Boveda)) {
        Write-Fallo "No existe la bóveda: $script:Boveda"
        Write-Info  'Ejecuta primero un escaneo (opción 2 o 3 del menú principal).'
        if (-not $SinPausa) { Pausar }
        return $false
    }

    $piezas = @(
        @{ Clave = '1'; Sw = 'Wallpaper';    Texto = 'Fondo de escritorio';                   Nota = 'El "Armonía" de Windows 7 u otro de la bóveda' }
        @{ Clave = '2'; Sw = 'Sounds';       Texto = 'Esquema de sonidos de Windows 7';       Nota = 'Queda registrado como "Frutiger Aero" en el panel de sonidos' }
        @{ Clave = '3'; Sw = 'Cursors';      Texto = 'Cursores Aero';                          Nota = 'Los punteros vidriosos de Vista' }
        @{ Clave = '4'; Sw = 'Screensaver';  Texto = 'Protector de pantalla';                  Nota = 'Burbujas, o Aurora de Vista si está en la bóveda' }
        @{ Clave = '5'; Sw = 'SampleMedia';  Texto = 'Medios de muestra';                      Nota = 'Koala.jpg, Kalimba.mp3, Wildlife.wmv... a C:\Users\Public' }
        @{ Clave = '6'; Sw = 'StartupSound'; Texto = 'Sonido de inicio de sesión';             Nota = 'El "pearl" de Vista/7. La parte global pide administrador' }
        @{ Clave = '7'; Sw = 'Theme';        Texto = 'Tema "Frutiger Aero (Recuperado)"';      Nota = 'Ata todo lo anterior en un tema de Windows' }
    )

    Write-Paso '¿Qué quieres restablecer como predeterminado?'
    foreach ($p in $piezas) {
        Write-Host '    ' -NoNewline
        Write-Host $p.Clave.PadRight(3) -NoNewline -ForegroundColor Cyan
        Write-Host $p.Texto -ForegroundColor Gray
        Write-Host ('        ' + $p.Nota) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '    T  Todo lo anterior' -ForegroundColor Cyan
    Write-Host '    x  Cancelar' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Puedes elegir varias separándolas por comas. Ejemplo: 1,2,3' -ForegroundColor DarkGray

    $sw = @{}
    while ($true) {
        Write-Host ''
        $r = (Read-Host '  Tu elección').Trim()
        if ($r -ieq 'x' -or $r -eq '') { return $false }
        if ($r -ieq 't') {
            $sw = @{ All = $true }
            break
        }
        $claves = $r -split '[,\s]+' | Where-Object { $_ }
        $malas = @($claves | Where-Object { $c = $_; -not ($piezas | Where-Object { $_.Clave -eq $c }) })
        if ($malas.Count -gt 0) {
            Write-Fallo "No reconozco: $($malas -join ', '). Usa números del 1 al 7, 'T' para todo o 'x' para cancelar."
            continue
        }
        foreach ($c in $claves) {
            $p = $piezas | Where-Object { $_.Clave -eq $c } | Select-Object -First 1
            $sw[$p.Sw] = $true
        }
        break
    }

    if ($sw.ContainsKey('StartupSound') -and -not $script:EsAdmin) {
        Write-Host ''
        Write-Aviso 'Has pedido el sonido de inicio, pero no eres administrador.'
        Write-Info  'Se programará el sonido al iniciar sesión (eso sí funciona), pero no se podrá'
        Write-Info  'reactivar el sonido de arranque global del sistema.'
        if (-not (Confirmar -Pregunta '¿Continuar igualmente?' -PorDefecto $true)) { return $false }
    }

    # Vista previa obligatoria antes de tocar nada
    Write-Paso 'Vista previa: esto es lo que se haría (todavía no se cambia nada)'
    Write-Host ''
    $ok = Invoke-Paso -Descripcion 'La vista previa' -Accion {
        & $script:ScriptRestore -Vault $script:Boveda @sw -WhatIf
    }
    if (-not $ok) { if (-not $SinPausa) { Pausar }; return $false }

    Write-Host ''
    Write-Info 'Todo esto es reversible: antes de aplicar se guarda tu aspecto actual,'
    Write-Info 'y la opción 7 del menú principal lo devuelve tal y como estaba.'
    Write-Host ''
    if (-not (Confirmar -Pregunta '¿Aplico estos cambios ahora?' -PorDefecto $false)) {
        Write-Info 'No se ha cambiado nada.'
        if (-not $SinPausa) { Pausar }
        return $false
    }

    Write-Paso 'Aplicando'
    Write-Host ''
    $ok = Invoke-Paso -Descripcion 'La restauración' -Accion {
        & $script:ScriptRestore -Vault $script:Boveda @sw
    } -Consejo 'Si el error menciona el registro, cierra otras herramientas de personalización e inténtalo de nuevo.'

    if ($ok) {
        Write-Host ''
        Write-Exito '¡Listo! Bienvenido de vuelta a 2007.'
        Write-Info  'Algunos cambios (sonidos, cursores) se ven del todo al cerrar y volver a iniciar sesión.'
    }
    if (-not $SinPausa) { Pausar }
    return $ok
}

function Do-Revertir {
    if (-not (Test-Scripts)) { Pausar; return }
    if (-not $script:EsWindows) {
        Write-Fallo 'Solo se puede revertir sobre un Windows en marcha.'
        Pausar; return
    }
    Write-Paso 'Deshacer los cambios'
    Write-Info 'Devuelve el fondo, los cursores, los sonidos y el protector de pantalla'
    Write-Info 'al estado que tenían antes de usar esta herramienta por primera vez.'
    Write-Info 'Los archivos rescatados en la bóveda NO se borran.'
    Write-Host ''
    if (-not (Confirmar -Pregunta '¿Deshacer los cambios?' -PorDefecto $false)) {
        Write-Info 'No se ha cambiado nada.'
        Pausar; return
    }
    Write-Host ''
    Invoke-Paso -Descripcion 'La reversión' -Accion {
        & $script:ScriptRestore -Revert
    } -Consejo 'Si no aparece el respaldo, puedes volver al aspecto original en Configuración > Personalización > Temas.' | Out-Null
    Pausar
}

function Do-VerBoveda {
    Write-Paso 'Contenido de la bóveda'
    $manifiesto = Join-Path $script:Boveda 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifiesto)) {
        Write-Fallo "Todavía no hay nada: no encuentro $manifiesto"
        Write-Info  'Ejecuta primero un escaneo (opción 2 o 3).'
        Pausar; return
    }
    $ok = Invoke-Paso -Descripcion 'La lectura del manifiesto' -Accion {
        $m = Get-Manifiesto -Ruta $manifiesto
        if ($m.Count -eq 0) {
            Write-Host ''
            Write-Aviso 'El manifiesto no contiene ninguna entrada.'
            Write-Info  'Vuelve a escanear (opción 2 o 3): puede que el anterior no encontrara nada.'
            return
        }
        $propiedades = @($m[0].PSObject.Properties.Name)
        if ($propiedades -notcontains 'Era' -or $propiedades -notcontains 'Categoria') {
            Write-Host ''
            Write-Aviso 'El manifiesto no tiene el formato esperado: le faltan Era o Categoria.'
            Write-Info  "Propiedades encontradas: $($propiedades -join ', ')"
            Write-Info  'Seguramente lo generó otra versión de la herramienta. Vuelve a escanear para regenerarlo.'
            return
        }

        # Se agrupa a mano en lugar de con Group-Object / Measure-Object: en Windows
        # PowerShell 5.1 esos cmdlets abortan con 'el valor del argumento "Property"
        # no es válido' si alguna entrada no trae la propiedad pedida.
        $grupos = @{}
        $totalBytes = [long]0
        foreach ($e in $m) {
            $era = [string]$e.Era
            if (-not $era) { $era = '(sin era)' }
            $cat = [string]$e.Categoria
            if (-not $cat) { $cat = '(sin categoría)' }
            $bytes = [long]0
            if ($null -ne $e.TamanoBytes) {
                [void][long]::TryParse([string]$e.TamanoBytes, [ref]$bytes)
            }
            $clave = $era + '|' + $cat
            if (-not $grupos.ContainsKey($clave)) {
                $grupos[$clave] = [pscustomobject]@{ Era = $era; Categoria = $cat; Archivos = 0; Bytes = [long]0 }
            }
            $grupos[$clave].Archivos++
            $grupos[$clave].Bytes += $bytes
            $totalBytes += $bytes
        }

        Write-Host ''
        Write-Host '     Era            Categoría              Archivos     Tamaño' -ForegroundColor White
        Write-Host '     ------------------------------------------------------------' -ForegroundColor DarkGray
        foreach ($g in ($grupos.Values | Sort-Object Era, Categoria)) {
            $mb = [math]::Round($g.Bytes / 1MB, 1)
            Write-Host ('     {0,-14} {1,-22} {2,8}   {3,7} MB' -f $g.Era, $g.Categoria, $g.Archivos, $mb) -ForegroundColor Gray
        }
        Write-Host '     ------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host ('     {0,-37} {1,8}   {2,7} MB' -f 'TOTAL', $m.Count, [math]::Round($totalBytes / 1MB, 1)) -ForegroundColor Green

        $conHash = @($m | Where-Object { $_.SHA256 }).Count
        Write-Host ''
        Write-Info "$conHash de $($m.Count) archivos tienen hash SHA-256 registrado para verificar su integridad."
    }
    if ($ok -and $script:EsWindows) {
        Write-Host ''
        if (Confirmar -Pregunta '¿Abro la carpeta en el Explorador?' -PorDefecto $false) {
            Start-Process explorer.exe $script:Boveda
        }
    }
    Pausar
}

function Do-Diagnostico {
    Write-Paso 'Comprobación del sistema'
    Write-Host ''

    $psv = $PSVersionTable.PSVersion
    if ($psv.Major -ge 5) { Write-Exito "PowerShell $psv" }
    else { Write-Fallo "PowerShell $psv es demasiado antiguo (hace falta 5.1 o superior)." }

    if ($script:EsWindows) {
        $os = 'Windows'
        try { $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { }
        Write-Exito "Sistema: $os"
    } else {
        Write-Aviso "Sistema: $([System.Environment]::OSVersion.Platform) (no es Windows)"
        Write-Info  'Aquí solo funciona el escaneo sobre un disco montado. Restaurar y extraer requieren Windows.'
    }

    if ($script:EsAdmin) {
        Write-Exito 'Permisos: administrador'
    } else {
        Write-Aviso 'Permisos: usuario normal'
        Write-Info  'Suficiente para casi todo. Hace falta administrador para montar install.wim,'
        Write-Info  'para leer partes de WinSxS y para reactivar el sonido de arranque global.'
    }

    try {
        $pol = Get-ExecutionPolicy
        if ($pol -in @('Restricted', 'AllSigned')) {
            Write-Aviso "Directiva de ejecución: $pol (restrictiva)"
            Write-Info  'Si algún script se niega a ejecutarse, abre PowerShell y escribe:'
            Write-Host  '        Set-ExecutionPolicy -Scope Process Bypass' -ForegroundColor Cyan
        } else {
            Write-Exito "Directiva de ejecución: $pol"
        }
    } catch { }

    if ($script:EsWindows) {
        if (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue) {
            Write-Exito 'Montaje de ISO/VHD disponible (Mount-DiskImage)'
        } else {
            Write-Aviso 'Mount-DiskImage no está disponible: no podrás montar ISOs desde aquí.'
        }
        if (Get-Command Mount-WindowsImage -ErrorAction SilentlyContinue) {
            Write-Exito 'Montaje de imágenes WIM disponible (DISM)'
        } else {
            Write-Aviso 'Mount-WindowsImage no está disponible: no podrás montar install.wim desde aquí.'
        }
    }

    foreach ($s in @($script:ScriptScan, $script:ScriptExtract, $script:ScriptRestore)) {
        $n = [System.IO.Path]::GetFileName($s)
        if (Test-Path -LiteralPath $s) { Write-Exito "Componente presente: $n" }
        else { Write-Fallo "Falta el componente: $n" }
    }

    try {
        $unidad = [System.IO.Path]::GetPathRoot($script:Boveda)
        $libre = (Get-PSDrive -Name $unidad.TrimEnd(':\/') -ErrorAction Stop).Free
        $libreGB = [math]::Round($libre / 1GB, 1)
        if ($libreGB -lt 1) { Write-Aviso "Espacio libre en $unidad : $libreGB GB (muy justo)" }
        else { Write-Exito "Espacio libre en $unidad : $libreGB GB" }
    } catch { }

    if ($script:EsWindows -and -not $script:EsAdmin) {
        Write-Host ''
        if (Confirmar -Pregunta '¿Quieres reabrir la herramienta como administrador?' -PorDefecto $false) {
            $ok = Invoke-Paso -Descripcion 'La elevación de permisos' -Accion {
                $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
                Start-Process powershell.exe -ArgumentList $argumentos -Verb RunAs -ErrorAction Stop
            } -Consejo 'Si aparece un aviso de Control de cuentas de usuario, acéptalo. Si lo rechazaste, vuelve a intentarlo.'
            if ($ok) {
                Write-Exito 'Se ha abierto una ventana nueva como administrador. Puedes cerrar esta.'
                Pausar
                Dismount-Todo
                exit 0
            }
        }
    }
    Pausar
}

function Do-CambiarBoveda {
    Write-Paso 'Cambiar la carpeta de la bóveda'
    Write-Info "Actual: $script:Boveda"
    Write-Info 'Escribe una ruta nueva (se creará si no existe), o "x" para cancelar.'
    Write-Host ''
    $r = (Read-Host '  Nueva ruta de la bóveda').Trim().Trim('"')
    if ($r -eq '' -or $r -ieq 'x') { Write-Info 'Sin cambios.'; Pausar; return }

    # La bóveda actual solo se sustituye si la nueva ruta queda realmente utilizable.
    $script:BovedaNueva = $null
    $ok = Invoke-Paso -Descripcion 'La creación de la carpeta' -Accion {
        if (-not (Test-Path -LiteralPath $r)) { New-Item -ItemType Directory -Path $r -Force | Out-Null }
        $script:BovedaNueva = (Resolve-Path -LiteralPath $r).Path
    } -Consejo 'Comprueba que la unidad existe, está conectada y no es de solo lectura.'

    if ($ok -and $script:BovedaNueva) {
        $script:Boveda = $script:BovedaNueva
        Write-Exito "Bóveda: $script:Boveda"
    } else {
        Write-Info "Sin cambios. La bóveda sigue siendo: $script:Boveda"
    }
    Pausar
}

function Do-Ayuda {
    Show-Cabecera
    Write-Paso '¿Qué es esto?'
    Write-Host ''
    Write-Info 'Windows Vista y 7 trajeron una estética hoy conocida como "Frutiger Aero":'
    Write-Info 'cristal, brillos, burbujas, naturaleza saturada. Windows 11 la retiró casi'
    Write-Info 'toda, y con cada actualización desaparecen más restos. Esta herramienta:'
    Write-Host ''
    Write-Host '     1. ENCUENTRA esos archivos donde queden (tu PC, un disco viejo, una ISO).' -ForegroundColor Gray
    Write-Host '     2. LOS ARCHIVA con su hash, para que no se conviertan en lost media.' -ForegroundColor Gray
    Write-Host '     3. LOS DEVUELVE como predeterminados en Windows 11, de forma reversible.' -ForegroundColor Gray
    Write-Host ''
    Write-Paso 'Eso que ves al arrancar no son imaginaciones tuyas'
    Write-Host ''
    Write-Info 'Mucha gente ve, durante el arranque de Windows 11, la barra de progreso'
    Write-Info 'clásica y por un instante una barra de tareas al estilo Vista. Es real:'
    Write-Host ''
    Write-Host '     - La barra clásica vive en los recursos del cargador (bootres.dll) y sale' -ForegroundColor Gray
    Write-Host '       cuando el arranque cae al modo de respaldo.' -ForegroundColor Gray
    Write-Host '     - Al iniciar sesión, el Explorador se dibuja unos fotogramas ANTES de que' -ForegroundColor Gray
    Write-Host '       el motor de temas y DWM terminen de cargar, y enseña el estilo básico' -ForegroundColor Gray
    Write-Host '       heredado: el mismo camino de dibujado que existe desde Vista.' -ForegroundColor Gray
    Write-Host ''
    Write-Info 'Windows 11 todavía distribuye cursores aero_*, los esquemas de sonido de'
    Write-Info 'Windows 7 y iconos de Vista dentro de imageres.dll. Eso es lo que rescatamos.'
    Write-Host ''
    Write-Paso 'Lo que esta herramienta NO hace'
    Write-Host ''
    Write-Info 'El cristal Aero real (barra de tareas translúcida, bordes con desenfoque)'
    Write-Info 'exige parchear la comprobación de firmas de Windows con software de terceros:'
    Write-Info 'puede romper el arranque tras cualquier actualización. Queda fuera a propósito.'
    Write-Info 'Aun así, la bóveda conserva los .msstyles originales: la preservación es completa.'
    Write-Host ''
    Write-Paso 'Seguridad'
    Write-Host ''
    Write-Info 'El escaneo y la extracción son de SOLO LECTURA: nunca modifican el origen.'
    Write-Info 'La restauración solo escribe en tu perfil de usuario, guarda tu aspecto previo'
    Write-Info 'y siempre te enseña una vista previa antes de tocar nada.'
    Pausar
}

# ---------------------------------------------------------------------------
# Asistente guiado
# ---------------------------------------------------------------------------

function Do-Asistente {
    Show-Cabecera
    Write-Host '  ASISTENTE GUIADO' -ForegroundColor White
    Write-Regla
    Write-Info 'Te llevo por todo el proceso. En cada paso puedes decir que no.'
    Write-Info 'Nada se cambia en tu sistema sin que lo confirmes antes.'
    Pausar

    # Paso 1 -----------------------------------------------------------------
    Show-Cabecera
    Write-Host '  PASO 1 de 5  -  Comprobando que todo está en su sitio' -ForegroundColor White
    Write-Regla
    if (-not (Test-Scripts)) { Pausar; return }
    Write-Exito "PowerShell $($PSVersionTable.PSVersion)"
    if ($script:EsAdmin) { Write-Exito 'Tienes permisos de administrador' }
    else { Write-Aviso 'No eres administrador: podrás hacer casi todo, pero no montar install.wim' }
    Write-Exito 'Los cuatro componentes están presentes'
    Pausar

    # Paso 2 -----------------------------------------------------------------
    Show-Cabecera
    Write-Host '  PASO 2 de 5  -  ¿De dónde rescatamos los archivos?' -ForegroundColor White
    Write-Regla
    Write-Info 'Empezamos por tu instalación actual: aún guarda cursores, sonidos y'
    Write-Info 'protectores de la era Aero, y quizá un Windows.old entero.'
    if (-not (Do-Escanear -RaizForzada "$env:SystemDrive\" -SinPausa)) {
        Write-Aviso 'El escaneo inicial no terminó bien; puedes reintentarlo desde el menú.'
        Pausar
        return
    }
    Pausar

    Show-Cabecera
    Write-Host '  PASO 2 de 5  -  ¿Tienes además un disco o una ISO de Vista/7?' -ForegroundColor White
    Write-Regla
    Write-Info 'Es la fuente completa: fondos originales, DreamScene, medios de muestra...'
    Write-Info 'Todo se acumula en la misma bóveda, sin duplicados.'
    Write-Host ''
    if (Confirmar -Pregunta '¿Quieres añadir otro origen ahora?' -PorDefecto $false) {
        Do-Escanear -SinPausa | Out-Null
        Pausar
    }

    # Paso 3 -----------------------------------------------------------------
    Show-Cabecera
    Write-Host '  PASO 3 de 5  -  Sacar los recursos escondidos dentro de las DLL' -ForegroundColor White
    Write-Regla
    Write-Info 'Los iconos vidriosos y las texturas del tema no son archivos sueltos:'
    Write-Info 'están incrustados en imageres.dll, shell32.dll y aero.msstyles.'
    Write-Host ''
    if (Confirmar -Pregunta '¿Los extraigo? (recomendado, solo lectura)' -PorDefecto $true) {
        Do-Extraer -SinPausa | Out-Null
        Pausar
    }

    # Paso 4 -----------------------------------------------------------------
    Show-Cabecera
    Write-Host '  PASO 4 de 5  -  Ver lo que hemos rescatado' -ForegroundColor White
    Write-Regla
    Do-VerBoveda

    # Paso 5 -----------------------------------------------------------------
    Show-Cabecera
    Write-Host '  PASO 5 de 5  -  Devolver la era Frutiger Aero a Windows 11' -ForegroundColor White
    Write-Regla
    Write-Info 'Ahora podemos poner todo esto como predeterminado. Verás primero una'
    Write-Info 'vista previa, y siempre podrás deshacerlo con la opción 7 del menú.'
    Write-Host ''
    if (Confirmar -Pregunta '¿Pasamos a la restauración?' -PorDefecto $true) {
        Do-Restaurar -SinPausa | Out-Null
    } else {
        Write-Info 'Sin problema: la bóveda queda guardada y puedes restaurar cuando quieras.'
    }

    Write-Host ''
    Write-Regla
    Write-Exito 'Asistente terminado.'
    Write-Info  "Tus archivos rescatados viven en: $script:Boveda"
    Write-Info  'Guárdalos en un disco externo o en la nube: es la mejor forma de que no se pierdan.'
    Pausar
}

# ---------------------------------------------------------------------------
# Bucle principal
# ---------------------------------------------------------------------------

function Start-Menu {
    while ($true) {
        Show-Cabecera
        $opciones = @(
            @{ Clave = '1'; Texto = 'Asistente guiado  (empieza por aquí)'; Nota = 'Te lleva paso a paso por todo el proceso' }
            @{ Clave = '2'; Texto = 'Escanear esta instalación de Windows'; Nota = "Rescata lo que quede en $env:SystemDrive\" }
            @{ Clave = '3'; Texto = 'Escanear otro origen'; Nota = 'Disco antiguo, carpeta, ISO, install.wim o VHD' }
            @{ Clave = '4'; Texto = 'Extraer los recursos incrustados en las DLL'; Nota = 'Iconos, texturas y sonidos dentro de imageres.dll y compañía' }
            @{ Clave = '5'; Texto = 'Restaurar en Windows 11'; Nota = 'Fondo, sonidos, cursores, tema... con vista previa antes de aplicar' }
            @{ Clave = '6'; Texto = 'Ver el contenido de la bóveda'; Nota = 'Resumen de todo lo rescatado' }
            @{ Clave = '7'; Texto = 'Deshacer los cambios'; Nota = 'Vuelve al aspecto que tenías antes' }
            @{ Clave = '8'; Texto = 'Comprobar el sistema'; Nota = 'Permisos, versiones, componentes... y reabrir como administrador' }
            @{ Clave = '9'; Texto = 'Cambiar la carpeta de la bóveda' }
            @{ Clave = '?'; Texto = '¿Qué es esto? / Ayuda' }
            @{ Clave = '0'; Texto = 'Salir' }
        )
        $sel = Read-Opcion -Titulo 'MENÚ PRINCIPAL' -Opciones $opciones

        # Un fallo inesperado dentro de una opción vuelve al menú en vez de cerrar
        # la herramienta: así no se pierde la bóveda ni los montajes en curso.
        try {
            switch ($sel) {
                '1' { Do-Asistente }
                '2' { Do-Escanear -RaizForzada "$env:SystemDrive\" | Out-Null }
                '3' { Do-Escanear | Out-Null }
                '4' { Do-Extraer | Out-Null }
                '5' { Do-Restaurar | Out-Null }
                '6' { Do-VerBoveda }
                '7' { Do-Revertir }
                '8' { Do-Diagnostico }
                '9' { Do-CambiarBoveda }
                '?' { Do-Ayuda }
                '0' {
                    Dismount-Todo
                    Write-Host ''
                    Write-Host '  Gracias por preservar la era Frutiger Aero. Hasta la próxima.' -ForegroundColor Cyan
                    Write-Host ''
                    return
                }
            }
        } catch {
            Write-Host ''
            Write-Fallo 'Esa opción se ha interrumpido por un error inesperado.'
            Write-Host "        Motivo: $($_.Exception.Message)" -ForegroundColor DarkRed
            Write-Host "        Dónde:  línea $($_.InvocationInfo.ScriptLineNumber) de $([System.IO.Path]::GetFileName($_.InvocationInfo.ScriptName))" -ForegroundColor DarkGray
            Write-Host "        Qué hacer: $(Get-Consejo -Err $_)" -ForegroundColor Yellow
            Write-Info 'Vuelves al menú; no se ha perdido nada de lo ya rescatado.'
            Pausar
        }
    }
}

try {
    Start-Menu
} catch {
    Write-Host ''
    Write-Fallo 'La herramienta se ha detenido por un error inesperado.'
    Write-Host "        Motivo: $($_.Exception.Message)" -ForegroundColor DarkRed
    Write-Host "        Dónde:  $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Write-Host "        Qué hacer: $(Get-Consejo -Err $_)" -ForegroundColor Yellow
    Write-Host ''
} finally {
    Dismount-Todo
}
