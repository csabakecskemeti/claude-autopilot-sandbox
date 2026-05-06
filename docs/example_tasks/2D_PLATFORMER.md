  Build a polished 2D platformer game using Phaser 3 and free Kenney assets.

  Game Concept

  A robot protagonist escapes a malfunctioning factory. Three levels of increasing difficulty: Assembly Line (tutorial), Furnace Core (hazards), Rooftop Escape (boss/finale).

  Technical Stack

  - Engine: Phaser 3 (latest via npm)
  - Assets: Download from kenney.nl - use "Platformer Kit" or "Pixel Platformer" (your choice based on what looks best)
  - Build: Webpack for bundling
  - Server: Any simple HTTP server to test (python3 -m http.server works)

  Core Requirements

  Player mechanics:
  - Smooth left/right movement with acceleration
  - Jump with variable height (hold longer = jump higher)
  - One attack or ability (your choice: shoot, dash, or stomp)
  - 3 hit points, collect items to restore

  Enemies (minimum 2 types):
  - One ground patrol enemy
  - One that presents a different challenge (flying, shooting, or stationary hazard)
  - Design their behavior to be fair but challenging

  Levels:
  - Each level minimum 3 screens wide with scrolling camera
  - Use tilemaps (JSON or built programmatically)
  - Clear visual progression between levels
  - Collectibles: coins/gems for score, health pickups
  - Each level ends with a goal/exit trigger

  UI/HUD:
  - Health display
  - Score/collectibles counter
  - Simple start screen and game over screen

  Creative Decisions - YOU DECIDE:

  - Exact visual style (pixel art vs vector from Kenney options)
  - Player ability type
  - Enemy behaviors and patterns
  - Level layouts and difficulty curve
  - Sound effects (if time permits, optional)
  - Any juice/polish (particles, screen shake, etc.)

  Quality Bar

  The game should be actually playable and fun - not just technically functional. A player should be able to:
  1. Start the game
  2. Learn controls naturally in level 1
  3. Face real challenge in levels 2-3
  4. Feel satisfaction completing it

  Verification

  - Run the game and take screenshots of each level
  - Verify player can complete all 3 levels
  - Test that death/respawn works
  - Test that score persists across levels

  Go build it. Make creative decisions confidently. Test thoroughly. Call supervisor when complete.
