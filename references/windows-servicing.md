# Windows, drivers y mantenimiento

## Índice

1. Auditoría y respaldo
2. Optimizaciones de bajo riesgo
3. Drivers y seguridad
4. Windows Update y DISM
5. Imágenes modificadas y corrupción estructural
6. Criterio de reinstalación

## 1. Auditoría y respaldo

Registrar antes de cambiar:

- `ProductName`, `EditionID`, `DisplayVersion`, `CurrentBuild`, `UBR`, `BuildLabEx`, activación/canal sin revelar claves;
- BIOS, chipset, GPU/LAN/audio drivers y fechas;
- políticas Windows Update, fechas de pausa, servicios y tareas;
- Game Mode, Game DVR/captura, HAGS, VBS/Memory Integrity, Hyper-V, plan de energía y pagefile;
- Run/RunOnce, Startup folders, tareas no Microsoft, procesos/overlays y navegador/PWA que se abre solo;
- salud DISM/SFC, WHEA, Display/nvlddmkm, Disk/stornvme, Kernel-Power y crashes de Fortnite.

Crear una carpeta de respaldo con fecha. Exportar solo claves relevantes y XML de tareas antes de escribir. No prometer que un punto de restauración existe hasta verificar que terminó correctamente.

## 2. Optimizaciones de bajo riesgo

Aplicar y medir, no acumular a ciegas:

- Activar Game Mode.
- Desactivar Game DVR/captura en segundo plano si no se usa.
- Desactivar overlays, filtros, Instant Replay/Highlights y telemetría visual de NVIDIA/Discord/Game Bar/Overwolf si el usuario acepta.
- Cerrar durante la prueba emuladores Android, streams, navegadores pesados, launchers y software RGB/monitorización redundante; nunca cerrar por sorpresa.
- Revisar Chrome/Edge/PWA/URL que se abre solo en Run keys, Startup, tareas, acceso directo del navegador, protocolo y configuración de “continuar donde lo dejaste”.
- Usar perfil de energía normal o alto rendimiento según temperatura/clocks. Preferir ajuste por juego sobre una política global extrema.
- Configurar “Prefer maximum performance” solo en el perfil de Fortnite cuando una prueba demuestre clocks erráticos; no es obligatorio en todos los equipos.
- Mantener suficiente espacio libre, pagefile del sistema y TRIM.

HAGS, Reflex y Low Latency Mode interactúan con juego/driver. Fortnite con Reflex debe controlar la cola; evitar duplicar controles del driver sin medir. Probar HAGS activado/desactivado con reinicio y comparar frametimes.

No usar como receta universal:

- `bcdedit /set useplatformclock`, `disabledynamictick`, resolución de timer permanente;
- `NetworkThrottlingIndex`, `SystemResponsiveness`, Nagle/TcpAckFrequency;
- prioridad `Realtime`, afinidad fija, desactivar servicios al azar o “debloat” masivo;
- desactivar fullscreen optimizations, MPO, HPET, Core Isolation o mitigaciones sin una hipótesis y reversión.

## 3. Drivers y seguridad

Orden sugerido cuando hay que normalizar una PC:

1. BIOS/firmware solo si corresponde y en ventana segura.
2. Chipset y ME/PSP oficiales.
3. LAN/Wi-Fi/audio del fabricante si el instalado es incorrecto o problemático.
4. GPU estable oficial; instalación limpia del proveedor si basta.
5. Windows estable y actualizaciones de seguridad.

No instalar automáticamente previews ni drivers opcionales de Windows Update. Comparar hardware IDs y versiones primero. Usar DDU en Modo Seguro solo ante corrupción/conflicto de driver demostrado; no en cada actualización.

Tratar VBS, Memory Integrity, Credential Guard, Hyper-V y mitigaciones como seguridad, no “bloqueos de kernel”. Desactivarlos puede mejorar algún caso, pero amplía superficie de ataque. Pedir consentimiento, respaldar y medir. Con anti-cheat, no alterar kernel, firmas, integridad de código ni servicios de seguridad para perseguir FPS.

Para procesos raros:

- comprobar ruta, editor/firma, hash y persistencia;
- usar Autoruns/Process Explorer oficiales o Defender;
- ejecutar análisis rápido/completo/offline cuando corresponda;
- no borrar archivos solo por nombre ni subirlos fuera del equipo sin permiso.

## 4. Windows Update y DISM

Comprobar primero:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Get-Service wuauserv,BITS,UsoSvc,WaaSMedicSvc,DoSvc
Get-ScheduledTask | Where-Object TaskPath -match 'WindowsUpdate|UpdateOrchestrator'
DISM /Online /Cleanup-Image /CheckHealth
```

Servicios como BITS, UsoSvc o WaaSMedic pueden detenerse cuando están inactivos; no exigir que todos estén siempre `Running`. Validar tipo de inicio, capacidad de escaneo y tareas como `WindowsUpdate\Scheduled Start` y `UpdateOrchestrator\Schedule Scan`.

Si hay políticas de pausa/bloqueo:

1. Exportar `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` y ajustes relacionados.
2. Registrar `Registry.pol` y tareas antes de modificar.
3. Quitar solo políticas identificadas y autorizadas; no borrar toda Policy sin inventario.
4. Restaurar servicios/tareas a valores apropiados para esa edición/build.
5. Ejecutar un scan y separar actualizaciones estables de previews/drivers opcionales.

Para caché dañada, detener servicios de forma controlada y renombrar —no borrar primero— `SoftwareDistribution` y `catroot2` a backups con fecha. Resolver rutas absolutas y no tocar otros directorios.

Secuencia de reparación:

```powershell
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth
SFC /Scannow
DISM /Online /Cleanup-Image /CheckHealth
```

Si se necesita fuente, preferir medio oficial de misma edición, arquitectura, idioma y build/base compatible. Validar origen, tamaño, hash/firma cuando se publique; montar en lectura y no ejecutar Setup:

```powershell
DISM /Get-WimInfo /WimFile:X:\sources\install.wim
DISM /Online /Cleanup-Image /RestoreHealth /Source:wim:X:\sources\install.wim:<index>
```

Omitir `/LimitAccess` cuando Windows Update deba complementar idiomas o versiones más nuevas. Usar una imagen Evaluation como fuente no instala ni cambia licencia por sí solo, pero puede carecer de componentes de la edición/idioma; no usarla para instalar el sistema productivo.

Para MSU checkpoint/cumulative, seguir el método vigente de Microsoft. Verificar firma Authenticode y hash; no asumir que un error del checkpoint equivale al del LCU. No repetir instalaciones indefinidamente.

## 5. Imágenes modificadas y corrupción estructural

Patrón aprendido con builds tipo KernelOS:

- políticas de pausa hasta fechas absurdas, exclusión de drivers, tareas deshabilitadas y caché WU congelada;
- paquetes de enablement/preview integrados como permanentes;
- edición LTSC basada oficialmente en una build, pero `DisplayVersion/CurrentBuild` de otra rama;
- manifiestos WinSxS retirados para Defender, BitLocker, Application Guard/HVSI, policy definitions, idiomas y FOD;
- DISM/SFC declaran sano, pero un LCU referencia componentes borrados, marca corrupción y falla `0x80073712`;
- una nueva reparación puede sanar el lote visible, mientras el siguiente intento descubre otra capa.

Ante este patrón:

1. Respaldar políticas, tareas y cachés.
2. Restaurar WU y demostrar que el scan funciona.
3. Reparar con fuente oficial y probar una vez el LCU estable correcto.
4. Si cada intento expone otro conjunto de manifiestos eliminados, detener el ciclo.
5. No tomar propiedad de WinSxS, no copiar manifests a mano, no editar COMPONENTS ni forzar la eliminación de un paquete permanente.

El scan exitoso más un fallo CBS repetible demuestra que WU no está bloqueado: la imagen no puede resolver su grafo de componentes.

## 6. Criterio de reinstalación

Recomendar instalación limpia cuando:

- el sistema es una rama/edición híbrida no soportada;
- el enablement que causó el salto es permanente;
- `0x80073712` reaparece tras fuente oficial y cada intento descubre nuevos componentes borrados;
- no existe medio igual o superior que permita repair install conservando aplicaciones;
- la seguridad/servicing quedó incompleta por un “lite OS”.

Usar medio oficial **no Evaluation** que coincida con la licencia, o una edición con licencia válida elegida por el usuario. Una vuelta de build superior a inferior normalmente requiere instalación limpia; no prometer conservar aplicaciones. Antes de preparar USB o instalar, respaldar datos, claves, perfiles/configuración de Fortnite, drivers necesarios y confirmar físicamente el disco/partición de destino.
