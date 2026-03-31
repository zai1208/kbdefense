import raylib
import tables
import sequtils
import std/strutils

const
  SCREEN_W = 800
  SCREEN_H = 600
  FONT_SIZE = 20
  CELL_W = 10
  CELL_H = 20
  GRID_COLS = 80
  GRID_ROWS = 40
  COMMANDS = ["TURRET", "WALL", "SWEEPER", "COREBASE"]

type
  Color2 = enum
    cWhite, cGrey, cGreen, cYellow, cRed

  Cell = object
    ch: char
    color: Color2
    lifetime: float32
    alpha: float32
    permanent: bool = false

var
  cursorX: int = 0
  cursorY: int = 0
  dirX: int = 1
  dirY: int = 0
  camX, camY: float32 = 0
  tickTimer: float32 = 0
  typingBuffer: string = ""
  grid: Table[(int, int), Cell]
  blinkTimer: float32 = 0
  blinkOn: bool = true

proc toRayColor(c: Color2): Color =
  case c
  of cWhite:  White
  of cGrey:   Gray
  of cGreen:  Green
  of cYellow: Yellow
  of cRed:    Red

proc placeChar(ch: char, col: Color2, lifetime: float32 = 0.0, alpha: float32, permanent: bool = false) =
  if not grid.getOrDefault((cursorX + dirX, cursorY + dirY)).permanent:
    grid[(cursorX, cursorY)] = Cell(ch: ch, color: col, lifetime: lifetime, alpha: alpha, permanent: permanent)
    cursorX += dirX
    cursorY += dirY
proc blinkRed() =
  var bx = cursorX - dirX
  var by = cursorY - dirY
  for c in countdown(typingBuffer.len - 1, 0):
    if typingBuffer[c] != ' ':
      grid[(bx, by)].color = cRed
      grid[(bx, by)].lifetime = 2.0
    bx -= dirX
    by -= dirY

proc executeCommand(cmd: string) =
  case cmd
  of "TURRET":
    cursorX -= dirX * 6
    for i in 0..2:
      for c in "TURRET":
        placeChar(c, cGreen, -1.0, 1.0, true)
      cursorY += 1
      cursorX -= dirX * 6
    cursorX += dirX * 6
    cursorY -= 3
  of "WALL":
    placeChar('#', cGrey, 0.0, 1.0)
  of "SWEEPER":
    placeChar('S', cYellow, 0.0, 1.0)
  of "COREBASE":
    placeChar('C', cRed, 0.0, 1.0)
proc handleInput() =
  # direction keys
  if isKeyPressed(KeyboardKey.Right): dirX = 1;  dirY = 0
  if isKeyPressed(KeyboardKey.Left):  dirX = -1; dirY = 0
  if isKeyPressed(KeyboardKey.Down):  dirX = 0;  dirY = 1
  if isKeyPressed(KeyboardKey.Up):    dirX = 0;  dirY = -1
  if isKeyPressed(KeyboardKey.Enter):
    var matched = ""
    for cmd in COMMANDS:
      if typingBuffer.endsWith(cmd):
        matched = cmd
        break
    if matched != "":
      executeCommand(matched)
    else:
      blinkRed()
    typingBuffer = ""
  if isKeyPressed(KeyboardKey.Backspace) and not grid.getOrDefault((cursorX - dirX, cursorY - dirY)).permanent:
    cursorX -= dirX
    cursorY -= dirY
    grid[(cursorX, cursorY)] = Cell(ch: '\0', color: cWhite)
    if typingBuffer.len > 0:
      typingBuffer.setLen(typingBuffer.len - 1)
  # typing
  var ch = getCharPressed()
  while ch != 0:
    if ch >= 32 and ch <= 126:
      let c = char(ch)
      typingBuffer.add(c)
      if c == ' ':
        # just advance cursor
        cursorX += dirX
        cursorY += dirY
      else:
        placeChar(c, cWhite, 6.0, 1.0)
    ch = getCharPressed()

proc gameTick() =
  discard # enemies, turrets etc later

proc main() =
  initWindow(SCREEN_W, SCREEN_H, "game")
  setTargetFPS(60)
  var codepoints: seq[int32] = @[0x25B6.int32, 0x25C0.int32, 0x25BC.int32, 0x25B2.int32]
  for i in 32..126:
    codepoints.add(i.int32)

  let font = loadFont("/usr/share/fonts/TTF/IosevkaTerm-Extended.ttf", FONT_SIZE, codepoints)
  setTextureFilter(font.texture, TextureFilter.Bilinear)
  let fontBold = loadFont("/usr/share/fonts/TTF/IosevkaTerm-ExtendedBold.ttf", FONT_SIZE, codepoints)
  setTextureFilter(fontBold.texture, TextureFilter.Bilinear)

  while not windowShouldClose():
    let dt = getFrameTime()

    # tick
    tickTimer += dt
    if tickTimer >= 1.0:
      gameTick()
      tickTimer = 0.0

    blinkTimer += dt
    if blinkTimer >= 0.5:
      blinkOn = not blinkOn
      blinkTimer = 0.0
    # input
    handleInput()

    # camera lerp toward cursor
    let targetX = float32(cursorX * CELL_W) - SCREEN_W / 2
    let targetY = float32(cursorY * CELL_H) - SCREEN_H / 2
    camX += (targetX - camX) * 0.1
    camY += (targetY - camY) * 0.1

    # draw
    beginDrawing()
    clearBackground(Color(r: 38, g: 38, b: 51, a: 255))

    for (pos, cell) in grid.mpairs:
      if cell.lifetime > 0:
        cell.lifetime -= dt
        cell.alpha -= dt / cell.lifetime
      if cell.lifetime <= 0 and cell.lifetime != -1.0:
        cell.ch = '\0'
      if cell.ch != '\0':
        let sx = float32(pos[0] * CELL_W) - camX
        let sy = float32(pos[1] * CELL_H) - camY
        let colour = toRayColor(cell.color)
        drawText(font, $cell.ch, Vector2(x: sx, y: sy),
                float32(FONT_SIZE), 0.0'f32, colorAlpha(toRayColor(cell.color), cell.alpha))

    # draw cursor
    let cx = float32(cursorX * CELL_W) - camX
    let cy = float32(cursorY * CELL_H) - camY

    let arrow =
      if dirX == 1:    ">"
      elif dirX == -1: "<"
      elif dirY == 1:  "v"
      else:            "^"
    if blinkOn:
      drawRectangle(int32(cx), int32(cy), CELL_W, CELL_H, White)
      drawText(fontBold, arrow, Vector2(x: cx, y: cy), float32(FONT_SIZE), 0.0'f32, Color(r: 38, g: 38, b: 51, a: 255))
    else:
      drawRectangle(int32(cx), int32(cy), CELL_W, CELL_H, Color(r: 255, g: 255, b: 255, a: 130))
      drawText(fontBold, arrow, Vector2(x: cx, y: cy), float32(FONT_SIZE), 0.0'f32, Color(r: 38, g: 38, b: 51, a: 255))
    endDrawing()

  closeWindow()

main()
