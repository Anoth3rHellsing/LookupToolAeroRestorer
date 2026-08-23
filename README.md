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

## Uso rápido: el menú guiado

**No hace falta recordar ningún comando.** Descarga el proyecto y haz doble clic
en **`Iniciar.cmd`** (o ejecuta `.\AeroTool.ps1` desde PowerShell). Aparece un
menú que te va preguntando y explica cada paso:

```
   ================================================================
        F R U T I G E R   A E R O   -  rescate y restauración
        Windows Vista / 7  ->  Windows 11
   ================================================================
   Bóveda: C:\AeroTool\AeroVault  [1.482 archivo(s)]

  MENÚ PRINCIPAL
  --------------------------------------------------------------------
    1  Asistente guiado  (empieza por aquí)
    2  Escanear esta instalación de Windows
    3  Escanear otro origen          <- disco, carpeta, ISO, install.wim, VHD
    4  Extraer los recursos incrustados en las DLL
    5  Restaurar en Windows 11
    6  Ver el contenido de la bóveda
    7  Deshacer los cambios
    8  Comprobar el sistema
    9  Cambiar la carpeta de la bóveda
    ?  ¿Qué es esto? / Ayuda
    0  Salir
```

La opción **1 (asistente guiado)** hace el recorrido completo en cinco pasos:
comprobar el sistema → escanear → extraer de las DLL → ver lo rescatado →
restaurar. En cada paso puedes decir que no, y **nada se cambia sin que lo
confirmes antes**.

Lo que el menú resuelve por ti:

- **Monta y desmonta las ISOs solo.** Si le das un `.iso` de Vista/7, lo monta,
  detecta `sources\install.wim` dentro y se ofrece a montarlo también (que es
  donde están de verdad los recursos), y lo desmonta todo al salir. También
  acepta `.vhd`/`.vhdx` y archivos `.wim` sueltos.
- **Explica cada error en castellano** y dice qué hacer: acceso denegado →
  cómo reabrir como administrador (con un botón para hacerlo); ruta que no
  existe → comprueba que la unidad sigue conectada; `.esd` en vez de `.wim` →
  te da el comando exacto para convertirlo.
- **Vista previa obligatoria** antes de aplicar nada al sistema.
- **Deshacer** (opción 7): guarda tu aspecto actual antes del primer cambio y
  lo devuelve tal cual estaba.

---

## Los componentes por separado

Si prefieres la línea de comandos, los cuatro scripts funcionan por su cuenta.
`AeroTool.ps1` no es más que un menú por encima de estos tres:

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
| `-Icons` | Iconos de Equipo, Papelera, Red, tu carpeta, Panel de control y unidad C: | HKCU\...\Explorer\CLSID |
| `-Glass` | Transparencia + acento azul cielo de Windows 7 en barra y Menú Inicio | HKCU\...\DWM y Personalize |
| `-Taskbar` | Barra a la izquierda, sin combinar, con etiquetas, iconos pequeños | HKCU\...\Explorer\Advanced |
| `-All` | Todo lo anterior | |

**Para revertir:** `.\AeroRestore.ps1 -Revert` (u opción 7 del menú).

La primera vez que se aplica algo, el script guarda tu configuración previa
—fondo, cursores, esquema de sonidos y protector— en
`%LOCALAPPDATA%\FrutigerAero\backup.json`, y ese respaldo original **nunca se
sobrescribe** en ejecuciones posteriores. Así, revertir siempre devuelve el
aspecto que tenías antes de conocer esta herramienta, no un estado Aero
intermedio. Revertir también elimina la tarea del sonido de inicio y el tema
generado; los archivos rescatados en la bóveda no se tocan.

---

### El "toque Aero" de la interfaz

Las tres últimas opciones son las que cambian la sensación del escritorio:

**`-Icons`** no usa un pack de iconos inventado: lee **qué icono usa hoy Windows 11**
para cada elemento (por ejemplo `imageres.dll,-109`) y pone el **mismo ID de recurso**
sacado del `imageres.dll` de Vista/7. Así el emparejado es correcto por construcción,
sin tablas de equivalencias adivinadas. Cuando un ID no existe en el binario antiguo,
ese icono se deja como está en vez de poner uno equivocado, y se te dice cuáles.

Para que funcione hace falta haber escaneado **una ISO o disco de Vista/7** y extraído
sus recursos: los iconos de tu Windows 11 son los modernos, y sustituirlos por sí
mismos no haría nada. La herramienta lo comprueba con el manifiesto (solo acepta
binarios marcados como era Vista o Win7) y, si no los encuentra, avisa y no toca nada.

**`-Glass`** pone la transparencia y el azul cielo por defecto de Windows 7
(`#74B8FC`) como color de acento en barra de tareas y Menú Inicio. Es lo más cerca
del cristal que se puede llegar sin parchear nada. Los valores `ColorizationBlurBalance`
y `ColorizationGlassAttribute` se escriben por fidelidad, pero Windows 11 los ignora:
el desenfoque real de los bordes ya no existe en el compositor.

**`-Taskbar`** devuelve la barra a la izquierda, con botones sin combinar y etiquetas
de texto, iconos pequeños, sin Vista de tareas ni widgets, y con todos los iconos del
área de notificación visibles. Lo de "sin combinar con etiquetas" e "iconos pequeños"
depende de la compilación de Windows 11: en versiones antiguas puede no tener efecto.

Estos tres cambios necesitan **reiniciar el Explorador** para verse; el menú se ofrece
a hacerlo por ti al terminar (es instantáneo y solo cierra las ventanas del Explorador).

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

La forma fácil es doble clic en `Iniciar.cmd` y elegir la opción 1. El
equivalente por línea de comandos es:

```powershell
# 1. Rescata todo lo que quede en tu máquina actual
.\AeroScan.ps1 -IncludeWinSxS

# 2. Si tienes un disco/ISO de Vista o 7, escanéalo también: es la fuente completa
.\AeroScan.ps1 -Root E:\ -OutputDir .\AeroVault

# 3. Extrae los tesoros incrustados en las DLLs
.\AeroExtract.ps1 -FromManifest .\AeroVault\manifest.json

# 4. Devuelve la era Frutiger Aero a tu Windows 11
.\AeroRestore.ps1 -Vault .\AeroVault -All

# 5. El toque Aero de la interfaz (iconos, color y barra de tareas)
.\AeroRestore.ps1 -Vault .\AeroVault -Icons -Glass -Taskbar -RestartExplorer

# 6. ¿Te arrepientes? Vuelve al aspecto anterior
.\AeroRestore.ps1 -Revert -RestartExplorer
```

## Archivos del proyecto

| Archivo | Para qué |
|---|---|
| `Iniciar.cmd` | Doble clic para abrir el menú (no cambia ninguna configuración de PowerShell) |
| `AeroTool.ps1` | Menú y asistente guiado: el punto de entrada recomendado |
| `AeroScan.ps1` | Escáner y archivador |
| `AeroExtract.ps1` | Extractor de recursos incrustados en DLL |
| `AeroRestore.ps1` | Restaurador para Windows 11 (y `-Revert`) |
