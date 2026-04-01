AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  NPC Top-Attack Missile  (Javelin LOBL static-point mode)
--
--  Physics model: MOVETYPE_VPHYSICS (gravity OFF, drag OFF)
--  Velocity applied via phys:SetVelocity() every Think tick.
--  Direction = exact bezier TANGENT at current t → no spiral possible.
--
--  Speed: 1200 u/s cruise matching original VJ rocket speed.
--
--  Bug fixes vs previous version:
--   1. phys sleep guard: if phys goes invalid/asleep mid-flight we
--      re-wake it, and after 2 consecutive failed ticks we detonate.
--   2. DoExplosion calls self:StopParticles() before Remove() to
--      prevent the client emitter orphaning smoke in mid-air.
-- ============================================================

ENT.HealthVal = 30
ENT.Damage    = 0
ENT.Radius    = 0
ENT.Dead      = false

-- Speed (units/s) — matches original VJ obj_vj_rocket launch speed
local SPEED_BOOST  = 200    -- soft-launch ejection before engine fires
local SPEED_CRUISE = 1200   -- engine-on cruise (same as VJ rocket)
local SPEED_ACCEL  = 3000   -- u/s^2 — reaches cruise in ~0.33s

-- Apex geometry
local APEX_FRAC = 0.55
local APEX_MIN  = 300
local APEX_MAX  = 800

-- Sounds
local SND_LAUNCH  = "weapons/rpg/rocket1.wav"
local SND_ENGINE  = "vehicles/combine_apc/apc_rocket_launch1.wav"
local SND_EXPLODE = "ambient/explosions/explode_8.wav"

-- ============================================================
--  Bezier helpers
-- ============================================================
local function BezierPos( p0, p1, p2, t )
    local u = 1 - t
    return p0*(u*u) + p1*(2*u*t) + p2*(t*t)
end

-- Derivative (tangent) of quadratic bezier — always points along the curve
local function BezierTangent( p0, p1, p2, t )
    return (p1 - p0) * (2*(1-t)) + (p2 - p1) * (2*t)
end

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    self:SetSolid( SOLID_BBOX )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    -- VPHYSICS: same as obj_vj_projectile_base
    if not self:PhysicsInit( MOVETYPE_VPHYSICS ) then
        self:PhysicsInitSphere( 4, "metal_bouncy" )
    end
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetMoveCollide( MOVECOLLIDE_FLY_BOUNCE )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:Wake()
        phys:SetMass( 1 )
        phys:EnableGravity( false )
        phys:EnableDrag( false )
        phys:SetBuoyancyRatio( 0 )
    end

    self:AddEFlags( EFL_DONTBLOCKLOS )
    self:AddEFlags( EFL_DONTWALKON )
    self:AddSolidFlags( FSOLID_NOT_STANDABLE )
    self:SetTrigger( true )

    -- State
    self.Dead          = false
    self.ArcReady      = false
    self.ArcT          = 0
    self.ArcLength     = nil
    self.Speed         = SPEED_BOOST
    self.SpawnTime     = CurTime()
    self.BadPhysTicks  = 0   -- consecutive ticks where phys was unavailable
    self.ArcP0 = nil
    self.ArcP1 = nil
    self.ArcP2 = nil

    self.EngineSound = CreateSound( self, SND_ENGINE )

    -- Soft-launch: tilt nose up 25 deg then eject
    local ang = self:GetAngles()
    ang.pitch = ang.pitch - 25
    self:SetAngles( ang )

    local ejPhys = self:GetPhysicsObject()
    if IsValid( ejPhys ) then
        ejPhys:SetVelocity( self:GetForward() * SPEED_BOOST )
    end

    sound.Play( SND_LAUNCH, self:GetPos(), 85, 100 )

    local selfRef = self
    timer.Simple( 0.5, function()
        if IsValid( selfRef ) and not selfRef.Dead then
            selfRef:FireEngine()
        end
    end )

    self:NextThink( CurTime() )
end

-- ============================================================
--  Collision
-- ============================================================
function ENT:PhysicsCollide( data, phys )
    if self.Dead then return end
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
--  FireEngine  -  bake arc once, null Target immediately
-- ============================================================
function ENT:FireEngine()
    if self.Dead then return end

    self.Damage = math.random( 2500, 4500 )
    self.Radius = math.random( 512,  760 )
    self:SetNWBool( "EngineStarted", true )
    self.EngineSound:PlayEx( 85, 100 )

    if not self.Target then
        self.ArcReady = false
        return
    end

    local p0 = self:GetPos()
    local p2 = Vector( self.Target.x, self.Target.y, self.Target.z )

    local hDist      = ( Vector(p0.x,p0.y,0) - Vector(p2.x,p2.y,0) ):Length()
    local apexHeight = math.Clamp( hDist * APEX_FRAC, APEX_MIN, APEX_MAX )
    local baseZ      = math.max( p0.z, p2.z )

    self.ArcP0    = p0
    self.ArcP1    = Vector( (p0.x+p2.x)*0.5, (p0.y+p2.y)*0.5, baseZ + apexHeight )
    self.ArcP2    = p2
    self.ArcT     = 0
    self.ArcReady = true
    self.Target   = nil

    -- Pre-compute arc length (20-sample polyline)
    local len  = 0
    local prev = self.ArcP0
    for i = 1, 20 do
        local nxt = BezierPos( self.ArcP0, self.ArcP1, self.ArcP2, i/20 )
        len  = len + ( nxt - prev ):Length()
        prev = nxt
    end
    self.ArcLength = math.max( len, 1 )

    print( string.format(
        "[TopMissile] Arc baked | hDist=%.0f apex=+%.0f arcLen=%.0f",
        hDist, apexHeight, self.ArcLength
    ))
end

-- ============================================================
--  Think
-- ============================================================
function ENT:Think()
    self:NextThink( CurTime() )
    if self.Dead then return true end

    -- Hard timeout (45 s)
    if CurTime() - self.SpawnTime > 45 then
        self:DoExplosion()
        return true
    end

    local phys = self:GetPhysicsObject()

    -- Physics object guard: VPHYSICS entities can have their phys
    -- object go to sleep or become temporarily invalid.
    -- We wake it immediately; if it stays bad for 3 consecutive ticks
    -- we detonate rather than leave a ghost missile.
    if not IsValid( phys ) then
        self.BadPhysTicks = self.BadPhysTicks + 1
        if self.BadPhysTicks >= 3 then
            self:DoExplosion()
        end
        return true
    end

    -- Re-wake physics if it fell asleep (engine idle optimisation)
    if not phys:IsMoveable() then
        phys:Wake()
    end
    self.BadPhysTicks = 0

    -- Pre-engine coast
    if not self.ArcReady then
        phys:SetVelocity( self:GetForward() * self.Speed )
        return true
    end

    local dt = FrameTime()
    if dt <= 0 then dt = 0.015 end

    -- Accelerate to cruise
    self.Speed = math.min( self.Speed + SPEED_ACCEL * dt, SPEED_CRUISE )

    -- Advance arc parameter t
    self.ArcT = math.min( self.ArcT + ( self.Speed / self.ArcLength ) * dt, 1 )

    -- Direction = tangent of the bezier at t (never overshoots)
    local tan = BezierTangent( self.ArcP0, self.ArcP1, self.ArcP2, self.ArcT )
    if tan:LengthSqr() < 0.001 then return true end

    local dir = tan:GetNormalized()
    self:SetAngles( dir:Angle() )
    phys:SetVelocity( dir * self.Speed )
    phys:Wake()   -- keep physics awake every tick

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

    -- Stop engine sound
    if self.EngineSound then self.EngineSound:Stop() end

    -- CRITICAL: stop all server-side particles BEFORE Remove()
    -- This signals the client to call Emitter:Finish() in OnRemove()
    -- so no smoke sprites are left floating in world space.
    self:StopParticles()

    sound.Play( SND_EXPLODE, pos, 100, 100 )
    util.ScreenShake( pos, 16, 200, 1, 3000 )

    local ang = Angle(0,0,0)
    ParticleEffect( "vj_explosion3", pos, ang )

    local ed = EffectData()
    ed:SetOrigin( pos )
    util.Effect( "VJ_Small_Explosion1", ed )

    -- Physics shockwave
    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor(dmg*0.5) ) )
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
    self:StopParticles()
end
