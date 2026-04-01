include( "shared.lua" )

-- ============================================================
--  CLIENT  - Javelin top-attack missile
--
--  Particles are emitted from a ParticleEmitter created per-entity.
--  OnRemove() calls Emitter:Finish() which immediately kills all
--  in-flight sprites owned by this emitter — prevents ghost smoke.
-- ============================================================

local SMOKE_SPRITES = {}
for i = 1, 9 do
    SMOKE_SPRITES[i] = "particle/smokesprites_000" .. i
end

local matFire = Material( "effects/fire_cloud1" )

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

    -- Recreate emitter if it was somehow lost
    if not self.Emitter or not self.Emitter:IsValid() then
        self.Emitter  = ParticleEmitter( self:GetPos(), false )
        self.Seed     = math.Rand( 0, 10000 )
        self.Emittime = 0
    end

    -- Rate-limit to once per frame
    if self.Emittime >= CurTime() then return end
    self.Emittime = CurTime()

    local engineOn = self:GetNWBool( "EngineStarted", false )
    local nozzle   = self:LocalToWorld( Vector( -20, 0, 0 ) )
    local fwd      = self:GetForward()
    local vel      = self:GetVelocity()

    -- -------------------------------------------------------
    --  PRE-IGNITION: light ejection smoke
    -- -------------------------------------------------------
    if not engineOn then
        local s = self.Emitter:Add( SMOKE_SPRITES[ math.random(1,9) ], nozzle )
        if s then
            s:SetVelocity( fwd * -800 )
            s:SetDieTime( math.Rand( 0.9, 1.2 ) )
            s:SetStartAlpha( math.Rand( 40, 70 ) )
            s:SetEndAlpha( 0 )
            s:SetStartSize( math.random( 18, 26 ) )
            s:SetEndSize( math.random( 80, 120 ) )
            s:SetColor( 180, 180, 180 )
            s:SetRoll( math.Rand( 180, 480 ) )
            s:SetRollDelta( math.Rand( -2, 2 ) )
            s:SetGravity( Vector( 0, math.random(1,90), math.random(51,155) ) )
            s:SetAirResistance( 60 )
        end
        return
    end

    -- -------------------------------------------------------
    --  ENGINE ON
    -- -------------------------------------------------------

    -- Dynamic light
    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        dlight.Pos        = self:GetPos()
        dlight.r          = 250 + math.random(-5,5)
        dlight.g          = 170 + math.random(-5,5)
        dlight.b          = 0
        dlight.Brightness = 1.5
        dlight.Decay      = 0.1
        dlight.Size       = 2048
        dlight.DieTime    = CurTime() + 0.15
    end

    -- Afterburner fire
    for _, cfg in ipairs({
        { mat="effects/fire_cloud1",  smin=6,  smax=10,  emin=28,  emax=44,  r=255, g=100, b=0   },
        { mat="effects/fire_cloud1",  smin=4,  smax=8,   emin=24,  emax=38,  r=255, g=150, b=0   },
        { mat="effects/yellowflare",  smin=4,  smax=8,   emin=110, emax=140, r=255, g=200, b=30  },
    }) do
        local p = self.Emitter:Add( cfg.mat, nozzle )
        if p then
            p:SetVelocity( fwd * -10 )
            p:SetDieTime( math.Rand( 0.06, 0.12 ) )
            p:SetStartAlpha( math.Rand( 222, 255 ) )
            p:SetEndAlpha( 0 )
            p:SetStartSize( math.random( cfg.smin, cfg.smax ) )
            p:SetEndSize( math.random( cfg.emin, cfg.emax ) )
            p:SetAirResistance( 150 )
            p:SetRoll( math.Rand( 180, 480 ) )
            p:SetRollDelta( math.Rand( -3, 3 ) )
            p:SetColor( cfg.r, cfg.g, cfg.b )
        end
    end

    -- Black smoke trail (5 sprites per frame, long-lived)
    for _ = 1, 5 do
        local t = self.Emitter:Add( SMOKE_SPRITES[ math.random(1,9) ], nozzle )
        if t then
            t:SetVelocity(
                ( vel / 10 ) * -1
                + Vector( math.Rand(-3,3), math.Rand(-3,3), math.Rand(2,12) )
                + fwd * -280
            )
            t:SetDieTime( math.Rand( 2.5, 4.0 ) )
            t:SetStartAlpha( math.Rand( 80, 120 ) )
            t:SetEndAlpha( 0 )
            t:SetStartSize( math.Rand( 28, 36 ) )
            t:SetEndSize( math.Rand( 90, 130 ) )
            t:SetRoll( math.Rand( 0, 360 ) )
            t:SetRollDelta( math.Rand( -0.8, 0.8 ) )
            t:SetColor( 10, 10, 10 )
            t:SetAirResistance( 80 )
            t:SetGravity(
                fwd * -400
                + VectorRand():GetNormalized() * math.Rand(-100,100)
                + Vector( 0, 0, math.random(-10,20) )
            )
        end
    end

    -- Beam exhaust cone
    local vNormal = ( nozzle - self:GetPos() ):GetNormalized()
    local scroll  = self.Seed + ( CurTime() * -10 )
    local Scale   = 0.5

    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( nozzle,                           32*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( nozzle + vNormal * 60  * Scale,   16*Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( nozzle + vNormal * 148 * Scale,   16*Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()

    scroll = scroll * 1.3
    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( nozzle,                           8*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( nozzle + vNormal * 32  * Scale,   8*Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( nozzle + vNormal * 108 * Scale,   8*Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()
end

-- ============================================================
--  Cleanup  -  MUST call Finish() to kill orphaned sprites
-- ============================================================
function ENT:OnRemove()
    if self.Emitter then
        self.Emitter:Finish()  -- kills ALL in-flight particles from this emitter
        self.Emitter = nil
    end
end
