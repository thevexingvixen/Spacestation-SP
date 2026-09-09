/**
 * Base AI controller for Spacestation SP crew members (real /mob/living/carbon/human pawns).
 *
 * Ambient crew: stay alive, escape restraints, react to attackers (report + flee), go to medbay
 * when hurt, keep away from armed people, answer people who address us by name, wander our
 * department, and chatter. Job subtypes add work behaviour (medical, security, engineering).
 */
/datum/ai_controller/sp_crew
	ai_movement = /datum/ai_movement/jps/sp_crew
	movement_delay = 0.4 SECONDS
	// Keep planning even when no player is nearby: a singleplayer station should feel alive everywhere.
	ai_traits = DEFAULT_AI_FLAGS | RUN_WHILE_UNWATCHED
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew.bt.json"
	blackboard = list(
		BB_SP_HURT_THRESHOLD = 60,
		BB_SP_THREAT_MIN_DISTANCE = 4,
		BB_SP_THREAT_MAX_DISTANCE = 7,
		BB_BASIC_MOB_SPEAK_LINES = list(
			BB_SPEAK_CHANCE = 2,
			BB_EMOTE_SAY = list(
				"Another day, another shift.",
				"Has anyone seen the clown?",
				"I could use a coffee.",
				"Is the shuttle ever going to be on time?",
				"Did you hear that noise from maintenance?",
				"Nanotrasen doesn't pay me enough for this.",
			),
			BB_EMOTE_SEE = list(
				"yawns.",
				"stretches.",
				"looks around.",
			),
		),
	)

/datum/ai_controller/sp_crew/TryPossessPawn(atom/new_pawn)
	if(!ishuman(new_pawn))
		return AI_CONTROLLER_INCOMPATIBLE
	var/mob/living/carbon/human/human_pawn = new_pawn
	if(!HAS_TRAIT(human_pawn, TRAIT_RELAYING_ATTACKER))
		human_pawn.AddElement(/datum/element/relay_attackers)
	RegisterSignal(human_pawn, COMSIG_ATOM_WAS_ATTACKED, PROC_REF(on_attacked))
	RegisterSignal(human_pawn, COMSIG_MOVABLE_PRE_HEAR, PROC_REF(on_pre_hear))
	RegisterSignal(human_pawn, COMSIG_MOVABLE_BUMP, PROC_REF(on_bump))
	// Until a proper needs subtree exists, AI crew do not starve. Documented limitation.
	ADD_TRAIT(human_pawn, TRAIT_NOHUNGER, SP_CREW_TRAIT)
	// A list value has to go in with override_blackboard_key: set_blackboard_key refuses to write over
	// one, and the CRASH left every crew member with no tastes at all, so nothing was ever worth taking.
	override_blackboard_key(BB_SP_INTERESTS, sp_roll_interests())
	setup_job_blackboard(human_pawn)
	return ..()

/// Hook for subtypes to seed job-specific blackboard keys (wander areas, lines, ...).
/datum/ai_controller/sp_crew/proc/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	return

/// Called by the spawner once the crew member is equipped, for job gear TG does not hand out.
/datum/ai_controller/sp_crew/proc/equip_extra_gear(mob/living/carbon/human/human_pawn)
	return

// --- Curiosity hooks ---------------------------------------------------------------------------
// The three decisions that separate a nosy crew member from a greytider. Overriding these is how an
// antagonist controller will be built: want everything, rummage constantly, and do something about a
// locked door other than complain.

/**
 * Would this person pocket that? Ordinary crew take things that match their own tastes, rolled once at
 * spawn, and leave anything they have no business carrying.
 */
/datum/ai_controller/sp_crew/proc/wants_item(obj/item/thing)
	if(QDELETED(thing) || (thing.item_flags & (ABSTRACT|DROPDEL)))
		return FALSE
	if(thing.w_class > WEIGHT_CLASS_NORMAL)
		return FALSE
	if(HAS_TRAIT(thing, TRAIT_NODROP) || is_type_in_typecache(thing, GLOB.sp_interest_blacklist))
		return FALSE
	var/list/interests = blackboard[BB_SP_INTERESTS]
	return length(interests) && is_type_in_list(thing, interests)

/// Whether this person is the sort to go through other people's lockers.
/datum/ai_controller/sp_crew/proc/may_rummage()
	return TRUE

/// Whether this person tries doors that are not theirs.
/datum/ai_controller/sp_crew/proc/may_try_doors()
	return TRUE

/**
 * The door said no. Crew take it personally for about a second and then get on with their shift; this
 * is the hook a greytider overrides to reach for a crowbar instead.
 */
/datum/ai_controller/sp_crew/proc/on_door_denied(obj/machinery/door/airlock/door)
	var/mob/living/carbon/human/human_pawn = pawn
	var/quiet_until = blackboard[BB_SP_NOSY_SPEAK_COOLDOWN] || 0
	if(!istype(human_pawn) || world.time < quiet_until)
		return
	set_blackboard_key(BB_SP_NOSY_SPEAK_COOLDOWN, world.time + 45 SECONDS)
	sp_crew_speak(human_pawn, pick(
		"Locked. Of course it is.",
		"Who do I have to ask to get in here?",
		"Not my access, apparently.",
		"Huh. Thought that one was open.",
	))

/datum/ai_controller/sp_crew/UnpossessPawn(destroy)
	if(!isnull(pawn))
		REMOVE_TRAIT(pawn, TRAIT_NOHUNGER, SP_CREW_TRAIT)
		UnregisterSignal(pawn, list(COMSIG_ATOM_WAS_ATTACKED, COMSIG_MOVABLE_PRE_HEAR, COMSIG_MOVABLE_BUMP, COMSIG_MOB_INCAPACITATE_CHANGED, COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED))
	return ..()

/// Walked into a closed firelock: push it open, the way a crew member would, so we can keep going.
/datum/ai_controller/sp_crew/proc/on_bump(datum/source, atom/bumped)
	SIGNAL_HANDLER
	var/obj/machinery/door/firedoor/firelock = bumped
	if(!istype(firelock) || !firelock.density || firelock.welded)
		return
	INVOKE_ASYNC(firelock, TYPE_PROC_REF(/obj/machinery/door, open))

/// Someone hurt us: remember them so the defense subtree can report and flee (or, for security, fight back).
/datum/ai_controller/sp_crew/proc/on_attacked(datum/source, atom/attacker)
	SIGNAL_HANDLER
	if(!isliving(attacker) || attacker == pawn)
		return
	add_blackboard_key_lazylist(BB_BASIC_MOB_RETALIATE_LIST, attacker)
	set_blackboard_key(BB_SP_ATTACKER, attacker)
	set_blackboard_key(BB_SP_ATTACKED_AT, world.time)
	sp_adjust_reputation(src, attacker, -6, "attacked us")
	// Whatever we were talking about is over.
	clear_blackboard_key(BB_SP_CHAT_PARTNER)
	clear_blackboard_key(BB_SP_CHAT_REPLY_DUE)

/**
 * Hearing. /mob/living/Hear() bails out early for client-less mobs, so we listen on the PRE_HEAR
 * signal which fires first. hearing_args is the Hear() argument list, indexed by the HEARING_* defines.
 */
/datum/ai_controller/sp_crew/proc/on_pre_hear(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	var/atom/movable/speaker = hearing_args[HEARING_SPEAKER]
	var/raw_message = hearing_args[HEARING_RAW_MESSAGE]
	if(QDELETED(speaker) || speaker == pawn || !istext(raw_message) || !length(raw_message))
		return

	var/is_radio = !isnull(hearing_args[HEARING_RADIO_FREQ])
	var/list/entry = list(
		SP_HEARD_SPEAKER = WEAKREF(speaker),
		SP_HEARD_NAME = speaker.name,
		SP_HEARD_MESSAGE = raw_message,
		SP_HEARD_TIME = world.time,
		SP_HEARD_RADIO = is_radio,
	)
	add_blackboard_key_lazylist(BB_SP_HEARD, entry)
	var/list/heard = blackboard[BB_SP_HEARD]
	while(length(heard) > SP_HEARD_MAX)
		remove_from_blackboard_lazylist_key(BB_SP_HEARD, heard[1])
		heard = blackboard[BB_SP_HEARD]

	// Radio speakers arrive wrapped in a virtualspeaker; unwrap to the real mob where we can.
	var/atom/movable/real_speaker = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/virtual = speaker
		real_speaker = virtual.source || speaker

	// Another AI crew member reporting an incident? They store the structured version for us.
	if(ishuman(real_speaker))
		var/mob/living/carbon/human/human_speaker = real_speaker
		var/datum/ai_controller/sp_crew/other = human_speaker.ai_controller
		if(istype(other))
			var/list/incident = other.blackboard[BB_SP_LAST_INCIDENT]
			if(length(incident) && world.time - incident[SP_INCIDENT_TIME] < 5 SECONDS)
				on_heard_incident(human_speaker, incident)
				return
	// A player (or anyone without our structured report) calling for help.
	if(isliving(real_speaker) && sp_message_is_distress(raw_message))
		on_heard_distress(real_speaker, raw_message, is_radio)

	if(is_radio || !isliving(real_speaker) || real_speaker == pawn)
		return
	consider_conversation(real_speaker, raw_message)

/**
 * Decides whether something said nearby was meant for us, and queues an answer if so.
 *
 * Another AI crew member opening a topic hands us the topic itself, so the reply fits what they said.
 * For anyone else -- a player, usually -- we answer if they used our name or said something that
 * clearly wants a response.
 */
/datum/ai_controller/sp_crew/proc/consider_conversation(mob/living/speaker, raw_message)
	var/mob/living/carbon/human/human_pawn = pawn
	if(!istype(human_pawn) || human_pawn.stat != STABLE)
		return
	var/reply_ready_at = blackboard[BB_SP_GREET_COOLDOWN]
	if(!isnull(reply_ready_at) && reply_ready_at > world.time)
		return

	// Another crew member talking to us: take the topic straight off their controller.
	if(ishuman(speaker))
		var/mob/living/carbon/human/human_speaker = speaker
		var/datum/ai_controller/sp_crew/their_ai = human_speaker.ai_controller
		if(istype(their_ai) && their_ai.blackboard[BB_SP_CHAT_PARTNER] == pawn)
			var/datum/sp_topic/topic = their_ai.blackboard[BB_SP_CHAT_TOPIC]
			if(!isnull(topic))
				set_blackboard_key(BB_SP_GREET_COOLDOWN, world.time + 8 SECONDS)
				set_blackboard_key(BB_SP_CHAT_TOPIC, topic)
				set_blackboard_key(BB_SP_CHAT_HEARD, raw_message)
				set_blackboard_key(BB_SP_CHAT_REPLY_DUE, speaker)
				return

	// Anyone else. Answer if they used our name, or said something plainly aimed at a person.
	var/list/name_parts = splittext(human_pawn.real_name, " ")
	var/first_name = length(name_parts) ? name_parts[1] : human_pawn.real_name
	var/named_us = length(first_name) >= 3 && findtext(raw_message, first_name)
	if(!named_us && isnull(sp_answer_for(src, speaker, raw_message)))
		return
	set_blackboard_key(BB_SP_GREET_COOLDOWN, world.time + 8 SECONDS)
	set_blackboard_key(BB_SP_CHAT_HEARD, raw_message)
	set_blackboard_key(BB_SP_CHAT_REPLY_DUE, speaker)

/// Another crew member reported an attack within earshot (or on a channel we hear). Base crew ignore it.
/datum/ai_controller/sp_crew/proc/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	return

/// Someone (usually the player) shouted words that sound like a call for help. Base crew ignore it.
/datum/ai_controller/sp_crew/proc/on_heard_distress(mob/living/speaker, raw_message, is_radio)
	return

// --- Able-to-run handling, mirrors /datum/ai_controller/basic_controller for a living pawn ---

/datum/ai_controller/sp_crew/on_stat_changed(mob/living/source, new_stat)
	. = ..()
	update_able_to_run()

/datum/ai_controller/sp_crew/setup_able_to_run()
	. = ..()
	RegisterSignal(pawn, COMSIG_MOB_INCAPACITATE_CHANGED, PROC_REF(update_able_to_run))
	RegisterSignals(pawn, list(COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED), PROC_REF(update_able_to_run))

/datum/ai_controller/sp_crew/clear_able_to_run()
	UnregisterSignal(pawn, list(COMSIG_MOB_INCAPACITATE_CHANGED, COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED))
	return ..()

/datum/ai_controller/sp_crew/get_able_to_run()
	. = ..()
	if(. & AI_UNABLE_TO_RUN)
		return .
	var/mob/living/living_pawn = pawn
	if(IS_UNCONSCIOUS_OR_CRIT(living_pawn))
		return AI_UNABLE_TO_RUN
	if(INCAPACITATED_IGNORING(living_pawn, INCAPABLE_GRAB))
		return AI_UNABLE_TO_RUN
	if(LAZYLEN(living_pawn.do_afters))
		return AI_UNABLE_TO_RUN | AI_PREVENT_CANCEL_ACTIONS
	return NONE

// --- Job controllers --------------------------------------------------------------------------

/// Medical staff: treat injured crew they can see, otherwise behave like base crew inside medical.
/datum/ai_controller/sp_crew/medical
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_medical.bt.json"

/datum/ai_controller/sp_crew/medical/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	var/static/list/medical_areas = list(
		/area/station/medical/medbay/central,
		/area/station/medical/medbay/lobby,
		/area/station/medical/medbay/aft,
		/area/station/medical/treatment_center,
		/area/station/medical/storage,
		/area/station/medical/exam_room,
		/area/station/medical/office,
		/area/station/medical/break_room,
	)
	set_blackboard_key(BB_SP_WANDER_AREAS, medical_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Anyone hurt? Come to medbay.",
			"Remember to take your pills.",
			"Please don't bleed on the floor.",
			"Where did I leave that health analyzer?",
		),
		BB_EMOTE_SEE = list("checks a clipboard.", "adjusts a pair of gloves."),
	))

/// Security: patrol hallways and the brig, respond to reports, subdue and cuff attackers.
/datum/ai_controller/sp_crew/security
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_security.bt.json"

/datum/ai_controller/sp_crew/security/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	var/static/list/patrol_areas
	if(isnull(patrol_areas))
		patrol_areas = typesof(/area/station/hallway) + typesof(/area/station/security)
	set_blackboard_key(BB_SP_WANDER_AREAS, patrol_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Nothing to see here, move along.",
			"Keep it civil, people.",
			"Anyone seen anything suspicious?",
			"Another quiet patrol. Too quiet.",
		),
		BB_EMOTE_SEE = list("scans the area.", "rests a hand on a baton."),
	))

/// Security fights back instead of fleeing: whoever hits us becomes the suspect.
/datum/ai_controller/sp_crew/security/on_attacked(datum/source, atom/attacker)
	. = ..()
	if(!isliving(attacker) || attacker == pawn)
		return
	set_blackboard_key(BB_SP_INCIDENT_TARGET, attacker)
	set_blackboard_key(BB_SP_INCIDENT_LOCATION, get_turf(attacker))

/datum/ai_controller/sp_crew/security/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	if(reporter == pawn)
		return
	var/datum/weakref/attacker_ref = incident[SP_INCIDENT_ATTACKER]
	var/mob/living/attacker = attacker_ref?.resolve()
	var/turf/where = incident[SP_INCIDENT_TURF]
	if(!isnull(attacker) && attacker != pawn)
		set_blackboard_key(BB_SP_INCIDENT_TARGET, attacker)
	if(!isnull(where))
		set_blackboard_key(BB_SP_INCIDENT_LOCATION, where)
	acknowledge_report()

/datum/ai_controller/sp_crew/security/on_heard_distress(mob/living/speaker, raw_message, is_radio)
	if(speaker == pawn || blackboard_key_exists(BB_SP_INCIDENT_TARGET))
		return
	var/turf/where = get_turf(speaker)
	if(isnull(where))
		return
	set_blackboard_key(BB_SP_INCIDENT_LOCATION, where)
	acknowledge_report()

/// Says "on my way" over the security channel, at most once every 20 seconds.
/datum/ai_controller/sp_crew/security/proc/acknowledge_report()
	var/ready_at = blackboard[BB_SP_ACK_COOLDOWN]
	if(!isnull(ready_at) && ready_at > world.time)
		return
	set_blackboard_key(BB_SP_ACK_COOLDOWN, world.time + 20 SECONDS)
	var/area/target_area = get_area(blackboard[BB_SP_INCIDENT_LOCATION])
	sp_crew_speak(pawn, "Copy, responding[target_area ? " to [target_area.name]" : ""].", RADIO_CHANNEL_SECURITY)

/// Engineering: keep the engine running and the SMES charged; otherwise wander engineering.
/datum/ai_controller/sp_crew/engineer
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_engineer.bt.json"

/**
 * Engineers patch hull breaches, which means standing in vacuum. TG only issues them a hardhat, so
 * SP gives them an EVA softsuit to carry; the repair subtree puts it on before heading out.
 */
/datum/ai_controller/sp_crew/engineer/equip_extra_gear(mob/living/carbon/human/human_pawn)
	// Breaches happen behind locked doors. JPS refuses to path through an airlock the pawn cannot open,
	// so without station-wide access an AI engineer simply never reaches most hull damage.
	var/obj/item/card/id/id_card = human_pawn.get_idcard(hand_first = FALSE)
	if(id_card)
		id_card.add_access(SSid_access.get_region_access_list(list(REGION_ALL_STATION)), mode = TRY_ADD_ALL_NO_WILDCARD)
	if(!length(human_pawn.get_all_contents_type(/obj/item/clothing/suit/space)))
		human_pawn.equip_to_storage(new /obj/item/clothing/suit/space/eva(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)
	if(!length(human_pawn.get_all_contents_type(/obj/item/clothing/head/helmet/space)))
		human_pawn.equip_to_storage(new /obj/item/clothing/head/helmet/space/eva(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)

/datum/ai_controller/sp_crew/engineer/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	// Repair work means standing in vacuum and taking chip damage; a high threshold would abort the
	// job and send them to medbay every few seconds. They still bail out when actually badly hurt.
	set_blackboard_key(BB_SP_HURT_THRESHOLD, 40)
	var/static/list/engineering_areas = list(
		/area/station/engineering/main,
		/area/station/engineering/engine_smes,
		/area/station/engineering/hallway,
		/area/station/engineering/storage,
		/area/station/engineering/storage_shared,
		/area/station/engineering/break_room,
		/area/station/engineering/lobby,
		/area/station/engineering/supermatter/room,
		/area/station/engineering/atmos,
	)
	set_blackboard_key(BB_SP_WANDER_AREAS, engineering_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Who left this wire exposed?",
			"The engine sounds fine. I think.",
			"If the lights flicker, that's normal. Probably.",
			"Has anyone seen my welding fuel?",
		),
		BB_EMOTE_SEE = list("checks a gauge.", "taps a wrench against a pipe."),
	))

/// Botanist: runs the hydroponics trays and keeps the kitchen supplied.
/datum/ai_controller/sp_crew/botanist
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_botanist.bt.json"

/**
 * TG gives botanists an apron and a plant analyser but no guarantee of seeds, a hoe or a watering can
 * (the tools are family heirlooms, which most characters do not roll). Hand them a working kit so the
 * garden actually gets planted, and a random spread of seeds so no two rounds grow the same things.
 */
/datum/ai_controller/sp_crew/botanist/equip_extra_gear(mob/living/carbon/human/human_pawn)
	if(!length(human_pawn.get_all_contents_type(/obj/item/cultivator)))
		human_pawn.equip_to_storage(new /obj/item/cultivator(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)
	if(isnull(sp_botany_watering_can(human_pawn)))
		var/obj/item/reagent_containers/cup/watering_can/can = new(human_pawn)
		can.reagents?.add_reagent(/datum/reagent/water, can.reagents.maximum_volume)
		human_pawn.equip_to_storage(can, ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)

	// Four large beakers of unstable mutagen: the sort of thing a botanist would ask chemistry for at
	// the start of a shift. A species mutation needs a plant's instability up around 60, which is a few
	// hundred units of the stuff, so anything less means they can never actually breed something new.
	for(var/beaker in 1 to 4)
		var/obj/item/reagent_containers/cup/beaker/large/mutagen = new(human_pawn)
		mutagen.name = "beaker of unstable mutagen"
		mutagen.reagents?.add_reagent(/datum/reagent/toxin/mutagen, mutagen.reagents.maximum_volume)
		human_pawn.equip_to_storage(mutagen, ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)

	// Six kinds of seed, drawn from the pool by weight, two packets of each.
	var/list/pool = GLOB.sp_botany_seed_pool.Copy()
	var/list/chosen = list()
	for(var/i in 1 to 6)
		if(!length(pool))
			break
		var/seed_type = pick_weight(pool)
		pool -= seed_type
		chosen += seed_type
		for(var/packet in 1 to 2)
			human_pawn.equip_to_storage(new seed_type(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)
	log_sp("[human_pawn.real_name] starts with seeds: [english_list(chosen)]")

/datum/ai_controller/sp_crew/botanist/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	set_blackboard_key(BB_SP_WANDER_AREAS, sp_botany_areas())
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"These trays don't water themselves.",
			"Everything grows better with a bit of attention.",
			"The kitchen's going to want more tomatoes.",
			"I'm trying something new in the back tray.",
			"Mind the weeds.",
		),
		BB_EMOTE_SEE = list("inspects a leaf.", "wipes soil off a pair of gloves."),
	))

/// Cargo technician: gets the crates off the shuttle and walks the requested ones where they belong.
/datum/ai_controller/sp_crew/cargo
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_cargo.bt.json"

/datum/ai_controller/sp_crew/cargo/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	var/static/list/cargo_areas = list(
		/area/station/cargo/storage,
		/area/station/cargo/office,
		/area/station/cargo/sorting,
		/area/station/cargo/warehouse,
		/area/station/cargo/lower,
		/area/station/cargo/breakroom,
	)
	set_blackboard_key(BB_SP_WANDER_AREAS, cargo_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"If it's not on the manifest, it isn't mine.",
			"Another crate, another day.",
			"Shuttle's the only thing that runs on time around here.",
			"Whoever keeps stacking crates in the doorway, don't.",
		),
		BB_EMOTE_SEE = list("checks a manifest.", "shoves a crate into place."),
	))

/// Quartermaster: the same, plus the paperwork and the shuttle itself.
/datum/ai_controller/sp_crew/cargo/quartermaster
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_quartermaster.bt.json"

/datum/ai_controller/sp_crew/cargo/quartermaster/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	. = ..()
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Requests go through me, not the shuttle.",
			"The budget is not infinite. Ask anyway.",
			"If your department needs something, say so on the radio.",
			"I've got orders to file.",
		),
		BB_EMOTE_SEE = list("thumbs through a stack of forms.", "taps at the supply console."),
	))

/// Chef: stocks the prep table, works the cooking tree, and puts what comes out on the counter.
/datum/ai_controller/sp_crew/chef
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_chef.bt.json"

/**
 * TG issues a chef an apron, a hat and a moustache. The knife, the rolling pin and the bowls are all
 * things a real kitchen already owns or a character rolls as an heirloom, so without them an AI chef
 * can cut nothing, roll nothing and serve no salad. Bowls in particular are the gate: a great many
 * recipes want one and the dinnerware vendor charges most of a paycheck for each.
 */
/datum/ai_controller/sp_crew/chef/equip_extra_gear(mob/living/carbon/human/human_pawn)
	if(!length(human_pawn.get_all_contents_type(/obj/item/knife)))
		human_pawn.equip_to_storage(new /obj/item/knife/kitchen(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)
	if(!length(human_pawn.get_all_contents_type(/obj/item/kitchen/rollingpin)))
		human_pawn.equip_to_storage(new /obj/item/kitchen/rollingpin(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)
	// Two only: a bowl is a bulky thing and the rest of the bag would be deleted for not fitting. The
	// kitchen's dinnerware vendor is the restock, and the chef buys from it out of their own wages.
	for(var/bowl in 1 to 2)
		human_pawn.equip_to_storage(new /obj/item/reagent_containers/cup/bowl(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)

/datum/ai_controller/sp_crew/chef/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	set_blackboard_key(BB_SP_WANDER_AREAS, sp_kitchen_areas())
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Nobody comes to the kitchen until it's on fire.",
			"You can't rush dough.",
			"If botany would send more tomatoes I'd send more food.",
			"Everything on the counter is free, that's the point.",
			"I'm not making anything special until somebody asks nicely.",
		),
		BB_EMOTE_SEE = list("wipes down a knife.", "checks the oven.", "tastes something and frowns."),
	))

/// Bartender: mixes drinks at the taps and lines them up on the bar.
/datum/ai_controller/sp_crew/bartender
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_bartender.bt.json"

/**
 * TG gives a bartender a bowtie, sunglasses and a box of beanbag shells, and no glassware whatsoever.
 * The station has no glasses on it either — the boozeomat sells bottles, not glasses — so without a
 * couple of boxes there is nothing to pour into. They buy more from the kitchen's dinnerware vendor,
 * which is next door on most maps, when these run out.
 */
/datum/ai_controller/sp_crew/bartender/equip_extra_gear(mob/living/carbon/human/human_pawn)
	for(var/box in 1 to 2)
		human_pawn.equip_to_storage(new /obj/item/storage/box/drinkingglasses(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)

/datum/ai_controller/sp_crew/bartender/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	set_blackboard_key(BB_SP_WANDER_AREAS, sp_bar_areas())
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"What'll it be?",
			"Everything on the bar is free. That's the arrangement.",
			"I don't want to hear about your shift. I want to hear your order.",
			"There's a reason the good stuff is behind me.",
			"One each. I'm not carrying anybody to medbay tonight.",
		),
		BB_EMOTE_SEE = list("polishes a glass.", "wipes down the bar.", "checks the taps."),
	))
