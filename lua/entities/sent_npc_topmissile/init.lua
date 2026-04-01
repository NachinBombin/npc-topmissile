AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile
--
--  Flight path: 1:1 port of sent_neuro_javelin (Hoffa & Smithy285)
--  Steering via PhysicsUpdate() + LerpAngle() + ApplyForceCenter()
--
--  KEY DIFFERENCE vs the original weapon-fired Javelin:
--  The original does a violent 108450 u/s soft-launch kick because
--  it fires from a shoulder-mounted weapon pointing at the sky.
--  We spawn from an NPC pod at an arbitrary horizontal angle, so
--  that kick would send it sideways and into a death-spin.
--
--  Solution: spawn with zero velocity, nose pointing straight up,
--  wait 0.75s for ejection smoke, then FireEngine() activates
--  PhysicsUpdate() which steers from rest.
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

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
        -- Start completely stationary — no kick, no tilt.
        -- PhysicsUpdate() will accelerate it once FireEngine() fires.
        self.PhysObj:SetVelocity( Vector( 0, 0, 0 ) )
        self.PhysObj:SetAngleVelocity( Vector( 0, 0, 0 ) )
    end

    -- Point nose straight up on spawn so the pre-ignition drift
    -- looks like a real cold-launch ejection, not a horizontal skid.
    self:SetAngles( Angle( -90, self:GetAngles().y, 0 ) )

    -- State
    self.SpeedValue           = 0
    self.Speed                = 0
    self.Destroyed            = false
    self.ActivatedAlmonds     = false
    self.InitialDistance      = nil
    self.Tracking             = false
    self.UseMovingTargetAiming = false
    self.SpawnTime            = CurTime()
    self.HealthVal            = 50
    self.Damage               = 0
    self.Radius               = 0

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
    self.Radius = math.random( 512, 760 )
    self.EngineSound:PlayEx( 511, 100 )
    self.ActivatedAlmonds = true
    self:SetNWBool( "EngineStarted", true )

    -- Invisible prop to carry the scud_trail particle (same as original)
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
    ParticleEffectAttach( "scud_trail", PATTACH_ABSORIGIN_FOLLOW, prop, 0 )
end

-- ============================================================
--  PhysicsCollide
-- ============================================================
function ENT:PhysicsCollide( data, physobj )
    if self.Destroyed then return end
    if data.Speed > 450 and data.DeltaTime > 0.2 and self.ActivatedAlmonds then
        self:MissileDoExplosion()
    end
end

-- ============================================================
--  PhysicsUpdate  — 1:1 sent_neuro_javelin steering
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end

    -- Accelerate up to ~2200 u/s
    if self:GetVelocity():Length() < 2200 then
        self.SpeedValue = self.SpeedValue + 250
    end

    -- Switch to moving-target lead if target is fast and missile is below it
    if IsValid( self.TargetEntity ) and not self.UseMovingTargetAiming then
        local zdiff = self:GetPos().z - self.TargetEntity:GetPos().z
        if zdiff < -200 and self.TargetEntity:GetVelocity():Length() > 200 then
            self.UseMovingTargetAiming = true
        end
    end

    if self.UseMovingTargetAiming and IsValid( self.TargetEntity ) then
        local dist = ( self.TargetEntity:GetPos() - self:GetPos() ):Length()
        local pos  = self.TargetEntity:GetPos() + Vector( 0, 0, math.Clamp( dist / 5, 0, 2500 ) )
        self:SetAngles( LerpAngle( 0.125, self:GetAngles(), ( pos - self:GetPos() ):GetNormalized():Angle() ) )

    elseif self.Target then
        local mp          = self:GetPos()
        local _2dDistance = ( Vector( mp.x, mp.y, 0 ) - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

        if not self.InitialDistance then
            self.InitialDistance = _2dDistance
        end

        local halfway   = self.InitialDistance * 0.9
        local twoThirds = self.InitialDistance * 0.4

        local pos
        if not self.Tracking then
            if _2dDistance > halfway then
                pos = self.Target + Vector( 0, 0, 512 )
            elseif _2dDistance > twoThirds then
                pos = self.Target + Vector( 0, 0, math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
            else
                pos = self.Target
                if IsValid( self.TargetEntity ) then
                    pos = self.TargetEntity:GetPos()
                    self.Tracking = true
                end
            end
        else
            pos = IsValid( self.TargetEntity ) and self.TargetEntity:GetPos() or self.Target
        end

        local lerpVal = _2dDistance < 1000 and 0.1 or 0.01
        self:SetAngles( LerpAngle( lerpVal, self:GetAngles(), ( pos - self:GetPos() ):GetNormalized():Angle() ) )
    end

    self:GetPhysicsObject():ApplyForceCenter( self:GetForward() * self.SpeedValue )
end

-- ============================================================
--  Think  — proximity detonate + timeout
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > 45 then
        self:MissileDoExplosion()
        return true
    end

    if self.UseMovingTargetAiming and IsValid( self.TargetEntity ) then
        if ( self:GetPos() - self.TargetEntity:GetPos() ):Length() < self.Radius * 0.65 then
            self:MissileDoExplosion()
        end
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

    ParticleEffect( "vj_explosion3", pos, Angle( 0, 0, 0 ) )

    local ed = EffectData()
    ed:SetOrigin( pos )
    util.Effect( "VJ_Small_Explosion1", ed )

    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude", tostring( math.floor( dmg * 5 ) ) )
        pe:SetKeyValue( "radius",    tostring( rad ) )
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
