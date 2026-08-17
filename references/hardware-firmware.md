# Hardware y firmware

## Índice

1. Inventario y carga real
2. RAM, slots y doble canal
3. GPU, PCIe y ReBAR
4. CPU, temperatura y potencia
5. BIOS y chipset
6. SSD, monitor y alimentación

## 1. Inventario y carga real

Tomar primero un inventario con el script de auditoría. Confirmar luego los datos críticos con una segunda fuente:

- Placa: modelo y revisión impresos en PCB o mostrados por UEFI; SMBIOS puede omitir la revisión.
- RAM/canales: HWiNFO, CPU-Z o UEFI; `Win32_PhysicalMemory` no prueba el modo de canal.
- PCIe: `nvidia-smi`, GPU-Z/HWiNFO y manual de placa; medir también con GPU bajo carga.
- Temperaturas/limitadores: HWiNFO o telemetría del fabricante durante el mismo escenario que presenta tirones.

No abrir el gabinete mientras el equipo esté encendido. Apagar, cortar energía, descargar estática y fotografiar cableado/slots antes de mover componentes.

## 2. RAM, slots y doble canal

Relevar:

```powershell
Get-CimInstance Win32_PhysicalMemory |
  Select-Object DeviceLocator,BankLabel,Capacity,Speed,ConfiguredClockSpeed,Manufacturer,PartNumber

Get-CimInstance Win32_PhysicalMemoryArray |
  Select-Object MemoryDevices,MaxCapacityEx
```

Interpretar con cuidado:

- Contar módulos, capacidad total, velocidades y slots declarados.
- Consultar el manual exacto. En muchas placas de cuatro slots, dos módulos van en A2/B2, pero existen excepciones.
- Confirmar “Dual Channel” o ancho efectivo en HWiNFO/CPU-Z/UEFI. Dos módulos no garantizan doble canal si están mal ubicados.
- Confirmar que `ConfiguredClockSpeed` coincide con el perfil XMP/EXPO esperado. DDR informa una tasa efectiva; no confundirla con el reloj físico.
- Si XMP produce WHEA, cierres o stutter, probar JEDEC y después un perfil/voltaje soportado. Estabilidad vale más que frecuencia nominal.
- No mezclar kits como primera solución. Igual capacidad y modelo reducen variables, pero tampoco garantizan compatibilidad entre kits separados.

Señales de memoria: 1% lows pobres con FPS promedio alto, paging, errores WHEA/memoria, velocidad JEDEC inesperada o un solo canal.

## 3. GPU, PCIe y ReBAR

Comprobar físicamente y por software:

- Usar la ranura larga primaria recomendada por el manual, normalmente la superior conectada a CPU.
- Verificar que el seguro esté cerrado, la tarjeta completamente insertada y los cables PCIe de la fuente estén firmes. Preferir cables separados cuando la fuente/GPU lo recomienden.
- Conectar el monitor a la GPU dedicada, no a la placa. Esto es crítico en CPU sin iGPU.
- Consultar ancho y generación máximos y actuales:

```powershell
nvidia-smi --query-gpu=name,pci.bus_id,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max --format=csv
nvidia-smi -q -d PCI
```

La generación actual puede bajar en reposo por ahorro. Repetir bajo carga 3D. Comparar ancho negociado con lo que soportan GPU, slot y CPU; una ranura física x16 puede estar cableada x4.

Para ReBAR comprobar:

- UEFI, CSM desactivado, Above 4G Decoding activado y Re-Size BAR activado/Auto.
- Tabla de particiones/arranque UEFI y soporte de VBIOS/driver.
- “Resizable BAR: Yes” en NVIDIA System Information o herramienta equivalente.

No asumir que ReBAR mejora todos los juegos; validar Fortnite con la misma escena.

## 4. CPU, temperatura y potencia

Medir por núcleo, no solo CPU total. Fortnite Performance Mode suele estar limitado por game thread aunque el total parezca bajo.

Registrar durante el tirón:

- núcleo lógico más ocupado, clocks P/E, temperatura, package power y flags de thermal/power/current limit;
- GPU utilization, clocks, temperatura, power draw y VRAM;
- frecuencia/latencia de RAM y paging;
- procesos que compiten por CPU, GPU Video Decode, disco o red.

No fijar afinidad, desactivar E-cores/Hyper-Threading ni usar prioridad `Realtime` como ajuste permanente. Solo realizar una prueba A/B reversible si existe evidencia de planificación problemática y registrar el resultado.

## 5. BIOS y chipset

Antes de actualizar:

1. Identificar fabricante, modelo exacto y revisión.
2. Consultar únicamente la página oficial y leer notas de cada versión.
3. Confirmar archivo, checksum si se publica, método de actualización y requisito de versión intermedia.
4. Guardar fotos/export de ajustes, perfil XMP, curvas y claves de recuperación de BitLocker/device encryption.
5. Volver a valores estables; no flashear con overclock inestable, tormenta o energía dudosa.
6. Usar la herramienta integrada de UEFI y USB FAT32 cuando el fabricante lo indique.
7. Tras el flash, cargar defaults, volver a configurar solo lo necesario y validar memoria/temperaturas.

Revisar luego: XMP/EXPO, ReBAR/Above 4G, UEFI/CSM, límites de potencia razonables, ventiladores y virtualización según necesidad. No copiar “tweaks BIOS Fortnite” de otra placa.

Instalar chipset, Intel ME/AMD PSP y LAN desde placa/fabricante cuando sean correctos para el hardware. No mezclar firmware de otra revisión.

## 6. SSD, monitor y alimentación

- Instalar Fortnite en SSD/NVMe con espacio libre suficiente; buscar eventos Disk/stornvme/storahci y salud SMART.
- Mantener pagefile administrado por el sistema en SSD. Desactivarlo puede convertir presión de memoria en cierres o stutter.
- Confirmar resolución y Hz en Windows y OSD del monitor. Un monitor de 200 Hz puede mostrar hasta 200 actualizaciones/s, pero un cap superior puede reducir cola/input latency a costa de consumo/variación.
- Confirmar cable DisplayPort/HDMI y puerto que soporten el modo elegido.
- Revisar PSU por modelo, potencia real, antigüedad, cables y transitorios; no diagnosticar PSU solo por watts nominales.
- Separar thermal throttling, power limiting y CPU/game-thread limiting mediante telemetría, no por intuición.
