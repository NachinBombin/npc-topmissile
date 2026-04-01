AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  –  NPC Top-Attack Terror Missile
--  MOVETYPE_FLY  |  Touch() detonation  |  Think() guidance
-- ============================================================

ENT.HealthVal  = 30
ENT.Damage     = 0
ENT.Radius     = 0
ENT.Destroyed  = false

local JITTER_MIN     = 256
local JITTER_MAX     = 1200

local SPEED_LAUNCH   = 900
local SPEED_MAX      = 2200
local SPEED_ACCEL    = 80

local STEER_FAR      = 0.025
local STEER_NEAR     = 0.12
local NEAR_THRESHOLD = 800

local SKY_MASK       = MASK_SOLID   -- used for ceiling trace
local CEIL_MARGIN    = 2048         -- how far above target we allow

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_EXPLODE = "weapons/explode3.wav"
local SND_WHOOSH  = "vehicles/combine_apc/apc_rocket_launch1.wav"

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
    self.Tracking         = false
    self.InitialDistance  = nil
    self.Speed            = SPEED_LAUNCH
    self.SpawnTime        = CurTime()
    self.CeilLimit        = nil   -- set once we know the target

    self.EngineSound = CreateSound( self, SND_WHOOSH )

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
--  Touch  –  ignore owner AND sky brushes
-- ============================================================
function ENT:Touch( other )
    if self.Destroyed then return end
    -- ignore the NPC that fired us
    if IsValid( other ) and other == self.Owner then return end

    -- ignore world sky brush  (surface is CONTENTS_SKY)
    -- do a tiny trace at our position; if the hit surface is sky, skip
    local tr = util.TraceLine( {
        start  = self:GetPos(),
        endpos = self:GetPos() + self:GetForward() * 16,
        filter = self,
        mask   = MASK_SOLID,
    } )
    if tr.HitSky then return end

    self:DoExplosion()
end

-- ============================================================
--  FireEngine  – ignition + jitter
-- ============================================================
function ENT:FireEngine()
    self.Damage           = math.random( 2500, 4500 )
    self.Radius           = math.random( 512,  760 )
    self.ActivatedAlmonds = true
    self:SetNWBool( "EngineStarted", true )
    self.EngineSound:PlayEx( 90, 100 )

    if self.Target then
        local angle  = math.Rand( 0, 360 )
        local dist   = math.Rand( JITTER_MIN, JITTER_MAX )
        local jitter = Vector(
            math.cos( math.rad( angle ) ) * dist,
            math.sin( math.rad( angle ) ) * dist,
            math.Rand( -150, 150 )
        )
        self.Target       = self.Target + jitter
        self.TargetEntity = nil

        -- build a ceiling limit: missile may not exceed target.z + CEIL_MARGIN
        -- this prevents it from climbing into the skybox
        self.CeilLimit = self.Target.z + CEIL_MARGIN
    end
end

-- ============================================================
--  Think  – guidance + ceiling guard + lifetime
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    -- lifetime kill
    if CurTime() - self.SpawnTime > 30 then
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

    -- accelerate
    if self.Speed < SPEED_MAX then
        self.Speed = math.min( self.Speed + SPEED_ACCEL, SPEED_MAX )
    end

    local mp      = self:GetPos()
    local _2dDist = Vector( mp.x, mp.y, 0 ):Distance(
                    Vector( self.Target.x, self.Target.y, 0 ) )

    if not self.InitialDistance then
        self.InitialDistance = _2dDist > 0 and _2dDist or 1
    end

    local halfway   = self.InitialDistance * 0.9
    local twoThirds = self.InitialDistance * 0.4
    local aimPos

    if not self.Tracking then
        if _2dDist > halfway then
            aimPos = self.Target + Vector( 0, 0, 512 )
        elseif _2dDist > twoThirds then
            aimPos = self.Target + Vector( 0, 0,
                math.Clamp( self.InitialDistance * 0.85, 256, 14500 ) )
        else
            aimPos        = self.Target
            self.Tracking = true
        end
    else
        aimPos = self.Target
    end

    -- ---- ceiling guard: clamp aimPos so we never steer into the sky ----
    if self.CeilLimit and aimPos.z > self.CeilLimit then
        aimPos = Vector( aimPos.x, aimPos.y, self.CeilLimit )
    end

    local steer  = _2dDist < NEAR_THRESHOLD and STEER_NEAR or STEER_FAR
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
