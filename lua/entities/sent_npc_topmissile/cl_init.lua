include( "shared.lua" )

-- ============================================================
--  CLIENT  –  rendering, particles, exhaust effects
--  100% stock GMod / HL2 materials only
-- ============================================================

local matFire     = Material( "effects/fire_cloud1" )
local matHeatWave = Material( "sprites/bf4_heatwave" )

function ENT:Initialize()
    self.Emitter = ParticleEmitter( self:GetPos(), false )
    self.Seed    = math.Rand( 0, 10000 )
    self.Emittime = 0
end

function ENT:Draw()
    self:DrawModel()

    if not self.Emitter then
        self.Emitter = ParticleEmitter( self:GetPos(), false )
        self.Seed    = math.Rand( 0, 10000 )
    end

    self:NextThink( CurTime() )

    local nozzle = self:LocalToWorld( Vector( -14, 0, 0 ) )

    -- ---- Pre-ignition smoke puff ----
    if not self:GetNWBool( "EngineStarted" ) then
        local smoke = self.Emitter:Add( "effects/smoke_a", nozzle )
        if smoke then
            smoke:SetVelocity( self:GetForward() * -800 )
            smoke:SetDieTime( math.Rand( 0.9, 1.2 ) )
            smoke:SetStartAlpha( math.Rand( 11, 25 ) )
            smoke:SetEndAlpha( 0 )
            smoke:SetStartSize( math.random( 14, 18 ) )
            smoke:SetEndSize( math.random( 66, 99 ) )
            smoke:SetRoll( math.Rand( 180, 480 ) )
            smoke:SetRollDelta( math.Rand( -2, 2 ) )
            smoke:SetGravity( Vector( 0, math.random( 1, 90 ), math.random( 51, 155 ) ) )
            smoke:SetAirResistance( 60 )
        end
        return
    end

    -- ---- Dynamic orange glow at nozzle ----
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

    -- ---- Exhaust fire particles ----
    for i = 1, 2 do
        local fire = self.Emitter:Add( "effects/smoke_a", nozzle )
        if fire then
            fire:SetVelocity( self:GetForward() * -10 )
            fire:SetDieTime( math.Rand( 0.05, 0.1 ) )
            fire:SetStartAlpha( math.Rand( 222, 255 ) )
            fire:SetEndAlpha( 0 )
            fire:SetStartSize( math.random( 3, 6 ) )
            fire:SetEndSize( math.random( 20, 33 ) )
            fire:SetAirResistance( 150 )
            fire:SetRoll( math.Rand( 180, 480 ) )
            fire:SetRollDelta( math.Rand( -3, 3 ) )
            fire:SetColor( 255, 90 + ( i * 20 ), 0 )
        end
    end

    -- Yellow flare
    local flare = self.Emitter:Add( "effects/yellowflare", nozzle )
    if flare then
        flare:SetVelocity( self:GetForward() * -10 )
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

    -- ---- Beam / heatwave render ----
    local vOffset = nozzle
    local vNormal = ( vOffset - self:GetPos() ):GetNormalized()
    local scroll  = self.Seed + ( CurTime() * -10 )
    local Scale   = 0.5

    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                          32 * Scale, scroll,     Color( 0,   0,   255, 128 ) )
        render.AddBeam( vOffset + vNormal * 60  * Scale,  16 * Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 148 * Scale,  16 * Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()

    scroll = scroll * 0.5
    render.UpdateRefractTexture()
    render.SetMaterial( matHeatWave )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                          45 * Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 16  * Scale,  16 * Scale, scroll + 2, Color( 255, 255, 255, 255 ) )
        render.AddBeam( vOffset + vNormal * 64  * Scale,  24 * Scale, scroll + 5, Color(   0,   0,   0,   0 ) )
    render.EndBeam()

    scroll = scroll * 1.3
    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                          8 * Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 32  * Scale,  8 * Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 108 * Scale,  8 * Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()
end
