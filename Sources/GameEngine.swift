import Foundation
import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

struct Cell {
    var alive: Bool = false
    var age: Int = 0
    var colorIndex: Int = 0
    var deathFrame: Int = 0
    var jitterX: CGFloat = 0
    var jitterY: CGFloat = 0
}

class GameEngine {
    let width: Int
    let height: Int
    var cells: [[Cell]]
    let maxDeathFrames = 18

    // Charmtone palette by Christian Rocha (meowgorithm)
    static let palette: [NSColor] = [
        NSColor(hex: 0xFF6E63),  // bengal
        NSColor(hex: 0xFF937D),  // uni
        NSColor(hex: 0xFF985A),  // tang
        NSColor(hex: 0xFFB587),  // yam
        NSColor(hex: 0xFF577D),  // coral
        NSColor(hex: 0xFF7F90),  // salmon
        NSColor(hex: 0xFF388B),  // cherry
        NSColor(hex: 0xFF6DAA),  // tuna
        NSColor(hex: 0xFF4FBF),  // pony
        NSColor(hex: 0xFF79D0),  // cheeky
        NSColor(hex: 0xFF60FF),  // dolly
        NSColor(hex: 0xFF84FF),  // blush
        NSColor(hex: 0xEB5DFF),  // crystal
        NSColor(hex: 0xC259FF),  // violet
        NSColor(hex: 0x9953FF),  // plum
        NSColor(hex: 0x6B50FF),  // charple
        NSColor(hex: 0x4949FF),  // sapphire
        NSColor(hex: 0x4776FF),  // thunder
        NSColor(hex: 0x00A4FF),  // malibu
        NSColor(hex: 0x0ADCD9),  // turtle
        NSColor(hex: 0x00FFB2),  // julep
        NSColor(hex: 0x12C78F),  // guac
        NSColor(hex: 0xE8FF27),  // citron
        NSColor(hex: 0xF5EF34),  // mustard
    ]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        cells = Array(repeating: Array(repeating: Cell(), count: height), count: width)
        randomize()
    }

    func randomize() {
        for x in 0..<width {
            for y in 0..<height {
                let alive = Double.random(in: 0...1) < 0.25
                cells[x][y] = Cell(
                    alive: alive,
                    age: alive ? Int.random(in: 0...5) : 0,
                    colorIndex: Int.random(in: 0..<Self.palette.count),
                    deathFrame: 0
                )
            }
        }
    }

    private func neighborCount(_ x: Int, _ y: Int) -> Int {
        var count = 0
        for dx in -1...1 {
            for dy in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let nx = (x + dx + width) % width
                let ny = (y + dy + height) % height
                if cells[nx][ny].alive { count += 1 }
            }
        }
        return count
    }

    private func dominantNeighborColor(_ x: Int, _ y: Int) -> Int {
        var counts = [Int: Int]()
        for dx in -1...1 {
            for dy in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let nx = (x + dx + width) % width
                let ny = (y + dy + height) % height
                if cells[nx][ny].alive {
                    counts[cells[nx][ny].colorIndex, default: 0] += 1
                }
            }
        }
        // Slight mutation chance
        if Double.random(in: 0...1) < 0.08 {
            return Int.random(in: 0..<Self.palette.count)
        }
        return counts.max(by: { $0.value < $1.value })?.key
            ?? Int.random(in: 0..<Self.palette.count)
    }

    func step() {
        var next = cells
        var aliveCount = 0

        for x in 0..<width {
            for y in 0..<height {
                let n = neighborCount(x, y)
                let cell = cells[x][y]

                if cell.alive {
                    if n < 2 || n > 3 {
                        next[x][y].alive = false
                        next[x][y].deathFrame = 1
                        next[x][y].jitterX = CGFloat.random(in: -2...2)
                        next[x][y].jitterY = CGFloat.random(in: -2...2)
                        next[x][y].age = 0
                    } else {
                        next[x][y].age = min(cell.age + 1, 50)
                        aliveCount += 1
                    }
                } else {
                    if n == 3 {
                        next[x][y].alive = true
                        next[x][y].age = 0
                        next[x][y].colorIndex = dominantNeighborColor(x, y)
                        next[x][y].deathFrame = 0
                        aliveCount += 1
                    } else if cell.deathFrame > 0 {
                        if cell.deathFrame >= maxDeathFrames {
                            next[x][y].deathFrame = 0
                        } else {
                            next[x][y].deathFrame = cell.deathFrame + 1
                            // Vibration intensity decreases as cell fades
                            let intensity = 2.5 * (1.0 - CGFloat(cell.deathFrame) / CGFloat(maxDeathFrames))
                            next[x][y].jitterX = CGFloat.random(in: -intensity...intensity)
                            next[x][y].jitterY = CGFloat.random(in: -intensity...intensity)
                        }
                    }
                }
            }
        }

        cells = next

        // Inject life if population drops too low
        let total = width * height
        if aliveCount < total / 25 {
            for _ in 0..<5 { injectPattern() }
        } else if aliveCount < total / 12 {
            injectPattern()
        }
    }

    private func injectPattern() {
        let cx = Int.random(in: 10..<max(11, width - 10))
        let cy = Int.random(in: 10..<max(11, height - 10))
        let color = Int.random(in: 0..<Self.palette.count)

        // Random selection of active patterns
        let patterns: [[(Int, Int)]] = [
            // R-pentomino
            [(0,0),(1,0),(-1,1),(0,1),(0,2)],
            // Acorn
            [(0,0),(1,0),(1,2),(3,1),(4,0),(5,0),(6,0)],
            // Glider
            [(0,0),(1,1),(2,1),(2,0),(2,-1)],
            // Lightweight spaceship
            [(0,0),(1,-1),(2,-1),(3,-1),(3,0),(3,1),(2,2),(0,1)],
            // Diehard
            [(0,0),(1,0),(1,1),(5,1),(6,1),(7,1),(6,-1)],
        ]

        let pattern = patterns.randomElement()!
        for (dx, dy) in pattern {
            let x = cx + dx, y = cy + dy
            if x >= 0 && x < width && y >= 0 && y < height {
                cells[x][y] = Cell(alive: true, age: 0, colorIndex: color, deathFrame: 0)
            }
        }
    }
}
