# Navigation (GoRouter) — Flutter

## Leitura Rápida

- **Quando adicionar uma nova rota**: defina constante em `app_routes.dart` e adicione `GoRoute` em `app_router.dart`.
- **Quando navegar para outra tela**: use `context.push/go/pop/replace` — SEMPRE na View, nunca no Cubit.
- **Quando o Cubit precisa disparar navegação**: emita um estado (ex: `LoginNavigateToHome`) e reaja via `BlocListener` na View — **apenas se a View for descartada** (`go`/`replace`). Se ela sobrevive (`push`), navegue direto na View; senão o estado de navegação substitui o de conteúdo e a tela fica em branco.
- **Quando usar parâmetros de path**: defina como `:id` na rota e acesse via `state.pathParameters['id']!`.
- **Quando passar objetos complexos**: use `extra` no `context.push` e recupere em `state.extra as T`.

---

## Estrutura

```
lib/config/routes/
├── app_routes.dart      # Constantes de rotas
└── app_router.dart      # Configuração do GoRouter
```

---

## Definindo Rotas (app_routes.dart)

```dart
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String home = '/home';

  // Feature: Auth
  static const String login = '/login';
  static const String register = '/register';

  // Feature: Profile
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';

  // Feature: Products
  static const String products = '/products';
  static const String productDetails = '/products/:id';
}
```

**Regras:**
- ✅ Sempre use constantes `static const String`
- ✅ Paths amigáveis: `/profile/edit`
- ✅ Parâmetros com dois-pontos: `/products/:id`
- ✅ Agrupe por feature com comentários

---

## Configurando Rotas (app_router.dart)

### Template Básico

```dart
import 'package:go_router/go_router.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashView(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeView(),
    ),
  ],
);
```

### Com Parâmetros

```dart
GoRoute(
  path: AppRoutes.productDetails,  // '/products/:id'
  builder: (context, state) {
    final id = state.pathParameters['id']!;  // ✅ Non-null
    return ProductDetailsView(productId: id);
  },
),
```

### Com Sub-rotas

```dart
GoRoute(
  path: AppRoutes.profile,
  builder: (context, state) => const ProfileView(),
  routes: [
    GoRoute(
      path: 'edit',  // ⚠️ SEM barra inicial em sub-rotas
      builder: (context, state) => const EditProfileView(),
    ),
  ],
),
```

---

## Navegando entre Telas

### push — Empilha nova tela
```dart
context.push(AppRoutes.home)
context.push('/products/${product.id}')
context.push('/products?category=electronics')
```

### go — Substitui a rota atual
```dart
context.go(AppRoutes.home)
```

### replace — Substitui no topo do stack
```dart
context.replace(AppRoutes.login)
```

### pop — Volta para tela anterior
```dart
context.pop()
context.pop('resultado')  // Passa resultado para quem chamou
```

### Aguardar resultado
```dart
final result = await context.push<String>(AppRoutes.editProfile);
if (result != null) { /* usa resultado */ }
```

---

## Padrões de Navegação

### ❌ ERRADO — BuildContext no Cubit

```dart
class HomeCubit extends Cubit<HomeState> {
  void navigateToDetails(BuildContext context) {
    context.push('/details');  // ❌ Nunca
  }
}
```

### ✅ CORRETO — Opção 1: Navegação direta na View

```dart
ElevatedButton(
  onPressed: () {
    _cubit.selectProduct(product);  // Lógica no Cubit
    context.push('/products/${product.id}');  // Navegação na View
  },
  child: Text(l10n.viewDetailsButton),
)
```

### ✅ CORRETO — Opção 2: Estado de navegação + BlocListener

**Só use quando a View de origem é descartada na navegação** — login → home, splash → home,
logout → login. Isto é, quando a transição usa `go`/`replace` e ninguém volta para a tela anterior.

```dart
// State
class LoginNavigateToHome extends LoginState {
  const LoginNavigateToHome();

  @override
  String toString() => 'LoginNavigateToHome';
}

// Cubit
result.when(
  ok: (_) => emit(const LoginNavigateToHome()),
  error: (e) => emit(LoginError(LoginErrorKind.invalidCredentials, error: e)),
);

// View
BlocConsumer<LoginCubit, LoginState>(
  listener: (context, state) {
    if (state is LoginNavigateToHome) context.go(AppRoutes.home);
  },
  builder: (context, state) { /* ... */ },
)
```

### ⚠️ Estado de navegação apaga a tela quando ela sobrevive

O State é **um só**. Emitir `HomeNavigateToDetails` substitui `HomeLoaded`, e o `BlocBuilder` da
mesma View passa a receber um estado que ele não sabe renderizar — cai no `SizedBox.shrink()` final
e a tela fica em branco. Ao voltar do `push`, o estado continua sendo o de navegação: a lista não
reaparece.

```dart
// ❌ ERRADO — a Home some ao empilhar os detalhes e não volta
void selectProduct(String id) => emit(HomeNavigateToDetails(id));
```

Para navegação de onde o usuário **volta** (`push`), navegue direto na View:

```dart
// ✅ CORRETO — o estado da Home permanece HomeLoaded
onTap: () {
  context.read<HomeCubit>().registerVisit(product.id); // efeito no Cubit, se houver
  context.push('/products/${product.id}');             // navegação na View
}
```

Se a navegação depende de uma decisão assíncrona do Cubit (checar permissão, salvar antes de sair),
mantenha o conteúdo no estado e carregue o destino como um campo consumível:

```dart
class HomeLoaded extends HomeState {
  const HomeLoaded({required this.products, this.navigateToId});

  final List<ProductEntity> products;
  final String? navigateToId; // ✅ intenção de navegação sem perder o conteúdo

  @override
  String toString() =>
      'HomeLoaded(products: ${products.length}, navigateToId: $navigateToId)';
}

// Cubit — emite com a intenção, depois limpa
void selectProduct(String id) {
  final current = state;
  if (current is! HomeLoaded) return;
  emit(HomeLoaded(products: current.products, navigateToId: id));
  emit(HomeLoaded(products: current.products)); // ✅ consome a intenção
}

// View
listener: (context, state) {
  if (state is HomeLoaded && state.navigateToId != null) {
    context.push('/products/${state.navigateToId}');
  }
},
```

| Transição | Padrão |
|---|---|
| `push` — usuário volta para esta tela | Navegue na View (Opção 1) |
| `go`/`replace` — a View é descartada | Estado de navegação (Opção 2) |
| Decisão assíncrona no Cubit, View sobrevive | Campo consumível dentro do estado de conteúdo |

### Navegação após ação assíncrona

```dart
BlocListener<LoginCubit, LoginState>(
  listener: (context, state) {
    if (state is LoginSuccess) context.go(AppRoutes.home);
  },
  child: BlocBuilder<LoginCubit, LoginState>(
    builder: (context, state) { /* ... */ },
  ),
)
```

---

## Casos Especiais

### Passando Objetos Complexos

```dart
// Navegação
context.push(AppRoutes.productDetails, extra: product);

// No router
GoRoute(
  path: AppRoutes.productDetails,
  builder: (context, state) {
    final product = state.extra as ProductEntity;
    return ProductDetailsView(product: product);
  },
),
```

### Guards / Redirects

```dart
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  redirect: (context, state) {
    final isLoggedIn = _checkIfLoggedIn();
    final isGoingToLogin = state.matchedLocation == AppRoutes.login;

    if (!isLoggedIn && !isGoingToLogin) return AppRoutes.login;
    if (isLoggedIn && isGoingToLogin) return AppRoutes.home;
    return null;
  },
  routes: [ /* ... */ ],
);
```

### Bottom Navigation Bar com ShellRoute

```dart
final GoRouter appRouter = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeView()),
        GoRoute(path: AppRoutes.products, builder: (_, __) => const ProductsView()),
        GoRoute(path: AppRoutes.profile, builder: (_, __) => const ProfileView()),
      ],
    ),
  ],
);
```

---

## Checklist para Nova Rota

- [ ] 1. Adicionar constante em `app_routes.dart`
- [ ] 2. Adicionar `GoRoute` em `app_router.dart`
- [ ] 3. Implementar navegação na View ou `BlocListener`
- [ ] 4. Testar navegação (push, pop, params)

---

## Erros Comuns

| Erro | Correto |
|---|---|
| `Navigator.of(context).push(...)` | `context.push(AppRoutes.home)` |
| Barra inicial em sub-rota: `path: '/edit'` | `path: 'edit'` (sem barra) |
| `state.pathParameters['id']` sem `!` | `state.pathParameters['id']!` |
| Navegação no Cubit com BuildContext | Navegação na View ou BlocListener |
