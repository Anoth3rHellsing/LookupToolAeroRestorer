#Requires -Version 5.1
<#
.SYNOPSIS
    Extrae los recursos multimedia incrustados (PNG, JPG, BMP, WAV, AVI, iconos,
    cursores) de binarios de Windows como imageres.dll, shell32.dll o aero.msstyles.

.DESCRIPTION
    Muchisima estetica Frutiger Aero no vive en archivos sueltos sino DENTRO de
    DLLs de recursos: los iconos vidriosos de imageres.dll, las texturas del tema
    Aero dentro de aero.msstyles, la animacion de arranque en bootres.dll, los
    sonidos de mmres.dll... Este script carga cada binario como archivo de datos
    (nunca se ejecuta su codigo), enumera sus recursos Win32 y los vuelca a disco
    en formatos estandar:

      - RT_GROUP_ICON  -> .ico reconstruido con todas sus resoluciones
      - RT_GROUP_CURSOR-> .cur reconstruido con su hotspot
      - RT_BITMAP      -> .bmp (se le anade la cabecera de archivo)
      - PNG / IMAGE / WAVE / AVI / RCDATA y tipos personalizados -> se detecta el
        formato por sus bytes magicos (.png, .jpg, .gif, .wav, .avi, .ani, .wmv...)

    Solo lectura: el binario de origen jamas se modifica.

.PARAMETER Path
    Uno o mas binarios (dll, exe, scr, msstyles, cpl) de los que extraer recursos.

.PARAMETER FromManifest
    Ruta a un manifest.json generado por AeroScan.ps1: procesa automaticamente
    todos los "CandidatoExtraccion" que este liste.

.PARAMETER OutputDir
    Carpeta de salida. Se crea una subcarpeta por cada binario procesado.

.PARAMETER IncludeUnknown
    Vuelca tambien los recursos cuyo formato no se reconoce (como .bin).

.EXAMPLE
    .\AeroExtract.ps1 C:\Windows\System32\imageres.dll

.EXAMPLE
    .\AeroExtract.ps1 -FromManifest .\AeroVault\manifest.json -OutputDir .\AeroExtracted
#>
[CmdletBinding(DefaultParameterSetName = 'Files')]
param(
    [Parameter(ParameterSetName = 'Files', Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [string[]]$Path,

    [Parameter(ParameterSetName = 'Manifest', Mandatory = $true)]
    [string]$FromManifest,

    [string]$OutputDir = (Join-Path (Get-Location).Path 'AeroExtracted'),

    [switch]$IncludeUnknown
)

begin {
    if ($env:OS -ne 'Windows_NT') {
        throw 'AeroExtract.ps1 usa la API Win32 de recursos y solo funciona en Windows.'
    }

    $source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

namespace AeroTools
{
    public static class ResourceExtractor
    {
        const uint LOAD_LIBRARY_AS_DATAFILE = 0x2;
        const uint LOAD_LIBRARY_AS_IMAGE_RESOURCE = 0x20;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr LoadLibraryExW(string lpFileName, IntPtr hFile, uint dwFlags);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool FreeLibrary(IntPtr hModule);

        delegate bool EnumResTypeProc(IntPtr hModule, IntPtr lpszType, IntPtr lParam);
        delegate bool EnumResNameProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool EnumResourceTypesW(IntPtr hModule, EnumResTypeProc lpEnumFunc, IntPtr lParam);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool EnumResourceNamesW(IntPtr hModule, IntPtr lpszType, EnumResNameProc lpEnumFunc, IntPtr lParam);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr FindResourceW(IntPtr hModule, IntPtr lpName, IntPtr lpType);

        [DllImport("kernel32.dll")]
        static extern IntPtr LoadResource(IntPtr hModule, IntPtr hResInfo);

        [DllImport("kernel32.dll")]
        static extern IntPtr LockResource(IntPtr hResData);

        [DllImport("kernel32.dll")]
        static extern uint SizeofResource(IntPtr hModule, IntPtr hResInfo);

        static bool IsIntRes(IntPtr p)
        {
            return ((ulong)p.ToInt64()) >> 16 == 0;
        }

        static string ResToString(IntPtr p)
        {
            if (IsIntRes(p)) return p.ToInt64().ToString();
            string s = Marshal.PtrToStringUni(p);
            return s == null ? "null" : s;
        }

        static string Clean(string s)
        {
            var sb = new System.Text.StringBuilder();
            foreach (char c in s)
                sb.Append(char.IsLetterOrDigit(c) || c == '-' || c == '.' ? c : '_');
            string result = sb.ToString().Trim('_');
            return result.Length == 0 ? "res" : result;
        }

        static byte[] GetBytes(IntPtr hMod, IntPtr type, IntPtr name)
        {
            IntPtr hRes = FindResourceW(hMod, name, type);
            if (hRes == IntPtr.Zero) return null;
            uint size = SizeofResource(hMod, hRes);
            if (size == 0) return null;
            IntPtr hData = LoadResource(hMod, hRes);
            if (hData == IntPtr.Zero) return null;
            IntPtr p = LockResource(hData);
            if (p == IntPtr.Zero) return null;
            byte[] buf = new byte[size];
            Marshal.Copy(p, buf, 0, (int)size);
            return buf;
        }

        // Tipos estandar sin interes estetico directo
        static readonly HashSet<long> SkipIntTypes = new HashSet<long>
            { 4, 5, 6, 7, 8, 9, 11, 16, 17, 24 };
        static readonly HashSet<string> SkipNamedTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            { "MUI", "REGISTRY", "TYPELIB", "REGINST", "WEVT_TEMPLATE", "XSD", "EMBEDDEDPRODUCTKEY" };

        static string SniffExt(byte[] d)
        {
            if (d.Length < 12) return null;
            if (d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4E && d[3] == 0x47) return ".png";
            if (d[0] == 0xFF && d[1] == 0xD8 && d[2] == 0xFF) return ".jpg";
            if (d[0] == 'G' && d[1] == 'I' && d[2] == 'F' && d[3] == '8') return ".gif";
            if (d[0] == 'B' && d[1] == 'M') return ".bmp";
            if (d[0] == 0x30 && d[1] == 0x26 && d[2] == 0xB2 && d[3] == 0x75) return ".wmv";
            if (d[0] == 'R' && d[1] == 'I' && d[2] == 'F' && d[3] == 'F')
            {
                string four = System.Text.Encoding.ASCII.GetString(d, 8, 4);
                if (four == "WAVE") return ".wav";
                if (four == "AVI ") return ".avi";
                if (four == "ACON") return ".ani";
                return ".riff";
            }
            return null;
        }

        static byte[] WrapDib(byte[] dib)
        {
            if (dib.Length < 40) return null;
            int headerSize = BitConverter.ToInt32(dib, 0);
            if (headerSize < 12 || headerSize > dib.Length) return null;
            int bitCount = BitConverter.ToUInt16(dib, 14);
            int compression = BitConverter.ToInt32(dib, 16);
            int clrUsed = BitConverter.ToInt32(dib, 32);
            int paletteEntries = 0;
            if (bitCount <= 8)
                paletteEntries = clrUsed != 0 ? clrUsed : (1 << bitCount);
            int offset = 14 + headerSize + paletteEntries * 4;
            if (headerSize == 40 && compression == 3) offset += 12;
            using (var ms = new MemoryStream())
            using (var w = new BinaryWriter(ms))
            {
                w.Write((byte)'B'); w.Write((byte)'M');
                w.Write((uint)(14 + dib.Length));
                w.Write((uint)0);
                w.Write((uint)offset);
                w.Write(dib);
                return ms.ToArray();
            }
        }

        static byte[] BuildIconOrCursor(IntPtr hMod, IntPtr groupName, bool cursor)
        {
            IntPtr groupType = (IntPtr)(cursor ? 12 : 14);
            IntPtr imageType = (IntPtr)(cursor ? 1 : 3);
            byte[] dir = GetBytes(hMod, groupType, groupName);
            if (dir == null || dir.Length < 6) return null;
            int count = BitConverter.ToUInt16(dir, 4);

            var metas = new List<byte[]>();
            var images = new List<byte[]>();
            for (int i = 0; i < count; i++)
            {
                int e = 6 + 14 * i;
                if (e + 14 > dir.Length) break;
                ushort id = BitConverter.ToUInt16(dir, e + 12);
                byte[] img = GetBytes(hMod, imageType, (IntPtr)id);
                if (img == null) continue;

                byte bw, bh, bc;
                ushort f1, f2;
                byte[] payload = img;
                if (cursor)
                {
                    // En GRPCURSORDIR ancho/alto son WORD y el alto viene doblado;
                    // el hotspot son los 4 primeros bytes del recurso RT_CURSOR.
                    int w16 = BitConverter.ToUInt16(dir, e);
                    int h16 = BitConverter.ToUInt16(dir, e + 2) / 2;
                    bw = (byte)(w16 >= 256 ? 0 : w16);
                    bh = (byte)(h16 >= 256 ? 0 : h16);
                    bc = 0;
                    if (img.Length <= 4) continue;
                    f1 = BitConverter.ToUInt16(img, 0);
                    f2 = BitConverter.ToUInt16(img, 2);
                    payload = new byte[img.Length - 4];
                    Array.Copy(img, 4, payload, 0, payload.Length);
                }
                else
                {
                    bw = dir[e];
                    bh = dir[e + 1];
                    bc = dir[e + 2];
                    f1 = BitConverter.ToUInt16(dir, e + 4);
                    f2 = BitConverter.ToUInt16(dir, e + 6);
                }

                using (var ms = new MemoryStream())
                using (var w = new BinaryWriter(ms))
                {
                    w.Write(bw); w.Write(bh); w.Write(bc); w.Write((byte)0);
                    w.Write(f1); w.Write(f2);
                    w.Write((uint)payload.Length);
                    w.Write((uint)0); // offset: se rellena al ensamblar
                    metas.Add(ms.ToArray());
                }
                images.Add(payload);
            }
            if (images.Count == 0) return null;

            using (var outMs = new MemoryStream())
            using (var w = new BinaryWriter(outMs))
            {
                w.Write((ushort)0);
                w.Write((ushort)(cursor ? 2 : 1));
                w.Write((ushort)images.Count);
                uint offset = (uint)(6 + 16 * images.Count);
                for (int i = 0; i < images.Count; i++)
                {
                    byte[] m = metas[i];
                    BitConverter.GetBytes(offset).CopyTo(m, 12);
                    w.Write(m);
                    offset += (uint)images[i].Length;
                }
                foreach (byte[] img in images) w.Write(img);
                return outMs.ToArray();
            }
        }

        static string WriteFile(string dir, string name, byte[] data)
        {
            string path = System.IO.Path.Combine(dir, name);
            File.WriteAllBytes(path, data);
            return path;
        }

        public static List<string> ExtractAll(string peFile, string outDir, bool includeUnknown)
        {
            var written = new List<string>();
            IntPtr hMod = LoadLibraryExW(peFile, IntPtr.Zero,
                LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
            if (hMod == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(
                    Marshal.GetLastWin32Error(), "No se pudo cargar como datos: " + peFile);
            try
            {
                Directory.CreateDirectory(outDir);
                EnumResourceTypesW(hMod, delegate(IntPtr m, IntPtr typePtr, IntPtr lp)
                {
                    bool typeIsInt = IsIntRes(typePtr);
                    long typeId = typeIsInt ? typePtr.ToInt64() : -1;
                    string typeName = ResToString(typePtr);
                    if (typeIsInt && SkipIntTypes.Contains(typeId)) return true;
                    if (typeIsInt && (typeId == 1 || typeId == 3)) return true; // via grupos
                    if (!typeIsInt && SkipNamedTypes.Contains(typeName)) return true;

                    EnumResourceNamesW(m, typePtr, delegate(IntPtr m2, IntPtr t2, IntPtr namePtr, IntPtr lp2)
                    {
                        try
                        {
                            string resName = Clean(ResToString(namePtr));
                            if (typeId == 14)
                            {
                                byte[] ico = BuildIconOrCursor(m2, namePtr, false);
                                if (ico != null)
                                    written.Add(WriteFile(outDir, "icono_" + resName + ".ico", ico));
                            }
                            else if (typeId == 12)
                            {
                                byte[] cur = BuildIconOrCursor(m2, namePtr, true);
                                if (cur != null)
                                    written.Add(WriteFile(outDir, "cursor_" + resName + ".cur", cur));
                            }
                            else if (typeId == 2)
                            {
                                byte[] dib = GetBytes(m2, t2, namePtr);
                                if (dib != null)
                                {
                                    byte[] bmp = WrapDib(dib);
                                    if (bmp != null)
                                        written.Add(WriteFile(outDir, "bitmap_" + resName + ".bmp", bmp));
                                }
                            }
                            else
                            {
                                byte[] data = GetBytes(m2, t2, namePtr);
                                if (data == null) return true;
                                string ext = SniffExt(data);
                                if (ext == null && !includeUnknown) return true;
                                string prefix = Clean(typeName).ToLowerInvariant();
                                written.Add(WriteFile(outDir,
                                    prefix + "_" + resName + (ext ?? ".bin"), data));
                            }
                        }
                        catch { /* recurso corrupto: continuar */ }
                        return true;
                    }, IntPtr.Zero);
                    return true;
                }, IntPtr.Zero);
            }
            finally
            {
                FreeLibrary(hMod);
            }
            return written;
        }
    }
}
'@

    if (-not ('AeroTools.ResourceExtractor' -as [type])) {
        Add-Type -TypeDefinition $source -Language CSharp
    }

    $targets = New-Object System.Collections.Generic.List[string]
}

process {
    if ($PSCmdlet.ParameterSetName -eq 'Files') {
        foreach ($p in $Path) {
            $resolved = Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue
            if ($resolved) { $targets.Add($resolved.Path) }
            else { Write-Warning "No existe: $p" }
        }
    }
}

end {
    if ($PSCmdlet.ParameterSetName -eq 'Manifest') {
        $manifest = Get-Content -LiteralPath $FromManifest -Raw | ConvertFrom-Json
        # Windows PowerShell 5.1 puede serializar la coleccion envuelta en un
        # objeto con una propiedad 'value'; se desenvuelve antes de recorrerla.
        if ($manifest -and -not ($manifest -is [System.Collections.IEnumerable]) -and
            (@($manifest.PSObject.Properties.Name) -contains 'value')) {
            $manifest = $manifest.value
        }
        foreach ($entry in @($manifest)) {
            if ($entry.Categoria -ne 'CandidatoExtraccion') { continue }
            $src = $entry.RutaBoveda
            if (-not $src) { $src = $entry.RutaOriginal }
            if ($src -and (Test-Path -LiteralPath $src)) { $targets.Add($src) }
        }
        Write-Host "Candidatos de extraccion en el manifiesto: $($targets.Count)"
    }

    if ($targets.Count -eq 0) {
        Write-Warning 'Nada que extraer.'
        return
    }

    $total = 0
    foreach ($t in $targets | Select-Object -Unique) {
        $base = [System.IO.Path]::GetFileName($t) -replace '[^\w.-]', '_'
        $sub = Join-Path $OutputDir $base
        try {
            $files = [AeroTools.ResourceExtractor]::ExtractAll($t, $sub, [bool]$IncludeUnknown)
            Write-Host ("  {0,-60} -> {1,5} recurso(s)" -f $t, $files.Count)
            $total += $files.Count
        } catch {
            Write-Warning "Fallo con ${t}: $($_.Exception.Message)"
        }
    }
    Write-Host ''
    Write-Host "Extraidos $total recursos en $OutputDir" -ForegroundColor Green
}
