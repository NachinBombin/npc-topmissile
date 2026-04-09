AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  --  NPC Top-Attack Terror Missile  (v4)
--
--  BUGS FIXED THIS VERSION:
--
--  BUG A: "stays in place" after v3
--    Root cause: EnableGravity(true) + ApplyForceCenter ramp.
--    SpeedValue starts at 0 and increments by 250/tick.  With
--    gravity on, the body falls and settles on the ground before
--    the ramp builds enough thrust to lift it.  The 108450 kick
--    in FireEngine() was correct but gravity immediately countered
--    it each subsequent tick while SpeedValue was still tiny.
--    Fix: disable gravity on the physics body and drive ALL
--    movement via SetVelocityInstantaneous() each tick, exactly
--    like the original working Javelin base.  No gravity fight.
--
--  BUG B: util.EffectExists crash
--    util.EffectExists does not exist in this version of GMod /
--    VJ Base.  Removed the call; vj_explosion3 is attempted
--    directly inside a pcall so a missing particle never errors.
--
--  CIRCLE BUG FIX (kept from v3):
--    phys:SetAngles() instead of entity:SetAngles() in
--    Initialize() and FireEngine().  PhysForward(phys) for
--    thrust direction so force and heading always agree.
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local SPEED_CAP  = 2200   -- units/s terminal velocity
local SPEED_STEP = 55     -- units/s added per PhysicsUpdate tick
local LIFETIME   = 45     -- seconds before auto-detonate

-- Terror jitter: committed at engine ignition, never corrected
local JITTER_MIN = 256
local JITTER_MAX = 1200

-- ============================================================
--  Helper: authoritative forward from the physics body.
--  After phys:SetAngles(), phys:GetAngles():Forward() reflects
--  the NEW orientation immediately; entity:GetForward() lags.
-- ============================================================
local function PhysForward( phys )
    return phys:GetAngles():Forward()
end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_rocket.mdl" )
    self:SetColor( Color( 0, 0, 0 ) )

    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:Wake()
        phys:SetMass( 500 )
        phys:EnableDrag( false )       -- no drag fighting the thrust
        phys:EnableGravity( false )    -- FIX A: gravity off; we own all motion
        phys:SetVelocity( Vector( 0, 0, 0 ) )
        phys:SetAngleVelocity( Vector( 0, 0, 0 ) )

        -- Point nose straight up using phys:SetAngles().
        -- entity:SetAngles() is ignored on MOVETYPE_VPHYSICS.
        local upAng = Angle( -90, self:GetAngles().y, 0 )
        phys:SetAngles( upAng )
        phys:SetAngleVelocity( Vector( 0, 0, 0 ) )
        self:SetAngles( upAng )
    end

    self.SpeedValue       = 0
    self.Destroyed        = false
    self.ActivatedAlmonds = false
    self.InitialDistance  = nil
    self.SpawnTime        = CurTime()
    self.HealthVal        = 50
    self.Damage           = 0
    self.Radius           = 0

    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetAngles():Forward()
        fwd.z = 0
        fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print( "[TopMissile] WARNING: no Target set -- using fallback" )
    end

    self.EngineSound = CreateSound( self, SND_ENGINE )
    sound.Play( SND_LAUNCH, self:GetPos(), 85, 100 )

    local selfRef = self
    timer.Simple( 0.75, function()
        if IsValid( selfRef ) and not selfRef.Destroyed then
            selfRef:FireEngine()
        end
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  FireEngine  (0.75 s after spawn)
-- ============================================================
function ENT:FireEngine()
    if self.Destroyed then return end

    self.Damage = math.random( 2500, 4500 )
    self.Radius = math.random( 512,  760  )
    self.EngineSound:PlayEx( 511, 100 )
    self.ActivatedAlmonds = true
    self.SpeedValue       = 800      -- start with a healthy base speed
    self:SetNWBool( "EngineStarted", true )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        -- Re-affirm nose-up in case gravity/collision nudged it during delay
        local upAng = Angle( -90, self:GetAngles().y, 0 )
        phys:SetAngles( upAng )
        phys:SetAngleVelocity( Vector( 0, 0, 0 ) )
        self:SetAngles( upAng )
        phys:EnableGravity( false )   -- confirm still off

        -- Initial upward kick via velocity (not force) so it moves immediately
        phys:SetVelocityInstantaneous( PhysForward( phys ) * 1800 )
    end

    -- TERROR JITTER: bake random miss offset into Target once
    if self.Target then
        local ang  = math.Rand( 0, 360 )
        local dist = math.Rand( JITTER_MIN, JITTER_MAX )
        self.Target = self.Target + Vector(
            math.cos( math.rad( ang ) ) * dist,
            math.sin( math.rad( ang ) ) * dist,
            math.Rand( -150, 150 )
        )
    end

    -- Invisible prop for exhaust trail particle
    local a = self:GetAngles()
    a:RotateAroundAxis( self:GetUp(), 180 )
    local prop = ents.Create( "prop_physics" )
    if IsValid( prop ) then
        prop:SetPos( self:LocalToWorld( Vector( -15, 0, 0 ) ) )
        prop:SetAngles( a )
        prop:SetParent( self )
        prop:SetModel( "models/items/ar2_grenade.mdl" )
        prop:Spawn()
        prop:SetRenderMode( RENDERMODE_TRANSALPHA )
        prop:SetColor( Color( 0, 0, 0, 0 ) )
        ParticleEffectAttach( "HelicopterMegaBomb_Trail", PATTACH_ABSORIGIN_FOLLOW, prop, 0 )
    end
end

-- ============================================================
--  PhysicsCollide
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed then return end
    if self.ActivatedAlmonds
       and data.Speed    > 200
       and data.DeltaTime > 0.1 then
        self:MissileDoExplosion()
    end
end

-- ============================================================
--  PhysicsUpdate  --  3-phase top-attack arc
--
--  Movement: SetVelocityInstantaneous() every tick so we fully
--  own the trajectory. No force accumulation, no gravity fight.
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return end

    -- Speed ramp up to cap
    if self.SpeedValue < SPEED_CAP then
        self.SpeedValue = self.SpeedValue + SPEED_STEP
    end

    -- 3-phase arc steering
    local mp = self:GetPos()
    local _2dDist = Vector( mp.x, mp.y, 0 ):Distance(
                    Vector( self.Target.x, self.Target.y, 0 ) )

    if not self.InitialDistance then
        self.InitialDistance = math.max( _2dDist, 1 )
    end

    local halfway   = self.InitialDistance * 0.9
    local twoThirds = self.InitialDistance * 0.4
    local aimPos

    if _2dDist > halfway then
        aimPos = self.Target + Vector( 0, 0, 512 )                        -- Phase 1: climb
    elseif _2dDist > twoThirds then
        aimPos = self.Target + Vector( 0, 0,
            math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )         -- Phase 2: apex
    else
        aimPos = self.Target                                               -- Phase 3: dive
    end

    -- Steer physics body toward aim point
    local lerpVal = _2dDist < 1000 and 0.12 or 0.02
    local wantAng = ( aimPos - mp ):GetNormalized():Angle()
    local newAng  = LerpAngle( lerpVal, phys:GetAngles(), wantAng )

    phys:SetAngles( newAng )
    phys:SetAngleVelocity( Vector( 0, 0, 0 ) )

    -- Drive velocity directly -- no gravity, no force accumulation
    phys:SetVelocityInstantaneous( PhysForward( phys ) * self.SpeedValue )
end

-- ============================================================
--  Think  --  lifetime timeout
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end
    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion()
    end
    return true
end

-- ============================================================
--  Damage  --  can be shot down
-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

-- ============================================================
--  Explosion
-- ============================================================
function ENT:MissileDoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true

    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()

    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or 1200
    local rad   = self.Radius > 0 and self.Radius or 512
    local owner = IsValid( self.Owner ) and self.Owner or self

    sound.Play( SND_EXPLODE, pos, 100, 100 )
    util.ScreenShake( pos, 16, 200, 1, 3000 )

    -- FIX B: util.EffectExists does not exist -- use pcall instead
    pcall( ParticleEffect, "vj_explosion3", pos, Angle( 0, 0, 0 ), nil )

    local ed = EffectData()
    ed:SetOrigin( pos )
    util.Effect( "Explosion", ed )

    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor( dmg * 5 ) ) )
        pe:SetKeyValue( "radius",     tostring( rad ) )
        pe:SetKeyValue( "spawnflags", "19" )
        pe:Spawn() pe:Activate()
        pe:Fire( "Explode", "", 0 )
        pe:Fire( "Kill",    "", 0.5 )
    end

    util.BlastDamage( self, owner, pos + Vector( 0, 0, 50 ), rad, dmg )
    self:Remove()
end

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    self.Destroyed = true
    if self.EngineSound then self.EngineSound:Stop() end
    self:StopParticles()
end
