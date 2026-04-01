AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile  (Javelin LOBL static-point mode)
--
--  Physics model: MOVETYPE_VPHYSICS (gravity OFF, drag OFF)
--  This matches obj_vj_projectile_base exactly.
--  Velocity is applied via phys:SetVelocity(), NOT self:SetVelocity().
--  Orientation is applied via self:SetAngles() each tick.
--
--  Navigation: pre-baked quadratic bezier arc, computed ONCE at
--  FireEngine() from the enemy ground position frozen at launch.
--  t advances using real FrameTime() so speed is frame-rate independent.
--  No lookahead spiral possible: we aim at the TANGENT of the arc,
--  not at a future point, so the direction is always mathematically
--  consistent with the current velocity.
-- ============================================================

ENT.HealthVal = 30
ENT.Damage    = 0
ENT.Radius    = 0
ENT.Dead      = false   -- mirrors VJ base naming to avoid double-fire

-- Speed constants (units/s)
local SPEED_BOOST  = 80    -- ejection boost before engine fires (low, upward)
local SPEED_CRUISE = 100   -- engine-on cruise speed (hard cap)
local SPEED_ACCEL  = 120   -- units/s^2 acceleration after engine fires

-- Apex: P1 is lifted above the P0-P2 midpoint by (hDist * FRAC) clamped.
local APEX_FRAC = 0.55
local APEX_MIN  = 300
local APEX_MAX  = 800

-- Sounds
local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

-- ============================================================
--  Quadratic bezier
--    B(t) = (1-t)^2*P0 + 2(1-t)*t*P1 + t^2*P2
--  Tangent (direction of motion at t):
--    B'(t) = 2(1-t)*(P1-P0) + 2t*(P2-P1)
-- ============================================================
local function BezierPos( p0, p1, p2, t )
    local u = 1 - t
    return p0*(u*u) + p1*(2*u*t) + p2*(t*t)
end

local function BezierTangent( p0, p1, p2, t )
    -- Returns the un-normalised tangent vector
    return (p1 - p0) * (2*(1-t)) + (p2 - p1) * (2*t)
end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )  -- same as obj_vj_rocket
    self:SetSolid( SOLID_BBOX )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    -- VPHYSICS is the correct movetype for VJ projectiles.
    -- It gives us a real physics object so phys:SetVelocity works properly.
    if not self:PhysicsInit( MOVETYPE_VPHYSICS ) then
        -- Fallback: sphere collider if model has no phys mesh
        self:PhysicsInitSphere( 4, "metal_bouncy" )
    end
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetMoveCollide( MOVECOLLIDE_FLY_BOUNCE )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:Wake()
        phys:SetMass( 1 )
        phys:EnableGravity( false )   -- we control all motion manually
        phys:EnableDrag( false )
        phys:SetBuoyancyRatio( 0 )
    end

    -- Helpers prevent projectile appearing inside the NPC
    self:AddEFlags( EFL_DONTBLOCKLOS )
    self:AddEFlags( EFL_DONTWALKON )
    self:AddSolidFlags( FSOLID_NOT_STANDABLE )

    -- State
    self.Dead       = false
    self.ArcReady   = false
    self.ArcT       = 0
    self.Speed      = SPEED_BOOST
    self.SpawnTime  = CurTime()
    self.ArcP0      = nil
    self.ArcP1      = nil
    self.ArcP2      = nil

    self.EngineSound = CreateSound( self, SND_ENGINE )

    -- Ejection: tilt upward ~25 deg and give a slow boost so it clears the mech.
    -- We apply via phys so the movetype is consistent from frame 1.
    local fwd = self:GetForward()
    -- Tilt the spawn angle upward
    local spawnAng = self:GetAngles()
    spawnAng.pitch = spawnAng.pitch - 25   -- negative pitch = nose up in GMod
    self:SetAngles( spawnAng )

    local ejectionDir = self:GetForward()  -- re-read after angle change
    if IsValid( phys ) then
        phys:SetVelocity( ejectionDir * SPEED_BOOST )
    end

    sound.Play( SND_LAUNCH, self:GetPos(), 85, 100 )

    -- Fire engine after 0.5 s (Javelin soft-launch delay)
    local selfRef = self
    timer.Simple( 0.5, function()
        if IsValid( selfRef ) and not selfRef.Dead then
            selfRef:FireEngine()
        end
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  Touch / StartTouch  -  collision
-- ============================================================
function ENT:PhysicsCollide( data, phys )
    if self.Dead then return end
    -- Ignore our own owner
    local owner = self:GetOwner()
    if IsValid( owner ) and data.HitEntity == owner then return end
    self:DoExplosion()
end

function ENT:StartTouch( ent )
    if self.Dead then return end
    local owner = self:GetOwner()
    if IsValid( owner ) and ent == owner then return end
    self:DoExplosion()
end

-- ============================================================
--  FireEngine  -  bake arc once, zero Target references after
-- ============================================================
function ENT:FireEngine()
    if self.Dead then return end

    self.Damage = math.random( 2500, 4500 )
    self.Radius = math.random( 512,  760 )
    self:SetNWBool( "EngineStarted", true )
    self.EngineSound:PlayEx( 85, 100 )

    if not self.Target then
        -- No target: just cruise straight and time-out naturally
        self.ArcReady = false
        return
    end

    local p0 = self:GetPos()                                      -- current missile pos
    local p2 = Vector( self.Target.x, self.Target.y, self.Target.z )  -- fixed ground target

    local hDist      = ( Vector(p0.x, p0.y, 0) - Vector(p2.x, p2.y, 0) ):Length()
    local apexHeight = math.Clamp( hDist * APEX_FRAC, APEX_MIN, APEX_MAX )
    local midX       = ( p0.x + p2.x ) * 0.5
    local midY       = ( p0.y + p2.y ) * 0.5
    local baseZ      = math.max( p0.z, p2.z )

    self.ArcP0    = p0
    self.ArcP1    = Vector( midX, midY, baseZ + apexHeight )
    self.ArcP2    = p2
    self.ArcT     = 0
    self.ArcReady = true
    self.Target   = nil   -- lock: no re-targeting ever

    print( string.format(
        "[TopMissile] Arc baked | hDist=%.0f apexZ=%.0f P0=%s P1=%s P2=%s",
        hDist, baseZ + apexHeight,
        tostring( self.ArcP0 ), tostring( self.ArcP1 ), tostring( self.ArcP2 )
    ))
end

-- ============================================================
--  Think  -  advance missile along baked arc each frame
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Dead then return true end

    -- Hard timeout
    if CurTime() - self.SpawnTime > 45 then
        self:DoExplosion()
        return true
    end

    local phys = self:GetPhysicsObject()
    if not IsValid( phys ) then return true end

    -- Pre-engine coast: just keep flying in current direction
    if not self.ArcReady then
        phys:SetVelocity( self:GetForward() * self.Speed )
        return true
    end

    -- -------------------------------------------------------
    --  Arc navigation
    -- -------------------------------------------------------
    local dt = FrameTime()   -- real server frame delta (avoids 1/66 assumption)

    -- Accelerate smoothly up to cruise speed
    self.Speed = math.min( self.Speed + SPEED_ACCEL * dt, SPEED_CRUISE )

    -- Estimate arc length once (first tick after engine fires)
    if not self.ArcLength then
        -- Approximate arc length with 20-sample sum
        local len = 0
        local prev = self.ArcP0
        for i = 1, 20 do
            local next = BezierPos( self.ArcP0, self.ArcP1, self.ArcP2, i / 20 )
            len = len + ( next - prev ):Length()
            prev = next
        end
        self.ArcLength = math.max( len, 1 )
    end

    -- Advance t proportionally: speed(u/s) / arcLen(u) * dt(s) = fraction of arc per frame
    self.ArcT = math.min( self.ArcT + ( self.Speed / self.ArcLength ) * dt, 1 )

    -- Aim direction = exact TANGENT of the bezier at current t
    -- This guarantees velocity is always tangent to the curve: no spirals.
    local tangent = BezierTangent( self.ArcP0, self.ArcP1, self.ArcP2, self.ArcT )
    if tangent:LengthSqr() < 0.001 then return true end  -- degenerate, skip

    local dir = tangent:GetNormalized()
    self:SetAngles( dir:Angle() )
    phys:SetVelocity( dir * self.Speed )

    -- Detonate when arc is complete
    if self.ArcT >= 0.99 then
        self:DoExplosion()
    end

    return true
end

-- ============================================================
--  Damage
-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self.Dead then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:DoExplosion() end
end

-- ============================================================
--  Explosion
-- ============================================================
function ENT:DoExplosion()
    if self.Dead then return end
    self.Dead = true

    local pos    = self:GetPos()
    local dmg    = self.Damage > 0 and self.Damage or 1200
    local radius = self.Radius > 0 and self.Radius or 512
    local owner  = IsValid( self.Owner ) and self.Owner or self

    if self.EngineSound then self.EngineSound:Stop() end

    sound.Play( SND_EXPLODE, pos, 100, 100 )
    util.ScreenShake( pos, 16, 200, 1, 3000 )

    -- VJ-style explosion effect
    local ang = Angle(0,0,0)
    ParticleEffect( "vj_explosion3",       pos, ang )
    ParticleEffect( "vj_rocket_idle1",     pos, ang )  -- brief trail burst

    local ed = EffectData()
    ed:SetOrigin( pos )
    util.Effect( "VJ_Small_Explosion1", ed )

    -- Physics shockwave
    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor( dmg * 0.5 ) ) )
        pe:SetKeyValue( "radius",     tostring( radius ) )
        pe:SetKeyValue( "spawnflags", "19" )
        pe:Spawn() pe:Activate()
        pe:Fire( "Explode", "", 0 )
        pe:Fire( "Kill",    "", 0.5 )
    end

    util.BlastDamage( self, owner, pos + Vector(0,0,50), radius, dmg )
    self:Remove()
end

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    self.Dead = true
    if self.EngineSound then self.EngineSound:Stop() end
end
