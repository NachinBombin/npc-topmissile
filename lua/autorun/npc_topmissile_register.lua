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
--  The missile will fly the full Javelin top-attack arc but
--  land NEAR the target, never on it.  The miss radius is
--  between JITTER_MIN and JITTER_MAX (set in init.lua).
--
--  Returns the missile entity on success, nil on failure.
-- ============================================================

if not SERVER then return end

-- Minimum safe firing distance (will refuse to fire if closer)
local MIN_FIRE_DIST = 1024

function LaunchNPCTopMissile( npc, target )
    if not IsValid( npc )    then return nil end
    if not IsValid( target ) then return nil end

    local dist = ( npc:GetPos() - target:GetPos() ):Length()
    if dist < MIN_FIRE_DIST then return nil end   -- too close; refuse

    local ent = ents.Create( "sent_npc_topmissile" )
    if not IsValid( ent ) then return nil end

    -- Fire from NPC eye level, pushed slightly forward so it clears the body
    local eyePos = npc:EyePos()
    local aimDir = ( target:GetPos() + Vector( 0, 0, 36 ) - eyePos ):GetNormalized()

    ent:SetPos( eyePos + aimDir * 32 )
    ent:SetAngles( aimDir:Angle() )
    ent:Spawn()
    ent:Activate()

    ent.Owner       = npc
    -- Pass the REAL target position here.  FireEngine() will apply the
    -- jitter offset to this value after the 0.75s soft-launch delay.
    ent.Target      = target:GetPos() + Vector( 0, 0, 36 )
    -- TargetEntity intentionally left nil here; FireEngine() also clears it
    -- after baking the jitter, so there is no live-tracking correction.

    return ent
end

-- ============================================================
--  EXAMPLE – uncomment to test in-game immediately.
--  Fires a missile from every living combine soldier at their
--  current enemy every 8 seconds (if range > 1024 units).
-- ============================================================
--[[
hook.Add( "Think", "NPCTopMissile_CombineExample", function()
    for _, npc in ipairs( ents.FindByClass( "npc_combine_s" ) ) do
        if not IsValid( npc ) or not npc:Alive() then continue end

        local enemy = npc:GetEnemy()
        if not IsValid( enemy ) then continue end

        if ( npc.TerrorMissileCooldown or 0 ) > CurTime() then continue end

        local dist = ( npc:GetPos() - enemy:GetPos() ):Length()
        if dist > MIN_FIRE_DIST then
            LaunchNPCTopMissile( npc, enemy )
            npc.TerrorMissileCooldown = CurTime() + 8
        end
    end
end )
]]
