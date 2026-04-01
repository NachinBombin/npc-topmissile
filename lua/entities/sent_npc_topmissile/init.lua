AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  - NPC Top-Attack Terror Missile
--  MOVETYPE_FLY  |  Touch() detonation  |  Think() guidance
--
--  GUIDANCE PHASES (timed from engine ignition):
--    Phase 1  0.0 - 1.5s : CLIMB  - aim straight up from current pos
--                          NO lateral steering whatsoever
--    Phase 2  1.5 - 3.5s : ARC    - aim at Target XY + apexHeight
--                          missile arcs forward and over
--    Phase 3  3.5s+      : DIVE   - aim straight at Target
-- ============================================================

ENT.HealthVal  = 30
ENT.Damage     = 0
ENT.Radius     = 0
ENT.Destroyed  = false

local JITTER_MAX     = 50

local SPEED_LAUNCH   = 200
local SPEED_MAX      = 450
local SPEED_ACCEL    = 6

local STEER_FAR      = 0.06
local STEER_NEAR     = 0.18
local NEAR_THRESHOLD = 600

local PHASE1_END     = 1.5
local PHASE2_END     = 3.5
local APEX_MIN       = 400
local APEX_MAX       = 1200
local CEIL_MARGIN    = 600

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
    self.EngineTime       = nil
    self.ApexZ            = nil   -- target.z + apexHeight, set at ignition
    self.CeilLimit        = nil

    self.EngineSound = CreateSound( self, SND_WHOOSH )

    -- soft-loft 22 deg upward
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
--  Touch  - ignore owner, ignore sky
-- ============================================================
function ENT:Touch( other )
    if self.Destroyed then return end
    if IsValid( other ) and other == self.Owner then return end

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
--  FireEngine  - ignition, tiny jitter, apex setup
-- ============================================================
function ENT:FireEngine()
    self.Damage           = math.random( 2500, 4500 )
    self.Radius           = math.random( 512,  760 )
    self.ActivatedAlmonds = true
    self.EngineTime       = CurTime()
    self:SetNWBool( "EngineStarted", true )
    self.EngineSound:PlayEx( 90, 100 )

    if self.Target then
        -- tiny jitter - XY only, no Z perturbation
        local angle  = math.Rand( 0, 360 )
        local dist   = math.Rand( 0, JITTER_MAX )
        self.Target  = self.Target + Vector(
            math.cos( math.rad( angle ) ) * dist,
            math.sin( math.rad( angle ) ) * dist,
            0
        )
        self.TargetEntity = nil

        -- apex: above the target, proportional to horizontal distance
        local hDist      = ( self:GetPos() - self.Target ):Length2D()
        local apexHeight = math.Clamp( hDist * 0.55, APEX_MIN, APEX_MAX )
        self.ApexZ       = self.Target.z + apexHeight
        self.CeilLimit   = self.ApexZ + CEIL_MARGIN
    end
end

-- ============================================================
--  Think  - timed phase guidance
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > 40 then
        self:DoExplosion()
        return true
    end

    if not self.ActivatedAlmonds then
        self:SetVelocity( self:GetForward() * self.Speed )
        return true
    end

    if not self.Target then
        self:SetVelocity( self:GetForward() * self.Speed )
        return true
    end

    if self.Speed < SPEED_MAX then
        self.Speed = math.min( self.Speed + SPEED_ACCEL, SPEED_MAX )
    end

    local mp      = self:GetPos()
    local elapsed = CurTime() - self.EngineTime
    local aimPos

    if elapsed < PHASE1_END then
        -- ---- PHASE 1: pure vertical climb ----
        -- Aim at a point directly above the missile's CURRENT position.
        -- XY is locked to self, so NO lateral steering at all.
        -- Z ramps upward over the phase duration.
        local t      = elapsed / PHASE1_END          -- 0 -> 1
        local climbZ = mp.z + 300 + t * 500          -- +300 to +800 above current
        aimPos = Vector( mp.x, mp.y, climbZ )

    elseif elapsed < PHASE2_END then
        -- ---- PHASE 2: arc forward over target ----
        -- Aim at target XY but at apex Z height.
        -- Missile will naturally arc over and forward.
        local apexZ = self.ApexZ or ( self.Target.z + 600 )
        aimPos = Vector( self.Target.x, self.Target.y, apexZ )

    else
        -- ---- PHASE 3: dive onto target ----
        aimPos = self.Target
    end

    -- hard ceiling backstop
    if self.CeilLimit and aimPos.z > self.CeilLimit then
        aimPos = Vector( aimPos.x, aimPos.y, self.CeilLimit )
    end

    local dist   = ( mp - self.Target ):Length()
    local steer  = dist < NEAR_THRESHOLD and STEER_NEAR or STEER_FAR
    local newAng = LerpAngle( steer, self:GetAngles(),
                   ( aimPos - mp ):GetNormalized():Angle() )
    self:SetAngles( newAng )
    self:SetVelocity( self:GetForward() * self.Speed )

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
