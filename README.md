# Taller Tycoon: código fuente

Prototipo Roblox/Luau con parcelas por jugador, monedas, garaje coleccionable, ingresos, mejoras, renacimientos y guardado con control de sesiones. Esta distribución contiene solo código, pruebas y documentación. No incluye modelos de terceros ni archivos de experiencia listos para abrir.

## Límites de esta copia

**No se puede reconstruir ni jugar sin aportar los cuatro modelos visuales.** `tools/build.py`, `tools/check.py` y `default.project.json` esperan esos archivos locales. El generador construye el escenario propio desde `tools/scene.py`; `assets/Workshop.rbxmx` tampoco se distribuye, se genera al reconstruir.

No se incluyen credenciales, datos de jugadores, historial Git, ejecutables ni modelos. Las sesiones de Studio usan datos temporales separados; el guardado real requiere verificarlo en una experiencia propia publicada. No hay pases de Robux configurados.

## Conseguir los modelos por separado

El registro local `assets/vehicle-sources.json`, fechado el 12 de noviembre de 2026, identifica estos modelos como publicados por Roblox (ID 1). Comprueba en Creator Store el autor, disponibilidad y condiciones vigentes antes de utilizarlos:

| Archivo de entrada | Modelo / enlace |
|---|---|
| Sedan.rbxmx | [Sedan, 6418239833](https://create.roblox.com/store/asset/6418239833/Sedan) |
| SportsCar.rbxmx | [Sports Car, 6433323089](https://create.roblox.com/store/asset/6433323089/Sports-Car) |
| Pickup.rbxmx | [Pickup Truck, 6418225759](https://create.roblox.com/store/asset/6418225759/Pickup-Truck) |
| Supercar.rbxmx | [Supercar, 6433330180](https://create.roblox.com/store/asset/6433330180/Supercar) |

1. Obtén cada modelo desde su página oficial con tu propia cuenta y bajo las [condiciones de Creator Store](https://en.help.roblox.com/hc/en-us/articles/21308223046932-Creator-Store-Terms).
2. Insértalo en un lugar de trabajo separado de Roblox Studio, sin ejecutar scripts del modelo. Selecciona una variante visual cuyo modelo raíz contenga un hijo `Body`.
3. Exporta esa variante como Roblox XML Model (`.rbxmx`) y colócala en `.tools/asset-candidates/` con el nombre exacto de la tabla. Si el archivo obtenido es binario `.rbxm`, no basta cambiar su extensión: expórtalo a XML desde Studio o conviértelo con una herramienta adecuada obtenida de su fuente oficial.
4. Ejecuta `python tools/prepare_vehicles.py`. La herramienta espera esa estructura `Body`, conserva geometría y elimina scripts/controladores. Escribe las cuatro plantillas normalizadas en `assets/vehicles/`. Si cambia la estructura del modelo oficial, habrá que adaptar el importador; no se garantiza compatibilidad con futuras versiones.
5. Ejecuta `python tools/build.py`. Genera `Taller Tycoon.rbxlx`, su nombre heredado `Taller de medianoche.rbxlx` y el escenario `assets/Workshop.rbxmx`, únicamente en tu copia de trabajo.
6. Abre `Taller Tycoon.rbxlx` en Studio y prueba con Play. Guarda aparte cualquier edición manual antes de reconstruir, porque el generador reemplaza esos archivos.

El indicador histórico `isPublicDomain` del registro es un campo de disponibilidad de la API, no una licencia independiente de redistribución. Los modelos y mallas no están incluidos en este repositorio; conserva los créditos y comprueba las condiciones aplicables. No se han descargado ni redistribuido modelos para esta publicación.

## Pruebas sin modelos

Python 3.10+ basta para las herramientas; para compilar/probar Luau, coloca los ejecutables oficiales `luau` y `luau-compile` en PATH o `.tools/luau`. No se incluyen esos ejecutables.

Desde la raíz:

```sh
python -c "import sys; sys.path.insert(0, 'tools'); import check; check.check_luau(True)"
```

Esta comprobación compila fuentes y ejecuta pruebas simuladas de economía/guardado, sin importar modelos, abrir Studio ni conectar DataStore. No verifica gráficos ni interacción real.

Después de preparar los modelos y construir:

```sh
python tools/check.py --require-luau
```

## Estructura

- `src/shared/Config.luau`: balance y precios.
- `src/shared/Economy.luau`: compras, ingresos y renacimientos.
- `src/server/`: validación, mundo, progreso y sesiones.
- `src/client/Main.client.luau`: interfaz y controles.
- `tools/`: escenario, importación visual, generador y comprobaciones.
- `tests/`: pruebas con servicios simulados.

El código se publica como prototipo. No se concede una licencia sobre modelos de Roblox ni se presenta este proyecto como producto oficial de Roblox.