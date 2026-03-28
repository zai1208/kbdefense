import raylib

const
  SCREEN_W = 800
  SCREEN_H = 600
  FONT_SIZE = 20
  CELL_W = 12
  CELL_H = 20

const testWords = [
  "TURRET",
  "TURRET",
  "TURRET",
  "",
  "COREBASE",
  "COREBASE",
  "COREBASE",
  "COREBASE",
  "",
  "SWEEPER",
  "",
  "....#####.....",
  "..WALL.WALL...",
  "R O D A X P L",
]

proc main() =
  initWindow(SCREEN_W, SCREEN_H, "Font Test")
  setTargetFPS(60)

  let font = loadFont("/usr/share/fonts/TTF/IosevkaTerm-Extended.ttf")
  setTextureFilter(font.texture, TextureFilter.Bilinear)
  while not windowShouldClose():
    beginDrawing()
    clearBackground(Black)

    for i, line in testWords:
      drawText(font, line, Vector2(x: 40.0, y: float32(40 + i * 20)), float32(20), 2.0'f32, White)

    endDrawing()

  closeWindow()

main()
