# NPC Top-Attack Terror Missile

A fully standalone Garry's Mod addon that gives NPCs a Javelin-style top-attack missile — one that **intentionally misses**.

The missile flies a convincing top-attack arc (climbs, apexes, dives) but has its aim jittered at engine ignition. It commits to landing 256–1200 units away from the actual target in a random direction. Pure psychological pressure.

## Features

- **Zero dependencies** — no other addon required. Stock HL2/GMod model, sounds, and particles only.
- **Black RPG rocket model** (`models/weapons/w_rocket.mdl` painted black via `SetColor`)
- **3-phase top-attack guidance** — climb → apex → terminal dive, just onto the wrong spot
- **Jitter baked at ignition** — committed at engine start (0.75s after launch), never corrects
- **Backblast damage** — damages entities behind the NPC launcher on fire
- **Can be shot down** — 30 HP, destroyed if damaged enough
- **30s lifetime safety net** — auto-detonates if it flies forever
- **Tunable** — `JITTER_MIN` / `JITTER_MAX` at the top of `init.lua`

## Installation

```
garrysmod/addons/npc-topmissile/
└── lua/
    ├── autorun/
    │   └── npc_topmissile_register.lua
    └── entities/
        └── sent_npc_topmissile/
            ├── shared.lua
            ├── cl_init.lua
            └── init.lua
```

## Usage

Call from anywhere in your NPC's AI:

```lua
LaunchNPCTopMissile( self, self:GetEnemy() )
```

Returns the missile entity (or `nil` if target is too close / invalid).

**Minimum fire distance:** 1024 units. The function silently refuses to fire if the target is closer.

### Example with cooldown

```lua
function ENT:Think()
    local enemy = self:GetEnemy()
    if IsValid( enemy ) then
        if ( self.MissileCooldown or 0 ) < CurTime() then
            if LaunchNPCTopMissile( self, enemy ) then
                self.MissileCooldown = CurTime() + 8
            end
        end
    end
end
```

## Tuning

In `lua/entities/sent_npc_topmissile/init.lua`:

| Variable | Default | Effect |
|---|---|---|
| `JITTER_MIN` | `256` | Minimum miss distance in units |
| `JITTER_MAX` | `1200` | Maximum miss distance in units |
| `ENT.HealthVal` | `30` | HP before missile is shot down |
| `ENT.Damage` | `2500–4500` random | Explosion damage |
| `ENT.Radius` | `512–760` random | Blast radius |

## Credits

Guidance flight profile and physics structure inspired by [javelin-top-attack](https://github.com/NachinBombin/javelin-top-attack) by Hoffa & Smithy285.
