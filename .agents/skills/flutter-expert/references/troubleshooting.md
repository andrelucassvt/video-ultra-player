# Troubleshooting — BLoC + GetIt + GoRouter

Consulte quando um erro em runtime, build ou análise estática aparecer durante a implementação.

| Sintoma | Causa provável | Recovery |
|---|---|---|
| `StateError: Object/factory not found for type XxxCubit` | Cubit não registrado, ou registrado como `LazySingleton` em vez de `Factory` | Adicionar `registerFactory(() => XxxCubit(...))` no AppInjector; conferir se as dependências do construtor também estão registradas |
| `BlocProvider.of<XxxCubit>` lança erro em runtime | Cubit não está acima do widget na árvore | Verificar se a rota provê o Cubit via `BlocProvider`; usar `context.read<XxxCubit>()` somente abaixo do provider |
| `flutter analyze` com erros de import | Import relativo em vez de absoluto | Substituir `import '../...'` por `import 'package:<app>/...'` |
| Chave l10n não encontrada em `context.l10n.<chave>` | Chave ausente em algum `.arb` ou código não regenerado | Adicionar a chave em todos os `.arb` e rodar `flutter gen-l10n` |
| Redirect loop no GoRouter | Condição do guard nunca é satisfeita | Logar o estado antes do `redirect`; verificar se o provider de autenticação já foi inicializado antes da avaliação da rota |
| `Result` nunca entra no caso `ok` | DataSource lança exceção sem `try/catch` no RepositoryImpl | Envolver a chamada em `try/catch` no RepositoryImpl e retornar `Result.error` no `catch` |
| Hot reload não reflete mudanças de estado | Estado persiste no Cubit em memória | Hot restart (`R` no terminal) |
| Entity/State não dispara rebuild quando os dados mudam | `==`/`hashCode` comparam por identidade e o BLoC descarta o novo estado como igual | Implementar `==`/`hashCode` sobre todos os campos relevantes, ou usar uma instância nova em vez de mutar a existente |
| Entity some de um `Set`/`Map` mesmo sendo "igual" | `==` usa `listEquals` mas `hashCode` usa `Object.hash(campo, lista)` — hash por identidade | `Object.hash(campo, Object.hashAll(lista))` — ver `domain.md` |
| Teste falha com `Expected: UserEntity … Actual: UserModel` | `==` da Entity checa `runtimeType`, e o Repository devolve Model | Remover `runtimeType == other.runtimeType` do `==`; `other is UserEntity` basta |
| API responde erro mas a tela mostra conteúdo vazio, sem mensagem | RepositoryImpl não checa status e o `fromJson` preencheu tudo com defaults (`?? ''`) | `ensureSuccess(response)` antes do parsing e defaults só em campos opcionais — ver `data.md` |
| Tela fica em branco depois de navegar e ao voltar | Estado de navegação substituiu o estado de conteúdo, e o `BlocBuilder` caiu no branch padrão | Com `push`, navegue direto na View; estado de navegação só quando a View é descartada — ver `navigation.md` |
| Teste de View lança `StateError: Object/factory not found` | O mock foi passado por `BlocProvider.value`, mas a View resolve o Cubit no `AppInjector` | Registrar o mock no `AppInjector` no `setUp` e `await reset()` no `tearDown` — ver `testing.md` |
| `MissingStubError` no primeiro `pump` de um teste de View | Método chamado no `initState` não foi stubado no `MockCubit` | `when(() => mockCubit.loadX()).thenAnswer((_) async {})` |
| Jank / frames perdidos | `build()` pesado, falta de `const`, rebuilds excessivos | `const` em widgets estáticos; extrair subárvores para `content/` ou `widgets/`; `BlocSelector` para reduzir o escopo do rebuild |
| Cubit emite depois de fechado (`Cannot emit new states after calling close`) | `emit` após `await` em um Cubit já descartado | Checar `isClosed` antes de emitir, ou cancelar a operação em `close()` |

Para travamento de UI durante processamento pesado, use a skill `flutter-isolates`.
