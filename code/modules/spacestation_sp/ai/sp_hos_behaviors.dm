/**
 * The Head of Security: the one member of the department who gives orders rather than only taking them.
 *
 * Orders travel the way crime reports already do (see on_pre_hear): the issuer writes the structured order
 * onto their own blackboard, then says it out loud on the security channel, and whoever hears them reads it
 * off the speaker. Nothing is broadcast to a roster, so an officer out of radio contact genuinely misses the
 * order, and an HoS with no headset gives none at all. That is what we want from a chain of command.
 */
/datum/ai_controller/sp_crew/security/hos
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_hos.bt.json"

/// The head of security is on duty while fetching from the armoury, too.
/datum/ai_controller/sp_crew/security/hos/busy_with_work()
	return ..() || blackboard_key_exists(BB_SP_ARMOURY_TARGET)

/datum/ai_controller/sp_crew/security/hos/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	. = ..()
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Keep me posted, all of you.",
			"I want eyes in the halls, not in the breakroom.",
			"Anything out of place, I hear about it.",
		),
		BB_EMOTE_SEE = list("reads over the department roster.", "watches a camera feed."),
	))

/// An order nobody can hear is not an order.
/datum/ai_controller/sp_crew/security/hos/proc/can_give_orders()
	var/mob/living/carbon/human/human_pawn = pawn
	return ishuman(human_pawn) && istype(human_pawn.ears, /obj/item/radio/headset)

/// Violence is what walks the alert ladder up, so the head of security keeps count of it.
/datum/ai_controller/sp_crew/security/hos/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	. = ..()
	var/datum/weakref/attacker_ref = incident[SP_INCIDENT_ATTACKER]
	if(isnull(attacker_ref?.resolve()))
		return
	set_blackboard_key(BB_SP_VIOLENCE_SEEN, (blackboard[BB_SP_VIOLENCE_SEEN] || 0) + 1)

/**
 * Puts an order where listeners will look for it, then says it out loud.
 *
 * The blackboard is written first on purpose: on_pre_hear reads it off the speaker at the moment it hears
 * them, so an order spoken before it was written would be heard as nothing at all. One order per utterance
 * for the same reason -- a second would overwrite the first before anybody had read it.
 */
/proc/sp_issue_order(datum/ai_controller/sp_crew/controller, kind, atom/where, message)
	var/mob/living/carbon/human/issuer = controller?.pawn
	if(!ishuman(issuer))
		return FALSE
	// A list has to go in with override_blackboard_key: set_blackboard_key refuses to write over one, so
	// every order after the first threw and left the previous order sitting there for listeners to re-read.
	controller.override_blackboard_key(BB_SP_LAST_ORDER, list(
		SP_ORDER_KIND = kind,
		SP_ORDER_TIME = world.time,
		SP_ORDER_WHERE = get_turf(where),
		SP_ORDER_ISSUER = WEAKREF(issuer),
	))
	sp_crew_speak(issuer, message, RADIO_CHANNEL_SECURITY)
	sp_record("sec.order_[kind]")
	log_sp("[issuer.real_name] ordered [kind]")
	return TRUE

/datum/bt_node/subtree/sp_hos_command
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_hos_command.bt.json"

/datum/bt_node/subtree/sp_security_meeting
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_security_meeting.bt.json"

/**
 * Walks the alert level up as reports of violence come in.
 *
 * This fork has no yellow alert -- the ladder is green, blue, red, delta -- so heightened-but-not-lethal is
 * blue. Going red is also where lethal force is authorised, rather than at the briefing, so that the two
 * orders are never spoken in one breath and cannot overwrite one another on the way out.
 */
/datum/bt_node/ai_behavior/sp_hos_consider_alert/perform(seconds_per_tick, datum/ai_controller/controller)
	var/datum/ai_controller/sp_crew/security/hos/hos = controller
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(hos) || !ishuman(pawn) || !hos.can_give_orders())
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/seen = controller.blackboard[BB_SP_VIOLENCE_SEEN] || 0
	var/wanted = SEC_LEVEL_GREEN
	if(seen >= SP_ALERT_RED_AFTER)
		wanted = SEC_LEVEL_RED
	else if(seen >= SP_ALERT_BLUE_AFTER)
		wanted = SEC_LEVEL_BLUE
	if(wanted <= SSsecurity_level.get_current_level_as_number())
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	SSsecurity_level.set_level(wanted)
	sp_record("sec.alert_raised")
	log_sp("[pawn.real_name] raised the alert to [SSsecurity_level.get_current_level_as_text()] after [seen] attacks")
	if(wanted >= SEC_LEVEL_RED)
		sp_issue_order(controller, SP_ORDER_LETHAL, pawn, "Red alert. Lethal force is authorised, do not take chances.")
	else
		sp_crew_speak(pawn, "Going to blue. Stay sharp and keep your batons to hand.", RADIO_CHANNEL_SECURITY)
	// Whatever the shift has turned into, it wants saying to their faces.
	controller.clear_blackboard_key(BB_SP_MEETING_COOLDOWN)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Calls the department together, and stands there themselves so there is somebody to gather round.
/datum/bt_node/ai_behavior/sp_hos_call_meeting/perform(seconds_per_tick, datum/ai_controller/controller)
	var/datum/ai_controller/sp_crew/security/hos/hos = controller
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(hos) || !ishuman(pawn) || !hos.can_give_orders())
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(world.time < (controller.blackboard[BB_SP_MEETING_COOLDOWN] || 0))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_MEETING_COOLDOWN, world.time + SP_MEETING_COOLDOWN)
	var/turf/spot = get_turf(pawn)
	if(!sp_issue_order(controller, SP_ORDER_MEETING, spot, "All security staff, on me for a briefing."))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.clear_blackboard_key(BB_SP_BRIEFED)
	controller.set_blackboard_key(BB_SP_MEETING_SPOT, spot)
	controller.set_blackboard_key(BB_SP_MEETING_UNTIL, world.time + SP_MEETING_TIME)
	sp_record("sec.meeting_called")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// The briefing itself: said once per meeting, and what is said depends on the kind of shift it has been.
/datum/bt_node/ai_behavior/sp_hos_brief/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!ishuman(pawn) || isnull(controller.blackboard[BB_SP_MEETING_SPOT]) || controller.blackboard[BB_SP_BRIEFED])
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_BRIEFED, TRUE)
	if(SSsecurity_level.get_current_level_as_number() >= SEC_LEVEL_RED)
		sp_issue_order(controller, SP_ORDER_ARM, pawn, "Draw from the armoury before you leave. I want everyone carrying.")
	else
		sp_issue_order(controller, SP_ORDER_STAND_DOWN, pawn, "Standard loadout, standard patrol. Mind your corners.")
	sp_record("sec.briefed")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Standing at a briefing, facing whoever called it, until it is over.
/datum/bt_node/ai_behavior/sp_attend_meeting/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/turf/spot = controller.blackboard[BB_SP_MEETING_SPOT]
	if(!ishuman(pawn) || isnull(spot) || world.time >= (controller.blackboard[BB_SP_MEETING_UNTIL] || 0))
		controller.clear_blackboard_key(BB_SP_MEETING_SPOT)
		controller.clear_blackboard_key(BB_SP_MEETING_UNTIL)
		controller.clear_blackboard_key(BB_SP_BRIEFED)
		sp_record("sec.meeting_attended")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	pawn.face_atom(spot)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Doing as you are told: drawing a kit ----------------------------------------------------------

/datum/bt_node/subtree/sp_security_arm
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_security_arm.bt.json"

/// A locker this pawn could actually get something out of: not welded shut, not locked against them, and on
/// their level. Checked on every pass, because a locker can be welded or locked after it was chosen.
/proc/sp_arm_locker_usable(obj/structure/closet/locker, mob/living/pawn)
	if(QDELETED(locker) || QDELETED(pawn) || locker.welded)
		return FALSE
	if(locker.locked && !locker.allowed(pawn))
		return FALSE
	var/turf/there = get_turf(locker)
	return !isnull(there) && there.z == pawn.z

/**
 * Finding somewhere an officer can actually draw a kit from.
 *
 * Their own locker is ACCESS_BRIG, which every officer carries. The armoury is ACCESS_ARMORY, which only the
 * head of security and the warden hold -- so this deliberately does not send anyone there. The locker has to
 * hold a belt, checked here rather than discovered on arrival: walking across the station to a locker with
 * nothing in it is the same wasted trip as picking a target nobody can reach.
 */
/datum/bt_node/ai_behavior/sp_find_arm_locker/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!ishuman(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// What are we short of? Each job says what it ought to be carrying and was not handed at spawn, best
	// first, and we go after the first thing we have not got. Security then has one addition nobody else
	// does: once the shift has actually turned, the energy gun, which lives in the armoury and is the only
	// thing that can go lethal.
	var/datum/ai_controller/sp_crew/crew = controller
	if(!istype(crew))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/wanted
	var/wanted_locker
	var/list/kit = crew.kit_wanted()
	for(var/piece in kit)
		if(!length(pawn.get_all_contents_type(piece)))
			wanted = piece
			wanted_locker = kit[piece]
			break
	if(isnull(wanted) && istype(crew, /datum/ai_controller/sp_crew/security))
		// A lethal weapon that exists. MetaStation has no energy guns whatsoever -- four lasers, in the warden's
		// locker and on a rack in the range -- so asking for an e_gun was asking for something unobtainable.
		// Note the disabler everyone carries is also /obj/item/gun/energy, so the check has to name both.
		if(SSsecurity_level.get_current_level_as_number() >= SEC_LEVEL_RED \
			&& !length(pawn.get_all_contents_type(/obj/item/gun/energy/e_gun)) \
			&& !length(pawn.get_all_contents_type(/obj/item/gun/energy/laser)))
			wanted = /obj/item/gun/energy/laser
	if(isnull(wanted))
		// Nothing left to fetch: the order is met, and this is how the whole thing comes to a stop.
		controller.clear_blackboard_key(BB_SP_ARM_ORDER)
		controller.clear_blackboard_key(BB_SP_ARM_LOCKER)
		controller.clear_blackboard_key(BB_SP_ARM_WANTED)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Stay on the trip we are already making. This leaf re-runs whenever the sequence restarts, which a
	// briefing or an incident causes constantly -- so picking the nearest locker afresh each time means an
	// officer who was pulled away retargets from wherever he now stands. One walked between three security
	// posts in five minutes and reached none; the only officer who came back with a belt was the one nobody
	// happened to interrupt.
	var/obj/structure/closet/current = controller.blackboard[BB_SP_ARM_LOCKER]
	if(!QDELETED(current) && sp_arm_locker_usable(current, pawn) && (!current.contents_initialized || length(current.get_all_contents_type(wanted))))
		// Patience measured by progress. Every interruption re-enters this leaf, so counting re-entries alone would
		// abandon a long honest walk; only re-entries that bring the officer no closer count against the locker.
		// A walk that cannot succeed, or a welded locker the take leaf keeps locking and unlocking, stops making
		// progress at once and is given up after SP_ARM_MAX_TRIES.
		var/dist = get_dist(pawn, current)
		var/last = controller.blackboard[BB_SP_ARM_LAST_DIST]
		var/tries = (isnull(last) || dist < last) ? 0 : (controller.blackboard[BB_SP_ARM_TRIES] || 0) + 1
		controller.set_blackboard_key(BB_SP_ARM_TRIES, tries)
		controller.set_blackboard_key(BB_SP_ARM_LAST_DIST, dist)
		if(tries <= SP_ARM_MAX_TRIES)
			if(world.time >= (controller.blackboard[BB_SP_ARM_REPORT] || 0))
				controller.set_blackboard_key(BB_SP_ARM_REPORT, world.time + 30 SECONDS)
				log_sp("[pawn.real_name] still [dist] tiles from [current.name]")
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
		controller.set_blackboard_key_assoc_lazylist(BB_SP_ARM_IGNORE, current, world.time + SP_ARM_IGNORE_TIME)
		log_sp("[pawn.real_name] gave up on [current.name] after [SP_ARM_MAX_TRIES] tries without getting closer")
	controller.clear_blackboard_key(BB_SP_ARM_LOCKER)
	controller.clear_blackboard_key(BB_SP_ARM_TRIES)
	controller.clear_blackboard_key(BB_SP_ARM_LAST_DIST)
	var/obj/structure/closet/best
	var/best_dist = INFINITY
	for(var/obj/structure/closet/candidate as anything in GLOB.roundstart_station_closets)
		// An armoury somebody has already unlocked counts: no officer holds ACCESS_ARMORY themselves.
		if(!sp_arm_locker_usable(candidate, pawn))
			continue
		var/list/given_up = controller.blackboard[BB_SP_ARM_IGNORE]
		if(given_up && given_up[candidate] > world.time)
			continue
		// A closet nobody has opened is empty -- PopulateContents() runs from dump_contents() on first open, not
		// at Initialize -- so its contents cannot be checked and we go by type instead. An opened one can be
		// checked, and is taken on its contents whatever it is: that is how an officer draws from an armoury the
		// head of security has unlocked. Trusting neither rejected every correct locker; trusting anything
		// unopened sent an officer to a pajama wardrobe in the Dormitories.
		if(candidate.contents_initialized)
			if(!length(candidate.get_all_contents_type(wanted)))
				continue
		else if(isnull(wanted_locker) || !istype(candidate, wanted_locker))
			continue
		var/dist = get_dist(pawn, candidate)
		if(dist >= best_dist)
			continue
		best = candidate
		best_dist = dist
	if(isnull(best))
		// Nothing we can open and nothing in what we can: drop it rather than pace about.
		controller.clear_blackboard_key(BB_SP_ARM_ORDER)
		log_sp("[pawn.real_name] was told to arm, but no locker they can open holds [wanted]")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(controller.blackboard[BB_SP_ARM_LOCKER] != best)
		log_sp("[pawn.real_name] set off for [best.name] in [get_area_name(best)] after [wanted]")
	controller.set_blackboard_key(BB_SP_ARM_LOCKER, best)
	controller.set_blackboard_key(BB_SP_ARM_WANTED, wanted)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Drawing the belt out of the locker.
 *
 * Nothing here equips anything: the belt goes in the pack, and that is enough, because sp_equip_item finds
 * what it wants with get_all_contents_type, which walks into containers. The baton an officer has never had
 * is sitting inside this belt, so fetching it is what quietly makes the existing arrest path work.
 */
/datum/bt_node/ai_behavior/sp_take_arm_kit
	/// Held across the async half.
	VAR_PRIVATE/atom/movable/reach

/datum/bt_node/ai_behavior/sp_take_arm_kit/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	reach = controller.blackboard[BB_SP_ARM_LOCKER]
	if(!istype(pawn) || QDELETED(reach) || !reach.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_take_arm_kit/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/closet/locker = reach
	if(!istype(locker))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_free_hands(pawn)
	if(locker.locked && locker.allowed(pawn))
		sp_ai_click(controller, locker, list(RIGHT_CLICK = "1"))
	if(!locker.opened)
		sp_ai_click(controller, locker)
	if(!async_still_valid() || QDELETED(pawn))
		return
	var/wanted = controller.blackboard[BB_SP_ARM_WANTED] || /obj/item/storage/belt/security
	// Not inside the locker: dump_contents() moves everything to drop_location() as it opens, so the belt is
	// on the floor beside us. This is why sp_take_scheme_item looks around the pawn rather than in the box.
	var/obj/item/belt = sp_reachable_item(pawn, wanted)
	if(QDELETED(belt))
		log_sp("[pawn.real_name] opened [locker.name] but found no [wanted] to take")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!do_after(pawn, SP_ARM_TIME, belt, timed_action_flags = IGNORE_HELD_ITEM))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!async_still_valid() || QDELETED(pawn) || QDELETED(belt))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!(pawn.back && belt.forceMove(pawn.back)) && !pawn.put_in_hands(belt))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	// The order stands: the pick leaf ends it once there is nothing left worth fetching.
	controller.clear_blackboard_key(BB_SP_ARM_LOCKER)
	controller.clear_blackboard_key(BB_SP_ARM_WANTED)
	controller.clear_blackboard_key(BB_SP_ARM_TRIES)
	controller.clear_blackboard_key(BB_SP_ARM_LAST_DIST)
	sp_record("sec.armed")
	log_sp("[pawn.real_name] drew [belt.name] in [get_area_name(locker)]")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

// --- The keys: opening the armoury -----------------------------------------------------------------

/// Riot gear, shotguns, energy guns, the tac locker. Every one of them ACCESS_ARMORY.
GLOBAL_LIST_INIT(sp_armoury_lockers, typecacheof(list(
	/obj/structure/closet/secure_closet/armory1,
	/obj/structure/closet/secure_closet/armory2,
	/obj/structure/closet/secure_closet/armory3,
	/obj/structure/closet/secure_closet/tac,
	// The one that actually exists on MetaStation: there are no armory1/2/3 or tac closets on this map at
	// all, which is why this search correctly found nothing for seven rounds. The warden's locker is the
	// ACCESS_ARMORY container here, and it holds a laser and a belt. The others stay for maps that have them.
	/obj/structure/closet/secure_closet/warden,
)))

/**
 * The head of security going and unlocking the armoury.
 *
 * This is what holding the keys is for. ACCESS_ARMORY sits on two trims in the whole game -- theirs and the
 * warden's -- so an order to draw heavier kit is worth nothing at all until somebody with the access walks
 * over and opens the door. Red only: riot gear on a quiet shift is theatre.
 */
/datum/bt_node/ai_behavior/sp_hos_find_armoury/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!ishuman(pawn) || SSsecurity_level.get_current_level_as_number() < SEC_LEVEL_RED)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Stay on the trip already begun, for the same reason the kit finder does: this leaf re-runs every time
	// the sequence restarts, so picking the nearest armoury afresh means a head of security called away by an
	// incident retargets from wherever they now stand. Six rounds and the armoury has never once been opened,
	// while officers correctly reported there was no energy gun they could reach.
	var/obj/structure/closet/current = controller.blackboard[BB_SP_ARMOURY_TARGET]
	if(!QDELETED(current) && current.locked && current.allowed(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	var/obj/structure/closet/best
	var/best_dist = INFINITY
	for(var/obj/structure/closet/candidate as anything in GLOB.roundstart_station_closets)
		if(!GLOB.sp_armoury_lockers[candidate.type] || !candidate.locked || !candidate.allowed(pawn))
			continue
		var/turf/there = get_turf(candidate)
		if(isnull(there) || there.z != pawn.z)
			continue
		var/dist = get_dist(pawn, candidate)
		if(dist >= best_dist)
			continue
		best = candidate
		best_dist = dist
	if(isnull(best))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(controller.blackboard[BB_SP_ARMOURY_TARGET] != best)
		log_sp("[pawn.real_name] set off to unlock [best.name] in [get_area_name(best)]")
	controller.set_blackboard_key(BB_SP_ARMOURY_TARGET, best)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Unlocking it, and saying so, because an armoury nobody knows is open may as well still be shut.
/datum/bt_node/ai_behavior/sp_hos_open_armoury
	/// Held across the async half.
	VAR_PRIVATE/atom/movable/reach

/datum/bt_node/ai_behavior/sp_hos_open_armoury/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	reach = controller.blackboard[BB_SP_ARMOURY_TARGET]
	if(!istype(pawn) || QDELETED(reach) || !reach.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_hos_open_armoury/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/closet/locker = reach
	if(!istype(locker))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_free_hands(pawn)
	// Somebody else with the keys -- the warden and the head of security both hold them -- may have got here first.
	var/was_shut = locker.locked || !locker.opened
	if(locker.locked && locker.allowed(pawn))
		sp_ai_click(controller, locker, list(RIGHT_CLICK = "1"))
	if(!async_still_valid() || QDELETED(pawn) || QDELETED(locker))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!locker.opened)
		sp_ai_click(controller, locker)
	if(!async_still_valid() || QDELETED(pawn) || QDELETED(locker))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	controller.clear_blackboard_key(BB_SP_ARMOURY_TARGET)
	if(locker.locked)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!was_shut)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED) // already open: nothing to announce twice
		return
	sp_record("sec.armoury_opened")
	log_sp("[pawn.real_name] unlocked [locker.name] in [get_area_name(locker)]")
	sp_crew_speak(pawn, "Armoury is open. Draw what you need.", RADIO_CHANNEL_SECURITY)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)
