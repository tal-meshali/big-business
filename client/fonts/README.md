# Fonts

`archivo_black.ttf` (Archivo, weight 900), `nunito_sans_extrabold.ttf` and `nunito_sans_bold.ttf` (Nunito Sans, weights 800 and 700) are the design's type, from Google Fonts under the SIL Open Font License 1.1 (see `OFL-Archivo.txt` and `OFL-NunitoSans.txt`). `UiTheme` loads them: Archivo Black for titles, counts and scores, Nunito Sans ExtraBold as the default UI font, Bold for paragraphs.

`emoji_subset.ttf` is Noto Color Emoji (SIL Open Font License 1.1, see `OFL.txt`) cut down to the emoji the game shows: the six emotes and the smiley on the emote button (the three medals are still in the subset but the dividend panel now shows places as numbers). It is the first fallback of every font built in `scripts/ui/ui_theme.gd`, so emoji render the same on every phone instead of depending on the system font (without it they draw as hex boxes when the OS font is unreachable).

Regenerate after adding an emoji anywhere in the client (`pip install fonttools`):

```
pyftsubset NotoColorEmoji.ttf \
  --unicodes="U+1F44B,U+1F44F,U+1F604,U+1F60A,U+1F622,U+1F62E,U+1F914,U+1F947,U+1F948,U+1F949" \
  --layout-features='' --no-hinting --output-file=client/fonts/emoji_subset.ttf
```

The source file ships with most Linux distributions (`fonts-noto-color-emoji`) and at https://github.com/googlefonts/noto-emoji. The font has one 109 px bitmap strike; `UiTheme.EMOJI_STRIKE_PX` must match it so the emoji scale to the label size.
