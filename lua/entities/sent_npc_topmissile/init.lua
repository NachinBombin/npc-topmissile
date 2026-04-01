AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile
--
--  Lifecycle (must be respected by the caller):
--
--    1.  missile = ents.Create( "sent_npc_topmissile" )
--    2.  missile.Owner  = npcEnt       -- BEFORE Spawn()  (Entity)
--    3.  missile.Target = targetPos    -- BEFORE Spawn()  (Vector)
--    4.  missile:SetPos( launchPos )   -- BEFORE Spawn()
--    5.  missile:Spawn()
--    6.  missile:Activate()
--
--  Do NOT call GetPhysicsObject():SetVelocity() on the caller side.
--  Initialize() starts the missile stationary; FireEngine() fires the
--  108 450 u/s upward kick after 0.75 s once the nose is pointing up.
--
--  This missile flies a STATIC 3-phase top-attack arc to self.Target.
--  It does NOT chase moving targets.  Remove TargetEntity from the
--  caller if you previously set it -- it is no longer read.
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local SPEED_CAP = game.SinglePlayer() and 1800 or 2300
local LIFETIME  = 45

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
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
    end

    -- Point nose straight up so the initial kick goes cleanly upward.
    -- On MOVETYPE_VPHYSICS we MUST use PhysObj:SetAngles(), not
    -- entity:SetAngles() -- the physics engine ignores the entity call.
    local upAng = Angle( -90, self:GetAngles().y, 0 )
    self:SetAngles( upAng )
    if IsValid( self.PhysObj ) then
        self.PhysObj:SetAngles( upAng )
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

    -- Validate Target
    if not self.Target or type( self.Target ) ~= "Vector" then
        local fwd = self:GetForward()
        fwd.z = 0
        fwd:Normalize()
        self.Target = self:GetPos() + fwd * 2000
        print( "[TopMissile] WARNING: no Target set before Spawn -- using fallback" )
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
--  FireEngine  (fires 0.75 s after spawn)
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
        -- Angle(-90,y,0):Forward() == (0,0,1) so this kicks straight up.
        phys:SetVelocityInstantaneous( self:GetForward() * 108450 )
        phys:SetVelocity( self:GetForward() * 108450 )
    end

    -- Invisible prop to carry the scud_trail particle
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
        ParticleEffectAttach( "scud_trail", PATTACH_ABSORIGIN_FOLLOW, prop, 0 )
    end
end

-- ============================================================
--  PhysicsCollide
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed then return end
    if self.ActivatedAlmonds
       and data.Speed    > 450
       and data.DeltaTime > 0.2 then
        self:MissileDoExplosion()
    end
end

-- ============================================================
--  PhysicsUpdate  --  static 3-phase top-attack arc
--
--  FIX (spiral): on MOVETYPE_VPHYSICS, entity:SetAngles() is
--  silently ignored -- the physics engine restores the rigid
--  body's own orientation every tick.  We must call
--  PhysObj:SetAngles() to actually rotate the body, then
--  immediately zero out angular velocity so the engine doesn't
--  add spin on top of our correction.
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target then return end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return end

    -- Speed ramp
    if self:GetVelocity():Length() < SPEED_CAP then
        self.SpeedValue = self.SpeedValue + 250
    end

    -- -------------------------------------------------------
    --  3-phase static top-attack arc
    -- -------------------------------------------------------
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
        -- Phase 1: climb -- aim 512 u above target
        aimPos = self.Target + Vector( 0, 0, 512 )

    elseif _2dDistance > twoThirds then
        -- Phase 2: apex -- aim high above target
        aimPos = self.Target + Vector( 0, 0,
            math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )

    else
        -- Phase 3: terminal dive -- aim straight at the frozen target point
        aimPos = self.Target
    end

    -- Steer: tighter lock-in as we get closer
    local lerpVal  = _2dDistance < 1000 and 0.1 or 0.01
    local wantDir  = ( aimPos - mp ):GetNormalized()
    local wantAng  = wantDir:Angle()
    local newAng   = LerpAngle( lerpVal, self:GetAngles(), wantAng )

    -- Apply to the physics body (not the entity) and kill angular velocity
    phys:SetAngles( newAng )
    phys:SetAngleVelocity( Vector( 0, 0, 0 ) )

    -- Thrust along the corrected forward vector
    phys:ApplyForceCenter( self:GetForward() * self.SpeedValue )
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
--  Damage
-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

-- ============================================================
--  Explosion
--
--  FIX: util.IsValidEffect does not exist in GMod.
--       The correct function is util.EffectExists().
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

    -- FIX: was util.IsValidEffect (nil) -- correct call is util.EffectExists
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
