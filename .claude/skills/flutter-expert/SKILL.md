---
name: flutter-expert
description: >
  Guia de implementação Flutter em Clean Architecture (Presentation → Domain ← Data, com BLoC/Cubit + GetIt +
  GoRouter). Use antes de implementar qualquer feature, tela, widget, service, rota, repositório ou camada em
  Flutter, e ao decidir o que criar (UI simples vs dados locais vs API). Cobre View, Cubit/State, Domain, Data,
  Services, DI, Navegação, Testes, layout/theming, diretrizes Apple e troubleshooting de BLoC + GetIt + GoRouter.
---

# Flutter Expert

Os padrões aqui descritos são uma **proposta de arquitetura de referência**, não uma regra universal.

**Em projeto desconhecido, explore antes de gerar código.** Se o projeto já tem convenção própria de pastas,
nomenclatura ou tratamento de erro, siga a do projeto — `references/architecture.md` explica como identificá-la
e onde a proposta continua valendo mesmo em estruturas diferentes.

## Referências

Leia apenas o que a tarefa exigir.

| Referência | Quando ler |
|---|---|
| `references/architecture.md` | Projeto desconhecido — entender a proposta e mapear a estrutura real |
| `references/view.md` | Views (tela, StatefulWidget, BlocBuilder, BlocConsumer, SafeArea) |
| `references/view-model.md` | Cubits e States (async, `Result<T>`, debounce, formulário, paginação, logs no BlocObserver) |
| `references/widget.md` | Criar ou extrair widgets (`widgets/`, `content/`, `common/widgets/`) |
| `references/domain.md` | Entities e Repository Interfaces (`lib/domain/**`) |
| `references/data.md` | Models, DataSources e RepositoryImpl (`lib/data/**`) |
| `references/service.md` | Services em `common/services/` (flags, contadores, gating, onboarding, premium) |
| `references/di.md` | Registro de dependências no AppInjector (`lib/config/inject/**`) |
| `references/navigation.md` | Rotas, guards, deep links, navegação (`lib/config/routes/**`) |
| `references/testing.md` | Testes de Cubit (`blocTest`), RepositoryImpl (fakes) e widget (`MockCubit`) |
| `references/layout-theming.md` | Layout adaptativo, `Stack`/`OverlayPortal`, `ThemeExtension`, `WidgetStateProperty`, component themes |
| `references/troubleshooting.md` | Erro em runtime/build durante a implementação |
| `references/apple-guidelines.md` | Submissão na App Store, rejeição Apple, `NSUsageDescription`, ATT, IAP obrigatório, Sign in with Apple, HIG, ATS |

## Exemplos

Código pronto e correto. Prefira partir do cenário mais próximo a gerar do zero.

| Exemplo | Cenário |
|---|---|
| `examples/example-tela-simples.md` | Tela sem API — View + Cubit + State + Rota + DI |
| `examples/example-feature-api.md` | Feature completa com API REST — todas as camadas |
| `examples/example-service.md` | Common Services — onboarding, feature gate, premium, review prompt |
| `examples/example-widgets.md` | Extração de widgets — StatelessWidget, StatefulWidget, content vs widgets |
| `examples/example-navegacao.md` | Navegação — push/go/pop, parâmetros, guard, ShellRoute |
| `examples/example-formulario.md` | Formulário com validação de campos e submit assíncrono |

---

## Convenções do time

Valem em todas as camadas. Onde o projeto já tiver convenção conflitante, siga o projeto.

- **Imports absolutos** — `package:<app>/...`, nunca relativos.
- **Textos da UI via `context.l10n.<chave>`** — nenhuma string visível ao usuário hardcoded.
- **`SafeArea`** envolvendo o conteúdo principal da View.
- **Navegação fica na View ou em `BlocListener`** — o Cubit não recebe `BuildContext`.
- **Erros viram `Result<T>` (Ok/Error) no Repository** — o Repository não relança exceção para cima.
  Ele checa o status HTTP antes do parsing e classifica a falha em `AppException`, preservando causa
  e stack trace. O Cubit escolhe a mensagem pelo **tipo** da falha, nunca por string.
- **DI**: Cubits em `registerFactory`; o restante em `registerLazySingleton`.
- **Entities**: `@immutable`, `const`, campos `final`, `copyWith()`, `==` e `hashCode` sobre os mesmos
  campos — `listEquals` no `==` exige `Object.hashAll` no `hashCode`, e `==` não checa `runtimeType`.
- **Cubit async**: emite `Loading` → chama o repository → resolve com `result.when()`.
- **Persistência local passa por `StorageService`** — o Cubit não fala com `SharedPreferences`.
- **`toString()` legível em todo State**, para o log do `BlocObserver`: declare o método na `sealed class` e
  implemente com nome explícito em cada State concreto. States com payload mostram os campos relevantes; States
  de erro incluem ao menos a mensagem e, quando houver, erro técnico/stack trace. Nunca exponha senha, token ou
  outro segredo; resuma payloads grandes.
- **Nome de View**: `snake_case` com sufixo `_view.dart` derivado do nome real da feature — não `view-teste.dart`,
  `nova_view` ou `screen1`.
- **Não crie arquivos `.md`** para documentar mudanças de código.

### Composição de View

A View orquestra estado, navegação e estrutura principal. Blocos de UI ficam **inline no `build()`** — nunca como
`Widget _buildXxx()` nem como classe privada dentro do arquivo da View.

Extraia para arquivo próprio só quando o bloco passar na regra de corte: **>45 linhas, ou repetido 2+ vezes, ou
com estado próprio** (controller, timer, `setState`). Destino da extração:

| Escopo | Pasta |
|---|---|
| Bloco de uma única View | `presentation/<feature>/content/` |
| Reutilizado dentro da feature | `presentation/<feature>/widgets/` |
| Compartilhado entre features | `common/widgets/` |

Dialogs, bottom sheets e handlers privados (`void _showXxx()`, `void _onXxx()`) podem permanecer na View.

---

## O que criar em uma nova feature

```
Precisa de API ou banco externo?
  ├─ SIM → Entity + Repository Interface (domain.md)
  │        + Model + DataSource + RepositoryImpl (data.md)
  │        + registro no AppInjector (di.md)
  │
  └─ NÃO ─ precisa persistir localmente?
             ├─ SIM → StorageService injetado no Cubit, sem Data Layer
             │        (view-model.md, Opção A2)
             └─ NÃO → View + Cubit + State + rota + DI
```

| Situação | O que criar | Referência |
|---|---|---|
| Tela simples / UI local | View + Cubit + State | `view.md` + `view-model.md` |
| Rota nova | AppRoutes + GoRoute | `navigation.md` |
| Cubit novo | `registerFactory` | `di.md` |
| Dados locais | StorageService no Cubit | `view-model.md` (Opção A2) |
| API externa | Entity + Interface + Model + DataSource + RepositoryImpl | `domain.md` + `data.md` |
| Flag, contador, gating, onboarding | `common/services/` | `service.md` |
| Widget novo | ver "Composição de View" acima | `widget.md` |

---

## Ordem de implementação

Domain → Data → DI → Presentation (Cubit + State + View + widgets) → Rota → L10n (`.arb` + `flutter gen-l10n`).

Comece pelo primeiro passo que a feature realmente exige: tela sem dados externos pula Domain e Data.
Quando algo falhar no caminho, consulte `references/troubleshooting.md`.

---

## Limites da arquitetura

Independentemente da estrutura de pastas do projeto, evite:

- Cubit acessando DataSource diretamente, sem passar por repositório ou serviço
- `domain/` importando qualquer coisa de `data/`
- Widgets fora de `presentation/` ou `common/widgets/`
- Arquivos barrel/export

A estrutura de pastas completa da proposta está em `references/architecture.md`.
