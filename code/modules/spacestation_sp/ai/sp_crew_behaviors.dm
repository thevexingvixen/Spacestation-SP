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

/**
 * Plastic flaps tell the pathfinder that anyone may walk through them, then stop anyone standing up. The Head
 * of Personnel, whose access opens the bridge's delivery windoor, was routed into the maintenance flaps in
 * front of it on the way to medbay and stood there until the walk gave up — and again every few minutes, for
 * the rest of the round. What CanAllowThrough is going to refuse, the pathfinder should not plan through.
 */
/obj/structure/plasticflaps/CanAStarPass(to_dir, datum/can_pass_info/pass_info)
	if(require_resting && pass_info.is_living && !pass_info.is_bot && pass_info.mob_size != MOB_SIZE_TINY && !(pass_info.pass_flags & PASSFLAPS))
		return FALSE
	return ..()

/**
 * A move_to_target that says so in the log when a walk fails. Inside a cooldown a failed walk is otherwise
 * silent, and looks like somebody who set off and changed their mind: it took a whole round's log to spot a
 * doctor who could never reach the theatre trays and a Head of Personnel stuck at a set of flaps.
 */
/datum/bt_node/ai_behavior/move_to_target/sp_reported

/datum/bt_node/ai_behavior/move_to_target/sp_reported/perform(seconds_per_tick, datum/ai_controller/controller)
	. = ..()
	if(!(. & AI_BEHAVIOR_FAILED))
		return
	var/atom/target = controller.blackboard[target_key]
	var/mob/living/pawn = controller.pawn
	log_sp("[pawn.real_name] could not walk to [QDELETED(target) ? "a target that is gone" : "[target] at [AREACOORD(target)]"] from [AREACOORD(pawn)]")

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

/**
 * Whether somebody armed is a worry. Not security or command, who are allowed; and not a monkey with a knife
 * until it starts swinging it. Pun Pun arms themselves with whatever turns up behind the bar, and crew in the
 * bar spent whole minutes shouting for security about a monkey that was minding its own business.
 */
/proc/sp_armed_threat(mob/living/carbon/human/candidate)
	if(candidate.stat != STABLE || !sp_is_armed(candidate) || sp_is_authority(candidate))
		return FALSE
	if(ismonkey(candidate))
		return candidate.combat_mode || candidate.ai_controller?.blackboard[BB_MONKEY_AGGRESSIVE]
	return TRUE

/// Security and command are allowed to carry weapons without scaring the crew.
/proc/sp_is_authority(mob/living/carbon/human/who)
	var/datum/job/role = who.mind?.assigned_role
	if(isnull(role))
		return FALSE
	if(role.job_flags & JOB_HEAD_OF_STAFF)
		return TRUE
	return (/datum/job_department/security in role.departments_list) || (/datum/job_department/command in role.departments_list)

/**
 * Whether a line from a player is a call for help.
 *
 * Read in whole words (sp_words()). Violence counts by word start, because "attacking" and "stabbed" are how
 * people shout it, with a few false friends ruled out by name. "Help" and "security" count only when the line
 * sounds urgent -- an exclamation mark, capitals, the word leading the line, or nothing but pleading -- and
 * never in a calm request: "can you help" used to send every officer in earshot running. Only players reach
 * this; AI crew report through the structured incident.
 */
/proc/sp_message_is_distress(message)
	var/list/words = sp_words(message)
	if(!length(words))
		return FALSE
	var/static/list/violence = list("attack", "murder", "kill", "shoot", "stab", "assault")
	var/static/list/false_friends = list("stable", "stability", "stabilise", "stabilize", "killjoy")
	for(var/word in words)
		if(word in false_friends)
			continue
		for(var/root in violence)
			if(findtext(word, root) == 1)
				return TRUE
	if(!("help" in words) && !("security" in words))
		return FALSE
	if(findtext(message, "!") || sp_is_shouting(message))
		return TRUE
	if(findtext(message, "?"))
		return FALSE
	for(var/request in list("can you", "could you", "would you", "will you"))
		if(sp_said(words, request))
			return FALSE
	if(words[1] == "help" || words[1] == "security")
		return TRUE
	var/static/list/pleading = list("help", "security", "me", "us", "please", "pls", "plz", "now", "someone", "somebody", "anyone")
	var/only_pleading = TRUE
	for(var/word in words)
		if(!(word in pleading))
			only_pleading = FALSE
			break
	if(only_pleading)
		return TRUE
	for(var/plea in list("help me", "help us", "someone help", "somebody help", "need help", "call security", "get security", "need security"))
		if(sp_said(words, plea))
			return TRUE
	return FALSE

/// Whether a line is written in capitals, the way people shout.
/proc/sp_is_shouting(message)
	var/plain = message
	for(var/entity in list("&#39;", "&quot;", "&amp;", "&lt;", "&gt;"))
		plain = replacetext(plain, entity, "")
	return plain != LOWER_TEXT(plain) && plain == uppertext(plain)

/// Puts whatever is in our hands away, so the next step starts from a clean grip.
/proc/sp_free_hands(mob/living/carbon/human/crew)
	for(var/obj/item/held in crew.held_items)
		if(isnull(held))
			continue
		if(crew.back && crew.transferItemToLoc(held, crew.back, silent = TRUE))
			continue
		crew.dropItemToGround(held)

/**
 * An open tile to stand on with this in arm's reach, the nearest to `near`, or null if there is none; the
 * thing's own tile counts when nothing there is in the way, as under a light switch. Walk there rather than
 * to "within a tile" of the thing: the pathfinder will not end a walk on a diagonal whose two corners are
 * both blocked, though an arm reaches across a table there. The theatre's surgery trays sit in corners with
 * a table on one side and the operating table on the other, and the doctor sent to them never set off.
 */
/proc/sp_reach_spot(atom/thing, atom/near)
	var/turf/target_turf = get_turf(thing)
	if(isnull(target_turf))
		return null
	var/turf/best
	for(var/turf/open/spot in range(1, target_turf))
		if(spot.is_blocked_turf(exclude_mobs = TRUE) || !spot.Adjacent(thing))
			continue
		if(isnull(best) || get_dist(near, spot) < get_dist(near, best))
			best = spot
	return best

/**
 * One click, waiting out the click delays first.
 *
 * ClickOn() drops anything that arrives within a decisecond of the last click, which is invisible when
 * a behaviour clicks once but silently eats every second click of a sequence — open the oven, put the
 * tray in, shut the door becomes open the oven and nothing else. It also drops any click made during the
 * attack cooldown (next_move) that a patch or a hit leaves behind. Only safe from an async behaviour,
 * because it sleeps.
 */
/proc/sp_ai_click(datum/ai_controller/controller, atom/target, list/modifiers)
	var/mob/living/pawn = controller.pawn
	if(QDELETED(pawn) || QDELETED(target))
		return FALSE
	var/wait = max(pawn.next_click + 1, pawn.next_move) - world.time
	if(wait > 0)
		sleep(wait)
	if(QDELETED(pawn) || QDELETED(target))
		return FALSE
	return controller.ai_interact(target, combat_mode = FALSE, modifiers = modifiers)

/**
 * One drag-and-drop, the way a player drags a patient onto a cryo tube or an operating table.
 *
 * TG only ever takes a drop from a client, through MouseDrop(), and AI crew have no client. This runs the
 * same handler with the same checks — both ends in reach, can_perform_action — with the pawn standing in
 * as usr. Returns FALSE only when something vanished; whether the drop did anything is for the caller to
 * look at. Only safe from an async behaviour, because it waits out the click delay first.
 */
/proc/sp_ai_drag_onto(datum/ai_controller/controller, atom/movable/dragged, atom/over)
	var/mob/living/pawn = controller.pawn
	if(QDELETED(pawn) || QDELETED(dragged) || QDELETED(over))
		return FALSE
	if(world.time <= pawn.next_click)
		sleep(pawn.next_click - world.time + 1)
	if(QDELETED(pawn) || QDELETED(dragged) || QDELETED(over))
		return FALSE
	usr = pawn
	dragged.base_mouse_drop_handler(over, dragged.loc, over.loc, "")
	return TRUE

/**
 * Buys one of something out of a vending machine, paid for from the buyer's own wages.
 *
 * Service departments are short of their own glassware — TG hands a chef no bowls and a bartender no
 * glasses — and the vendor that stocks them charges. Returns the item, or null if it is sold out, the
 * machine is dead, or they cannot afford it.
 */
/proc/sp_vend_product(mob/living/carbon/human/buyer, obj/machinery/vending/vendor, product_path)
	if(QDELETED(vendor) || QDELETED(buyer) || !vendor.is_operational)
		return null
	var/datum/data/vending_product/chosen
	for(var/datum/data/vending_product/record as anything in vendor.product_records)
		if(record.product_path == product_path && record.amount > 0)
			chosen = record
			break
	if(isnull(chosen))
		return null
	var/price = vendor.all_products_free ? 0 : (chosen.price || vendor.default_price)
	if(price > 0)
		var/obj/item/card/id/id_card = buyer.get_idcard(hand_first = FALSE)
		var/datum/bank_account/account = id_card?.registered_account
		// Staff buy from their own department's machines at a discount, the same as they would at the screen.
		if(!isnull(account?.account_job) && account.account_job.paycheck_department == vendor.payment_department)
			price = max(round(price * DEPARTMENT_DISCOUNT), 1)
		if(isnull(account) || !account.adjust_money(-price, "Vending: [chosen.name]"))
			return null
	var/obj/item/bought = vendor.dispense(chosen, get_turf(buyer))
	if(isnull(bought))
		return null
	log_sp("[buyer.real_name] bought [bought.name] from [vendor.name] for [price] credits")
	return bought

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
	/// Try the areas in random order. FALSE tries them in the order listed, first choice first.
	var/shuffle_areas = TRUE

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

	// Try a few areas, in random order unless the list is a ranking; some will not exist on this z-level.
	if(shuffle_areas)
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

/**
 * Where a patient goes to be seen. The lobby, if the map has one: the rest of medbay is behind doors only
 * medical staff can open, and JPS will not path anyone through a door they have no access for, so a patient
 * who picked a spot on the treatment floor never got there — they gave up and went home.
 */
/datum/bt_node/ai_behavior/sp_pick_wander_turf/medbay
	target_key = BB_SP_MEDBAY_TARGET
	areas_key = null
	shuffle_areas = FALSE
	fixed_areas = list(
		/area/station/medical/medbay/lobby,
		/area/station/medical/treatment_center,
		/area/station/medical/medbay/central,
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

/// A look up at whoever said our name, unless they have gone or it is too late for one (SP_REPLY_STALE).
/datum/bt_node/ai_behavior/sp_say/greet/perform(seconds_per_tick, datum/ai_controller/controller)
	var/atom/named_by = controller.blackboard[BB_SP_ATTENTION_TARGET]
	var/asked_at = controller.blackboard[BB_SP_CHAT_ASKED_AT]
	controller.clear_blackboard_key(BB_SP_CHAT_ASKED_AT)
	if(QDELETED(named_by) || (!isnull(asked_at) && world.time - asked_at > SP_REPLY_STALE))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return ..()

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
		if(!sp_armed_threat(candidate))
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
	controller.override_blackboard_key(BB_SP_LAST_INCIDENT, list(
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
	// A security baton comes out of the belt switched off, and an inactive baton is only a club: try_stun()
	// returns FALSE and the hit falls through to plain brute damage, so an arrest was a beating that went on
	// until the suspect reached crit. attack_self() toggles, so turn it on directly, and only when it is off.
	var/obj/item/melee/baton/security/stick = equipped
	if(istype(stick) && !stick.active && stick.cell?.charge >= stick.cell_hit_cost)
		stick.turn_on(pawn)
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

/// Have a word with somebody a crime was reported against. Ranks below the response to actual violence.
/datum/bt_node/subtree/sp_security_confront
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_security_confront.bt.json"

/// What an officer says walking up to somebody, by what they are said to have done.
GLOBAL_LIST_INIT(sp_confrontation_lines, list(
	SP_CRIME_THEFT = list("That is not yours. Hand it over.", "I hear you have been helping yourself.", "Pockets out."),
	SP_CRIME_VANDALISM = list("You break it, the station pays for it. Pack it in.", "Enough of that.", "Was that you?"),
	SP_CRIME_TRESPASS = list("You are not supposed to be in here.", "Out. Now.", "Wrong side of that door, is it not?"),
))

/**
 * A word with somebody a crime was reported against, rather than a baton.
 *
 * Security's existing response is for people who hit people, and putting a petty thief through the same
 * routine would have an officer beating an assistant senseless over a light tube. So a suspect gets spoken to,
 * thought less of, and written up; the record is the memory. Only once it shows a pattern
 * (SP_CRIMES_BEFORE_ARREST) does the officer call an arrest and hand them to the baton path, and anybody who
 * swings back becomes an attacker on their own (the security controller's on_attacked), which is escalation
 * enough without a special case here.
 */
/datum/bt_node/ai_behavior/sp_confront_suspect

/datum/bt_node/ai_behavior/sp_confront_suspect/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/suspect = controller.blackboard[BB_SP_SUSPECT]
	var/crime = controller.blackboard[BB_SP_SUSPECT_CRIME]
	controller.clear_blackboard_key(BB_SP_SUSPECT)
	controller.clear_blackboard_key(BB_SP_SUSPECT_CRIME)
	if(!istype(pawn) || QDELETED(suspect) || !suspect.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(suspect)
	var/area/scene = get_area(suspect)
	var/priors = sp_file_crime_record(suspect, crime, "Reported in [scene ? scene.name : "the station"].", pawn)
	sp_adjust_reputation(controller, suspect, SP_WITNESS_REPUTATION_HIT, "had to have a word with them")
	sp_record("sec.confronted")
	controller.clear_blackboard_key(BB_SP_SUSPECT_SINCE)
	log_sp("[pawn.real_name] had a word with [suspect.real_name] about [crime || "it"] in [scene ? scene.name : "the station"]")
	// A pattern on the record, rather than one bad afternoon: now it is an arrest.
	// sp_mark_for_arrest() returns FALSE for anybody already wanted, and nothing ever clears WANTED_ARREST, so a
	// repeat offender could never be arrested a second time. The pattern on the record decides, not the flag.
	if(priors > SP_CRIMES_BEFORE_ARREST)
		sp_mark_for_arrest(suspect)
		sp_crew_speak(pawn, "[suspect.real_name], that is once too many. You are coming with me.", RADIO_CHANNEL_SECURITY)
		controller.set_blackboard_key(BB_SP_INCIDENT_TARGET, suspect)
		// Petty crime is never met with lethal force, whatever standing orders say; sp_set_fire_mode reads this.
		controller.set_blackboard_key(BB_SP_ARREST_NONLETHAL, suspect)
		controller.set_blackboard_key(BB_SP_INCIDENT_LOCATION, get_turf(suspect))
		log_sp("[pawn.real_name] called an arrest on [suspect.real_name] ([priors] crimes on record)")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	var/list/lines = GLOB.sp_confrontation_lines[crime]
	sp_crew_speak(pawn, length(lines) ? pick(lines) : "I will be keeping an eye on you.")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * The suspect is somewhere we cannot walk to: say so on the radio, and hold on to the incident.
 *
 * Officers carry brig and maintenance access, not atmospherics or engineering, so a suspect who wanders into
 * one is genuinely out of reach and the pathfinder is right to refuse. Giving up on them would be wrong --
 * they have to come out -- and silently retrying is what made an arrest that never happened look like an
 * arrest that was never called. This is a note in passing rather than something an officer stands and
 * does: it always fails, so the shift carries on and the incident stays open.
 */
/datum/bt_node/ai_behavior/sp_lost_them
	time_between_perform = 10 SECONDS

/datum/bt_node/ai_behavior/sp_lost_them/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/target = controller.blackboard[BB_SP_INCIDENT_TARGET]
	if(!istype(pawn) || QDELETED(target))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/said_at = controller.blackboard[BB_SP_LOST_THEM_AT] || 0
	if(world.time - said_at < SP_LOST_THEM_GAP)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED // already called in; get on with the patrol
	controller.set_blackboard_key(BB_SP_LOST_THEM_AT, world.time)
	sp_crew_speak(pawn, "[target.real_name] is in [get_area_name(target)] and I cannot get in. Keep an eye out.", RADIO_CHANNEL_SECURITY)
	sp_record("sec.lost_them")
	log_sp("[pawn.real_name] cannot reach [target.real_name] in [get_area_name(target)] and called it in")
	// Always fails, so the incident stays open and the officer gets on with the shift rather than standing
	// at a door they cannot open. When the suspect comes back out, the ordinary approach picks them up.
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

/**
 * A suspect who cannot be reached at all: call it in, and after a while let it go.
 *
 * Security carry brig and maintenance access, so a suspect sitting in the Head of Personnel's office or in
 * atmospherics is genuinely out of reach, and the pathfinder is right to refuse. An officer who keeps trying
 * is an officer who never does anything else for the rest of the shift, so after SP_SUSPECT_PATIENCE the word
 * is called in over the radio and the suspect is dropped. The record keeps the crimes either way.
 */
/datum/bt_node/ai_behavior/sp_give_up_suspect
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_give_up_suspect/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/suspect = controller.blackboard[BB_SP_SUSPECT]
	if(!istype(pawn) || QDELETED(suspect))
		controller.clear_blackboard_key(BB_SP_SUSPECT_SINCE)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/failing_since = controller.blackboard[BB_SP_SUSPECT_SINCE]
	if(isnull(failing_since))
		controller.set_blackboard_key(BB_SP_SUSPECT_SINCE, world.time)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(world.time - failing_since < SP_SUSPECT_PATIENCE)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_crew_speak(pawn, "[suspect.real_name] is in [get_area_name(suspect)] and I cannot get to them. Somebody with the access, please.", RADIO_CHANNEL_SECURITY)
	log_sp("[pawn.real_name] gave up on reaching [suspect.real_name] in [get_area_name(suspect)]")
	sp_record("sec.lost_them")
	controller.clear_blackboard_key(BB_SP_SUSPECT)
	controller.clear_blackboard_key(BB_SP_SUSPECT_CRIME)
	controller.clear_blackboard_key(BB_SP_SUSPECT_SINCE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Clears the current incident (and our own attacker memory). Always succeeds.
/datum/bt_node/ai_behavior/sp_clear_incident

/datum/bt_node/ai_behavior/sp_clear_incident/perform(seconds_per_tick, datum/ai_controller/controller)
	// An escort that reached here is over too, and the prisoner is let go of rather than dragged about.
	sp_abandon_escort(controller)
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
	// An escort already under way holds this branch whatever the incident key now says. A report arriving
	// mid-walk used to swap the target out from under the officer, who then simply dragged the prisoner along.
	var/mob/living/prisoner = controller.blackboard[BB_SP_PRISONER]
	if(!QDELETED(prisoner) && prisoner.stat != DEAD && HAS_TRAIT(prisoner, TRAIT_RESTRAINED))
		return TRUE
	var/mob/living/target = controller.blackboard[key]
	if(QDELETED(target) || !isliving(target))
		return TRUE
	return target.stat == DEAD || HAS_TRAIT(target, TRAIT_RESTRAINED)

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

/// Security sidearm: an energy gun if one has been drawn, else the disabler every officer starts the shift with.
/datum/bt_node/ai_behavior/sp_equip_item/sidearm
	item_types = list(/obj/item/gun/energy/e_gun, /obj/item/gun/energy/disabler)
	target_key = BB_SP_WEAPON

/**
 * Shoots the mob in target_key with whatever is in hand.
 *
 * ai_interact() has no adjacency check of its own -- it sets combat mode, calls ClickOn() and puts the mode
 * back -- so a gun clicked at something across the room fires at it. The Adjacent() test in sp_attack_target
 * is that leaf's own choice rather than a limit of the interaction layer, which is why this is a sibling and
 * not a rewrite. Combat mode stays off on purpose: clicking with it on while stood next to somebody
 * pistol-whips them instead of firing.
 */
/datum/bt_node/ai_behavior/sp_shoot_target
	/// Blackboard key holding the target.
	var/target_key = BB_SP_INCIDENT_TARGET
	/// Furthest we will take a shot from.
	var/max_range = 7

/datum/bt_node/ai_behavior/sp_shoot_target/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/target = controller.blackboard[target_key]
	var/mob/living/pawn = controller.pawn
	if(QDELETED(target) || QDELETED(pawn))
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	var/obj/item/gun/held = pawn.get_active_held_item()
	// An empty gun is not a gun. A disabler carries twenty shots (e_cost = LASER_SHOTS(20, ...)), and an
	// officer who spent them went on holding the trigger: the shot silently did nothing, this leaf kept
	// succeeding, and the selector never fell through to anything else. Failing here hands the problem on.
	if(!istype(held) || !held.can_shoot())
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	if(get_dist(pawn, target) > max_range || !can_see(pawn, target, max_range))
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	// Never fire through somebody else. TG's basic ranged attack guards this and I left it out as apparatus
	// I did not need; a briefing then put the whole department on one spot and an officer shot the head of
	// security in the back on the way to a monkey. Anyone who is not the target counts, which is stricter
	// than TG's targeting-strategy version and right for security, who should not be hitting bystanders.
	for(var/turf/along as anything in get_line(pawn, target))
		for(var/mob/living/bystander in along)
			if(bystander != target && bystander != pawn)
				return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	if(world.time < pawn.next_move)
		return AI_BEHAVIOR_INSTANT // still winding up
	pawn.face_atom(target)
	INVOKE_ASYNC(controller, TYPE_PROC_REF(/datum/ai_controller, ai_interact), target, FALSE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// A casing that stuns is not a lethal one. ammo_type holds instances once update_ammo_types() has run, but
/// the gun's own Destroy() says it is "sometimes paths, sometimes atom", so both are handled.
/proc/sp_casing_is_lethal(casing)
	var/static/list/stunning = list(/obj/item/ammo_casing/energy/disabler, /obj/item/ammo_casing/energy/electrode)
	for(var/stun_path in stunning)
		if(ispath(casing) ? ispath(casing, stun_path) : istype(casing, stun_path))
			return FALSE
	return TRUE

/**
 * Setting a held energy gun to match standing orders before firing it.
 *
 * select_fire() cycles rather than sets -- select++, wrapping at ammo_type.len -- so reaching a particular
 * mode means cycling until it comes round, bounded by the number of modes. A disabler has one casing and no
 * lethal setting at all, so this does nothing whatsoever to the weapon an officer starts the shift with:
 * going lethal really does mean drawing an energy gun from the armoury first.
 *
 * Succeeds even when there is nothing to set, because the shot that follows is no worse for it.
 */
/datum/bt_node/ai_behavior/sp_set_fire_mode/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!ishuman(pawn))
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	var/obj/item/gun/energy/gun = pawn.get_active_held_item()
	if(!istype(gun) || length(gun.ammo_type) < 2)
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED
	// Lethal only under standing orders, and never against somebody being arrested for petty crime: a third
	// smashed light tube was being answered with lethal fire at red alert.
	var/mob/living/petty = controller.blackboard[BB_SP_ARREST_NONLETHAL]
	var/wanted = !isnull(controller.blackboard[BB_SP_USE_LETHALS]) && (isnull(petty) || petty != controller.blackboard[BB_SP_INCIDENT_TARGET])
	if(sp_casing_is_lethal(gun.ammo_type[gun.select]) == wanted)
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED
	for(var/i in 1 to length(gun.ammo_type))
		gun.select_fire(pawn)
		if(sp_casing_is_lethal(gun.ammo_type[gun.select]) == wanted)
			break
	// Only said once per actual change: this leaf runs every time the sequence does.
	sp_record(wanted ? "sec.went_lethal" : "sec.went_stun")
	log_sp("[pawn.real_name] set [gun.name] to [wanted ? "lethal" : "stun"]")
	return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED

/// Lets go of the prisoner and forgets the escort. Every way an escort can fail comes through here.
/proc/sp_abandon_escort(datum/ai_controller/controller)
	var/mob/living/pawn = controller?.pawn
	var/mob/living/prisoner = controller?.blackboard[BB_SP_PRISONER]
	if(!QDELETED(pawn) && !QDELETED(prisoner) && pawn.pulling == prisoner)
		pawn.stop_pulling()
	sp_clear_escort_keys(controller)

/proc/sp_clear_escort_keys(datum/ai_controller/controller)
	controller?.clear_blackboard_key(BB_SP_PRISONER)
	controller?.clear_blackboard_key(BB_SP_CELL)
	controller?.clear_blackboard_key(BB_SP_CELL_SPOT)
	controller?.clear_blackboard_key(BB_SP_CELL_OUTSIDE)

/**
 * Picking a cell for somebody just cuffed, and taking hold of them for the walk.
 *
 * The prisoner is held in BB_SP_PRISONER from here on, not read from INCIDENT_TARGET, which any fresh report
 * overwrites. A corpse is not a prisoner, and a pull begun from across a room breaks on the first step, so
 * both are refused -- and an escort resumed after its prisoner slipped away is let go of properly.
 */
/datum/bt_node/ai_behavior/sp_find_cell/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/prisoner = controller.blackboard[BB_SP_PRISONER] || controller.blackboard[BB_SP_INCIDENT_TARGET]
	if(!ishuman(pawn) || QDELETED(prisoner) || prisoner.stat == DEAD || !prisoner.Adjacent(pawn) || sp_sentence_time(prisoner) <= 0)
		sp_abandon_escort(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/machinery/status_display/door_timer/cell = sp_free_cell(pawn)
	var/list/doorway = sp_cell_doorway(cell)
	if(!length(doorway) || (pawn.pulling != prisoner && !pawn.start_pulling(prisoner, supress_message = TRUE)))
		sp_abandon_escort(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_hold_still(prisoner, pawn, SP_ESCORT_TIME)
	controller.set_blackboard_key(BB_SP_PRISONER, prisoner)
	controller.set_blackboard_key(BB_SP_CELL, cell)
	controller.set_blackboard_key(BB_SP_CELL_SPOT, doorway[1])
	controller.set_blackboard_key(BB_SP_CELL_OUTSIDE, doorway[2])
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * The one move that puts a pulled prisoner in a cell and leaves the officer outside it.
 *
 * Standing, the prisoner is dense, and stepping into them swaps the pair: TG lets a puller swap places with
 * whoever they are pulling (can_mobswap_with), while refusing to let anyone shove a restrained person past the
 * one pulling them -- which is the move the first version of this tried, and why it never jailed anybody.
 * Lying down, they are not dense at all (TRAIT_UNDENSE), so there is nothing to swap with and the officer
 * simply walks onto their tile; dragging them the last step (Move_Pulled) finishes it. Returns TRUE once the
 * prisoner is in and the officer is out.
 */
/proc/sp_swap_into_cell(mob/living/pawn, mob/living/prisoner, turf/inside, turf/outside)
	if(QDELETED(pawn) || QDELETED(prisoner) || !isturf(inside) || !isturf(outside))
		return FALSE
	if(get_turf(pawn) == inside && get_turf(prisoner) == outside)
		step(pawn, get_dir(inside, outside))
	if(get_turf(pawn) == outside && get_turf(prisoner) == outside)
		pawn.Move_Pulled(inside)
	return get_turf(pawn) == outside && get_turf(prisoner) == inside

/**
 * Opens a cell's doors for the handover and stops them shutting themselves again.
 *
 * A windoor bumped open closes five seconds later on its own, which is long enough to shut in the middle of
 * the swap and leave the officer holding a prisoner in a doorway. timer_start() closes them for good once the
 * sentence starts. Returns TRUE while anything is still shut, so the caller waits rather than walking into it.
 */
/proc/sp_open_cell_doors(obj/machinery/status_display/door_timer/cell, mob/living/pawn)
	var/waiting = FALSE
	for(var/datum/weakref/door_ref as anything in cell?.doors)
		var/obj/machinery/door/window/brigdoor/door = door_ref.resolve()
		if(!istype(door))
			continue
		door.autoclose = FALSE
		if(!door.density)
			continue
		waiting = TRUE
		if(!door.operating && door.allowed(pawn))
			INVOKE_ASYNC(door, TYPE_PROC_REF(/obj/machinery/door/window, open))
	return waiting

/**
 * Putting a cuffed prisoner in the cell and starting the clock, with the officer ending up outside.
 *
 * The officer arrives standing just inside the door, which leaves the prisoner they are pulling just outside
 * it, and the handover is one move back out (sp_swap_into_cell()). Ending up outside is not cosmetic:
 * timer_start() shuts the linked doors itself, so an officer still inside would serve the sentence alongside
 * them. A prisoner who breaks the pull on the way is not dragged back; they are simply still at large.
 */
/datum/bt_node/ai_behavior/sp_jail_target
	/// Held across the async half: the tile just inside the cell door.
	VAR_PRIVATE/turf/reach

/datum/bt_node/ai_behavior/sp_jail_target/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	reach = controller.blackboard[BB_SP_CELL_SPOT]
	if(!istype(pawn) || isnull(reach) || get_turf(pawn) != reach)
		sp_abandon_escort(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_jail_target/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/turf/inside = reach
	var/turf/outside = controller.blackboard[BB_SP_CELL_OUTSIDE]
	var/mob/living/prisoner = controller.blackboard[BB_SP_PRISONER]
	var/obj/machinery/status_display/door_timer/cell = controller.blackboard[BB_SP_CELL]
	var/jailed = FALSE
	// A few goes, one action each: the door may still be swinging open, and a prisoner lying down takes a move
	// more than a standing one. Nothing here loops on a prisoner who is no longer in hand.
	for(var/attempt in 1 to 5)
		if(!isturf(inside) || !isturf(outside) || QDELETED(prisoner) || QDELETED(cell) || pawn.pulling != prisoner)
			break
		if(get_turf(pawn) == outside && get_turf(prisoner) == inside)
			jailed = TRUE
			break
		if(get_turf(prisoner) != outside || (get_turf(pawn) != inside && get_turf(pawn) != outside))
			break
		if(sp_open_cell_doors(cell, pawn))
			sleep(1.2 SECONDS) // a windoor drops its density only at the end of the opening animation
		else
			sp_swap_into_cell(pawn, prisoner, inside, outside)
			sleep(0.2 SECONDS)
		if(!async_still_valid())
			return
	if(!jailed)
		sp_abandon_escort(controller)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	pawn.stop_pulling()
	var/sentence = sp_sentence_time(prisoner)
	cell.set_timer(sentence)
	cell.timer_start()
	var/datum/record/crew/record = find_record(prisoner.real_name)
	if(record)
		record.wanted_status = WANTED_PRISONER
		update_matching_security_huds(prisoner.real_name)
	// Only let the incident go if it is still about this prisoner: a report that arrived mid-escort stands.
	if(controller.blackboard[BB_SP_INCIDENT_TARGET] == prisoner)
		controller.clear_blackboard_key(BB_SP_INCIDENT_TARGET)
		controller.clear_blackboard_key(BB_SP_INCIDENT_LOCATION)
	sp_clear_escort_keys(controller)
	sp_record("sec.jailed")
	log_sp("[pawn.real_name] put [prisoner.real_name] in [cell.name] for [round(sentence / 600)] minutes")
	sp_crew_speak(pawn, "[prisoner.real_name] is in a cell. [round(sentence / 600)] minutes.", RADIO_CHANNEL_SECURITY)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)
