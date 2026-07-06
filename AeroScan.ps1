#Requires -Version 5.1
<#
.SYNOPSIS
    Escanea una instalacion de Windows en busca de archivos de la era Frutiger Aero
    (Windows Vista / Windows 7) y los archiva en una "boveda" de preservacion.

.DESCRIPTION
    Recorre las rutas donde viven (o sobreviven) los recursos esteticos de la era
    Frutiger Aero: fondos de pantalla, sonidos, cursores Aero, temas .theme/.msstyles,
    protectores de pantalla, videos DreamScene, imagenes/musica/videos de muestra,
    gadgets de Windows Sidebar, restos en Windows.old y componentes antiguos en WinSxS.

    Cada archivo se clasifica por era:
      - Vista         : version PE 6.0.6000-6.0.6003 o nombre conocido de Vista.
      - Win7          : version PE 6.1.7600-6.1.7799 o nombre conocido de Windows 7.
      - Superviviente : recurso de la era Aero que Windows 10/11 todavia incluye
                        (cursores aero_*, esquemas de sonido de Win7, Bubbles.scr, etc.).
      - Moderno       : archivo actual sin valor de preservacion (no se copia).

    Los archivos Vista/Win7/Superviviente se copian a la boveda (-OutputDir) con su
    hash SHA-256 y se genera un manifiesto JSON + CSV. Ademas se marcan como
    "CandidatoExtraccion" las DLL que contienen recursos legado incrustados
    (imageres.dll, shell32.dll, aero.msstyles...) para procesarlas con AeroExtract.ps1.

    El script SOLO LEE del sistema analizado: nunca modifica ni borra nada.

.PARAMETER Root
    Raiz del volumen o carpeta a analizar. Por defecto, la unidad del sistema (C:\).
    Puede apuntar a un disco viejo (D:\), una imagen montada de Vista/7, o una
    carpeta que contenga un arbol "Windows".

.PARAMETER OutputDir
    Carpeta de la boveda donde se copian los hallazgos. Por defecto .\AeroVault.

.PARAMETER IncludeWinSxS
    Incluye el almacen de componentes WinSxS (lento; util tras una actualizacion
    in-place desde 7, donde quedan miles de restos con version 6.0/6.1).

.PARAMETER ManifestOnly
    Solo genera el manifiesto, sin copiar archivos.

.PARAMETER NoHash
    Omite el calculo de SHA-256 (mas rapido).

.EXAMPLE
    .\AeroScan.ps1
    Escanea C:\ y guarda los hallazgos en .\AeroVault.

.EXAMPLE
    .\AeroScan.ps1 -Root E:\ -OutputDir D:\PreservacionAero -IncludeWinSxS
    Escanea un disco viejo con Windows 7 montado como E:\.
#>
[CmdletBinding()]
param(
    [string]$Root = "$env:SystemDrive\",
    [string]$OutputDir = (Join-Path (Get-Location).Path 'AeroVault'),
    [switch]$IncludeWinSxS,
    [switch]$ManifestOnly,
    [switch]$NoHash
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Catalogo de nombres conocidos (en minusculas)
# ---------------------------------------------------------------------------

# Medios de muestra exclusivos de Windows Vista
$KnownVistaFiles = @(
    # Sample Pictures
    'autumn leaves.jpg','creek.jpg','desert landscape.jpg','dock.jpg',
    'forest flowers.jpg','forest.jpg','frangipani flowers.jpg','garden.jpg',
    'green sea turtle.jpg','humpback whale.jpg','oryx antelope.jpg',
    'toco toucan.jpg','tree.jpg','waterfall.jpg','winter leaves.jpg',
    # Sample Music
    'amanda.wma','despertar.wma','din din wo.wma','distance.wma',
    "i guess you're right.wma",'love comes.wma','muita bobeira.wma',
    "oam's blues.wma",'one step beyond.wma',
    # Sample Videos
    'bear.wmv','butterfly.wmv','lake.wmv',
    # Protector de pantalla exclusivo de Vista
    'aurora.scr'
)

# Medios de muestra exclusivos de Windows 7
$KnownWin7Files = @(
    # Sample Pictures
    'chrysanthemum.jpg','desert.jpg','hydrangeas.jpg','jellyfish.jpg',
    'koala.jpg','lighthouse.jpg','penguins.jpg','tulips.jpg',
    # Sample Music
    'kalimba.mp3','maid with the flaxen hair.mp3','sleep away.mp3',
    # Sample Videos
    'wildlife.wmv'
)

# Recursos de la era Aero que Windows 10/11 aun distribuye
$LegacySurvivorPatterns = @(
    'aero_*',                       # cursores Aero (identicos desde Vista)
    'windows logon*.wav','windows logoff*.wav','windows unlock.wav',
    'windows ding.wav','windows notify*.wav','windows exclamation.wav',
    'windows error.wav','windows critical stop.wav','windows background.wav',
    'windows foreground.wav','windows navigation start.wav',
    'windows hardware *.wav','windows battery *.wav','windows print complete.wav',
    'windows user account control.wav','windows default.wav','windows startup.wav',
    'windows shutdown.wav','windows minimize.wav','windows restore.wav',
    'windows recycle.wav','windows pop-up blocked.wav','windows information bar.wav',
    'windows feed discovered.wav','windows balloon.wav','windows message nudge.wav',
    'tada.wav','chimes.wav','chord.wav','ding.wav','notify.wav','recycle.wav',
    'ringout.wav','ir_*.wav','speech *.wav',
    'bubbles.scr','ribbons.scr','mystify.scr','sstext3d.scr','photoscreensaver.scr',
    'aero.theme','aero.msstyles'
)

# Carpetas de esquemas de sonido introducidas por Windows 7
$Win7SoundSchemeFolders = @(
    'afternoon','calligraphy','characters','cityscape','delta','festival',
    'garden','heritage','landscape','quirky','raga','savanna','sonata'
)

# Carpetas tematicas de fondos de Windows 7
$Win7WallpaperFolders = @('architecture','characters','landscapes','nature','scenes')

# Binarios que contienen recursos legado incrustados: candidatos para AeroExtract.ps1
$ExtractionCandidateNames = @(
    'imageres.dll','shell32.dll','wmploc.dll','ddores.dll','ieframe.dll',
    'authui.dll','spwizimg.dll','bootres.dll','themeui.dll','shellstyle.dll',
    'zipfldr.dll','netshell.dll','wpdshext.dll','mmres.dll','setup.exe',
    'aero.msstyles','aerolite.msstyles','explorerframe.dll','imagesp1.dll',
    'basebrd.dll','winload.exe','winresume.exe'
)

$MediaExtensions = @('.jpg','.jpeg','.png','.bmp','.gif','.wav','.mid','.midi',
                     '.mp3','.wma','.wmv','.mpg','.avi','.cur','.ani','.ico',
                     '.theme','.themepack','.msstyles','.scr','.gadget','.html',
                     '.css','.js','.xml','.dll')

# ---------------------------------------------------------------------------
# Funciones auxiliares
# ---------------------------------------------------------------------------

function Get-PeEra {
    param([System.IO.FileInfo]$File)
    try { $vi = $File.VersionInfo } catch { return $null }
    if ($null -eq $vi) { return $null }
    if ($vi.FileMajorPart -eq 0 -and $vi.FileMinorPart -eq 0 -and $vi.FileBuildPart -eq 0) { return $null }
    if ($vi.FileMajorPart -eq 6 -and $vi.FileMinorPart -eq 0 -and
        $vi.FileBuildPart -ge 6000 -and $vi.FileBuildPart -le 6003) { return 'Vista' }
    if ($vi.FileMajorPart -eq 6 -and $vi.FileMinorPart -eq 1 -and
        $vi.FileBuildPart -ge 7600 -and $vi.FileBuildPart -le 7799) { return 'Win7' }
    return 'Otro'
}

function Get-WindowsRootEra {
    param([string]$WinRoot)
    foreach ($probe in @('System32\kernel32.dll','System32\ntoskrnl.exe','explorer.exe')) {
        $p = Join-Path $WinRoot $probe
        if (Test-Path -LiteralPath $p) {
            $era = Get-PeEra (Get-Item -LiteralPath $p)
            if ($era) { return $era }
        }
    }
    return 'Desconocido'
}

function Get-FileEra {
    param([System.IO.FileInfo]$File, [string]$RootEra)
    $name = $File.Name.ToLowerInvariant()
    $ext  = $File.Extension.ToLowerInvariant()

    if ($ext -in @('.dll','.exe','.scr','.cpl','.msstyles')) {
        $pe = Get-PeEra $File
        if ($pe -eq 'Vista' -or $pe -eq 'Win7') { return $pe }
        if ($pe -eq 'Otro' -and $RootEra -notin @('Vista','Win7')) { return 'Moderno' }
    }

    if ($KnownVistaFiles -contains $name) { return 'Vista' }
    if ($KnownWin7Files  -contains $name) { return 'Win7' }

    # Dentro de un arbol Windows que ES Vista/7, todo recurso multimedia es de esa era
    if ($RootEra -in @('Vista','Win7')) { return $RootEra }

    foreach ($pat in $LegacySurvivorPatterns) {
        if ($name -like $pat) { return 'Superviviente' }
    }

    $parent = (Split-Path -Leaf (Split-Path -Parent $File.FullName)).ToLowerInvariant()
    if ($Win7SoundSchemeFolders -contains $parent -and $ext -eq '.wav') { return 'Superviviente' }
    if ($Win7WallpaperFolders  -contains $parent -and $ext -in @('.jpg','.jpeg','.png')) { return 'Superviviente' }

    return 'Moderno'
}

$script:Manifest = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [System.IO.FileInfo]$File,
        [string]$Category,
        [string]$Era,
        [string]$SourceRoot,
        [bool]$Vault,
        [string]$Note = ''
    )
    $rel = $File.FullName
    if ($rel.ToLowerInvariant().StartsWith($SourceRoot.ToLowerInvariant())) {
        $rel = $rel.Substring($SourceRoot.Length).TrimStart('\','/')
    }
    $hash = $null
    if (-not $NoHash) {
        try { $hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch {}
    }
    $vaultPath = $null
    if ($Vault -and -not $ManifestOnly) {
        $dest = Join-Path (Join-Path (Join-Path $OutputDir $Era) $Category) $rel
        try {
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $File.FullName -Destination $dest -Force -ErrorAction Stop
            $vaultPath = $dest
        } catch {
            Write-Warning "No se pudo copiar $($File.FullName): $($_.Exception.Message)"
        }
    }
    $script:Manifest.Add([pscustomobject]@{
        Nombre       = $File.Name
        Categoria    = $Category
        Era          = $Era
        RutaOriginal = $File.FullName
        RutaRelativa = $rel
        RutaBoveda   = $vaultPath
        TamanoBytes  = $File.Length
        SHA256       = $hash
        Modificado   = $File.LastWriteTimeUtc.ToString('o')
        Nota         = $Note
    })
}

function Scan-Folder {
    param(
        [string]$Folder,
        [string[]]$Extensions,
        [string]$Category,
        [string]$SourceRoot,
        [string]$RootEra,
        [switch]$Recurse
    )
    if (-not (Test-Path -LiteralPath $Folder)) { return }
    Write-Host "  -> $Folder" -ForegroundColor DarkGray
    $items = Get-ChildItem -LiteralPath $Folder -File -Recurse:$Recurse -Force -ErrorAction SilentlyContinue
    foreach ($f in $items) {
        if ($Extensions -and ($f.Extension.ToLowerInvariant() -notin $Extensions)) { continue }
        $era = Get-FileEra -File $f -RootEra $RootEra
        if ($era -in @('Vista','Win7','Superviviente')) {
            Add-Finding -File $f -Category $Category -Era $era -SourceRoot $SourceRoot -Vault $true
        }
    }
}

# ---------------------------------------------------------------------------
# Escaneo principal
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '=== AeroScan: rescate de la era Frutiger Aero ===' -ForegroundColor Cyan
Write-Host "Raiz analizada : $Root"
Write-Host "Boveda         : $OutputDir"
Write-Host ''

if (-not $ManifestOnly -and -not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Arboles Windows a analizar: la instalacion actual y Windows.old si existe
$windowsRoots = @()
foreach ($cand in @((Join-Path $Root 'Windows'), (Join-Path $Root 'Windows.old\Windows'))) {
    if (Test-Path -LiteralPath $cand) { $windowsRoots += $cand }
}
if ($windowsRoots.Count -eq 0) {
    Write-Warning "No se encontro ninguna carpeta 'Windows' bajo $Root"
}

foreach ($winRoot in $windowsRoots) {
    $rootEra = Get-WindowsRootEra -WinRoot $winRoot
    Write-Host "Analizando arbol Windows: $winRoot (era detectada: $rootEra)" -ForegroundColor Yellow

    Scan-Folder -Folder (Join-Path $winRoot 'Web\Wallpaper') `
        -Extensions @('.jpg','.jpeg','.png','.bmp') -Category 'Fondos' `
        -SourceRoot $Root -RootEra $rootEra -Recurse
    Scan-Folder -Folder (Join-Path $winRoot 'Web\Windows DreamScene') `
        -Extensions @('.wmv','.mpg','.avi') -Category 'DreamScene' `
        -SourceRoot $Root -RootEra $rootEra -Recurse
    Scan-Folder -Folder (Join-Path $winRoot 'Media') `
        -Extensions @('.wav','.mid','.midi') -Category 'Sonidos' `
        -SourceRoot $Root -RootEra $rootEra -Recurse
    Scan-Folder -Folder (Join-Path $winRoot 'Cursors') `
        -Extensions @('.cur','.ani') -Category 'Cursores' `
        -SourceRoot $Root -RootEra $rootEra -Recurse
    Scan-Folder -Folder (Join-Path $winRoot 'Resources\Themes') `
        -Extensions @('.theme','.themepack','.msstyles') -Category 'Temas' `
        -SourceRoot $Root -RootEra $rootEra -Recurse
    Scan-Folder -Folder (Join-Path $winRoot 'System32') `
        -Extensions @('.scr') -Category 'Protectores' `
        -SourceRoot $Root -RootEra $rootEra
    Scan-Folder -Folder (Join-Path $winRoot 'System32\oobe') `
        -Extensions @('.jpg','.jpeg','.png','.bmp') -Category 'OOBE' `
        -SourceRoot $Root -RootEra $rootEra -Recurse
    Scan-Folder -Folder (Join-Path $winRoot 'Globalization\MCT') `
        -Extensions @('.jpg','.jpeg','.png','.wav','.theme') -Category 'Regionales' `
        -SourceRoot $Root -RootEra $rootEra -Recurse

    # Candidatos de extraccion: binarios con recursos legado incrustados
    foreach ($sub in @('System32','Branding\Basebrd','Resources\Themes\Aero','Boot')) {
        $dir = Join-Path $winRoot $sub
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $bins = Get-ChildItem -LiteralPath $dir -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $ExtractionCandidateNames -contains $_.Name.ToLowerInvariant() }
        foreach ($b in $bins) {
            $era = Get-FileEra -File $b -RootEra $rootEra
            $doVault = ($era -in @('Vista','Win7'))
            Add-Finding -File $b -Category 'CandidatoExtraccion' -Era $era `
                -SourceRoot $Root -Vault $doVault `
                -Note 'Contiene recursos incrustados; procesar con AeroExtract.ps1'
        }
    }

    # WinSxS: restos versionados 6.0.60xx (Vista) / 6.1.76xx-77xx (7)
    if ($IncludeWinSxS) {
        $sxs = Join-Path $winRoot 'WinSxS'
        if (Test-Path -LiteralPath $sxs) {
            Write-Host "  -> $sxs (esto puede tardar varios minutos)" -ForegroundColor DarkGray
            $oldDirs = Get-ChildItem -LiteralPath $sxs -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '_6\.(0\.60\d{2}|1\.7[67]\d{2})\.' }
            foreach ($d in $oldDirs) {
                $files = Get-ChildItem -LiteralPath $d.FullName -File -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension.ToLowerInvariant() -in @(
                        '.jpg','.jpeg','.png','.bmp','.gif','.wav','.mid','.wmv',
                        '.cur','.ani','.ico','.theme','.msstyles','.scr') }
                foreach ($f in $files) {
                    $era = if ($d.Name -match '_6\.0\.') { 'Vista' } else { 'Win7' }
                    Add-Finding -File $f -Category 'WinSxS' -Era $era -SourceRoot $Root -Vault $true
                }
            }
        }
    }
}

# Medios de muestra en perfiles publicos (y los de Windows.old)
$publicRoots = @((Join-Path $Root 'Users\Public'), (Join-Path $Root 'Windows.old\Users\Public'))
foreach ($pub in $publicRoots) {
    foreach ($sub in @('Pictures\Sample Pictures','Music\Sample Music','Videos\Sample Videos',
                       'Pictures','Music','Videos')) {
        $dir = Join-Path $pub $sub
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $files = Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $name = $f.Name.ToLowerInvariant()
            $era = $null
            if ($KnownVistaFiles -contains $name) { $era = 'Vista' }
            elseif ($KnownWin7Files -contains $name) { $era = 'Win7' }
            if ($era) {
                Add-Finding -File $f -Category 'Muestras' -Era $era -SourceRoot $Root -Vault $true
            }
        }
    }
}

# Gadgets de Windows Sidebar (solo existen en Vista/7 o restos de una actualizacion)
foreach ($pf in @('Program Files','Program Files (x86)','Windows.old\Program Files','Windows.old\Program Files (x86)')) {
    $gadgets = Join-Path $Root (Join-Path $pf 'Windows Sidebar\Gadgets')
    if (Test-Path -LiteralPath $gadgets) {
        $files = Get-ChildItem -LiteralPath $gadgets -File -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            Add-Finding -File $f -Category 'Gadgets' -Era 'Win7' -SourceRoot $Root -Vault $true `
                -Note 'Gadget de Windows Sidebar'
        }
    }
}

# ---------------------------------------------------------------------------
# Manifiesto y resumen
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$jsonPath = Join-Path $OutputDir 'manifest.json'
$csvPath  = Join-Path $OutputDir 'manifest.csv'
$script:Manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$script:Manifest | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host '=== Resumen ===' -ForegroundColor Cyan
$script:Manifest | Group-Object Era, Categoria | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-45} {1,6} archivo(s)" -f $_.Name, $_.Count)
}
$totalMB = [math]::Round((($script:Manifest | Measure-Object TamanoBytes -Sum).Sum) / 1MB, 1)
Write-Host ''
Write-Host ("Total: {0} hallazgos ({1} MB). Manifiesto: {2}" -f $script:Manifest.Count, $totalMB, $jsonPath) -ForegroundColor Green
$candidatos = @($script:Manifest | Where-Object { $_.Categoria -eq 'CandidatoExtraccion' })
if ($candidatos.Count -gt 0) {
    Write-Host ''
    Write-Host 'Sugerencia: extrae los recursos incrustados de los candidatos con:' -ForegroundColor Yellow
    Write-Host "  .\AeroExtract.ps1 -FromManifest '$jsonPath'" -ForegroundColor Yellow
}
