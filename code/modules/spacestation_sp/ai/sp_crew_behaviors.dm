// Behavior-tree leaves, decorators, subtrees and targeting strategies used by Spacestation SP crew.

// --- Subtree declarations (trees live next to this file) --------------------------------------

/// Shared high-priority reactions: escape restraints, react to attackers, seek medbay, avoid armed people, answer to our name.
/datum/bt_node/subtree/sp_crew_core
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_core.bt.json"

/// Walk to a random turf inside our department (or the areas in BB_SP_WANDER_AREAS), then linger.
/datum/bt_node/subtree/sp_department_wander
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_department_wander.bt.json"

/// When hurt: shout for help and walk to medbay.
/datum/bt_node/subtree/sp_crew_safety
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_safety.bt.json"

/// When someone addresses us by name: face them and answer.
/datum/bt_node/subtree/sp_crew_social
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_social.bt.json"

/// When attacked: report it (radio if we have one, otherwise shout) and get away.
/datum/bt_node/subtree/sp_crew_defense
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_defense.bt.json"

/// When someone nearby is wielding a weapon: warn them and keep our distance.
/datum/bt_node/subtree/sp_crew_threat
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_threat.bt.json"

/// Medical: find a treatable patient, equip the right medical stack, walk over and apply it.
/datum/bt_node/subtree/sp_medical_treat
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_medical_treat.bt.json"

/// Security: respond to a reported incident, subdue and cuff the suspect.
/datum/bt_node/subtree/sp_security_respond
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_security_respond.bt.json"

/// Engineering: when the station is short on power, go to the engine room and set the engine up.
/datum/bt_node/subtree/sp_engineer_power
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_engineer_power.bt.json"

/// Engineering: walk to a hull breach and patch it with the RCD.
/datum/bt_node/subtree/sp_engineer_repair
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_engineer_repair.bt.json"

// --- Movement -----------------------------------------------------------------------------------

/**
 * Station-wide pathfinding. TG's default AI movement caps paths at AI_MAX_PATH_LENGTH (30 tiles),
 * which is fine for animals that lose interest after 14 tiles but leaves crew unable to walk to
 * medbay, the engine room, or an incident on the far side of the station.
 */
/datum/ai_movement/jps/sp_crew
	max_pathing_attempts = 40
	maximum_length = 220

// --- Helpers ----------------------------------------------------------------------------------

/// Is this human holding something we would call a weapon?
/proc/sp_is_armed(mob/living/carbon/human/who)
	for(var/obj/item/held in who.held_items)
		if(istype(held, /obj/item/gun))
			return TRUE
		if(istype(held, /obj/item/melee))
			return TRUE
		if(istype(held, /obj/item/storage)) // toolboxes hurt, but everyone carries them
			continue
		if(held.force >= 12)
			return TRUE
	return FALSE

/// Security and command are allowed to carry weapons without scaring the crew.
/proc/sp_is_authority(mob/living/carbon/human/who)
	var/datum/job/role = who.mind?.assigned_role
	if(isnull(role))
		return FALSE
	if(role.job_flags & JOB_HEAD_OF_STAFF)
		return TRUE
	return (/datum/job_department/security in role.departments_list) || (/datum/job_department/command in role.departments_list)

/// Words that make security treat a spoken line from a player as a call for help.
/proc/sp_message_is_distress(message)
	var/static/list/distress_words = list("help", "attack", "murder", "kill", "shooting", "stab", "security", "assault")
	var/lowered = LOWER_TEXT(message)
	for(var/word in distress_words)
		if(findtext(lowered, word))
			return TRUE
	return FALSE

/**
 * Speaks for an AI crew member. If `channel` is given and the crew member wears a headset that has that
 * channel (common is on every headset), the line goes over the radio; otherwise it is said out loud.
 */
/proc/sp_crew_speak(mob/living/carbon/human/speaker, message, channel = null)
	if(QDELETED(speaker) || !length(message))
		return
	var/prefix = ""
	if(channel)
		var/obj/item/radio/headset/headset = speaker.ears
		if(istype(headset))
			if(channel == RADIO_CHANNEL_COMMON)
				prefix = RADIO_KEY_COMMON
			else
				var/static/list/channel_keys = list(
					RADIO_CHANNEL_SECURITY = RADIO_KEY_SECURITY,
					RADIO_CHANNEL_ENGINEERING = RADIO_KEY_ENGINEERING,
					RADIO_CHANNEL_MEDICAL = RADIO_KEY_MEDICAL,
					RADIO_CHANNEL_COMMAND = RADIO_KEY_COMMAND,
					RADIO_CHANNEL_SUPPLY = RADIO_KEY_SUPPLY,
					RADIO_CHANNEL_SERVICE = RADIO_KEY_SERVICE,
				)
				var/key = channel_keys[channel]
				if(key && LAZYACCESS(headset.channels, channel))
					prefix = "." + key
				else
					prefix = RADIO_KEY_COMMON
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(sp_crew_say_now), speaker, prefix + message)

/proc/sp_crew_say_now(mob/living/speaker, text)
	if(QDELETED(speaker))
		return
	speaker.say(text, forced = "AI Controller")

/// Finds the first item of one of `types` (in order of preference) anywhere in our inventory and puts it in our active hand.
/// Returns the item, or null if we do not carry one or could not equip it.
/proc/sp_equip_from_inventory(mob/living/carbon/pawn, list/types)
	var/list/carried = list()
	for(var/wanted_type in types)
		carried += pawn.get_all_contents_type(wanted_type)
	if(!length(carried))
		return null
	var/obj/item/chosen
	for(var/wanted_type in types)
		for(var/obj/item/candidate as anything in carried)
			if(istype(candidate, wanted_type))
				chosen = candidate
				break
		if(chosen)
			break
	if(isnull(chosen))
		return null

	if(!pawn.is_holding(chosen))
		if(!pawn.put_in_hands(chosen))
			// Both hands full; free the active one and try again.
			var/obj/item/active = pawn.get_active_held_item()
			if(isnull(active) || !pawn.dropItemToGround(active) || !pawn.put_in_hands(chosen))
				return null
	if(pawn.get_active_held_item() != chosen)
		pawn.swap_hand()
	return pawn.get_active_held_item() == chosen ? chosen : null

// --- Leaves: movement -------------------------------------------------------------------------

/**
 * Picks a random walkable turf inside one of a set of areas and stores it in target_key.
 * Areas come from the blackboard list in areas_key, else from fixed_areas, else from the type
 * of BB_SP_HOME_AREA (including subtypes).
 */
/datum/bt_node/ai_behavior/sp_pick_wander_turf
	/// Blackboard key to write the chosen turf into.
	var/target_key = BB_SP_WANDER_TARGET
	/// Blackboard key holding a list of /area typepaths to choose from. Optional.
	var/areas_key = BB_SP_WANDER_AREAS
	/// Fixed list of /area typepaths, used when areas_key yields nothing. Optional.
	var/list/fixed_areas
	/// How many random turfs to test before giving up on an area.
	var/attempts = 12

/datum/bt_node/ai_behavior/sp_pick_wander_turf/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/pawn = controller.pawn
	var/turf/pawn_turf = get_turf(pawn)
	if(isnull(pawn_turf))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/list/area_types = list()
	var/include_subtypes = FALSE
	var/list/from_bb = areas_key ? controller.blackboard[areas_key] : null
	if(length(from_bb))
		area_types = from_bb.Copy()
	else if(length(fixed_areas))
		area_types = fixed_areas.Copy()
	else
		var/area/home = controller.blackboard[BB_SP_HOME_AREA]
		if(isnull(home))
			home = get_area(pawn)
		if(isnull(home))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		area_types = list(home.type)
		include_subtypes = TRUE

	// Try a few areas in random order; some will not exist on this z-level.
	area_types = shuffle(area_types)
	for(var/area_type in area_types)
		var/list/turfs = get_area_turfs(area_type, pawn_turf.z, include_subtypes)
		if(!length(turfs))
			continue
		for(var/i in 1 to attempts)
			var/turf/candidate = pick(turfs)
			if(candidate == pawn_turf || candidate.density || isgroundlessturf(candidate))
				continue
			if(candidate.is_blocked_turf(exclude_mobs = TRUE))
				continue
			controller.set_blackboard_key(target_key, candidate)
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

/// Medbay variant with a fixed area list, used by the safety subtree.
/datum/bt_node/ai_behavior/sp_pick_wander_turf/medbay
	target_key = BB_SP_MEDBAY_TARGET
	areas_key = null
	fixed_areas = list(
		/area/station/medical/treatment_center,
		/area/station/medical/medbay/central,
		/area/station/medical/medbay/lobby,
		/area/station/medical/medbay/aft,
		/area/station/medical/exam_room,
	)

/// Engine room variant, used by the engineer power subtree.
/datum/bt_node/ai_behavior/sp_pick_wander_turf/engine
	target_key = BB_SP_ENGINE_TARGET
	areas_key = null
	fixed_areas = list(
		/area/station/engineering/supermatter/room,
		/area/station/engineering/engine_smes,
		/area/station/engineering/main,
	)

// --- Leaves: speech ---------------------------------------------------------------------------

/**
 * Says one of `lines`, optionally facing the atom in face_key first.
 * "%TARGET%" in a line is replaced with that atom's name, "%AREA%" with our current area.
 * If radio_channel is set the line goes over the radio when we have a headset for it.
 */
/datum/bt_node/ai_behavior/sp_say
	/// Lines to pick from.
	var/list/lines
	/// Optional blackboard key holding an atom to face / name in the line.
	var/face_key
	/// Optional radio channel (RADIO_CHANNEL_*) to try first.
	var/radio_channel

/datum/bt_node/ai_behavior/sp_say/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || !length(lines))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/atom/target = face_key ? controller.blackboard[face_key] : null
	var/line = pick(lines)
	if(!QDELETED(target))
		pawn.face_atom(target)
		line = replacetext(line, "%TARGET%", target.name)
	var/area/here = get_area(pawn)
	line = replacetext(line, "%AREA%", here ? here.name : "the station")
	sp_crew_speak(pawn, line, radio_channel)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/datum/bt_node/ai_behavior/sp_say/need_medic
	lines = list(
		"I need a doctor!",
		"Medic! Somebody get a medic!",
		"Ow... I'm heading to medbay.",
		"Is there a doctor around? I'm hurt.",
	)

/datum/bt_node/ai_behavior/sp_say/greet
	face_key = BB_SP_ATTENTION_TARGET
	lines = list(
		"Yes, %TARGET%?",
		"What do you need, %TARGET%?",
		"Hm? Oh, hello %TARGET%.",
		"I'm a bit busy, %TARGET%, but go ahead.",
		"You called?",
	)

/datum/bt_node/ai_behavior/sp_say/threat_warning
	face_key = BB_SP_THREAT
	lines = list(
		"Whoa, %TARGET%, put that away!",
		"Hey! What are you doing with that?",
		"Stay back, I mean it.",
		"Is that a weapon? Keep your distance!",
		"Security! Someone's armed in %AREA%!",
	)

/datum/bt_node/ai_behavior/sp_say/security_ack
	radio_channel = RADIO_CHANNEL_SECURITY
	lines = list(
		"Copy, responding.",
		"On my way.",
		"Security responding, hold on.",
	)

/datum/bt_node/ai_behavior/sp_say/security_resolved
	radio_channel = RADIO_CHANNEL_SECURITY
	lines = list(
		"Situation handled.",
		"Suspect is down, area secure.",
		"Nothing more to see here.",
	)

/datum/bt_node/ai_behavior/sp_say/engine_go
	radio_channel = RADIO_CHANNEL_ENGINEERING
	lines = list(
		"Power's getting low, heading to the engine.",
		"Going to check on the supermatter.",
		"Engine room, on my way.",
	)

// --- Leaves: threats and attacks --------------------------------------------------------------

/// Keeps BB_SP_THREAT pointing at the nearest visible, conscious, armed non-authority human, or clears it.
/datum/bt_node/ai_behavior/sp_scan_threats
	time_between_perform = 1 SECONDS
	/// Blackboard key holding the threat.
	var/threat_key = BB_SP_THREAT
	/// How far we look.
	var/scan_range = 5
	/// How long we keep worrying after losing sight of the threat.
	var/forget_after = 6 SECONDS

/datum/bt_node/ai_behavior/sp_scan_threats/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/pawn = controller.pawn
	var/mob/living/current = controller.blackboard[threat_key]
	var/mob/living/found
	for(var/mob/living/carbon/human/candidate in oview(scan_range, pawn))
		if(candidate.stat != STABLE || !sp_is_armed(candidate) || sp_is_authority(candidate))
			continue
		if(!can_see(pawn, candidate, scan_range))
			continue
		found = candidate
		if(candidate == current)
			break
	if(found)
		if(found != current)
			controller.set_blackboard_key(threat_key, found)
		controller.set_blackboard_key(BB_SP_THREAT_SEEN_AT, world.time)
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED
	if(!isnull(current))
		var/seen_at = controller.blackboard[BB_SP_THREAT_SEEN_AT] || 0
		if(QDELETED(current) || world.time - seen_at > forget_after)
			controller.clear_blackboard_key(threat_key)
	return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED

/// Reports the attacker in BB_SP_ATTACKER: over the radio if we have one, otherwise by shouting.
/// Also records a structured incident in BB_SP_LAST_INCIDENT so security who hear us know where to go.
/datum/bt_node/ai_behavior/sp_report_attack
	/// Blackboard key holding the attacker.
	var/attacker_key = BB_SP_ATTACKER

/datum/bt_node/ai_behavior/sp_report_attack/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/mob/living/attacker = controller.blackboard[attacker_key]
	var/area/here = get_area(pawn)
	var/where = here ? here.name : "the station"
	var/who = QDELETED(attacker) ? "Someone" : attacker.name
	var/message = pick(
		"Help! [who] is attacking me in [where]!",
		"Security! [who] just attacked me in [where]!",
		"[who] is assaulting me, I'm in [where]! Help!",
	)
	controller.set_blackboard_key(BB_SP_LAST_INCIDENT, list(
		SP_INCIDENT_ATTACKER = QDELETED(attacker) ? null : WEAKREF(attacker),
		SP_INCIDENT_VICTIM = WEAKREF(pawn),
		SP_INCIDENT_TURF = get_turf(pawn),
		SP_INCIDENT_TIME = world.time,
	))
	sp_crew_speak(pawn, message, RADIO_CHANNEL_COMMON)
	log_sp("[pawn.real_name] reported an attack by [who] in [where] ([istype(pawn.ears, /obj/item/radio/headset) ? "radio" : "shouted"])")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Forgets the attacker once they are gone or enough time has passed. Always succeeds.
/datum/bt_node/ai_behavior/sp_expire_attacker
	/// How long after the last hit we stay in defense mode.
	var/remember_for = 20 SECONDS

/datum/bt_node/ai_behavior/sp_expire_attacker/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/attacker = controller.blackboard[BB_SP_ATTACKER]
	var/attacked_at = controller.blackboard[BB_SP_ATTACKED_AT] || 0
	if(QDELETED(attacker) || attacker.stat != STABLE || world.time - attacked_at > remember_for)
		controller.clear_blackboard_key(BB_SP_ATTACKER)
		controller.clear_blackboard_key(BB_SP_FLEE_TARGET)
	return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED

// --- Leaves: security -------------------------------------------------------------------------

/// Puts the first carried item of item_types into our active hand and stores it in target_key.
/datum/bt_node/ai_behavior/sp_equip_item
	/// Typepaths to look for, best first.
	var/list/item_types
	/// Blackboard key to write the equipped item into.
	var/target_key

/datum/bt_node/ai_behavior/sp_equip_item/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/pawn = controller.pawn
	if(!iscarbon(pawn) || !length(item_types))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/equipped = sp_equip_from_inventory(pawn, item_types)
	if(isnull(equipped))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(target_key)
		controller.set_blackboard_key(target_key, equipped)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Security weapon: baton if we have one. Fails if we carry none (we then fight unarmed).
/datum/bt_node/ai_behavior/sp_equip_item/baton
	item_types = list(/obj/item/melee/baton/security, /obj/item/melee/baton)
	target_key = BB_SP_WEAPON

/datum/bt_node/ai_behavior/sp_equip_item/handcuffs
	item_types = list(/obj/item/restraints/handcuffs)
	target_key = BB_SP_CUFFS

/// Melee-attacks the mob in target_key with whatever we hold (combat mode on). One swing per perform.
/datum/bt_node/ai_behavior/sp_attack_target
	/// Blackboard key holding the target.
	var/target_key = BB_SP_INCIDENT_TARGET

/datum/bt_node/ai_behavior/sp_attack_target/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/target = controller.blackboard[target_key]
	var/mob/living/pawn = controller.pawn
	if(QDELETED(target))
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	if(!target.Adjacent(pawn))
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	if(world.time < pawn.next_move)
		return AI_BEHAVIOR_INSTANT // still winding up
	pawn.face_atom(target)
	INVOKE_ASYNC(controller, TYPE_PROC_REF(/datum/ai_controller, ai_interact), target, TRUE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Clears the current incident (and our own attacker memory). Always succeeds.
/datum/bt_node/ai_behavior/sp_clear_incident

/datum/bt_node/ai_behavior/sp_clear_incident/perform(seconds_per_tick, datum/ai_controller/controller)
	controller.clear_blackboard_key(BB_SP_INCIDENT_TARGET)
	controller.clear_blackboard_key(BB_SP_INCIDENT_LOCATION)
	controller.clear_blackboard_key(BB_SP_ATTACKER)
	return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED

// --- Leaves: engineering ----------------------------------------------------------------------

/// Succeeds when the station needs an engineer at the engine (engine off or APCs draining).
/datum/bt_node/ai_behavior/sp_power_check
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_power_check/perform(seconds_per_tick, datum/ai_controller/controller)
	if(sp_station_power_needs_work())
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

/// Runs the scripted coolant-loop setup (see sp_engineering.dm) and reports the result over the engineering channel.
/datum/bt_node/ai_behavior/sp_run_engine_setup

/datum/bt_node/ai_behavior/sp_run_engine_setup/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/summary = sp_run_engine_setup(pawn)
	sp_crew_speak(pawn, summary, RADIO_CHANNEL_ENGINEERING)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Starts the emitters if the chamber is ready. Always succeeds (the engineer just reports otherwise).
/datum/bt_node/ai_behavior/sp_start_emitters

/datum/bt_node/ai_behavior/sp_start_emitters/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/summary = sp_start_emitters(pawn)
	if(summary)
		sp_crew_speak(pawn, summary, RADIO_CHANNEL_ENGINEERING)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Medical ----------------------------------------------------------------------------------

/**
 * Medical: puts a suitable medical stack into our hands for the patient in patient_key.
 * Searches our whole inventory (medkits included). Stores the item in target_key.
 */
/datum/bt_node/ai_behavior/sp_equip_medical_item
	/// Blackboard key holding the patient.
	var/patient_key = BB_SP_PATIENT
	/// Blackboard key to write the equipped item into.
	var/target_key = BB_SP_MEDICAL_ITEM
	/// Brute-treating stacks, best first.
	var/static/list/brute_types = list(/obj/item/stack/medical/suture, /obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/wrap/gauze)
	/// Burn-treating stacks, best first.
	var/static/list/burn_types = list(/obj/item/stack/medical/mesh, /obj/item/stack/medical/ointment, /obj/item/stack/medical/aloe)

/datum/bt_node/ai_behavior/sp_equip_medical_item/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/pawn = controller.pawn
	var/mob/living/patient = controller.blackboard[patient_key]
	if(!iscarbon(pawn) || QDELETED(patient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/list/wanted = list()
	if(patient.get_brute_loss() >= patient.get_fire_loss())
		wanted = brute_types + burn_types
	else
		wanted = burn_types + brute_types
	if(patient.get_brute_loss() <= 0)
		wanted -= brute_types
	if(patient.get_fire_loss() <= 0)
		wanted -= burn_types
	if(!length(wanted))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/obj/item/chosen = sp_equip_from_inventory(pawn, wanted)
	if(isnull(chosen))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(target_key, chosen)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Decorators -------------------------------------------------------------------------------

/// Passes when the mob in `key` is down: not conscious, incapacitated, or restrained.
/datum/bt_node/decorator/sp_target_incapacitated
	var/key = BB_SP_INCIDENT_TARGET

/datum/bt_node/decorator/sp_target_incapacitated/check_condition(datum/ai_controller/controller)
	var/mob/living/target = controller.blackboard[key]
	if(QDELETED(target) || !isliving(target))
		return FALSE
	if(target.stat != STABLE)
		return TRUE
	if(HAS_TRAIT(target, TRAIT_RESTRAINED))
		return TRUE
	return !!INCAPACITATED_IGNORING(target, NONE)

/// Passes when the mob in `key` is already restrained or dead (nothing left for security to do).
/datum/bt_node/decorator/sp_target_secured
	var/key = BB_SP_INCIDENT_TARGET

/datum/bt_node/decorator/sp_target_secured/check_condition(datum/ai_controller/controller)
	var/mob/living/target = controller.blackboard[key]
	if(QDELETED(target) || !isliving(target))
		return TRUE
	return target.stat == DEAD || HAS_TRAIT(target, TRAIT_RESTRAINED)

// --- Targeting --------------------------------------------------------------------------------

/// Living, not us, not dead, and carrying enough brute or burn damage for a medical stack to matter.
/datum/targeting_strategy/sp_treatable_patient
	/// Minimum brute or burn damage before we bother.
	var/minimum_damage = 10

/datum/targeting_strategy/sp_treatable_patient/is_valid_target(mob/living/living_mob, atom/target, vision_range, datum/ai_controller/controller = null)
	. = ..()
	if(!.)
		return FALSE
	if(target == living_mob || !isliving(target))
		return FALSE
	var/mob/living/patient = target
	if(patient.stat == DEAD)
		return FALSE
	return (patient.get_brute_loss() >= minimum_damage) || (patient.get_fire_loss() >= minimum_damage)

// --- Leaves: hull breach repair ----------------------------------------------------------------

/// Finds the nearest hull breach and a safe tile to patch it from. Fails when there is nothing to fix.
/datum/bt_node/ai_behavior/sp_find_breach
	time_between_perform = 3 SECONDS

/datum/bt_node/ai_behavior/sp_find_breach/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/pawn = controller.pawn
	// Some damage simply cannot be walked to: a room sealed behind blast doors, or a hole with no
	// standing room left. Give up on a breach we have been failing to reach and let another engineer
	// (or a player) deal with it, rather than looping on it forever.
	var/list/ignored = controller.blackboard[BB_SP_BREACH_IGNORE]
	var/turf/attempting = controller.blackboard[BB_SP_BREACH_ATTEMPT]
	var/attempt_started = controller.blackboard[BB_SP_BREACH_ATTEMPT_AT] || 0
	if(!isnull(attempting) && world.time - attempt_started > SP_BREACH_ATTEMPT_TIMEOUT)
		controller.set_blackboard_key_assoc(BB_SP_BREACH_IGNORE, attempting, world.time + SP_BREACH_IGNORE_TIME)
		controller.clear_blackboard_key(BB_SP_BREACH_ATTEMPT)
		log_sp("[pawn] giving up on the breach at [AREACOORD(attempting)] for now, cannot reach it")

	var/turf/breach = sp_find_nearest_breach(pawn, ignored)
	if(isnull(breach))
		controller.clear_blackboard_key(BB_SP_BREACH_TARGET)
		controller.clear_blackboard_key(BB_SP_BREACH_STANDPOINT)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/turf/standpoint = sp_breach_standpoint(breach, pawn)
	if(isnull(standpoint))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_BREACH_TARGET, breach)
	controller.set_blackboard_key(BB_SP_BREACH_STANDPOINT, standpoint)
	if(controller.blackboard[BB_SP_BREACH_ATTEMPT] != breach)
		controller.set_blackboard_key(BB_SP_BREACH_ATTEMPT, breach)
		controller.set_blackboard_key(BB_SP_BREACH_ATTEMPT_AT, world.time)
#ifdef SP_BREACH_DEBUG
	log_sp("[pawn.real_name] targeting breach at [AREACOORD(breach)], standpoint [AREACOORD(standpoint)], distance [get_dist(get_turf(pawn), standpoint)]")
#endif
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Announces the breach we are heading to over the engineering channel.
/datum/bt_node/ai_behavior/sp_announce_breach

/datum/bt_node/ai_behavior/sp_announce_breach/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/turf/breach = controller.blackboard[BB_SP_BREACH_TARGET]
	if(!istype(pawn) || isnull(breach))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/area/where = get_area(breach)
	sp_crew_speak(pawn, "Hull breach in [where ? where.name : "the station"], I'm on it.", RADIO_CHANNEL_ENGINEERING)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Puts on the EVA suit and helmet we carry, so vacuum work does not freeze us. Always succeeds.
/datum/bt_node/ai_behavior/sp_wear_eva

/datum/bt_node/ai_behavior/sp_wear_eva/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// bypass_equip_delay_self is essential: a do_after here would trip update_able_to_run(), which calls
	// fail_movement() and kills the walk to the breach.
	if(!istype(pawn.wear_suit, /obj/item/clothing/suit/space))
		var/list/suits = pawn.get_all_contents_type(/obj/item/clothing/suit/space)
		if(length(suits))
			pawn.equip_to_slot_if_possible(suits[1], ITEM_SLOT_OCLOTHING, disable_warning = TRUE, bypass_equip_delay_self = TRUE)
	if(!istype(pawn.head, /obj/item/clothing/head/helmet/space))
		var/list/helmets = pawn.get_all_contents_type(/obj/item/clothing/head/helmet/space)
		if(length(helmets))
			// The hardhat is in the way; stow it so the sealed helmet can go on.
			var/obj/item/old_head = pawn.head
			if(old_head && pawn.temporarilyRemoveItemFromInventory(old_head))
				pawn.equip_to_storage(old_head, ITEM_SLOT_BACK, indirect_action = TRUE)
			pawn.equip_to_slot_if_possible(helmets[1], ITEM_SLOT_HEAD, disable_warning = TRUE, bypass_equip_delay_self = TRUE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Puts on a breath mask and opens an emergency tank before working next to vacuum. Always succeeds.
/datum/bt_node/ai_behavior/sp_open_internals

/datum/bt_node/ai_behavior/sp_open_internals/perform(seconds_per_tick, datum/ai_controller/controller)
	sp_open_internals(controller.pawn)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Closes internals once the work is done. Always succeeds.
/datum/bt_node/ai_behavior/sp_close_internals

/datum/bt_node/ai_behavior/sp_close_internals/perform(seconds_per_tick, datum/ai_controller/controller)
	sp_close_internals(controller.pawn)
	return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED

/// Equips the RCD every engineer carries.
/datum/bt_node/ai_behavior/sp_equip_item/rcd
	item_types = list(/obj/item/construction/rcd)
	target_key = BB_SP_RCD

/// Lays plating over the breach we are standing next to.
/datum/bt_node/ai_behavior/sp_patch_breach

/datum/bt_node/ai_behavior/sp_patch_breach/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/turf/breach = controller.blackboard[BB_SP_BREACH_TARGET]
	if(!istype(pawn) || isnull(breach))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!isspaceturf(breach)) // somebody else got there first
		controller.clear_blackboard_key(BB_SP_BREACH_TARGET)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	if(!sp_patch_breach_cluster(pawn, breach))
		var/obj/item/construction/rcd/device = pawn.get_active_held_item()
		if(istype(device) && device.matter < 3)
			sp_crew_speak(pawn, "My RCD's out of matter, I need a refill.", RADIO_CHANNEL_ENGINEERING)
#ifdef SP_BREACH_DEBUG
		log_sp("[pawn.real_name] failed to patch [AREACOORD(breach)]: holding [device || "nothing"], adjacent [breach.Adjacent(pawn) ? "yes" : "no"], matter [istype(device) ? device.matter : "n/a"]")
#endif
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.clear_blackboard_key(BB_SP_BREACH_TARGET)
	controller.clear_blackboard_key(BB_SP_BREACH_STANDPOINT)
	controller.clear_blackboard_key(BB_SP_BREACH_ATTEMPT)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

#ifdef SP_BREACH_DEBUG
/// Debug only: reports where we are relative to the breach we are walking to.
/datum/bt_node/ai_behavior/sp_breach_progress
	time_between_perform = 10 SECONDS

/datum/bt_node/ai_behavior/sp_breach_progress/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/pawn = controller.pawn
	var/turf/standpoint = controller.blackboard[BB_SP_BREACH_STANDPOINT]
	var/turf/here = get_turf(pawn)
	if(!isnull(standpoint) && !isnull(here))
		log_sp("[pawn] en route: at [AREACOORD(here)], [get_dist(here, standpoint)] from standpoint")
	return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED
#endif

#ifdef SP_BREACH_DEBUG
/// Debug only: a move_to_target that reports why it gave up.
/datum/bt_node/ai_behavior/move_to_target/sp_logged

/datum/bt_node/ai_behavior/move_to_target/sp_logged/setup(datum/ai_controller/controller)
	. = ..()
	var/atom/target = controller.blackboard[target_key]
	log_sp("[controller.pawn] move setup -> [target ? AREACOORD(target) : "null"], ok=[. ? "yes" : "no"], movement=[controller.ai_movement.type]")

/datum/bt_node/ai_behavior/move_to_target/sp_logged/perform(seconds_per_tick, datum/ai_controller/controller)
	. = ..()
	if(. & AI_BEHAVIOR_FAILED)
		log_sp("[controller.pawn] move FAILED (movement_failed=[movement_failed], attempts=[controller.consecutive_pathing_attempts])")
	else if(. & AI_BEHAVIOR_SUCCEEDED)
		log_sp("[controller.pawn] move SUCCEEDED, arrived")
#endif
