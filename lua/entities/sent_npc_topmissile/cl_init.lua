include( "shared.lua" )

-- ============================================================
--  CLIENT  – rendering, particles, exhaust
--  Vanilla GMod / HL2 assets ONLY
-- ============================================================

local matFire = Material( "effects/fire_cloud1" )

local SMOKE_SPRITES = {}
for i = 1, 9 do
    SMOKE_SPRITES[i] = "particle/smokesprites_000" .. i
end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetRenderMode( RENDERMODE_NORMAL )
    self:SetModelScale( 1 )
    self.Emitter  = ParticleEmitter( self:GetPos(), false )
    self.Seed     = math.Rand( 0, 10000 )
    self.Emittime = 0
end

function ENT:Think()
    self:NextThink( CurTime() )
    return true
end

-- ============================================================
--  Draw
-- ============================================================
function ENT:Draw()
    self:DrawModel()

    if not self.Emitter then
        self.Emitter  = ParticleEmitter( self:GetPos(), false )
        self.Seed     = math.Rand( 0, 10000 )
        self.Emittime = 0
    end

    if self.Emittime >= CurTime() then return end
    self.Emittime = CurTime()

    local engineOn = self:GetNWBool( "EngineStarted", false )
    local nozzle   = self:LocalToWorld( Vector( -20, 0, 0 ) )
    local fwd      = self:GetForward()
    local vel      = self:GetVelocity()

    -- ============================================================
    --  PRE-IGNITION smoke puff
    -- ============================================================
    if not engineOn then
        local smoke = self.Emitter:Add( SMOKE_SPRITES[ math.random(1,9) ], nozzle )
        if smoke then
            smoke:SetVelocity( fwd * -800 )
            smoke:SetDieTime( math.Rand( 0.9, 1.2 ) )
            smoke:SetStartAlpha( math.Rand( 40, 70 ) )
            smoke:SetEndAlpha( 0 )
            smoke:SetStartSize( math.random( 18, 26 ) )
            smoke:SetEndSize( math.random( 80, 120 ) )
            smoke:SetColor( 180, 180, 180 )
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
        dlight.Brightness = 1.5
        dlight.Decay      = 0.1
        dlight.Size       = 2048
        dlight.DieTime    = CurTime() + 0.15
    end

    -- ============================================================
    --  AFTERBURNER FIRE CONE
    -- ============================================================
    local fire1 = self.Emitter:Add( "effects/fire_cloud1", nozzle )
    if fire1 then
        fire1:SetVelocity( fwd * -10 )
        fire1:SetDieTime( math.Rand( 0.06, 0.12 ) )
        fire1:SetStartAlpha( math.Rand( 222, 255 ) )
        fire1:SetEndAlpha( 0 )
        fire1:SetStartSize( math.random( 6, 10 ) )
        fire1:SetEndSize( math.random( 28, 44 ) )
        fire1:SetAirResistance( 150 )
        fire1:SetRoll( math.Rand( 180, 480 ) )
        fire1:SetRollDelta( math.Rand( -3, 3 ) )
        fire1:SetStartLength( 18 )
        fire1:SetEndLength( math.Rand( 120, 180 ) )
        fire1:SetColor( 255, 100, 0 )
    end

    local fire2 = self.Emitter:Add( "effects/fire_cloud1", nozzle )
    if fire2 then
        fire2:SetVelocity( fwd * -10 )
        fire2:SetDieTime( math.Rand( 0.06, 0.12 ) )
        fire2:SetStartAlpha( math.Rand( 222, 255 ) )
        fire2:SetEndAlpha( 0 )
        fire2:SetStartSize( math.random( 4, 8 ) )
        fire2:SetEndSize( math.random( 24, 38 ) )
        fire2:SetAirResistance( 150 )
        fire2:SetRoll( math.Rand( 180, 480 ) )
        fire2:SetRollDelta( math.Rand( -3, 3 ) )
        fire2:SetColor( 255, 150, 0 )
    end

    local flare = self.Emitter:Add( "effects/yellowflare", nozzle )
    if flare then
        flare:SetVelocity( fwd * -10 )
        flare:SetDieTime( math.Rand( 0.03, 0.06 ) )
        flare:SetStartAlpha( math.Rand( 222, 255 ) )
        flare:SetEndAlpha( 0 )
        flare:SetStartSize( math.random( 4, 8 ) )
        flare:SetEndSize( math.random( 110, 140 ) )
        flare:SetAirResistance( 150 )
        flare:SetRoll( math.Rand( 180, 480 ) )
        flare:SetRollDelta( math.Rand( -3, 3 ) )
        flare:SetColor( 255, 200, 30 )
    end

    -- ============================================================
    --  SMOKE TRAIL  – fat, black, persistent
    --  5 sprites/frame, long die time, large end size
    -- ============================================================
    for i = 1, 5 do
        local trail = self.Emitter:Add( SMOKE_SPRITES[ math.random(1,9) ], nozzle )
        if trail then
            trail:SetVelocity(
                ( vel / 10 ) * -1
                + Vector( math.Rand(-3,3), math.Rand(-3,3), math.Rand(2,12) )
                + fwd * -280
            )
            trail:SetDieTime( math.Rand( 2.5, 4.0 ) )
            trail:SetStartAlpha( math.Rand( 80, 120 ) )
            trail:SetEndAlpha( 0 )
            trail:SetStartSize( math.Rand( 28, 36 ) )
            trail:SetEndSize( math.Rand( 90, 130 ) )
            trail:SetRoll( math.Rand( 0, 360 ) )
            trail:SetRollDelta( math.Rand( -0.8, 0.8 ) )
            trail:SetColor( 10, 10, 10 )   -- pure black
            trail:SetAirResistance( 80 )
            trail:SetGravity(
                fwd * -400
                + VectorRand():GetNormalized() * math.Rand(-100,100)
                + Vector( 0, 0, math.random(-10,20) )
            )
        end
    end

    -- ============================================================
    --  BEAM EXHAUST  (fire_cloud1 only – always in GMod)
    -- ============================================================
    local vOffset = nozzle
    local vNormal = ( vOffset - self:GetPos() ):GetNormalized()
    local scroll  = self.Seed + ( CurTime() * -10 )
    local Scale   = 0.5

    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                          32*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 60  * Scale,  16*Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 148 * Scale,  16*Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()

    scroll = scroll * 1.3
    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                          8*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 32  * Scale,  8*Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 108 * Scale,  8*Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
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
