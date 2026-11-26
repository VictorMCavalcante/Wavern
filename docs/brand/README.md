# Marca Wavern

O Wavern é um mixer de volume por app. O símbolo é uma mesa de som: três trilhos de fader com os botões em alturas crescentes, e a linha de uma onda passando pelo centro de cada botão. Fica no mesmo quadrado escuro com lilás em gradiente e brilho do ícone do CrispShot.

| Arquivo | Uso |
|---|---|
| `mark.svg` | símbolo sozinho (avatar, favicon) |
| `logo.svg` | símbolo + nome (README, site) |
| `icon.png` | ícone do app em 1024 px |
| `../../Resources/AppIcon.icns` | ícone do `.app`, gerado por `swift scripts/make-icon.swift Resources/AppIcon.icns` (também regrava `icon.png`) |
| `Sources/Wavern/BrandGlyph.swift` | glifo da barra de menu, template de 18 pt desenhado em código: botões nivelados em repouso, em onda quando algo toca |

Em 16 e 32 px o script usa uma variante mais simples: sem brilho e sem a linha da onda, com trilhos mais fortes e botões maiores.

## Paleta

| Nome | Hex | Uso |
|---|---|---|
| Lilás claro | `#C084FC` | acento, gradientes (`Theme.accentLight`) |
| Violeta fundo | `#7C3AED` | fim do gradiente de acento (`Theme.accentDeep`) |
| Brilho | `#A855F7` | halo atrás do símbolo, boost (`Theme.accentGlow`) |
| Tinta escura | `#11111B` a 0.92 | superfície do painel no modo escuro |
| Tinta clara | `#F6F0FF` a 0.92 | superfície do painel no modo claro |
| Aurora escura | `#7C3AED` `#4338CA` `#C084FC` a 0.55 | blobs do fundo no modo escuro |
| Aurora clara | `#C084FC` `#A78BFA` `#E9D5FF` a 0.55 | blobs do fundo no modo claro |
| Mudo | `#FF453A` | mudo e ações destrutivas |

O ícone do app usa as cores próprias do símbolo:

| Elemento | Valor |
|---|---|
| Fundo | gradiente diagonal `#2a2a33` → `#121218` → `#0b0b10`, borda branca a 0.12 |
| Trilhos | branco a 0.14 |
| Botões e onda | gradiente `#D8B4FE` → `#C084FC` → `#8B3DFF` |
| Brilho | radial `#A855F7` a 0.55 |

Texto e ícones do painel (`icon`, `quiet`, `hover`, `pressed`, `divider`) seguem os valores do CrispShot, em `Theme.swift`. Nada de `.accentColor` do sistema.

O nome é escrito sempre em minúsculas no logotipo ("wavern") e com inicial maiúscula no texto ("Wavern").
