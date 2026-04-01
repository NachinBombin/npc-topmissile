AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  –  NPC Top-Attack Terror Missile
--
--  Standalone: zero dependency on the Javelin addon.
--  Uses only stock HL2 / GMod models, sounds, and particles.
--
--  TERROR BEHAVIOUR:
--    The missile aims at the target's position + a large random
--    jitter offset baked in at engine ignition.  It will
--    faithfully home onto that wrong point, flying the full
--    top-attack arc but landing anywhere from 256 to 1200 units
--    away from the actual enemy.  The jitter is committed once
--    and never corrected, so the miss is guaranteed from launch.
-- ============================================================

-- ---- Stats ----
ENT.HealthVal  = 30          -- can be shot down
ENT.Damage     = 0           -- randomised in FireEngine
ENT.Radius     = 0           -- randomised in FireEngine
ENT.Destroyed  = false

-- ---- Jitter config ----
local JITTER_MIN = 256   -- minimum miss distance (units)
local JITTER_MAX = 1200  -- maximum miss distance (units)

-- ---- Stock sounds (HL2 / base GMod, no custom files needed) ----
local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_EXPLODE = "weapons/explode3.wav"
local SND_WHOOSH  = "vehicles/combine_apc/apc_rocket_launch1.wav"

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_rocket.mdl" )
    self:SetColor( Color( 0, 0, 0 ) )

    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )

    self.PhysObj = self:GetPhysicsObject()
    if self.PhysObj:IsValid() then
        self.PhysObj:Wake()
        self.PhysObj:SetMass( 500 )
        self.PhysObj:EnableDrag( true )
        self.PhysObj:EnableGravity( true )
    end

    self.SpeedValue            = 0
    self.Destroyed             = false
    self.ActivatedAlmonds      = false
    self.UseMovingTargetAiming = false
    self.Tracking              = false
    self.InitialDistance       = nil

    self.EngineSound = CreateSound( self, SND_WHOOSH )

    -- FIX: loft the missile upward (not sideways) at spawn
    local a = self:GetAngles()
    a:RotateAroundAxis( self:GetRight(), 22 )
    self:SetAngles( a )
    self:SetPos( self:GetPos() + self:GetUp() * 32 + self:GetForward() * -32 )

    -- FIX: sane ejection velocity (was 108450 which teleported the missile out of the map)
    if self.PhysObj:IsValid() then
        self.PhysObj:SetVelocityInstantaneous( self:GetForward() * 900 )
    end

    -- Launch flash (stock)
    local launchAng = self:GetAngles()
    launchAng:RotateAroundAxis( self:GetUp(), 180 )
    ParticleEffect( "weapon_muzzle_smoke", self:GetPos(), launchAng, nil )

    -- Launch sound
    sound.Play( SND_LAUNCH, self:GetPos(), 511, 100 )

    -- Engine fires after 0.75s soft-launch delay
    timer.Simple( 0.75, function()
        if not IsValid( self ) then return end
        self:FireEngine()
    end )

    self.HealthVal = 30
end

-- ============================================================
--  Engine ignition + bake in the jitter offset
-- ============================================================
function ENT:FireEngine()
    self.Damage           = math.random( 2500, 4500 )
    self.Radius           = math.random( 512, 760 )
    self.ActivatedAlmonds = true
    self:SetNWBool( "EngineStarted", true )
    self.EngineSound:PlayEx( 511, 100 )

    -- TERROR JITTER: bake a random miss offset onto Target once, never correct it.
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
    end

    -- Invisible exhaust prop for smoke trail
    local a = self:GetAngles()
    a:RotateAroundAxis( self:GetUp(), 180 )

    local prop = ents.Create( "prop_physics" )
    prop:SetPos( self:LocalToWorld( Vector( -15, 0, 0 ) ) )
    prop:SetAngles( a )
    prop:SetParent( self )
    prop:SetModel( "models/items/ar2_grenade.mdl" )
    prop:Spawn()
    prop:SetRenderMode( RENDERMODE_TRANSALPHA )
    prop:SetColor( Color( 0, 0, 0, 0 ) )

    ParticleEffectAttach( "HelicopterMegaBomb_Trail", PATTACH_ABSORIGIN_FOLLOW, prop, 0 )
    ParticleEffect( "weapon_muzzle_smoke", self:GetPos(), a, nil )
end

-- ============================================================
--  Physics collision → detonate
-- ============================================================
function ENT:PhysicsCollide( data )
    if self.Destroyed then return end
    self:DoExplosion()
end

-- ============================================================
--  Physics update → top-attack guidance toward jittered point
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end

    -- Speed ramp up to ~2200 units/s
    if self:GetVelocity():Length() < 2200 then
        self.SpeedValue = self.SpeedValue + 250
    end

    if not self.Target then return end

    local mp      = self:GetPos()
    local _2dDist = ( Vector( mp.x, mp.y, 0 ) - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

    -- FIX: guard against zero InitialDistance to prevent degenerate phase thresholds
    if not self.InitialDistance then
        self.InitialDistance = _2dDist > 0 and _2dDist or 1
    end

    local halfway   = self.InitialDistance * 0.9
    local twoThirds = self.InitialDistance * 0.4
    local pos       = self.Target

    if not self.Tracking then
        if _2dDist > halfway then
            -- Phase 1 – climb
            pos = self.Target + Vector( 0, 0, 512 )
        elseif _2dDist > twoThirds then
            -- Phase 2 – apex
            pos = self.Target + Vector( 0, 0, math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
        else
            -- Phase 3 – terminal dive onto the jittered point
            pos           = self.Target
            self.Tracking = true
        end
    else
        pos = self.Target
    end

    local lerpVal = _2dDist < 1000 and 0.1 or 0.01
    self:SetAngles( LerpAngle( lerpVal, self:GetAngles(), ( pos - mp ):GetNormalized():Angle() ) )
    self.PhysObj:ApplyForceCenter( self:GetForward() * self.SpeedValue )
end

-- ============================================================
--  Think → 30s lifetime safety net
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )

    if not self.SpawnTime then
        self.SpawnTime = CurTime()
    end
    if CurTime() - self.SpawnTime > 30 then
        self:DoExplosion()
    end

    return true
end

-- ============================================================
--  Damage – can be shot down
-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then
        self:DoExplosion()
    end
end

-- ============================================================
--  Explosion
-- ============================================================
function ENT:DoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true

    local pos   = self:GetPos()
    local owner = IsValid( self.Owner ) and self.Owner or self

    self:EmitSound( SND_EXPLODE, 511, 100 )
    sound.Play( SND_EXPLODE, pos, 511, 100 )

    local ed = EffectData()
    ed:SetOrigin( pos )
    ed:SetMagnitude( self.Radius )
    ed:SetScale( 1 )
    ed:SetRadius( self.Radius )
    util.Effect( "Explosion", ed )

    ParticleEffect( "explosion_huge",      pos, self:GetAngles(), nil )
    ParticleEffect( "weapon_muzzle_smoke", pos, self:GetAngles(), nil )

    -- Wake nearby props
    for _, v in ipairs( ents.FindInSphere( pos, self.Radius / 4 ) ) do
        if not v.HealthVal then
            local vp = v:GetPhysicsObject()
            if IsValid( vp ) then
                vp:Wake()
                vp:EnableMotion( true )
                vp:EnableGravity( true )
            end
        end
    end

    -- Physics shockwave
    local pe = ents.Create( "env_physexplosion" )
    pe:SetPos( pos )
    pe:SetKeyValue( "Magnitude",  tostring( 5 * self.Damage ) )
    pe:SetKeyValue( "radius",     tostring( self.Radius ) )
    pe:SetKeyValue( "spawnflags", "19" )
    pe:Spawn()
    pe:Activate()
    pe:Fire( "Explode", "", 0 )
    pe:Fire( "Kill",    "", 0.5 )

    util.BlastDamage( self, owner, pos + Vector( 0, 0, 50 ), self.Radius, self.Damage )

    self:Remove()
end

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    if self.EngineSound then
        self.EngineSound:Stop()
    end
end
