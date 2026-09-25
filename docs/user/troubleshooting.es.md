# Solución de problemas

Empieza por aquí: **volver a correr `./setup.sh` siempre es seguro.** Salta lo que ya está hecho y repara lo que falta. Si un paso falla, el log completo está en `build/setup.log`.

## Instalación

**"VoxType needs the full Xcode"** — Las Command Line Tools solas no alcanzan para compilar una app de Mac. Instala [Xcode](https://apps.apple.com/app/id497799835) desde la App Store, ábrelo una vez y vuelve a correr `./setup.sh`.

**Me pide la contraseña** — Solo para la configuración única de Xcode (aceptar su licencia y terminar su primer arranque) y, si aceptas, para instalar Homebrew. Escribe la contraseña con la que entras a tu Mac. Mientras escribes no aparece nada en pantalla, es normal.

**Una ventana pide instalar las "herramientas de desarrollo de línea de comandos"** — macOS lo pide la primera vez que usas `git`. Haz clic en **Instalar**, espera a que diga que terminó y vuelve a pegar las líneas de instalación.

**"No such file or directory" o "command not found: ./setup.sh"** — La Terminal no está dentro de la carpeta de VoxType. Escribe `cd voxtype`, presiona Retorno y vuelve a correr `./setup.sh`. Si lo clonaste en un lugar distinto de tu carpeta personal, escribe `cd ` (con un espacio después), arrastra la carpeta de VoxType a la ventana de la Terminal y presiona Retorno.

**Descargué el zip "Source code" y el instalador falla** — El zip no incluye el motor de voz, que es un submódulo de git, y un zip no es un repositorio de git, así que la parte que falta no se puede bajar después. Bórralo y sigue los pasos de [Instalación](../../README.es.md#instalación), que usan `git clone --recursive`.

**"The whisper.cpp folder is empty"** — El proyecto se descargó sin su motor de voz. Corre `git submodule update --init` dentro de la carpeta, o vuelve a clonar con `git clone --recursive`.

**La descarga del modelo se detuvo** — Corre `./setup.sh --model`. La descarga continúa donde se quedó, y cada archivo se compara con un checksum conocido antes de usarse.

**Falla la verificación de "Apple Silicon" o "macOS 14"** — VoxType usa la GPU de Apple (Metal) y APIs de macOS 14. Los Mac con Intel y las versiones anteriores de macOS no son compatibles.

## Usando VoxType

**No pasa nada al presionar ⌥ Espacio**
1. Revisa que el ícono de VoxType esté en la barra de menús. Si no está, abre VoxType desde Aplicaciones.
2. Puede que otra app ya use ⌥ Espacio (algunos lanzadores y selectores de idioma del teclado lo hacen). Ciérrala o cámbiale el atajo.
3. Si el ícono dice *Loading model…*, espera unos segundos. La primera carga después de abrir la app es la más lenta.

**El texto aparece en el widget pero no se pega**
VoxType necesita el permiso de **Accesibilidad** para pegar.
1. Abre Configuración del Sistema → Privacidad y seguridad → Accesibilidad.
2. Si VoxType está en la lista, selecciónalo y quítalo con **−**. (Después de actualizar, la entrada vieja deja de funcionar aunque siga viéndose activada.)
3. Haz clic en **+**, elige **Aplicaciones → VoxType** y actívalo.
4. Cierra VoxType desde su menú y vuelve a abrirlo.

**Nunca me escucha / el widget no aparece**
Revisa Configuración del Sistema → Privacidad y seguridad → **Micrófono** y confirma que VoxType esté activado. Revisa también que esté seleccionado el micrófono correcto en Configuración del Sistema → Sonido → Entrada.

**"VoxType needs a speech model"** — Corre `./setup.sh --model` y luego cierra y vuelve a abrir VoxType.

**Salen palabras equivocadas** — En Settings, elige el idioma en el que hablas en lugar de detección automática, y agrega nombres o términos técnicos en **Custom Vocabulary**. Si usas la limpieza con IA, prueba a apagarla: reescribe el texto y puede traducir frases en las que mezclas idiomas.

**Se corta la primera o las dos primeras palabras** — Activa **Settings → Keep microphone ready**. Así VoxType mantiene el micrófono abierto entre dictados y está listo apenas presionas el atajo. Mientras está activado, macOS muestra el indicador naranja del micrófono.

## Limpieza con IA (Ollama)

**Ollama no conecta** — Asegúrate de que Ollama esté corriendo: abre la app de Ollama o corre `ollama serve` en la Terminal. Luego revisa que el nombre del modelo en Settings sea uno que ya descargaste (`ollama list`). Corre `./setup.sh --ollama` para configurarlo de nuevo.

## ¿Sigues con el problema?

Abre un issue en GitHub. Cuenta qué hiciste, qué esperabas y qué pasó, y adjunta `build/setup.log` si el problema es de instalación.
