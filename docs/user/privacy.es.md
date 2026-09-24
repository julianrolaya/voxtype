# Privacidad

VoxType está hecho para funcionar sin internet. Esto es exactamente lo que hace con tus datos.

## Lo que se queda en tu Mac

| Qué | Dónde | Detalle |
|---|---|---|
| Tu voz | Solo en memoria | El audio se transcribe y se descarta. Nunca se guarda en disco. |
| Historial de dictados | `~/Library/Application Support/VoxType/history.json` | Tus últimos 50 dictados. Bórralos en **History → Clear All**. |
| Modelos de voz | `~/Library/Application Support/VoxType/Models/` | Los descarga `setup.sh` una sola vez. |
| Ajustes | Preferencias de macOS (`com.voxtype.app`) | Modelo, idioma, vocabulario, opciones del widget. |
| API key de OpenAI | Llavero de macOS | Solo si ingresas una. Nunca se guarda en texto plano. |
| Registro de tiempos | `~/Library/Application Support/VoxType/perf.jsonl` | **Apagado por defecto.** Solo registra tiempos y cantidad de caracteres, nunca tu texto. |

## El portapapeles

Para escribir en cualquier app, VoxType pone el texto en el portapapeles, presiona ⌘V por ti y, cerca de medio segundo después, devuelve lo que tenías antes en el portapapeles. Si usas un gestor de portapapeles, puede que registre tus dictados.

## Lo que sale por la red

- **Por defecto: nada.** La transcripción y la limpieza opcional con Ollama ocurren en tu Mac. Ollama solo escucha en `localhost`.
- **Solo si eliges OpenAI** como proveedor de limpieza con IA: el texto transcrito (no tu audio) se envía a la API de OpenAI por HTTPS, bajo [los términos de OpenAI](https://openai.com/policies).
- `setup.sh` descarga el modelo de voz desde Hugging Face y, si se lo pides, instala Homebrew, cmake y Ollama. La app VoxType en sí no descarga nada.

VoxType no tiene analítica, telemetría ni reporte de fallos.

## Borrar todo

Corre `./uninstall.sh`. Te pregunta antes de borrar tu historial, modelos, ajustes y key guardada.
