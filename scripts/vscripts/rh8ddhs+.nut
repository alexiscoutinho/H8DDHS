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
		if (classname != "weapon_first_aid_kit")
			return true

		if (RandomInt( 1, 100 ) > 25) {
			local fallen

			while (fallen = Entities.FindByClassname( fallen, "infected" )) {
				if (NetProps.GetPropInt( fallen, "m_Gender" ) == GENDER_FALLEN)
					break
			}

			local defib = SpawnEntityFromTable( "prop_dynamic", {
				model = "models/w_models/weapons/w_eq_defibrillator.mdl"
				solid = 4
			} )

			DoEntFire( "!caller", "SetParent", "!activator", 0.0, fallen, defib )
			DoEntFire( "!self", "SetParentAttachment", "medkit", 0.0, null, defib )
			local code = "self.SetLocalAngles( QAngle( -90, 0, 0 ) ); self.SetLocalOrigin( Vector( 1.5, 1, 4 ) )"
			DoEntFire( "!self", "RunScriptCode", code, 0.0, null, defib )

			fallen.ValidateScriptScope()
			fallen.GetScriptScope().defib <- defib
		}
		return false
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

const GENDER_FALLEN = 14

function OnGameEvent_zombie_death( params ) {
	if (params.gender != GENDER_FALLEN)
		return

	local fallen = EntIndexToHScript( params.victim )
	local scope = fallen.GetScriptScope()

	if (scope && ("defib" in scope) && scope.defib.IsValid()) {
		scope.defib.Kill()

		local w_defib = SpawnEntityFromTable( "weapon_defibrillator", {
			angles = scope.defib.GetAngles().ToKVString()
			origin = scope.defib.GetOrigin()
		} )

		w_defib.ApplyAbsVelocityImpulse( GetPhysVelocity( scope.defib ) )
		w_defib.ApplyLocalAngularVelocityImpulse( GetPhysAngularVelocity( scope.defib ) )
	}
}

function OnGameEvent_round_start( params ) {
	Convars.SetValue( "pain_pills_decay_rate", 0.0 )
}

function OnGameEvent_player_left_safe_area( params ) {
	DirectorOptions.TempHealthDecayRate = 0.27
}

function OnGameEvent_defibrillator_used( params ) {
	local player = GetPlayerFromUserID( params.subject )
	if (!player)
		return

	player.SetHealth( 1 )
	player.SetHealthBuffer( 99 )
}

function OnGameEvent_player_bot_replace( params ) {
	local player = GetPlayerFromUserID( params.player )
	if (!player)
		return

	local scope = player.GetScriptScope()
	if (scope.HeartbeatOn) {
		StopSoundOn( "Player.Heartbeat", player )
		scope.HeartbeatOn = false
	}
	AddThinkToEnt( player, null )
}

function OnGameEvent_bot_player_replace( params ) {
	local player = GetPlayerFromUserID( params.player )
	if (!player)
		return

	if (player.GetHealth() >= player.GetMaxHealth() / 4)
		StopSoundOn( "Player.Heartbeat", player )
	else
		player.GetScriptScope().HeartbeatOn = true // unreliable if sb_takecontrol was used
}

function OnGameEvent_player_complete_sacrifice( params ) {
	local player = GetPlayerFromUserID( params.userid )
	if (!player)
		return

	NetProps.SetPropInt( player, "m_takedamage", 0 )
	NetProps.SetPropInt( player, "m_isIncapacitated", 1 )
}

function HealthEffectsThink() {
	if (self.IsHangingFromLedge())
		return

	local health = self.GetHealth()

	if (health >= self.GetMaxHealth() / 4) {
		if (HeartbeatOn) {
			StopSoundOn( "Player.Heartbeat", self )
			HeartbeatOn = false

			if (NetProps.GetPropInt( self, "m_bIsOnThirdStrike" ) == 1) {
				NetProps.SetPropInt( self, "m_bIsOnThirdStrike", 0 )
				NetProps.SetPropInt( self, "m_isGoingToDie", 0 )
			}
		}
	}
	else if (health > 1) {
		if (!HeartbeatOn) {
			EmitSoundOnClient( "Player.Heartbeat", self )
			HeartbeatOn = true
		}
		else if (NetProps.GetPropInt( self, "m_bIsOnThirdStrike" ) == 1) {
			NetProps.SetPropInt( self, "m_bIsOnThirdStrike", 0 )
			NetProps.SetPropInt( self, "m_isGoingToDie", 0 )
		}
	}
	else {
		if (NetProps.GetPropInt( self, "m_bIsOnThirdStrike" ) == 0) {
			NetProps.SetPropInt( self, "m_bIsOnThirdStrike", 1 )
			NetProps.SetPropInt( self, "m_isGoingToDie", 1 )

			if (!HeartbeatOn) {
				EmitSoundOnClient( "Player.Heartbeat", self )
				HeartbeatOn = true
			}
		}
	}
}

function OnGameEvent_player_spawn( params ) {
	local player = GetPlayerFromUserID( params.userid )
	if (!player || NetProps.GetPropInt( player, "m_iTeamNum" ) != 2)
		return

	if (!player.GetScriptScope()) {
		player.ValidateScriptScope()
		local scope = player.GetScriptScope()
		scope.HeartbeatOn <- false
		scope.HealthEffectsThink <- HealthEffectsThink
	}
	AddThinkToEnt( player, "HealthEffectsThink" )
}

function OnGameEvent_player_death( params ) {
	if (!("userid" in params))
		return

	local player = GetPlayerFromUserID( params.userid )
	if (!player || !player.IsSurvivor())
		return

	local scope = player.GetScriptScope()
	if (scope.HeartbeatOn) {
		StopSoundOn( "Player.Heartbeat", player )
		scope.HeartbeatOn = false
	}
	AddThinkToEnt( player, null )
}

if (!Director.IsSessionStartMap()) {
	function PlayerSpawnDeadAfterTransition( userid ) {
		local player = GetPlayerFromUserID( userid )
		if (!player)
			return

		player.SetHealth( 24 )
		player.SetHealthBuffer( 26 )
	}

	function PlayerSpawnAliveAfterTransition( userid ) {
		local player = GetPlayerFromUserID( userid )
		if (!player)
			return

		local oldHealth = player.GetHealth()
		local maxHeal = player.GetMaxHealth() / 2
		local healAmount = 0

		if (oldHealth < maxHeal) {
			healAmount = floor( (maxHeal - oldHealth) * 0.8 + 0.5 )
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
			EntFire( "worldspawn", "RunScriptCode", "g_ModeScript.PlayerSpawnDeadAfterTransition(" + params.userid + ")", 0.0 )
		else
			EntFire( "worldspawn", "RunScriptCode", "g_ModeScript.PlayerSpawnAliveAfterTransition(" + params.userid + ")", 0.0 )
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