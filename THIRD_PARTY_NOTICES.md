# Third-party notices

VoxType builds on the following open-source work. Thank you to their authors.

## whisper.cpp and ggml

Speech recognition engine, included as a git submodule in `whisper.cpp/` and compiled into VoxType.

- Source: https://github.com/ggml-org/whisper.cpp
- License: MIT — Copyright (c) 2023-2026 The ggml authors
- Full text: [`whisper.cpp/LICENSE`](whisper.cpp/LICENSE)

## OpenAI Whisper models

The speech models that `setup.sh` downloads (`ggml-*.bin`) are OpenAI's Whisper models, converted to the ggml format by the whisper.cpp project and hosted on Hugging Face.

- Original models: https://github.com/openai/whisper
- License: MIT — Copyright (c) 2022 OpenAI
- Converted files: https://huggingface.co/ggerganov/whisper.cpp

## Optional components

These are not part of VoxType. They are installed only if you choose to, and each has its own license:

- [Ollama](https://github.com/ollama/ollama) (MIT), and the models you download with it, such as Meta's Llama 3.2 under the [Llama 3.2 Community License](https://www.llama.com/llama3_2/license/).
- [Homebrew](https://brew.sh) (BSD 2-Clause) and [CMake](https://cmake.org) (BSD 3-Clause), used only to build.
