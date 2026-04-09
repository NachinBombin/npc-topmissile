AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  --  NPC Top-Attack Terror Missile  (v3 -- circle-fix)
--
--  ROOT CAUSE OF THE "FLIES IN CIRCLES" BUG:
--
--    The Gekko calls:
--        missile:SetAngles( Angle(-90, yaw, 0) )   -- nose up
--        missile:Spawn()
--        missile:Activate()            -- triggers Initialize()
--
--    Inside Initialize(), the OLD code called:
--        self:SetAngles( upAng )       -- entity call -- IGNORED on VPHYSICS
--
--    On MOVETYPE_VPHYSICS the SOURCE physics engine owns orientation.
--    entity:SetAngles() queues a wish that the physics engine
--    immediately overwrites.  The body stayed in whatever random
--    orientation the engine assigned at Spawn().
--
--    In PhysicsUpdate() the steering does:
--        phys:SetAngles( newAng )        -- correct
--        phys:ApplyForceCenter( self:GetForward() * speed )
--
--    BUT self:GetForward() returns the ENTITY forward, which lags
--    one tick behind the physics body's orientation after the
--    phys:SetAngles() call.  So thrust is always applied in the
--    PREVIOUS frame's direction -- the missile circles endlessly
--    because force and heading never agree.
--
--  TWO-PART FIX:
--    1.  In Initialize() and FireEngine(): use phys:SetAngles()
--        AND phys:SetAngleVelocity(0) so the body is truly pointing up.
--    2.  In PhysicsUpdate(): use PhysForward(phys) -- reads
--        phys:GetAngles():Forward() -- for thrust so force always
--        matches the physics body's CURRENT orientation.
--
--  CALLER SIDE (Gekko) is UNCHANGED -- it still sets:
--    missile:SetAngles( Angle(-90, yaw, 0) )
--    missile.Target = enemy:GetPos() + Vector(0,0,40)
--    missile:Spawn() / :Activate()
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local SPEED_CAP = game.SinglePlayer() and 1800 or 2300
local LIFETIME  = 45

-- Terror jitter: missile lands NEAR target, never on it
local JITTER_MIN = 256
local JITTER_MAX = 1200

-- ============================================================
--  Helper: physics body's authoritative forward vector.
--  phys:GetAngles():Forward() is one tick ahead of entity:GetAngles()
--  after a phys:SetAngles() call -- use this for thrust.
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

    self.PhysObj = self:GetPhysicsObject()
    if IsValid( self.PhysObj ) then
        self.PhysObj:Wake()
        self.PhysObj:SetMass( 500 )
        self.PhysObj:EnableDrag( true )
        self.PhysObj:EnableGravity( true )
        self.PhysObj:SetVelocity( Vector( 0, 0, 0 ) )
        self.PhysObj:SetAngleVelocity( Vector( 0, 0, 0 ) )

        -- FIX PART 1:
        -- entity:SetAngles() is silently ignored on MOVETYPE_VPHYSICS.
        -- We MUST call phys:SetAngles() so the rigid body is actually
        -- pointing nose-up before FireEngine() kicks it upward.
        local upAng = Angle( -90, self:GetAngles().y, 0 )
        self.PhysObj:SetAngles( upAng )
        self.PhysObj:SetAngleVelocity( Vector( 0, 0, 0 ) )
        self:SetAngles( upAng )   -- keep entity in sync for any GetForward() callers
    end

    -- State
    self.SpeedValue       = 0
    self.Destroyed        = false
    self.ActivatedAlmonds = false
    self.InitialDistance  = nil
    self.Tracking         = false
    self.SpawnTime        = CurTime()
    self.HealthVal        = 50
    self.Damage           = 0
    self.Radius           = 0

    -- Validate Target (set by Gekko BEFORE Spawn())
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
    self:SetNWBool( "EngineStarted", true )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        -- FIX PART 1 (repeated): re-affirm nose-up via phys:SetAngles()
        -- in case any collision or gravity nudged the body during the delay.
        local upAng = Angle( -90, self:GetAngles().y, 0 )
        phys:SetAngles( upAng )
        phys:SetAngleVelocity( Vector( 0, 0, 0 ) )
        self:SetAngles( upAng )

        -- Kick straight up using PhysForward so the direction is authoritative.
        phys:SetVelocityInstantaneous( PhysForward( phys ) * 108450 )
    end

    -- TERROR JITTER: bake a random miss offset into Target once.
    -- Committed at engine ignition, never corrected.
    if self.Target then
        local angle  = math.Rand( 0, 360 )
        local dist   = math.Rand( JITTER_MIN, JITTER_MAX )
        local jitter = Vector(
            math.cos( math.rad( angle ) ) * dist,
            math.sin( math.rad( angle ) ) * dist,
            math.Rand( -150, 150 )
        )
        self.Target = self.Target + jitter
    end

    -- Invisible prop for exhaust trail
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
       and data.Speed > 450
       and data.DeltaTime > 0.2 then
        self:MissileDoExplosion()
    end
end

-- ============================================================
--  PhysicsUpdate  --  3-phase top-attack arc
--
--  FIX PART 2:
--  Thrust uses PhysForward(phys) -- reads phys:GetAngles():Forward()
--  which reflects the orientation we JUST set this tick via
--  phys:SetAngles().  self:GetForward() lags one tick behind and
--  was the direct cause of the circles.
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target            then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return end

    -- Speed ramp
    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = self.SpeedValue + 250
    end

    -- 3-phase arc
    local mp          = self:GetPos()
    local _2dDistance = Vector( mp.x, mp.y, 0 ):Distance(
                        Vector( self.Target.x, self.Target.y, 0 ) )

    if not self.InitialDistance then
        self.InitialDistance = _2dDistance
    end

    local halfway   = self.InitialDistance * 0.9
    local twoThirds = self.InitialDistance * 0.4
    local aimPos

    if _2dDistance > halfway then
        aimPos = self.Target + Vector( 0, 0, 512 )                             -- Phase 1: climb
    elseif _2dDistance > twoThirds then
        aimPos = self.Target + Vector( 0, 0,
            math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )              -- Phase 2: apex
    else
        aimPos = self.Target                                                    -- Phase 3: dive
    end

    local lerpVal = _2dDistance < 1000 and 0.1 or 0.01
    local wantAng = ( aimPos - mp ):GetNormalized():Angle()
    local newAng  = LerpAngle( lerpVal, phys:GetAngles(), wantAng )

    phys:SetAngles( newAng )
    phys:SetAngleVelocity( Vector( 0, 0, 0 ) )

    -- FIX PART 2: use PhysForward, not self:GetForward()
    phys:ApplyForceCenter( PhysForward( phys ) * self.SpeedValue )
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

    if util.EffectExists( "vj_explosion3" ) then
        ParticleEffect( "vj_explosion3", pos, Angle( 0, 0, 0 ) )
    end

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
