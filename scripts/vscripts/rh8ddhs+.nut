printl("Activating Realism Hard Eight Death's Door Headshot!+")

MutationOptions <- {
	ActiveChallenge = 1

	cm_SpecialRespawnInterval = 15
	cm_MaxSpecials = 8
	cm_BaseSpecialLimit = 2
	cm_DominatorLimit = 8

	cm_ShouldHurry = true
	cm_AllowPillConversion = false
	cm_AllowSurvivorRescue = false
	SurvivorMaxIncapacitatedCount = 0
	TempHealthDecayRate = 0.0

	cm_HeadshotOnly = true

	function AllowFallenSurvivorItem( classname ) {
		if (classname == "weapon_first_aid_kit")
			return false
		return true
	}

	weaponsToConvert = {
		weapon_first_aid_kit = "weapon_pain_pills_spawn"
		weapon_adrenaline = "weapon_pain_pills_spawn"
	}

	function ConvertWeaponSpawn( classname ) {
		if (classname in weaponsToConvert)
			return weaponsToConvert[ classname ]
		return 0
	}

	DefaultItems = [
		"weapon_pistol",
		"weapon_pistol",
	]

	function GetDefaultItem( idx ) {
		if (idx < DefaultItems.len())
			return DefaultItems[ idx ]
		return 0
	}
}

function OnGameEvent_round_start( params ) {
	Convars.SetValue( "pain_pills_decay_rate", 0.0 )
}

function OnGameEvent_player_left_safe_area( params ) {
	DirectorOptions.TempHealthDecayRate = 0.27
}

function OnGameEvent_player_hurt_concise( params ) {
	local player = GetPlayerFromUserID( params.userid )

	if (!player || !player.IsSurvivor() || player.IsHangingFromLedge())
		return

	if (NetProps.GetPropInt( player, "m_bIsOnThirdStrike" ) == 0 && player.GetHealth() < player.GetMaxHealth() / 4) {
		player.SetReviveCount( 0 )
		NetProps.SetPropInt( player, "m_isGoingToDie", 1 )
	}
}

function OnGameEvent_defibrillator_used( params ) {
	local player = GetPlayerFromUserID( params.subject )

	if (!player || !player.IsSurvivor())
		return

	player.SetHealth( 24 )
	player.SetHealthBuffer( 36 )
	player.SetReviveCount( 0 )
	NetProps.SetPropInt( player, "m_isGoingToDie", 1 )
}

function CheckHealthAfterLedgeHang( userid ) {
	local player = GetPlayerFromUserID( userid )
	if (!player || !player.IsSurvivor())
		return

	if (player.GetHealth() < player.GetMaxHealth() / 4) {
		player.SetReviveCount( 0 )
		NetProps.SetPropInt( player, "m_isGoingToDie", 1 )
	}
}

function OnGameEvent_revive_success( params ) {
	local player = GetPlayerFromUserID( params.subject )

	if (!params.ledge_hang || !player || !player.IsSurvivor())
		return

	if (NetProps.GetPropInt( player, "m_bIsOnThirdStrike" ) == 0)
		EntFire( "worldspawn", "RunScriptCode", "g_ModeScript.CheckHealthAfterLedgeHang(" + params.subject + ")", 0.1 )
}

function OnGameEvent_bot_player_replace( params ) {
	local player = GetPlayerFromUserID( params.player )

	if (!player || NetProps.GetPropInt( player, "m_bIsOnThirdStrike" ) == 1)
		return

	StopSoundOn( "Player.Heartbeat", player )
}

if (!Director.IsSessionStartMap()) {
	function PlayerSpawnDeadAfterTransition( userid ) {
		local player = GetPlayerFromUserID( userid )
		if (!player)
			return

		player.SetHealth( 24 )
		player.SetHealthBuffer( 26 )
		player.SetReviveCount( 0 )
		NetProps.SetPropInt( player, "m_isGoingToDie", 1 )
	}

	function PlayerSpawnAliveAfterTransition( userid ) {
		local player = GetPlayerFromUserID( userid )
		if (!player)
			return

		local maxHealth = player.GetMaxHealth()
		local oldHealth = player.GetHealth()
		local maxHeal = maxHealth / 2
		local healAmount = 0

		if (oldHealth < maxHeal)
			healAmount = floor( (maxHeal - oldHealth) * 0.8 + 0.5 )

		if (healAmount > 0) {
			player.SetHealth( oldHealth + healAmount )
			local bufferHealth = player.GetHealthBuffer() - healAmount
			if (bufferHealth < 0.0)
				bufferHealth = 0.0
			player.SetHealthBuffer( bufferHealth )
		}
		NetProps.SetPropInt( player, "m_bIsOnThirdStrike", 0 )
		NetProps.SetPropInt( player, "m_isGoingToDie", 0 )
	}

	function OnGameEvent_player_transitioned( params ) {
		local player = GetPlayerFromUserID( params.userid )

		if (!player || !player.IsSurvivor())
			return

		if (NetProps.GetPropInt( player, "m_lifeState" ) == 2)
			EntFire( "worldspawn", "RunScriptCode", "g_ModeScript.PlayerSpawnDeadAfterTransition(" + params.userid + ")", 0.1 )
		else
			EntFire( "worldspawn", "RunScriptCode", "g_ModeScript.PlayerSpawnAliveAfterTransition(" + params.userid + ")", 0.1 )
	}
}

extraIncludedInflictors <- {prop_minigun=1, prop_minigun_l4d1=1, env_weaponfire=1}
const HITGROUP_HEAD = 1

const DMG_FALL = 32
const DMG_POISON = 131072 // also occurs during the Tank death animation
const DMG_PLASMA = 16777216 // M60 and prop_minigun (l4d2) damage
const DMG_DISSOLVE = 67108864 // chainsaw damage
const DMG_DIRECT = 268435456
alwaysAllowedDmg <- DMG_HEADSHOT | DMG_DIRECT | DMG_DISSOLVE | DMG_PLASMA | DMG_POISON | DMG_BLAST | DMG_FALL

function AllowTakeDamage( damageTable ) {
	local victim = damageTable.Victim, victimcls = victim.GetClassname()
	local inflictor = damageTable.Inflictor, inflictorcls = inflictor.GetClassname()
	local dmgtype = damageTable.DamageType

	if (victimcls == "infected" || victim.IsPlayer() && !victim.IsSurvivor() || victimcls == "witch") {
		if (NetProps.GetPropInt( inflictor, "m_iTeamNum" ) >= 2 || inflictorcls in extraIncludedInflictors) {
			if (victim.IsPlayer() && dmgtype & DMG_BUCKSHOT && NetProps.GetPropInt( victim, "m_LastHitGroup" ) == HITGROUP_HEAD)
				dmgtype = dmgtype | DMG_HEADSHOT // because of https://github.com/Tsuey/L4D2-Community-Update/issues/41

			if (!(dmgtype & alwaysAllowedDmg) && inflictorcls != "tank_rock" && inflictorcls != "weapon_tank_claw")
				damageTable.DamageDone = 0
		}
	}
	return true
}