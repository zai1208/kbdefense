import raylib
import tables
import sequtils
import std/strutils
import std/math
import std/random

const
  cloudMask = [
    (1, 0), (2, 0),           # row 0:  @$
    (0, 1), (1, 1), (2, 1), (3, 1),  # row 1: $%@$
    (1, 2), (2, 2), (3, 2),  # row 2:  @$%
    (2, 3)                    # row 3:   @
  ]
  SCREEN_W = 800
  SCREEN_H = 600
  FONT_SIZE = 20
  CELL_W = 10
  CELL_H = 20
  GRID_COLS = 80
  GRID_ROWS = 40
  COMMANDS = ["TURRET", "WALL", "SWEEPER", "COREBASE"]

type
  Cell = object
    ch: char
    color: Color
    targetColor: Color
    lifetime: float32
    maxLifetime: float32
    alpha: uint8
    permanent: bool = false
    bufferIndex: int = -1

  Turret = object
    x, y: int
    facingX: int
    facingY: int
    hp: int

  Core = object
    x, y: int
    hp: int

  Enemy = object
    x, y: int
    drawX, drawY: float32  # visual position, lerps toward x,y
    size: int
    hp: int
    chars: array[10, char]
    moveTimer: float32
    moveSpeed: float32
    resourceDrop: int

var
  cursorX: int = 0
  cursorY: int = 0

  turretCost = 10
  wallCost = 4
  coreCost = 50

  dirX: int = 1
  dirY: int = 0

  camX, camY: float32 = 0

  tickTimer: float32 = 0

  typingBuffer: string = ""

  grid: Table[(int, int), Cell]
  turrets: seq[Turret] = @[]
  cores: seq[Core] = @[]
  enemies: seq[Enemy] = @[]

  blinkTimer: float32 = 0
  blinkOn: bool = true

  warningMsg: string = ""
  warningTimer: float32 = 0.0
  resources: int = 100
  corehp: int = 18
  maxCorehp: int = 18
  wave: int = 1

proc warn(msg: string) =
  warningMsg = msg
  warningTimer = 2.0

proc canPlace(x: int, y: int): bool =
  for row in 0..<y:
    for col in 0..<x:
      let tx = cursorX - dirX * (col + 1)
      let ty = cursorY + row
      if grid.getOrDefault((tx, ty)).permanent:
        return false
  return true

proc canPlaceCore(): bool =
  #TODO: Add check for if actually on a core tile
  return canPlace(8, 4)

proc barrelCells(facingX, facingY: int): seq[(int, int)] =
  if facingX == 1 and facingY == 0:
    return @[(3,1),(4,1),(5,1)]
  elif facingX == -1 and facingY == 0:
    return @[(0,1),(1,1),(2,1)]
  elif facingX == 0 and facingY == -1:
    return @[(2,0),(3,0),(2,1),(3,1)]
  elif facingX == 0 and facingY == 1:
    return @[(2,1),(3,1),(2,2),(3,2)]
  elif facingX == 1 and facingY == -1:
    return @[(2,0),(3,0),(4,0),(5,0),(2,1),(3,1),(4,1),(5,1)]
  elif facingX == -1 and facingY == -1:
    return @[(0,0),(1,0),(2,0),(3,0),(0,1),(1,1),(2,1),(3,1)]
  elif facingX == 1 and facingY == 1:
    return @[(2,1),(3,1),(4,1),(5,1),(2,2),(3,2),(4,2),(5,2)]
  elif facingX == -1 and facingY == 1:
    return @[(0,1),(1,1),(2,1),(3,1),(0,2),(1,2),(2,2),(3,2)]
  else:
    return @[]

proc nearestCorebase(ex, ey: int): (int, int) =
  var bestX = 0
  var bestY = 0
  var bestDist = int.high
  for core in cores:
    let dist = abs(core.x - ex) + abs(core.y - ey)
    if dist < bestDist:
      bestDist = dist
      bestX = core.x
      bestY = core.y
  return (bestX, bestY)



proc spawnEnemy(x, y, size: int) =
  enemies.add(Enemy(x: x, y: y, drawX: float32(x), drawY: float32(y), size: size, hp: size * size, moveTimer: 0.0, moveSpeed: 0.5, resourceDrop: size * 2))

proc updateEnemies(dt: float32) =
  for enemy in enemies.mitems:
    enemy.moveTimer += dt
    if enemy.moveTimer >= enemy.moveSpeed:
      enemy.moveTimer = 0.0
      let (cx, cy) = nearestCorebase(enemy.x, enemy.y)
      let dx = cx - enemy.x
      let dy = cy - enemy.y
      if abs(dx) > abs(dy):
        enemy.x += sgn(dx)
      else:
        enemy.y += sgn(dy)

proc drawEnemies(font: Font) =
  for enemy in enemies.mitems:
    for (dc, dr) in cloudMask:
      let sx = (float32(enemy.x) + float32(dc)) * CELL_W - camX
      let sy = (float32(enemy.y) + float32(dr)) * CELL_H - camY
      if enemy.moveTimer >= enemy.moveSpeed * 0.9:
        enemy.chars[(dr * 6 + dc) mod 10] = char(rand(33..126))
      drawText(font, $enemy.chars[(dr * 6 + dc) mod 10], Vector2(x: sx, y: sy), float32(FONT_SIZE), 0.0'f32, Red)

proc placeChar(ch: char, col: Color, lifetime: float32 = 0.0, alpha: uint8, permanent: bool = false, targetColor: Color = White, bufferIndex: int = -1) =
  if not grid.getOrDefault((cursorX + dirX, cursorY + dirY)).permanent:
    grid[(cursorX, cursorY)] = Cell(ch: ch, color: col, targetColor: targetColor, lifetime: lifetime, maxLifetime: lifetime, alpha: alpha, permanent: permanent, bufferIndex: bufferIndex)
    cursorX += dirX
    cursorY += dirY

proc blinkRed() =
  var bx = cursorX - dirX
  var by = cursorY - dirY
  for c in countdown(typingBuffer.len - 1, 0):
    if typingBuffer[c] != ' ' and grid.contains((bx, by)) and not grid[(bx, by)].permanent:
      grid[(bx, by)].color = Red
      grid[(bx, by)].targetColor = White
    bx -= dirX
    by -= dirY

proc executeCommand(cmd: string) =
  case cmd
  of "TURRET":
    if canPlace(6, 3) and dirX == 1 and dirY == 0 and resources >= turretCost:
      resources -= turretCost
      cursorX -= dirX * 6
      for i in 0..2:
        for c in "TURRET":
          placeChar(c, Color(r: 128, g: 239, b: 128, a: 128), -1.0, 255, true, Color(r: 128, g: 239, b: 128, a: 128))
        cursorY += 1
        cursorX -= dirX * 6
      cursorX += dirX * 6
      cursorY -= 3
      turrets.add(Turret(x: cursorX - dirX * 6, y: cursorY, facingX: dirX, facingY: dirY))
    else:
      if resources < turretCost:
        warn("Not enough resources!")
      else:
        warn("Cannot place turret here!")
      blinkRed()
  of "WALL":
    if canPlace(4, 1) and resources >= wallCost:
      resources -= wallCost
      cursorX -= dirX * 4
      cursorY -= dirY * 4
      for c in "WALL":
        placeChar(c, Green, -1.0, 255, true, Green)
    else:
      if resources < wallCost:
        warn("Not enough resources!")
      else:
        warn("Cannot place wall here!")
      blinkRed()
  of "SWEEPER":
    #TODO: Implement sweeper
    discard
  of "COREBASE":
    if canPlaceCore() and dirX == 1 and dirY == 0 and resources >= coreCost:
      resources -= coreCost
      cursorX -= dirX * 8
      cursorY -= dirY * 4
      for row in 0..<4:
        for c in "COREBASE":
          placeChar(c, Color(r: 53, g: 200, b: 220, a: 255), -1.0, 255, true, Color(r: 53, g: 200, b: 220, a: 255))
        cursorY += 1
        cursorX -= dirX * 8
      cursorX += dirX * 8
      cursorY -= 4
      cores.add(Core(x: cursorX - dirX * 8, y: cursorY))
      spawnEnemy(15, 15, wave * 3)
      spawnEnemy(20, 15, wave * 3)
      spawnEnemy(15, 20, wave * 3)
    else:
      if resources < coreCost:
        warn("Not enough resources!")
      else:
        warn("Cannot place core base here!")
      blinkRed()

proc handleInput() =
  # direction keys
  if isKeyPressed(KeyboardKey.Right): dirX = 1;  dirY = 0
  if isKeyPressed(KeyboardKey.Left):  dirX = -1; dirY = 0
  if isKeyPressed(KeyboardKey.Down):  dirX = 0;  dirY = 1
  if isKeyPressed(KeyboardKey.Up):    dirX = 0;  dirY = -1
  if isKeyPressed(KeyboardKey.Space):
    typingBuffer = ""
  if isKeyPressed(KeyboardKey.Enter):
    var matched = ""
    for cmd in COMMANDS:
      if typingBuffer.endsWith(cmd) and not grid.getOrDefault((cursorX - dirX, cursorY - dirY)).permanent:
        matched = cmd
        break
    if matched != "":
      executeCommand(matched)
    else:
      if not grid.getOrDefault((cursorX - dirX, cursorY - dirY)).permanent:
        blinkRed()
  if isKeyPressed(KeyboardKey.Backspace) and not grid.getOrDefault((cursorX - dirX, cursorY - dirY)).permanent and not (grid.getOrDefault((cursorX - dirX, cursorY - dirY)).ch == '\0'):
    cursorX -= dirX
    cursorY -= dirY
    grid[(cursorX, cursorY)] = Cell(ch: '\0', color: White)
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
        placeChar(c, White, 6.0, 255, bufferIndex = typingBuffer.len - 1)
    ch = getCharPressed()

proc barrelUpdate() = 
  for turret in turrets.mitems:
    let dark = barrelCells(turret.facingX, turret.facingY)
    for row in 0..<3:
      for col in 0..<6:
        let tx = turret.x + col
        let ty = turret.y + row
        if grid.contains((tx, ty)):
          if (col, row) in dark:
            grid[(tx, ty)].color = Color(r: 0, g: 255, b: 0, a: 255)
            grid[(tx, ty)].targetColor = Color(r: 0, g: 255, b: 0, a: 255)
          else:
            grid[(tx, ty)].color = Color(r: 128, g: 239, b: 128, a: 128)
            grid[(tx, ty)].targetColor = Color(r: 128, g: 239, b: 128, a: 128)
    turret.hp = 0
    for row in 0..<3:
      for col in 0..<6:
        if grid.getOrDefault((turret.x + col, turret.y + row)).ch != '\0':
          turret.hp += 1

proc main() =
  initWindow(SCREEN_W, SCREEN_H, "SECTOR\\0")
  setTargetFPS(60)
  randomize()
  var codepoints: seq[int32] = @[0x2588.int32, 0x2591.int32]
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
      tickTimer = 0.0

    blinkTimer += dt
    if blinkTimer >= 0.5:
      blinkOn = not blinkOn
      blinkTimer = 0.0

    updateEnemies(dt)
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

    barrelUpdate()

    for (pos, cell) in grid.mpairs:
      if cell.lifetime > 0:
        cell.lifetime -= dt
        cell.color.a = uint8(255.0 * max(cell.lifetime, 0) / cell.maxLifetime)
      if cell.lifetime <= 0 and not cell.permanent:
        if cell.bufferIndex >= 0 and cell.bufferIndex < typingBuffer.len:
          typingBuffer[cell.bufferIndex] = ' '
        cell.ch = '\0'
        cell.color.a = 0
      if cell.color != cell.targetColor:
        # lerp r, g, b toward target
        cell.color.r = uint8(float32(cell.color.r) + (float32(cell.targetColor.r) - float32(cell.color.r)) * dt * 3.0)
        cell.color.g = uint8(float32(cell.color.g) + (float32(cell.targetColor.g) - float32(cell.color.g)) * dt * 3.0)
        cell.color.b = uint8(float32(cell.color.b) + (float32(cell.targetColor.b) - float32(cell.color.b)) * dt * 3.0)

      if cell.ch != '\0':
        let sx = float32(pos[0] * CELL_W) - camX
        let sy = float32(pos[1] * CELL_H) - camY
        drawText(font, $cell.ch, Vector2(x: sx, y: sy),
                float32(FONT_SIZE), 0.0'f32, cell.color)
    if typingBuffer.allIt(it == ' '):
      typingBuffer = ""
    drawEnemies(font)
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
    if warningTimer > 0:
      warningTimer -= dt
      drawText(font, warningMsg, Vector2(x: 10.0, y: float32(SCREEN_H - 30)), float32(FONT_SIZE), 0.0'f32, colorAlpha(Red, warningTimer / 2.0))
    let filled = int(float32(corehp) / float32(maxCorehp) * 10.0)
    let bar = "█".repeat(filled) & "░".repeat(10 - filled)
    let hud = "RES: " & $resources & "    CORE: " & $corehp & "/" & $maxCorehp & " " & bar & "    WAVE: " & $wave
    drawText(font, hud, Vector2(x: 10.0, y: 10.0), float32(FONT_SIZE), 0.0'f32, White)

    endDrawing()

  closeWindow()

main()
