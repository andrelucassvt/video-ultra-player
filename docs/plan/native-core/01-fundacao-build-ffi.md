# Core nativo C++ — Parte 1: Fundação de build e ponte FFI

> **Objetivo da parte:** `libvup_core.so` compila no host Linux (com testes GoogleTest) e dentro do APK do plugin; o Dart chama `vup_core_version()` via FFI.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** nenhuma

## Contexto

O repositório não tem código C/C++ nem dependência de FFI. Esta parte cria o esqueleto que todas as fases usam: o layout `src/` (núcleo portável separado do código de plataforma), a API C como única superfície exposta, o build no host para testes rápidos sem aparelho e o build Android via `externalNativeBuild`. Nenhuma API pública do plugin muda.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `src/CMakeLists.txt` | criar | Alvo `vup_core` (SHARED), C++20, `-Wall -Wextra -Werror`; opção `VUP_BUILD_TESTS`; inclui `platform/android/` só quando `ANDROID` |
| `src/include/vup_core.h` | criar | API C: `vup_core_version()`, `vup_core_abi_version()`; `extern "C"`, `VUP_EXPORT` |
| `src/core/version.cpp` | criar | Implementação da API mínima |
| `src/tests/CMakeLists.txt` + `src/tests/version_test.cpp` | criar | GoogleTest via `FetchContent` (tag fixa `v1.15.2`) |
| `android/build.gradle.kts` | alterar | `externalNativeBuild { cmake { path = file("../src/CMakeLists.txt") } }`, `ndkVersion = "28.2.13676358"`, `abiFilters` |
| `pubspec.yaml` | alterar | `ffi` em `dependencies`, `ffigen` em `dev_dependencies` |
| `ffigen.yaml` | criar | Gera `lib/src/ffi/vup_core_bindings.g.dart` a partir de `src/include/vup_core.h` |
| `lib/src/ffi/vup_core_library.dart` | criar | Carrega a lib (`DynamicLibrary.open('libvup_core.so')` no Android; `UnsupportedError` nas demais plataformas) |
| `lib/video_ultra_player_core_bench.dart` | criar | Entrada **experimental** separada (não exportada por `video_ultra_player.dart`): `coreVersion()` |
| `test/core_library_test.dart` | criar | Contrato do loader fora do Android |
| `.gitignore` | alterar | `build/host/` |

## Fases

### Fase 1 — Testes do host (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Criar `src/CMakeLists.txt` com `project(vup_core LANGUAGES CXX)`, `CMAKE_CXX_STANDARD 20`, alvo `vup_core` listando `core/version.cpp`, `target_include_directories(... PUBLIC include)` e `if(VUP_BUILD_TESTS) add_subdirectory(tests) endif()`
- [ ] Criar `src/tests/CMakeLists.txt` com `FetchContent_Declare(googletest GIT_TAG v1.15.2)`, executável `vup_core_tests` ligado a `vup_core` e `GTest::gtest_main`, `gtest_discover_tests`
- [ ] Criar `src/tests/version_test.cpp`: `vup_core_version()` devolve `"0.1.0"` (string não nula, terminada em `\0`); `vup_core_abi_version()` devolve `1`
- [ ] Criar `src/include/vup_core.h` só com as declarações (macro `VUP_EXPORT` = `__attribute__((visibility("default")))`, guard `extern "C"`), sem implementação
- [ ] Verificação: `cmake -S src -B build/host -DVUP_BUILD_TESTS=ON && cmake --build build/host` falha **na linkagem** por símbolos ausentes (não por erro de sintaxe)

### Fase 2 — API C mínima (fazer os testes passarem)

- [ ] Criar `src/core/version.cpp` implementando as duas funções (`static constexpr const char* kVersion = "0.1.0"`)
- [ ] No `CMakeLists.txt`: `set_target_properties(vup_core PROPERTIES CXX_VISIBILITY_PRESET hidden)` para exportar só o que tem `VUP_EXPORT`
- [ ] Adicionar `build/host/` ao `.gitignore`
- [ ] Verificação: `cmake --build build/host && ctest --test-dir build/host --output-on-failure` passa

### Fase 3 — Build Android

- [ ] Em `android/build.gradle.kts`: `ndkVersion = "28.2.13676358"` dentro de `android {}`; `externalNativeBuild { cmake { path = file("../src/CMakeLists.txt"); version = "3.22.1" } }`; em `defaultConfig`: `ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }` e `externalNativeBuild { cmake { arguments += listOf("-DANDROID_STL=c++_shared") } }`
- [ ] Em `src/CMakeLists.txt`: quando `ANDROID`, `target_compile_definitions(vup_core PRIVATE __ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__)` e `target_compile_options(vup_core PRIVATE -Werror=unguarded-availability)` — o plugin mantém `minSdk 24` e as APIs 26+ (AImageReader, AHardwareBuffer) da parte 2 ficam atrás de `__builtin_available(android 26, *)`
- [ ] Confirmar que o CMake do SDK Android tem a versão `3.22.1` instalada (`ls ~/Android/Sdk/cmake`); se não houver, usar a versão presente e registrar aqui
- [ ] Verificação: `cd example && flutter build apk --debug` conclui e `unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libvup_core.so` lista as 3 ABIs; anotar o aumento de tamanho do APK em relação ao `master`

### Fase 4 — Ponte Dart (testes primeiro)

- [ ] Adicionar `ffi: ^2.1.0` em `dependencies` e `ffigen` em `dev_dependencies` do `pubspec.yaml` com `flutter pub add` (sem `pub upgrade`)
- [ ] Criar `test/core_library_test.dart`: fora do Android (host do `flutter test`), `VupCoreLibrary.open()` lança `UnsupportedError` com mensagem citando "Android"; `coreVersion()` propaga o mesmo erro
- [ ] Criar `ffigen.yaml` (`headers.entry-points: [src/include/vup_core.h]`, `output: lib/src/ffi/vup_core_bindings.g.dart`, `name: VupCoreBindings`) e gerar com `dart run ffigen`; adicionar `lib/src/ffi/*.g.dart` ao `analyzer.exclude`
- [ ] Criar `lib/src/ffi/vup_core_library.dart` (`VupCoreLibrary.open()` → `VupCoreBindings`, cacheado em `static final`) e `lib/video_ultra_player_core_bench.dart` com `String coreVersion()` (dartdoc marcando como experimental)
- [ ] Verificação: `flutter test` e `flutter analyze` limpos

### Fase 5 — Checkpoint

- [ ] Verificação final: `ctest --test-dir build/host` + `flutter test` + `flutter analyze` + `flutter build apk --debug` (em `example/`) passam
- [ ] Checkpoint: commit das mudanças da parte + resumo curto do que ficou pronto, seguindo direto para a parte 2

## Critérios de Sucesso

- [ ] Testes C++ rodam no host Linux sem aparelho
- [ ] APK de debug contém `libvup_core.so` para as 3 ABIs
- [ ] `coreVersion()` existe numa entrada experimental separada; a API pública `video_ultra_player.dart` não muda
- [ ] Build sem erros
- [ ] Todos os testes unitários passando (`flutter test`, `ctest`, `./gradlew testDebugUnitTest`)
- [ ] _(manual — feito pelo usuário)_ No emulador, uma chamada a `coreVersion()` no example devolve `"0.1.0"`

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `FetchContent` exige rede no configure | Média | Tag fixa; se o ambiente estiver offline, vendorizar GoogleTest em `src/third_party/` |
| `c++_shared` conflita com outro plugin que embarque `libc++_shared.so` diferente | Baixa | NDK fixado; se ocorrer, trocar para `c++_static` (só uma `.so` nossa usa a STL) |
| `externalNativeBuild` deixa o build do example mais lento | Média | Aceitável; o CMake cacheia entre builds |

## Rollback

Reverter o commit da parte: remove `src/`, `lib/src/ffi/`, `ffigen.yaml`, a entrada experimental e o bloco `externalNativeBuild`.
