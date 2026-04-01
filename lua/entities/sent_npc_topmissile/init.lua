AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile
--
--  Navigation model: pre-baked quadratic bezier arc.
--  At FireEngine() we compute three control points once:
--    P0 = missile world position at ignition
--    P1 = apex  (midpoint XY, elevated above both endpoints)
--    P2 = fixed ground target (set by Gekko, NEVER updated again)
--
--  Each Think() tick we advance a scalar t (0->1) and aim the
--  missile at the NEXT point on the arc.  No LerpAngle fighting,
--  no phases, no tracking, no jitter.
--
--  Speed is intentionally capped at 100 u/s so the arc is visible.
-- ============================================================

ENT.HealthVal = 30
ENT.Damage    = 0
ENT.Radius    = 0
ENT.Destroyed = false

local SPEED_LAUNCH  = 60     -- initial coast speed before engine fires
local SPEED_MAX     = 100    -- absolute cap (units/s)
local SPEED_ACCEL   = 4      -- units/s per Think tick

-- Apex lift: how high above the midpoint we push P1.
-- Expressed as a fraction of the horizontal distance.
local APEX_FRAC     = 0.7
local APEX_MIN      = 350
local APEX_MAX      = 900

-- How far ahead on the arc we aim each tick (0-1, smaller = tighter)
local LOOKAHEAD     = 0.04

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_EXPLODE = "weapons/explode3.wav"
local SND_WHOOSH  = "vehicles/combine_apc/apc_rocket_launch1.wav"

-- ============================================================
--  Bezier helpers
-- ============================================================
local function BezierPoint( p0, p1, p2, t )
    -- quadratic bezier: B(t) = (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
    local u = 1 - t
    return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile.mdl" )
    self:SetMoveType( MOVETYPE_FLY )
    self:SetSolid( SOLID_BBOX )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )
    self:SetCollisionBounds( Vector( -4, -4, -4 ), Vector( 4, 4, 4 ) )

    self.Destroyed  = false
    self.ArcReady   = false
    self.ArcT       = 0       -- current position on the arc (0 -> 1)
    self.Speed      = SPEED_LAUNCH
    self.SpawnTime  = CurTime()

    -- Arc control points (set in FireEngine)
    self.ArcP0 = nil
    self.ArcP1 = nil
    self.ArcP2 = nil

    self.EngineSound = CreateSound( self, SND_WHOOSH )

    -- Tilt upward 20 deg on spawn so it doesn't immediately nosedive
    local a = self:GetAngles()
    a:RotateAroundAxis( self:GetRight(), 20 )
    self:SetAngles( a )
    self:SetVelocity( self:GetForward() * SPEED_LAUNCH )

    sound.Play( SND_LAUNCH, self:GetPos(), 90, 100 )

    local selfRef = self
    timer.Simple( 0.6, function()
        if not IsValid( selfRef ) then return end
        selfRef:FireEngine()
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  Touch
-- ============================================================
function ENT:Touch( other )
    if self.Destroyed then return end
    if IsValid( other ) and other == self.Owner then return end

    -- ignore sky brush
    if other:IsWorld() then
        local tr = util.TraceLine({
            start  = self:GetPos(),
            endpos = self:GetPos() + Vector( 0, 0, 64 ),
            filter = self,
            mask   = MASK_SOLID,
        })
        if tr.HitSky then return end
    end

    self:DoExplosion()
end

-- ============================================================
--  FireEngine  -  compute arc once, never touch Target again
-- ============================================================
function ENT:FireEngine()
    self.Damage = math.random( 2500, 4500 )
    self.Radius = math.random( 512,  760 )
    self:SetNWBool( "EngineStarted", true )
    self.EngineSound:PlayEx( 90, 100 )

    if not self.Target then
        -- No target set by spawner — just fly straight and self-destruct
        self.ArcReady = false
        return
    end

    -- P0: where the missile is right now
    local p0 = self:GetPos()

    -- P2: the fixed ground target, locked forever
    local p2 = Vector( self.Target.x, self.Target.y, self.Target.z )

    -- P1: apex — midpoint XY, lifted by APEX_FRAC * horizontal distance
    local hDist      = ( p0 - p2 ):Length2D()
    local apexHeight = math.Clamp( hDist * APEX_FRAC, APEX_MIN, APEX_MAX )
    local midXY      = ( p0 + p2 ) * 0.5
    local p1         = Vector( midXY.x, midXY.y, math.max( p0.z, p2.z ) + apexHeight )

    self.ArcP0    = p0
    self.ArcP1    = p1
    self.ArcP2    = p2
    self.ArcT     = 0
    self.ArcReady = true

    -- Null out Target so nothing can accidentally re-read/update it
    self.Target = nil

    print( string.format(
        "[TopMissile] Arc baked | hDist=%.0f apex=%.0f P0=%s P1=%s P2=%s",
        hDist, apexHeight, tostring(p0), tostring(p1), tostring(p2)
    ))
end

-- ============================================================
--  Think  -  advance along pre-baked arc
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    -- safety timeout
    if CurTime() - self.SpawnTime > 60 then
        self:DoExplosion()
        return true
    end

    -- before arc is ready, coast forward
    if not self.ArcReady then
        self:SetVelocity( self:GetForward() * self.Speed )
        return true
    end

    -- accelerate up to cap
    if self.Speed < SPEED_MAX then
        self.Speed = math.min( self.Speed + SPEED_ACCEL, SPEED_MAX )
    end

    local mp = self:GetPos()

    -- Advance t by how far we moved as a fraction of total arc length.
    -- Approximate arc length as |P2 - P0| (good enough for guidance).
    local approxLen = ( self.ArcP2 - self.ArcP0 ):Length()
    if approxLen < 1 then approxLen = 1 end
    local dt = self.Speed / approxLen   -- fraction of arc covered this tick (1 tick ~= 1/66 s but we don't divide by tick rate; speed is low enough)
    self.ArcT = math.min( self.ArcT + dt * (1/66), 1 )

    -- lookahead point on the arc
    local lookT   = math.min( self.ArcT + LOOKAHEAD, 1 )
    local aimPos  = BezierPoint( self.ArcP0, self.ArcP1, self.ArcP2, lookT )

    -- point nose directly at lookahead (no LerpAngle — arc is smooth enough)
    local dir = ( aimPos - mp ):GetNormalized()
    self:SetAngles( dir:Angle() )
    self:SetVelocity( dir * self.Speed )

    -- explode when we reach the end of the arc
    if self.ArcT >= 0.98 then
        self:DoExplosion()
    end

    return true
end

-- ============================================================
--  Damage
-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:DoExplosion() end
end

-- ============================================================
--  Explosion
-- ============================================================
function ENT:DoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true

    local dmg    = self.Damage > 0 and self.Damage or 1200
    local radius = self.Radius > 0 and self.Radius or 512
    local pos    = self:GetPos()
    local owner  = IsValid( self.Owner ) and self.Owner or self

    if self.EngineSound then self.EngineSound:Stop() end

    sound.Play( SND_EXPLODE, pos, 100, 100 )

    local ed = EffectData()
    ed:SetOrigin( pos )
    ed:SetMagnitude( radius )
    ed:SetScale( 1 )
    ed:SetRadius( radius )
    util.Effect( "Explosion", ed )

    ParticleEffect( "explosion_huge",      pos, self:GetAngles(), nil )
    ParticleEffect( "weapon_muzzle_smoke", pos, self:GetAngles(), nil )

    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor( dmg * 0.5 ) ) )
        pe:SetKeyValue( "radius",     tostring( radius ) )
        pe:SetKeyValue( "spawnflags", "19" )
        pe:Spawn()
        pe:Activate()
        pe:Fire( "Explode", "", 0 )
        pe:Fire( "Kill",    "", 0.5 )
    end

    util.BlastDamage( self, owner, pos + Vector( 0, 0, 50 ), radius, dmg )
    self:Remove()
end

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    if self.EngineSound then self.EngineSound:Stop() end
end
