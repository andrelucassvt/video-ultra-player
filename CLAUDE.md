# Base App Flutter — Claude Code Instructions

Projeto Flutter com Clean Architecture. Todas as regras aqui são obrigatórias para geração e modificação de código.

---

## 🏗️ Arquitetura

```
Presentation → Domain ← Data
```

- **Presentation**: Views (StatefulWidget) + Cubits/States (BLoC)
- **Domain**: Entities + Repository Interfaces (contratos puros)
- **Data**: Models + DataSources + Repository Implementations

**Dependências proibidas**: `domain` não importa `data`; Cubit não acessa DataSource diretamente; classes de `data/` não são importadas em `domain/`.

---

## 📂 Estrutura de Pastas (OBRIGATÓRIA)

```
lib/
├── presentation/
│   └── <feature>/
│       ├── view/<feature>_view.dart
│       ├── view_model/<feature>_cubit.dart
│       ├── view_model/<feature>_state.dart
│       ├── widgets/          # reutilizáveis dentro da feature
│       └── content/          # auxiliares de UI específicos (não reutilizáveis)
│
├── domain/
│   ├── entities/<entity>_entity.dart
│   └── interfaces/<feature>_repository.dart
│
├── data/
│   ├── models/<entity>_model.dart
│   ├── datasources/<feature>_remote_datasource.dart
│   └── repositories/<feature>_repository_impl.dart
│
├── common/
│   ├── widgets/
│   ├── styles/
│   ├── utils/
│   └── services/
│
└── config/
    ├── error/result_pattern.dart
    ├── routes/app_router.dart + app_routes.dart
    ├── inject/app_injector.dart
    └── app_initializer.dart
```

**Proibido:**
- Widgets fora de `presentation/` (exceto `common/widgets/`)
- Acessar DataSources diretamente do Cubit
- Importar classes de `data/` dentro de `domain/`
- Criar arquivos barrel/export

---

## 🧭 Fluxo para nova feature

```
Feature precisa de API ou banco externo?
  ├─ SIM → Entity + Repository Interface (domain)
  │         + Model + DataSource + RepositoryImpl (data)
  │         + registrar DataSource e Repository no AppInjector
  │
  └─ NÃO ─ precisa persistir dados localmente?
              ├─ SIM → injetar StorageService no Cubit (sem Data Layer)
              └─ NÃO → apenas View + Cubit + State + rota + DI
```

| Situação | O que criar |
|---|---|
| Tela simples / UI local | View + Cubit + State + rota + DI |
| Dados locais | + `StorageService` no Cubit |
| API externa | + Entity + Interface + Model + DataSource + RepositoryImpl |
| Widget reutilizável na feature | `presentation/<feature>/widgets/` |
| Widget reutilizável entre features | `common/widgets/` |
| Auxiliar de UI específico de uma View | `presentation/<feature>/content/` |
| Recurso do dispositivo (storage, bio, notif) | `common/services/` |

---

## ⚡ Regras Globais

### Geral
- **Imports**: SEMPRE absolutos — `package:base_app/...` — NUNCA relativos
- **Textos na UI**: SEMPRE `context.l10n.<chave>` — ZERO strings hardcoded visíveis ao usuário
- **Logs**: `log()` de `dart:developer` — NUNCA `print()`
- **`const`**: use sempre que possível; trailing commas obrigatório
- **Arquivos `.md`**: NUNCA crie para documentar mudanças de código

### View (StatefulWidget)
- Instancia Cubit via `AppInjector.inject.get<XxxCubit>()`; chama `_cubit.close()` no `dispose()`
- Carrega dados no `initState()`; sem lógica de negócio na View
- Envolva o conteúdo principal com `SafeArea`
- NUNCA crie `Widget _buildXxx()` nem classes privadas de widget na View — extraia para `widgets/` (reutilizável) ou `content/` (auxiliar específico); dialog/bottomSheet são exceção
- Navegação SEMPRE na View ou `BlocListener` — NUNCA passe `BuildContext` ao Cubit

### Cubit
- Dependências injetadas via construtor
- Async: SEMPRE emita `Loading` primeiro → chame repository → use `result.when()`
- NUNCA acesse `SharedPreferences` diretamente — use `StorageService`
- NUNCA acesse DataSource diretamente — passe pelo Repository

### State
- `sealed class` + `@immutable` + `const`; propriedades `final`; sem métodos de lógica

### Entity
- `@immutable`, `const`, `final`, `copyWith()`, `==`, `hashCode`
- Sem imports de infra; sem serialização

### Repository Interface (domain)
- Apenas contratos; retorna `Result<T>`; usa Entities; sem implementações

### Model (data)
- Extende a Entity; implementa `fromJson()`/`toJson()`; sem lógica de negócio

### DataSource
- Retorna dados brutos; lança exceções (sem try/catch); não retorna Models ou Entities

### RepositoryImpl (data)
- SEMPRE `try/catch`; retorna `Result<T>`; converte dados em Models

### DI (GetIt via AppInjector)
- `registerFactory` → Cubits (nova instância a cada `get()`)
- `registerLazySingleton` → Services, Repositories, DataSources e tudo mais
- NUNCA registre Widgets ou classes de UI

### Services (`common/services/`)
- SEMPRE interface abstrata + implementação concreta separada
- Injetados no Cubit via construtor; NUNCA acessados diretamente da View
- Registrados como `registerLazySingleton`

### Dart Moderno
- **null safety**: evite `!`; prefira `??`, `?.` e early return para garantir não-nulabilidade
- **pattern matching**: use `switch` com `when` e padrões onde simplificam condicionais
- **exhaustive switch**: prefira `switch` expressão para enums — evite `if/else if` encadeado
- **records**: use `(Type, Type)` para retornar múltiplos valores sem criar uma classe intermediária
- **arrow functions**: use `=>` para funções de uma única expressão

### Layout
- **Expanded vs Flexible**: `Expanded` preenche espaço disponível; `Flexible` encolhe sem crescer; nunca combine os dois no mesmo `Row`/`Column`
- **Wrap**: use quando widgets em `Row`/`Column` puderem ultrapassar a tela
- **Listas**: SEMPRE `ListView.builder` para listas longas — NUNCA `Column` + `.map()` para muitos itens
- **`build()` puro**: nunca faça chamadas de rede, I/O ou cálculos pesados dentro de `build()`

### Imagens
- **`Image.network`**: sempre inclua `loadingBuilder` e `errorBuilder`
- **Listas/reutilizadas**: use `cached_network_image` para imagens que aparecem em listas ou são repetidas

### Acessibilidade
- **Semantics**: adicione `Semantics(label: ...)` em elementos interativos sem texto visível (ícones, imagens clicáveis)
- **Contraste WCAG**: texto normal mínimo 4.5:1; texto grande mínimo 3:1 contra o fundo
- **Texto dinâmico**: não fixe alturas de containers com texto; use `TextOverflow` e `maxLines` com cuidado

---

## 📦 Pacotes Principais

```yaml
dependencies:
  bloc: ^9.0.1
  flutter_bloc: ^9.1.1
  get_it: ^8.0.2
  go_router: ^16.2.4
  dio: ^5.7.0
  shared_preferences: ^2.5.3
  intl: ^0.20.2
  flutter_localizations: sdk

dev_dependencies:
  bloc_test: ^10.0.0
  flutter_test: sdk
  flutter_lints: ^2.0.0
```

---

## 📋 Convenções

| Elemento | Convenção | Exemplo |
|---|---|---|
| Arquivos | `snake_case` | `home_view.dart` |
| Classes | `PascalCase` | `HomeCubit` |
| Variáveis/Métodos | `camelCase` | `loadHome()` |
| Privados | `_` prefix | `_cubit` |

- Máximo 80 caracteres por linha
- `ListView.builder` para listas longas

---

## 📖 Documentação de Flows

A pasta `./flow/` contém documentação gerada dos fluxos do projeto:

- `flow/project-structure.md` — estrutura geral, features, camadas e configuração
- `flow/flow-suggestions.md` — lista de flows ainda não documentados _(se existir)_
- `flow/<feature>.md` — flow completo de cada feature documentada

Antes de implementar uma nova feature ou debugar um fluxo existente, consulte os documentos em `./flow/` se existirem. Use `/flow <nome>` para criar ou atualizar um flow específico, ou `/flow-init` para gerar a documentação inicial do projeto inteiro.
