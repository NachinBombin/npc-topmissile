-- ============================================================
--  NPC Top-Attack Terror Missile – Launch Utility
--  FULLY STANDALONE – no other addon dependency required.
--
--  Drop this addon into garrysmod/addons/ and call:
--
--      LaunchNPCTopMissile( npcEntity, targetEntity )
--
--  from your NPC's AI (Think, schedule, SCHED_RANGE_ATTACK1, etc.)
--
--  Returns the missile entity on success, nil on failure.
--
--  *** CRITICAL SPAWN ORDER ***
--  Target / Owner MUST be set BEFORE Spawn() is called so that
--  Initialize() can read them.  SetVelocity must NOT be called
--  by the caller — FireEngine() handles the 108 450 u/s kick.
-- ============================================================

if not SERVER then return end

local MIN_FIRE_DIST = 1024

function LaunchNPCTopMissile( npc, target )
    if not IsValid( npc )    then return nil end
    if not IsValid( target ) then return nil end

    local dist = ( npc:GetPos() - target:GetPos() ):Length()
    if dist < MIN_FIRE_DIST then return nil end

    local ent = ents.Create( "sent_npc_topmissile" )
    if not IsValid( ent ) then return nil end

    -- -------------------------------------------------------
    --  Step 1: set pos / angle BEFORE Spawn()
    --  Initialize() will override the angle to Angle(-90, y, 0)
    --  but we need a valid y (yaw) so the arc goes the right way.
    -- -------------------------------------------------------
    local eyePos = npc:EyePos()
    local aimDir = ( target:GetPos() + Vector( 0, 0, 36 ) - eyePos ):GetNormalized()
    local launchYaw = aimDir:Angle().y

    ent:SetPos( eyePos + aimDir * 32 )
    ent:SetAngles( Angle( 0, launchYaw, 0 ) )  -- pitch overridden by Initialize()

    -- -------------------------------------------------------
    --  Step 2: set Owner + Target BEFORE Spawn() so Initialize()
    --  can read them and set up the fallback correctly.
    -- -------------------------------------------------------
    ent.Owner        = npc
    ent.Target       = target:GetPos() + Vector( 0, 0, 36 )
    ent.TargetEntity = target   -- enables live-tracking in final dive phase

    -- -------------------------------------------------------
    --  Step 3: Spawn + Activate  (Initialize() runs here)
    -- -------------------------------------------------------
    ent:Spawn()
    ent:Activate()

    -- NOTE: do NOT call GetPhysicsObject():SetVelocity() here.
    -- The missile starts stationary; FireEngine() fires the kick
    -- 0.75 s later once the nose is already pointing straight up.

    return ent
end
