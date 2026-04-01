AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  –  NPC Top-Attack Terror Missile
--  MOVETYPE_FLY  |  Touch() detonation  |  Think() guidance
--
--  GUIDANCE PHASES (timed from engine ignition):
--    Phase 1  0.0 – 1.5s  : climb  – aim at fixed point above spawn
--    Phase 2  1.5 – 3.5s  : arc    – aim at Target + apexHeight
--    Phase 3  3.5s+       : dive   – aim straight at Target
-- ============================================================

ENT.HealthVal  = 30
ENT.Damage     = 0
ENT.Radius     = 0
ENT.Destroyed  = false

local JITTER_MIN     = 50
local JITTER_MAX     = 300

local SPEED_LAUNCH   = 400
local SPEED_MAX      = 900
local SPEED_ACCEL    = 12

local STEER_FAR      = 0.06
local STEER_NEAR     = 0.18
local NEAR_THRESHOLD = 600

local PHASE1_END     = 1.5    -- seconds after engine start
local PHASE2_END     = 3.5    -- seconds after engine start
local APEX_MIN       = 400
local APEX_MAX       = 1400
local CEIL_MARGIN    = 800    -- max above apex we will ever aim

local SND_LAUNCH     = "weapons/rpg/rocket1.wav"
local SND_EXPLODE    = "weapons/explode3.wav"
local SND_WHOOSH     = "vehicles/combine_apc/apc_rocket_launch1.wav"

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile.mdl" )

    self:SetMoveType( MOVETYPE_FLY )
    self:SetSolid( SOLID_BBOX )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )
    self:SetCollisionBounds( Vector( -4, -4, -4 ), Vector( 4, 4, 4 ) )

    self.Destroyed        = false
    self.ActivatedAlmonds = false
    self.Speed            = SPEED_LAUNCH
    self.SpawnTime        = CurTime()
    self.EngineTime       = nil   -- set at FireEngine()
    self.ApexPoint        = nil   -- set at FireEngine()
    self.CeilLimit        = nil   -- set at FireEngine()
    self.SpawnPos         = self:GetPos()

    self.EngineSound = CreateSound( self, SND_WHOOSH )

    -- soft-loft: tilt 22 deg upward at spawn
    local a = self:GetAngles()
    a:RotateAroundAxis( self:GetRight(), 22 )
    self:SetAngles( a )
    self:SetPos( self:GetPos() + self:GetUp() * 32 )
    self:SetVelocity( self:GetForward() * SPEED_LAUNCH )

    sound.Play( SND_LAUNCH, self:GetPos(), 90, 100 )

    local selfRef = self
    timer.Simple( 0.75, function()
        if not IsValid( selfRef ) then return end
        selfRef:FireEngine()
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  Touch  –  ignore owner, ignore sky
-- ============================================================
function ENT:Touch( other )
    if self.Destroyed then return end
    if IsValid( other ) and other == self.Owner then return end

    -- sky brush check: trace straight up a short distance
    -- if we are near the sky ceiling, HitSky will be true
    if other:IsWorld() then
        local tr = util.TraceLine( {
            start  = self:GetPos(),
            endpos = self:GetPos() + Vector( 0, 0, 64 ),
            filter = self,
            mask   = MASK_SOLID,
        } )
        if tr.HitSky then return end
    end

    self:DoExplosion()
end

-- ============================================================
--  FireEngine  – ignition, jitter, phase setup
-- ============================================================
function ENT:FireEngine()
    self.Damage           = math.random( 2500, 4500 )
    self.Radius           = math.random( 512,  760 )
    self.ActivatedAlmonds = true
    self.EngineTime       = CurTime()
    self:SetNWBool( "EngineStarted", true )
    self.EngineSound:PlayEx( 90, 100 )

    if self.Target then
        -- small jitter baked in at ignition
        local angle  = math.Rand( 0, 360 )
        local dist   = math.Rand( JITTER_MIN, JITTER_MAX )
        local jitter = Vector(
            math.cos( math.rad( angle ) ) * dist,
            math.sin( math.rad( angle ) ) * dist,
            math.Rand( -60, 60 )
        )
        self.Target       = self.Target + jitter
        self.TargetEntity = nil

        -- apex height: proportional to real distance at ignition
        local realDist   = ( self:GetPos() - self.Target ):Length2D()
        local apexHeight = math.Clamp( realDist * 0.55, APEX_MIN, APEX_MAX )

        -- ApexPoint: horizontally midway between current pos and target,
        -- elevated by apexHeight above the higher of the two z values
        local midXY      = ( self:GetPos() + self.Target ) * 0.5
        local baseZ      = math.max( self:GetPos().z, self.Target.z )
        self.ApexPoint   = Vector( midXY.x, midXY.y, baseZ + apexHeight )

        -- ceiling: apex + margin  (hard stop against skybox)
        self.CeilLimit   = self.ApexPoint.z + CEIL_MARGIN
    end
end

-- ============================================================
--  Think  – timed phase guidance
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    -- lifetime kill
    if CurTime() - self.SpawnTime > 40 then
        self:DoExplosion()
        return true
    end

    -- pre-ignition: fly straight
    if not self.ActivatedAlmonds then
        self:SetVelocity( self:GetForward() * self.Speed )
        return true
    end

    if not self.Target then
        self:SetVelocity( self:GetForward() * self.Speed )
        return true
    end

    -- accelerate gradually
    if self.Speed < SPEED_MAX then
        self.Speed = math.min( self.Speed + SPEED_ACCEL, SPEED_MAX )
    end

    local mp       = self:GetPos()
    local elapsed  = CurTime() - self.EngineTime
    local aimPos

    -- ---- PHASE 1: climb straight up above spawn ----
    if elapsed < PHASE1_END then
        -- aim at a point directly above the spawn position
        -- height ramps up over the phase so the missile arcs naturally
        local climbZ = self.SpawnPos.z + 500 + ( elapsed / PHASE1_END ) * 400
        aimPos = Vector( self.SpawnPos.x, self.SpawnPos.y, climbZ )

    -- ---- PHASE 2: arc toward apex over target ----
    elseif elapsed < PHASE2_END then
        aimPos = self.ApexPoint or ( self.Target + Vector( 0, 0, 600 ) )

    -- ---- PHASE 3: dive onto target ----
    else
        aimPos = self.Target
    end

    -- hard ceiling backstop
    if self.CeilLimit and aimPos.z > self.CeilLimit then
        aimPos = Vector( aimPos.x, aimPos.y, self.CeilLimit )
    end

    -- steer
    local dist   = ( mp - self.Target ):Length()
    local steer  = dist < NEAR_THRESHOLD and STEER_NEAR or STEER_FAR
    local newAng = LerpAngle( steer, self:GetAngles(),
                   ( aimPos - mp ):GetNormalized():Angle() )
    self:SetAngles( newAng )
    self:SetVelocity( self:GetForward() * self.Speed )

    return true
end

-- ============================================================
--  Damage  – can be shot down
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
