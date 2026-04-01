AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile
--
--  Speed logic is a 1:1 match of sent_neuro_javelin (Hoffa & Smithy285):
--    - SpeedValue starts at 0, ramps +250 per PhysicsUpdate tick
--    - speedCap = 2300 u/s (multiplayer value from original)
--    - 108450 u/s initial kick — in the original this fires on Initialize()
--      from a shoulder weapon already pointing at the sky.
--      We fire it in FireEngine() (0.75s after spawn) once the nose
--      is already pointing straight up, so the kick goes upward cleanly
--      instead of sideways.
-- ============================================================

local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local speedCap = game.SinglePlayer() and 1800 or 2300  -- exact from original

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
        self.PhysObj:SetMass( 500 )  -- exact from original
        self.PhysObj:EnableDrag( true )
        self.PhysObj:EnableGravity( true )
        -- Start stationary; the 108450 kick fires in FireEngine() below.
        self.PhysObj:SetVelocity( Vector( 0, 0, 0 ) )
        self.PhysObj:SetAngleVelocity( Vector( 0, 0, 0 ) )
    end

    -- Point nose straight up so the 108450 kick goes upward, not sideways.
    self:SetAngles( Angle( -90, self:GetAngles().y, 0 ) )

    -- State (exact field names from original)
    self.SpeedValue            = 0
    self.Speed                 = 0
    self.Destroyed             = false
    self.ActivatedAlmonds      = false
    self.InitialDistance       = nil
    self.Tracking              = false
    self.UseMovingTargetAiming = false
    self.SpawnTime             = CurTime()
    self.HealthVal             = 50   -- exact from original
    self.Damage                = 0
    self.Radius                = 0

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
--  Applies the same 108450 u/s kick the original fires on spawn,
--  but deferred so the nose is already pointing up.
-- ============================================================
function ENT:FireEngine()
    if self.Destroyed then return end

    self.Damage = math.random( 2500, 4500 )   -- exact from original
    self.Radius = math.random( 512, 760 )     -- exact from original
    self.EngineSound:PlayEx( 511, 100 )
    self.ActivatedAlmonds = true
    self:SetNWBool( "EngineStarted", true )

    -- 108450 kick — identical value to the original, now firing upward
    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:SetVelocityInstantaneous( self:GetForward() * 108450 )
        phys:SetVelocity( self:GetForward() * 108450 )
    end

    -- Invisible prop to carry the scud_trail particle (exact from original)
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
--  PhysicsUpdate  — exact Javelin steering + exact speed values
-- ============================================================
function ENT:PhysicsUpdate()
    if not self.ActivatedAlmonds then return end
    if not self.Target then return end

    -- Exact ramp from original: +250 per tick up to speedCap
    if self:GetVelocity():Length() < speedCap then
        self.SpeedValue = self.SpeedValue + 250
    end

    -- Moving-target lead switch (exact from original)
    if IsValid( self.TargetEntity ) and not self.UseMovingTargetAiming then
        local zdiff  = self:GetPos().z - self.TargetEntity:GetPos().z
        local tspeed = self.TargetEntity:GetVelocity():Length()
        if zdiff < -200 and tspeed > 200 then
            self.UseMovingTargetAiming = true
        end
    end

    if self.UseMovingTargetAiming and IsValid( self.TargetEntity ) then
        local dist = ( self.TargetEntity:GetPos() - self:GetPos() ):Length()
        local pos  = self.TargetEntity:GetPos() + Vector( 0, 0, math.Clamp( dist / 5, 0, 2500 ) )
        self:SetAngles( LerpAngle( 0.125, self:GetAngles(), ( pos - self:GetPos() ):GetNormalized():Angle() ) )

    else
        local mp          = self:GetPos()
        local _2dDistance = ( Vector( mp.x, mp.y, 0 ) - Vector( self.Target.x, self.Target.y, 0 ) ):Length()

        if not self.InitialDistance then self.InitialDistance = _2dDistance end

        local halfway   = self.InitialDistance * 0.9
        local twoThirds = self.InitialDistance * 0.4

        local pos = self.Target

        if not self.Tracking then
            if _2dDistance > halfway then
                pos = self.Target + Vector( 0, 0, 512 )
            elseif _2dDistance < halfway and _2dDistance > twoThirds then
                pos = self.Target + Vector( 0, 0, math.Clamp( self.InitialDistance * 0.85, 0, 14500 ) )
            elseif _2dDistance < twoThirds then
                pos = self.Target
                if IsValid( self.TargetEntity ) then
                    pos = self.TargetEntity:GetPos()
                    self.Tracking = true
                end
            end
        else
            if IsValid( self.TargetEntity ) then
                pos = self.TargetEntity:GetPos()
            end
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
