# Fortnite y medición

## Índice

1. Línea base reproducible
2. Performance Mode y cuello de game thread
3. Límite de FPS, Hz y sincronización
4. Configuración y archivos
5. Replays, assets, shaders y procesos
6. Interpretación y entrega

## 1. Línea base reproducible

Registrar antes de tocar:

- versión de Fortnite, modo de render, resolución, fullscreen, 3D resolution y límite;
- refresh real de Windows/monitor, VRR, V-Sync, Reflex y HAGS;
- partida/Creative/replay, ubicación/ruta, duración y primera partida tras parche;
- replays/captura/highlights, stream/OBS/navegador y procesos de fondo;
- promedio, 1% low, 0.1% low, p95/p99 frametime, GPU, núcleo más cargado, clocks, temperaturas, RAM, disco y red.

Usar tres corridas comparables y medianas. Una partida pública no es determinista: controlar cuanto sea posible y no presentar una sola muestra como conclusión.

PresentMon/CapFrameX ofrecen frametime real. El script de sesión incluido correlaciona CPU/GPU/memoria/disco/red, pero no reemplaza una captura de FPS.

## 2. Performance Mode y game thread

Respetar Performance Mode si el usuario lo eligió. Es común que:

- la RTX/otra GPU quede con uso bajo;
- un hilo/núcleo limite draw calls, simulación, streaming y lógica;
- bajar resolución cambie poco los 1% lows;
- subir de GPU no mejore el cuello principal.

Buscar procesos de fondo, RAM/canales, clocks/temperaturas CPU, replays, asset streaming, disco, shaders, versión/parche y límite de FPS. No existe un switch que “arregle” por completo el game thread del motor; mejorar consistencia y eliminar interferencias sí es posible.

No desactivar E-cores, Hyper-Threading, afinidades ni seguridad como primera medida. Probar solo con evidencia, un cambio por vez y reversión.

## 3. Límite de FPS, Hz y sincronización

Separar refresh y cap:

- Un panel de 200 Hz no obliga a generar exactamente 200 FPS.
- Un cap sostenible por debajo del peor tramo suele mejorar estabilidad y temperatura.
- Un cap sobre el refresh puede reducir edad de frame/input latency si CPU/GPU lo sostienen, pero no hace que el panel muestre más de 200 actualizaciones/s y puede empeorar variación/consumo.
- Para competencia con V-Sync off, comparar 180/200/220/240 u opciones relevantes al hardware.
- Para VRR sin tearing, seguir el método vigente del fabricante; suele usarse un cap ligeramente inferior al refresh, pero validar juego/driver.

Usar un solo limitador principal. Evitar combinar cap interno, NVIDIA Max Frame Rate, RTSS y V-Sync sin entender la cola.

Comparar 1720x1080 estirada y 1920x1080 nativa por visibilidad, escalado y frametime. En un escenario CPU-bound, la estirada puede no elevar FPS; la preferencia competitiva sigue siendo válida.

## 4. Configuración y archivos

Ruta habitual:

```text
%LOCALAPPDATA%\FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini
```

Antes de editar:

1. Cerrar Fortnite solo con autorización y fuera de partida.
2. Copiar el archivo con fecha y hash.
3. Registrar atributo ReadOnly; quitarlo solo si impide un cambio solicitado.
4. Editar únicamente claves existentes/entendidas y validar que el juego no las sobrescriba.
5. No convertir el archivo a ReadOnly como solución universal; bloquea cambios legítimos y puede dejar settings inconsistentes.

Revisar: `FrameRateLimit`, V-Sync, motion blur, fullscreen/resolution, dynamic resolution, replay flags y claves que indiquen RHI/feature level. Los nombres cambian entre versiones: no inyectar una lista vieja sin comparar el archivo actual.

Usar Epic Launcher “Verify” ante archivos faltantes/crashes. Respaldar configuración antes de borrar caches.

## 5. Replays, assets, shaders y procesos

Replays pueden añadir trabajo de CPU/disco y provocar spikes, especialmente en peleas/endgame. Probar con:

- record replays;
- large team replays;
- Creative replays;
- high-quality replay/capture.

El usuario puede preferir conservarlos. Presentar la diferencia medida y dejar la elección, no prohibirlos.

Tras parche, driver o limpieza de shader cache, las primeras partidas pueden compilar shaders y rendir peor. Limpiar shader cache solo ante corrupción/hipótesis concreta; avisar que empeorará temporalmente.

Asset/cosmetic streaming puede causar red/disco/CPU spikes. Comparar la opción vigente de predescarga/desactivar streaming según Epic y el espacio disponible. No borrar paquetes mientras el juego está abierto.

Un stream Full HD puede competir por:

- ancho de banda y bufferbloat;
- GPU Video Decode y composición del escritorio;
- CPU/RAM del navegador;
- overlays/aceleración de hardware.

Hacer una prueba con stream activo y otra sin él. Lo mismo para OBS, Discord screen share, NVIDIA overlay, emuladores Android, Zen/Chrome/Edge y launchers.

## 6. Interpretación y entrega

Correlacionar cada spike con una causa observable:

- GPU 95–99%: bajar carga GPU o mejorar GPU/temperatura.
- GPU baja + núcleo alto: game-thread/CPU.
- GPU/CPU clocks bajan: temperatura/potencia.
- disk active/queue sube: streaming, replay, pagefile o SSD.
- RAM comprometida/paging: memoria/procesos.
- RTT sube sin caída de FPS: red.
- FPS baja sin cambio de RTT: sistema/juego.

No usar solo “GPU usage” o FPS promedio. Informar qué se midió, qué no, magnitud de mejora, variación entre corridas y ajustes que no ayudaron.
