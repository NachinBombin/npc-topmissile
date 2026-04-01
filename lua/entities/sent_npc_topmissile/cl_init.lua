include( "shared.lua" )

-- ============================================================
--  CLIENT  – rendering, particles, exhaust
--  Vanilla GMod / HL2 assets ONLY
--
--  Trail sprite: particle/smokesprites_000N  (9 variants, all stock HL2)
--  Fire sprite:  effects/fire_cloud1         (stock GMod)
--  Flare sprite: effects/yellowflare         (stock GMod)
--  Beam mat:     effects/fire_cloud1         (no custom materials)
-- ============================================================

local matFire = Material( "effects/fire_cloud1" )

-- pre-cache all 9 smoke sprite paths
local SMOKE_SPRITES = {}
for i = 1, 9 do
    SMOKE_SPRITES[i] = "particle/smokesprites_000" .. i
end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetRenderMode( RENDERMODE_NORMAL )   -- MODEL MUST BE VISIBLE
    self:SetModelScale( 1 )

    self.Emitter  = ParticleEmitter( self:GetPos(), false )
    self.Seed     = math.Rand( 0, 10000 )
    self.Emittime = 0
end

-- ============================================================
--  Think  (client side, keeps NextThink ticking for Draw)
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    return true
end

-- ============================================================
--  Draw
-- ============================================================
function ENT:Draw()
    -- 1. Always render the physical model first
    self:DrawModel()

    -- 2. Lazy-create emitter if somehow lost
    if not self.Emitter then
        self.Emitter  = ParticleEmitter( self:GetPos(), false )
        self.Seed     = math.Rand( 0, 10000 )
        self.Emittime = 0
    end

    -- 3. Throttle: only emit particles at the same rate the reference uses
    if self.Emittime >= CurTime() then return end
    self.Emittime = CurTime()   -- no hard interval - emit every Draw tick
                                -- but the throttle check prevents re-entry

    local engineOn = self:GetNWBool( "EngineStarted", false )
    -- nozzle is at the tail of w_missile.mdl
    local nozzle   = self:LocalToWorld( Vector( -20, 0, 0 ) )
    local fwd      = self:GetForward()
    local vel      = self:GetVelocity()

    -- ============================================================
    --  PRE-IGNITION: soft launch smoke puff (matches reference)
    -- ============================================================
    if not engineOn then
        local smoke = self.Emitter:Add( SMOKE_SPRITES[ math.random(1,9) ], nozzle )
        if smoke then
            smoke:SetVelocity( fwd * -800 )
            smoke:SetDieTime( math.Rand( 0.9, 1.2 ) )
            smoke:SetStartAlpha( math.Rand( 11, 25 ) )
            smoke:SetEndAlpha( 0 )
            smoke:SetStartSize( math.random( 14, 18 ) )
            smoke:SetEndSize( math.random( 66, 99 ) )
            smoke:SetColor( 200, 200, 200 )
            smoke:SetRoll( math.Rand( 180, 480 ) )
            smoke:SetRollDelta( math.Rand( -2, 2 ) )
            smoke:SetGravity( Vector( 0, math.random(1,90), math.random(51,155) ) )
            smoke:SetAirResistance( 60 )
        end
        return
    end

    -- ============================================================
    --  DYNAMIC ORANGE LIGHT
    -- ============================================================
    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        dlight.Pos        = self:GetPos()
        dlight.r          = 250 + math.random( -5, 5 )
        dlight.g          = 170 + math.random( -5, 5 )
        dlight.b          = 0
        dlight.Brightness = 1
        dlight.Decay      = 0.1
        dlight.Size       = 2048
        dlight.DieTime    = CurTime() + 0.15
    end

    -- ============================================================
    --  AFTERBURNER FIRE  (matches reference: smoke_a + startlength)
    -- ============================================================
    local fire1 = self.Emitter:Add( "effects/fire_cloud1", nozzle )
    if fire1 then
        fire1:SetVelocity( fwd * -10 )
        fire1:SetDieTime( math.Rand( 0.05, 0.1 ) )
        fire1:SetStartAlpha( math.Rand( 222, 255 ) )
        fire1:SetEndAlpha( 0 )
        fire1:SetStartSize( math.random( 4, 5 ) )
        fire1:SetEndSize( math.random( 20, 33 ) )
        fire1:SetAirResistance( 150 )
        fire1:SetRoll( math.Rand( 180, 480 ) )
        fire1:SetRollDelta( math.Rand( -3, 3 ) )
        fire1:SetStartLength( 15 )
        fire1:SetEndLength( math.Rand( 100, 150 ) )
        fire1:SetColor( 255, 100, 0 )
    end

    local fire2 = self.Emitter:Add( "effects/fire_cloud1", nozzle )
    if fire2 then
        fire2:SetVelocity( fwd * -10 )
        fire2:SetDieTime( math.Rand( 0.05, 0.1 ) )
        fire2:SetStartAlpha( math.Rand( 222, 255 ) )
        fire2:SetEndAlpha( 0 )
        fire2:SetStartSize( math.random( 3, 6 ) )
        fire2:SetEndSize( math.random( 20, 33 ) )
        fire2:SetAirResistance( 150 )
        fire2:SetRoll( math.Rand( 180, 480 ) )
        fire2:SetRollDelta( math.Rand( -3, 3 ) )
        fire2:SetColor( 255, 110, 0 )
    end

    -- yellow flare at nozzle tip
    local flare = self.Emitter:Add( "effects/yellowflare", nozzle )
    if flare then
        flare:SetVelocity( fwd * -10 )
        flare:SetDieTime( math.Rand( 0.03, 0.05 ) )
        flare:SetStartAlpha( math.Rand( 222, 255 ) )
        flare:SetEndAlpha( 0 )
        flare:SetStartSize( math.random( 1, 5 ) )
        flare:SetEndSize( math.random( 99, 100 ) )
        flare:SetAirResistance( 150 )
        flare:SetRoll( math.Rand( 180, 480 ) )
        flare:SetRollDelta( math.Rand( -3, 3 ) )
        flare:SetColor( 255, 120, 0 )
    end

    -- ============================================================
    --  SMOKE TRAIL  - dark/black chunky sprites
    --  Uses particle/smokesprites_000N : the stock HL2 sprites
    --  that the reference's scud_trail particle system uses internally.
    --  SetColor(20,20,20) = near-black
    -- ============================================================
    for i = 1, 3 do
        local trail = self.Emitter:Add( SMOKE_SPRITES[ math.random(1,9) ], nozzle )
        if trail then
            -- velocity: oppose missile direction + small random spread
            trail:SetVelocity(
                ( vel / 10 ) * -1
                + Vector( math.Rand(-2.5,2.5), math.Rand(-2.5,2.5), math.Rand(2.5,15.5) )
                + fwd * -280
            )
            trail:SetDieTime( math.Rand( 0.42, 0.725 ) )
            trail:SetStartAlpha( math.Rand( 35, 65 ) )
            trail:SetEndAlpha( 0 )
            trail:SetStartSize( math.Rand( 12, 14 ) )
            trail:SetEndSize( math.Rand( 25, 35 ) )
            trail:SetRoll( math.Rand( 0, 360 ) )
            trail:SetRollDelta( math.Rand( -1, 1 ) )
            -- near-black trail
            trail:SetColor( 20, 20, 20 )
            trail:SetAirResistance( 100 )
            trail:SetGravity(
                fwd * -500
                + VectorRand():GetNormalized() * math.Rand(-140,140)
                + Vector( 0, 0, math.random(-15,15) )
            )
        end
    end

    -- ============================================================
    --  BEAM EXHAUST  - fire plume rendered with render.StartBeam
    --  Uses matFire only (effects/fire_cloud1 - always in GMod)
    --  NO heatwave material (crashes on some builds)
    -- ============================================================
    local vOffset = nozzle
    local vNormal = ( vOffset - self:GetPos() ):GetNormalized()
    local scroll  = self.Seed + ( CurTime() * -10 )
    local Scale   = 0.5

    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                              32 * Scale, scroll,     Color( 0,   0,   255, 128 ) )
        render.AddBeam( vOffset + vNormal * 60  * Scale,     16 * Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 148 * Scale,     16 * Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()

    scroll = scroll * 1.3
    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                              8 * Scale, scroll,     Color( 0,   0,   255, 128 ) )
        render.AddBeam( vOffset + vNormal * 32  * Scale,     8 * Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 108 * Scale,     8 * Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()
end

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    if self.Emitter then
        self.Emitter:Finish()
        self.Emitter = nil
    end
end
