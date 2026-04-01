include( "shared.lua" )

-- ============================================================
--  CLIENT  -  1:1 port of sent_neuro_javelin + sent_neuro_missile_base
--             Draw() code by Hoffa & Smithy285, adapted for our entity.
--
--  Ghost-smoke fix: OnRemove() calls Emitter:Finish() which
--  immediately kills all in-flight sprites from this emitter.
-- ============================================================

local matHeatWave = Material( "sprites/heat_shimmer" )  -- vanilla fallback
local matFire     = Material( "effects/fire_cloud1" )

ENT.NozzlePos = Vector( -12, 0, 0 )

function ENT:Initialize()
    self:SetRenderMode( RENDERMODE_NORMAL )
    local pos    = self:LocalToWorld( self.NozzlePos )
    self.Emitter = ParticleEmitter( pos, false )
    self.Seed    = math.Rand( 0, 10000 )
    self.Emittime = 0
    self.OnStart  = CurTime()
end

function ENT:Think()
    self:NextThink( CurTime() )
    return true
end

-- ============================================================
--  Draw  -  exact copy of MissileEffectDraw_fire() logic
-- ============================================================
function ENT:Draw()
    self:DrawModel()

    -- Recreate emitter if somehow lost
    if not self.Emitter or not self.Emitter:IsValid() then
        local pos    = self:LocalToWorld( self.NozzlePos )
        self.Emitter = ParticleEmitter( pos, false )
        self.Seed    = math.Rand( 0, 10000 )
        self.OnStart = CurTime()
    end

    if not self.Emittime then self.Emittime = 0 end
    -- Throttle to one particle batch per frame at most
    if self.Emittime >= CurTime() then return end
    self.Emittime = CurTime()

    local engineOn = self:GetNWBool( "EngineStarted", false )
    local nozzle   = self:LocalToWorld( self.NozzlePos )

    -- -------------------------------------------------------
    --  PRE-IGNITION smoke  (0.75 s window before FireEngine)
    --  Exact copy from sent_neuro_javelin
    -- -------------------------------------------------------
    if not engineOn then
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

    -- -------------------------------------------------------
    --  ENGINE ON  —  MissileEffectDraw_fire() exact copy
    -- -------------------------------------------------------

    -- Dynamic light
    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        local c = Color( 250 + math.random(-5,5), 170 + math.random(-5,5), 0, 100 )
        dlight.Pos        = self:GetPos()
        dlight.r          = c.r
        dlight.g          = c.g
        dlight.b          = c.b
        dlight.Brightness = 1
        dlight.Decay      = 0.1
        dlight.Size       = 2048
        dlight.DieTime    = CurTime() + 0.15
    end

    -- 3 smoke trail sprites
    for i = 1, 3 do
        local particle = self.Emitter:Add(
            "particle/smokesprites_000" .. math.random( 1, 9 ), nozzle
        )
        if particle then
            particle:SetVelocity(
                ( self:GetVelocity() / 10 ) * -1
                + Vector( math.Rand(-2.5,2.5), math.Rand(-2.5,2.5), math.Rand(2.5,15.5) )
                + self:GetForward() * -280
            )
            particle:SetDieTime( math.Rand( 0.42, 0.725 ) )
            particle:SetStartAlpha( math.Rand( 35, 65 ) )
            particle:SetEndAlpha( 0 )
            particle:SetStartSize( math.Rand( 12, 14 ) )
            particle:SetEndSize( math.Rand( 25, 35 ) )
            particle:SetRoll( math.Rand( 0, 360 ) )
            particle:SetRollDelta( math.Rand( -1, 1 ) )
            particle:SetColor(
                math.Rand( 185, 205 ),
                math.Rand( 185, 205 ),
                math.Rand( 180, 205 )
            )
            particle:SetAirResistance( 100 )
            particle:SetGravity(
                self:GetForward() * -500
                + VectorRand():GetNormalized() * math.Rand( -140, 140 )
                + Vector( 0, 0, math.random( -15, 15 ) )
            )
        end
    end

    -- Beam exhaust
    local vOffset = nozzle
    local vNormal = ( vOffset - self:GetPos() ):GetNormalized()
    local scroll  = self.Seed + ( CurTime() * -10 )
    local Scale   = 0.5

    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                           32*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 60  * Scale,   16*Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 148 * Scale,   16*Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()

    scroll = scroll * 0.5

    render.UpdateRefractTexture()
    render.SetMaterial( matHeatWave )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                           45*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 16 * Scale,    16*Scale, scroll + 2, Color( 255, 255, 255, 255 ) )
        render.AddBeam( vOffset + vNormal * 64 * Scale,    24*Scale, scroll + 5, Color(   0,   0,   0,   0 ) )
    render.EndBeam()

    scroll = scroll * 1.3

    render.SetMaterial( matFire )
    render.StartBeam( 3 )
        render.AddBeam( vOffset,                           8*Scale, scroll,     Color(   0,   0, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 32  * Scale,   8*Scale, scroll + 1, Color( 255, 255, 255, 128 ) )
        render.AddBeam( vOffset + vNormal * 108 * Scale,   8*Scale, scroll + 3, Color( 255, 255, 255,   0 ) )
    render.EndBeam()
end

-- ============================================================
--  Cleanup  -  Finish() kills all in-flight orphan sprites
-- ============================================================
function ENT:OnRemove()
    if self.Emitter then
        self.Emitter:Finish()
        self.Emitter = nil
    end
end
