# LookupToolAeroRestorer

Herramienta de **preservación y restauración de la estética Frutiger Aero** de
Windows Vista y Windows 7: escanea una instalación de Windows (o un disco/imagen
antigua), rescata todos los recursos de esa era antes de que se conviertan en
*lost media*, y restablece como predeterminado en Windows 11 todo lo que se
puede restablecer de forma segura y nativa.

Todo funciona con PowerShell, sin instalar nada, y **jamás modifica ni borra
archivos del sistema**: el escáner y el extractor son de solo lectura, y el
restaurador solo escribe en tu perfil de usuario (HKCU) y carpetas de usuario.

---

## ¿Por qué? El fantasma de Vista dentro de Windows 11

Muchos usuarios (¡incluido quien encargó esta herramienta!) han visto que,
mientras Windows 11 arranca o justo al iniciar sesión, aparecen por un instante
la **barra de progreso clásica** y una **barra de tareas estilo Vista/básica**.
No es una alucinación. Ocurre porque Windows nunca ha eliminado del todo sus
capas anteriores:

- La barra de progreso clásica del arranque vive en los recursos del cargador
  (`bootres.dll`, `winload.exe`) y aparece cuando el arranque cae al modo de
  respaldo (p. ej. tras una actualización o en modo seguro).
- Al iniciar sesión, `explorer.exe` puede dibujarse durante unos frames **antes**
  de que el motor de temas y DWM terminen de cargar, mostrando el estilo visual
  básico heredado — el mismo camino de renderizado que existe desde Vista.
- Windows 10/11 todavía **distribuye** recursos de la era Aero: los cursores
  vidriosos `aero_*.cur`, los 13 esquemas de sonido de Windows 7 (Sonata,
  Landscape, Raga...), los protectores Burbujas/Cintas/Mystify, e iconos de
  Vista incrustados en `imageres.dll` y `shell32.dll`.

Esos restos son exactamente lo que esta herramienta localiza, archiva y — donde
es posible — vuelve a poner en primer plano.

---

## Los tres componentes

### 1. `AeroScan.ps1` — el escáner/archivador

Recorre una instalación de Windows y clasifica cada hallazgo por era
(**Vista** = versión PE 6.0.60xx, **Win7** = 6.1.76xx, **Superviviente** =
recurso Aero que Win 10/11 aún incluye). Copia todo a una bóveda con hash
SHA-256 y manifiesto JSON + CSV.

Dónde busca:

| Ruta | Qué hay ahí |
|---|---|
| `Windows\Web\Wallpaper` | Fondos (img0.jpg "Armonía" de 7, imgN de Vista, Architecture/Nature/Scenes...) |
| `Windows\Web\Windows DreamScene` | Vídeos DreamScene de Vista Ultimate |
| `Windows\Media` | Sonidos, incluido *Windows Logon Sound.wav* y los esquemas de Win7 |
| `Windows\Cursors` | Cursores Aero (`aero_*.cur/.ani`) |
| `Windows\Resources\Themes` | `.theme` y `.msstyles` |
| `Windows\System32` | Protectores `.scr` (Aurora de Vista, Burbujas...) y DLLs de recursos |
| `Windows\Globalization\MCT` | Fondos/temas regionales de Win7 |
| `Users\Public\Pictures/Music/Videos` | Koala.jpg, Kalimba.mp3, Wildlife.wmv, muestras de Vista... |
| `Program Files\Windows Sidebar\Gadgets` | Gadgets de la barra lateral |
| `Windows.old\...` | Todo lo anterior si actualizaste desde 7 |
| `Windows\WinSxS` (con `-IncludeWinSxS`) | Miles de restos versionados 6.0/6.1 tras actualizaciones in-place |

```powershell
# Escanear la instalación actual
.\AeroScan.ps1

# Un disco viejo con Windows 7 conectado como E:\ (¡el mejor botín!)
.\AeroScan.ps1 -Root E:\ -OutputDir D:\PreservacionAero -IncludeWinSxS

# Una ISO de Vista/7: monta la ISO (doble clic), monta su install.wim y escanea
Mount-WindowsImage -ImagePath F:\sources\install.wim -Index 1 -Path C:\MontajeVista -ReadOnly
.\AeroScan.ps1 -Root C:\MontajeVista
Dismount-WindowsImage -Path C:\MontajeVista -Discard
```

### 2. `AeroExtract.ps1` — el minero de DLLs

Gran parte de la estética no está en archivos sueltos sino **dentro** de
binarios: los iconos vidriosos en `imageres.dll`, las texturas del tema en
`aero.msstyles`, la animación de arranque en `bootres.dll`. Este script carga
cada binario como datos (sin ejecutar su código), enumera sus recursos Win32 y
los vuelca como `.png`, `.jpg`, `.bmp`, `.wav`, `.avi`, `.ico` (reconstruyendo
el icono multi-resolución) y `.cur` (con su hotspot).

```powershell
# Un binario concreto
.\AeroExtract.ps1 C:\Windows\System32\imageres.dll

# Todos los candidatos que AeroScan marcó en el manifiesto
.\AeroExtract.ps1 -FromManifest .\AeroVault\manifest.json
```

### 3. `AeroRestore.ps1` — el restaurador para Windows 11

Restablece como predeterminado todo lo que Windows 11 permite de forma nativa
y reversible. Soporta `-WhatIf` para previsualizar sin tocar nada.

```powershell
# Ver qué haría
.\AeroRestore.ps1 -Vault .\AeroVault -All -WhatIf

# Aplicarlo todo
.\AeroRestore.ps1 -Vault .\AeroVault -All

# Solo algunas piezas
.\AeroRestore.ps1 -Vault .\AeroVault -Wallpaper -Sounds -Cursors -Theme
```

| Interruptor | Qué restablece | Cómo |
|---|---|---|
| `-Wallpaper` | Fondo "Armonía" (img0.jpg) u otro de la bóveda | HKCU + SystemParametersInfo |
| `-Sounds` | Esquema de sonidos completo de Win7, registrado como "Frutiger Aero" en el panel de sonidos | HKCU\AppEvents |
| `-Cursors` | Esquema de cursores Windows Aero | HKCU\Control Panel\Cursors |
| `-Screensaver` | Burbujas (o Aurora.scr de Vista si está en la bóveda) | HKCU |
| `-SampleMedia` | Sample Pictures/Music/Videos en C:\Users\Public | Copia de archivos |
| `-StartupSound` | Reactiva el sonido de inicio y programa el *Windows Logon Sound* de Vista/7 al iniciar sesión | HKLM (admin) + tarea programada de usuario |
| `-Theme` | Tema "Frutiger Aero (Recuperado)" que ata todo, con presentación de fondos | `.theme` en tu perfil |
| `-All` | Todo lo anterior | |

**Para revertir:** Configuración → Personalización → Temas → "Windows (claro)",
y `Unregister-ScheduledTask FrutigerAero-LogonSound` si activaste el sonido de
inicio.

---

## Lo que NO se puede restablecer (y por qué esta herramienta no lo intenta)

El **Aero Glass real** — la barra de tareas translúcida de Vista/7, los bordes
de cristal, el desenfoque de DWM — vive en `aero.msstyles` + el compositor DWM,
y Windows 11:

1. Protege esos archivos con **Windows Resource Protection**: aunque los
   reemplaces, el sistema los restaura.
2. Exige que los `.msstyles` estén **firmados por Microsoft**; un tema de
   terceros requiere parchear la comprobación de firmas en memoria.

Existen proyectos de terceros que hacen ese parcheo, pero implican inyectar
código sin firmar en procesos del sistema: pueden romper el arranque tras
cualquier Windows Update y son indistinguibles de malware para un antivirus.
Por eso quedan **fuera del alcance** de esta herramienta, que se limita a lo
que Windows soporta oficialmente. La bóveda que genera AeroScan, eso sí,
conserva los `.msstyles` originales para que la preservación sea completa.

## Requisitos y notas

- Windows 10/11 con PowerShell 5.1+ (incluido de serie). `AeroScan.ps1` también
  funciona en PowerShell 7 sobre Linux/macOS apuntando a un disco montado.
- Si nunca has ejecutado scripts: `Set-ExecutionPolicy -Scope Process Bypass`
  en la sesión actual.
- No hace falta administrador salvo para `-StartupSound` (la parte HKLM) y para
  leer algunas zonas de WinSxS.
- **Nota legal:** los recursos rescatados son propiedad de Microsoft. Consérvalos
  como copia de seguridad personal de tu propia licencia; no redistribuyas
  públicamente la bóveda.

## Flujo recomendado

```powershell
# 1. Rescata todo lo que quede en tu máquina actual
.\AeroScan.ps1 -IncludeWinSxS

# 2. Si tienes un disco/ISO de Vista o 7, escanéalo también: es la fuente completa
.\AeroScan.ps1 -Root E:\ -OutputDir .\AeroVault

# 3. Extrae los tesoros incrustados en las DLLs
.\AeroExtract.ps1 -FromManifest .\AeroVault\manifest.json

# 4. Devuelve la era Frutiger Aero a tu Windows 11
.\AeroRestore.ps1 -Vault .\AeroVault -All
```
