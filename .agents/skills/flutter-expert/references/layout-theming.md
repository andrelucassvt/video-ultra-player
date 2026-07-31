# Layout e Theming Avançado — Flutter

Consulte quando a tarefa envolver layout adaptativo, sobreposição de widgets, design tokens ou estilo compartilhado entre componentes.

---

## Layout

| Widget | Quando usar |
|---|---|
| `Expanded` | Preencher todo o espaço restante no eixo principal |
| `Flexible` | Ocupar no máximo o espaço disponível, mas pode ser menor |
| `Wrap` | Itens que podem quebrar linha quando ultrapassam a largura |
| `LayoutBuilder` | Decisões de layout baseadas no espaço disponível do pai |

- **Stack + Positioned**: ancora widgets nas bordas com coordenadas exatas. Para alinhamento semântico (`center`, `bottomRight`) prefira `Align`, que não depende de coordenadas fixas.
- **OverlayPortal**: dropdowns e tooltips customizados que precisam renderizar acima da árvore de widgets.
- **LayoutBuilder**: envolva a seção que adapta layout ao espaço do pai. No widget raiz da tela, `MediaQuery` costuma ser suficiente e mais barato.

Para breakpoints, navegação responsiva e comportamento por tipo de input (mouse, teclado, toque), use a skill `flutter-adaptive-ui`.

---

## Theming

### ThemeExtension

Design tokens customizados (cores, espaçamentos, tipografia próprios do produto) vivem em `ThemeExtension<T>`:

1. Implemente `copyWith` e `lerp` — sem `lerp` correto a transição entre temas fica abrupta.
2. Registre em `ThemeData.extensions`.
3. Acesse via `Theme.of(context).extension<MyColors>()!`.

### WidgetStateProperty

- `WidgetStateProperty.resolveWith` para variar propriedades por estado (`pressed`, `disabled`, `hovered`, `focused`).
- `WidgetStateProperty.all(value)` quando o valor é o mesmo em todos os estados.

### Component Themes

Estilo compartilhado entre várias instâncias do mesmo componente pertence ao `ThemeData` (`appBarTheme`, `elevatedButtonTheme`, `cardTheme`, `inputDecorationTheme`), não a um `.copyWith` inline repetido em cada widget. Reserve o override inline para o caso realmente pontual.
