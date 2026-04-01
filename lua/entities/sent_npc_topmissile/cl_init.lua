include( "shared.lua" )

-- ============================================================
--  CLIENT  –  rendering, particles, exhaust effects
--  100% stock GMod / HL2 materials only
-- ============================================================

local matFire = Material( "effects/fire_cloud1" )
local matHeat = Material( "effects/heatwave" )   -- stock GMod refract

function ENT:Initialize()
    -- Make the model visible
    self:SetRenderMode( RENDERMODE_NORMAL )
    self:SetModelScale( 1 )

    self.Emitter  = ParticleEmitter( self:GetPos(), false )
    self.Seed     = math.Rand( 0, 10000 )
end

function ENT:Think()
    self:NextThink( CurTime() )
    return true
end

function ENT:Draw()
    -- Always draw the model first so it is never invisible
    self:DrawModel()

    if not self.Emitter then
        self.Emitter = ParticleEmitter( self:GetPos(), false )
        self.Seed    = math.Rand( 0, 10000 )
    end

    -- Nozzle is at the back of the rocket model
    local nozzle  = self:LocalToWorld( Vector( -20, 0, 0 ) )
    local forward = self:GetForward()
    local engineOn = self:GetNWBool( "EngineStarted", false )

    -- ======================================================
    --  PRE-IGNITION: soft white/grey smoke puff
    -- ======================================================
    if not engineOn then
        local smoke = self.Emitter:Add( "effects/smoke_a", nozzle )
        if smoke then
            smoke:SetVelocity( forward * -300 + VectorRand() * 20 )
            smoke:SetDieTime( math.Rand( 0.6, 1.0 ) )
            smoke:SetStartAlpha( math.Rand( 60, 100 ) )
            smoke:SetEndAlpha( 0 )
            smoke:SetStartSize( math.random( 8, 14 ) )
            smoke:SetEndSize( math.random( 40, 70 ) )
            smoke:SetColor( 200, 200, 200 )
            smoke:SetRoll( math.Rand( 0, 360 ) )
            smoke:SetRollDelta( math.Rand( -1, 1 ) )
            smoke:SetGravity( Vector( 0, 0, 30 ) )
            smoke:SetAirResistance( 40 )
        end
        return
    end

    -- ======================================================
    --  AFTERBURNER CONE – orange/yellow fire at nozzle
    -- ======================================================
    for i = 1, 3 do
        local fire = self.Emitter:Add( "effects/fire_cloud1", nozzle )
        if fire then
            fire:SetVelocity( forward * -math.Rand( 60, 140 ) + VectorRand() * 15 )
            fire:SetDieTime( math.Rand( 0.04, 0.09 ) )
            fire:SetStartAlpha( math.Rand( 200, 255 ) )
            fire:SetEndAlpha( 0 )
            fire:SetStartSize( math.random( 6, 12 ) )
            fire:SetEndSize( math.random( 22, 40 ) )
            fire:SetAirResistance( 80 )
            fire:SetRoll( math.Rand( 0, 360 ) )
            fire:SetRollDelta( math.Rand( -4, 4 ) )
            -- Alternate orange and yellow
            if i == 1 then
                fire:SetColor( 255, 80,  0   )
            elseif i == 2 then
                fire:SetColor( 255, 160, 0   )
            else
                fire:SetColor( 255, 220, 30  )
            end
        end
    end

    -- Bright yellow flare at nozzle tip
    local flare = self.Emitter:Add( "effects/yellowflare", nozzle )
    if flare then
        flare:SetVelocity( forward * -20 )
        flare:SetDieTime( math.Rand( 0.02, 0.05 ) )
        flare:SetStartAlpha( 255 )
        flare:SetEndAlpha( 0 )
        flare:SetStartSize( math.random( 10, 18 ) )
        flare:SetEndSize( math.random( 60, 90 ) )
        flare:SetRoll( math.Rand( 0, 360 ) )
        flare:SetColor( 255, 200, 50 )
    end

    -- ======================================================
    --  SMOKE TRAIL  – billowing dark smoke behind the missile
    -- ======================================================
    for i = 1, 2 do
        local trail = self.Emitter:Add( "effects/smoke_a", nozzle )
        if trail then
            trail:SetVelocity( forward * -math.Rand( 20, 60 )
                             + VectorRand() * 8 )
            trail:SetDieTime( math.Rand( 1.2, 2.2 ) )
            trail:SetStartAlpha( math.Rand( 80, 140 ) )
            trail:SetEndAlpha( 0 )
            trail:SetStartSize( math.random( 12, 20 ) )
            trail:SetEndSize( math.random( 80, 140 ) )
            trail:SetColor( 60, 60, 60 )
            trail:SetRoll( math.Rand( 0, 360 ) )
            trail:SetRollDelta( math.Rand( -0.5, 0.5 ) )
            trail:SetGravity( Vector( 0, 0, 18 ) )
            trail:SetAirResistance( 20 )
        end
    end

    -- ======================================================
    --  DYNAMIC ORANGE LIGHT – illuminates surroundings
    -- ======================================================
    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        dlight.Pos        = self:GetPos()
        dlight.r          = 255
        dlight.g          = 140 + math.random( -10, 10 )
        dlight.b          = 0
        dlight.Brightness = 2
        dlight.Decay      = 256
        dlight.Size       = 300
        dlight.DieTime    = CurTime() + 0.05
    end

    -- ======================================================
    --  BEAM EXHAUST  – fire plume using render.StartBeam
    -- ======================================================
    local scroll = self.Seed + CurTime() * -12
    local tip    = nozzle
    local vN     = forward * -1   -- pointing backwards

    render.SetMaterial( matFire )
    render.StartBeam( 4 )
        render.AddBeam( tip,                   28, scroll,     Color( 255, 100,   0, 200 ) )
        render.AddBeam( tip + vN * 20,          20, scroll + 1, Color( 255, 180,   0, 160 ) )
        render.AddBeam( tip + vN * 50,          12, scroll + 2, Color( 255, 220,  50, 80  ) )
        render.AddBeam( tip + vN * 90,           4, scroll + 3, Color( 255, 255, 200, 0   ) )
    render.EndBeam()

    -- Heat distortion shimmer
    render.UpdateRefractTexture()
    render.SetMaterial( matHeat )
    render.StartBeam( 3 )
        render.AddBeam( tip,          30, scroll * 0.4, Color( 0, 0, 255, 60  ) )
        render.AddBeam( tip + vN * 20, 14, scroll * 0.4, Color( 0, 0, 255, 120 ) )
        render.AddBeam( tip + vN * 48,  0, scroll * 0.4, Color( 0, 0, 255, 0   ) )
    render.EndBeam()
end

function ENT:OnRemove()
    if self.Emitter then
        self.Emitter:Finish()
        self.Emitter = nil
    end
end
