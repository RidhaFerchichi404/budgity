# Design system: "Evergreen"

Dark-only, green-tinted, calm. The goal is a *financially responsible* feel: quiet surfaces, one accent,
and color used to carry meaning, not decoration. The source of truth is `lib/app/theme/app_theme.dart`.

## Tokens

| Token | Hex | Use |
|---|---|---|
| background | `#0B1210` | Page |
| surface | `#111A17` | Cards, nav bar |
| surfaceHigh / Highest | `#17221E` / `#1E2B26` | Inputs, dialogs / badges, progress track |
| outline | `#2A3A34` | Hairline card borders, dividers |
| onSurface / muted | `#E6EFEB` / `#9BB0A7` | Primary / secondary text |
| primary | `#3DD9A0` | Actions, focus, "on track" |
| primaryContainer | `#0F3B2C` | Selected nav, income badges, balance hero tint |
| income | `#4ADE9A` | Money in |
| expense | = onSurface | Money out stays **neutral**, with a "−" sign |
| warning | `#F2C25B` | Budget ≥ 80 % |
| over | `#FF8A80` | Over budget, destructive actions |

Every text pair is ≥ 4.5:1 and the progress bar is ≥ 3:1, enforced by `test/unit/theme_contrast_test.dart`.

## Rules

- **Red means over budget, not spending.** Ordinary expenses are neutral so the app doesn't feel like a scold.
- **Color is never the only signal.** Amounts carry +/−, and budgets show a % and a word ("On track",
  "Close to limit", "Over budget").
- **Type:** IBM Plex Sans (bundled, works offline), tabular figures for every amount.
- **Shape:** flat cards, 1 px outline, 14 px radius (20 px for the balance hero and dialogs), no shadows.
- **Hierarchy:** one hero number per screen (the dashboard's total balance). Section labels are small uppercase.
- **Touch:** buttons are ≥ 48 px tall, and list rows use the standard ListTile height.

## Visual review

`flutter test test/visual --update-goldens` renders the main screens to `test/visual/goldens/*.png`
with real fonts and sample data. These are tagged `golden` and excluded from Linux CI.
