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
	RegisterSignal(human_pawn, COMSIG_ATOM_EXAMINE, PROC_REF(on_examined))
	// Until a proper needs subtree exists, AI crew do not starve. Documented limitation.
	ADD_TRAIT(human_pawn, TRAIT_NOHUNGER, SP_CREW_TRAIT)
	// A list value has to go in with override_blackboard_key: set_blackboard_key refuses to write over
	// one, and the CRASH left every crew member with no tastes at all, so nothing was ever worth taking.
	override_blackboard_key(BB_SP_INTERESTS, sp_roll_interests())
	setup_job_blackboard(human_pawn)
	// Anything this job ought to be carrying and was not handed at spawn: go and get it. This raises the
	// same key an arming order does, so one subtree serves both a roundstart kit and a red alert, and the
	// pick leaf ends it once there is nothing left worth fetching.
	if(length(kit_wanted()))
		set_blackboard_key(BB_SP_ARM_ORDER, TRUE)
	return ..()

/// Hook for subtypes to seed job-specific blackboard keys (wander areas, lines, ...).
/datum/ai_controller/sp_crew/proc/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	return

/// Called by the spawner once the crew member is equipped, for job gear TG does not hand out.
/datum/ai_controller/sp_crew/proc/equip_extra_gear(mob/living/carbon/human/human_pawn)
	return

/**
 * What this job ought to be carrying but was not handed at spawn, paired with the kind of locker it lives in.
 *
 * The locker type matters as much as the item. A closed closet is empty until somebody opens it, so an
 * unopened one cannot be searched -- and a finder that accepts any unopened closet sends an officer to a
 * pajama wardrobe in the Dormitories, which is exactly what happened before this was paired up.
 *
 * Fetching beats handing over: a locker on the station is a thing the crew can be seen walking to, and a
 * department whose kit has been looted or burned should feel that. It is only worth doing where the item
 * genuinely exists somewhere reachable -- a botanist sent after a watering can no locker holds would simply
 * never garden. Engineering stays empty on purpose: what equip_extra_gear gives them is not kit but
 * station-wide ID access, without which JPS will not path them through an airlock to a breach at all.
 */
/datum/ai_controller/sp_crew/proc/kit_wanted()
	return null

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

/// Whether we tell anyone about a crime we see (sp_crime.dm). Not while we have a scheme of our own on the go:
/// drawing security's attention is the last thing we want.
/datum/ai_controller/sp_crew/proc/reports_crimes()
	return isnull(blackboard[BB_SP_SCHEME])

/// Whether we shut a locker again after going through it. A greytider leaves it hanging open.
/datum/ai_controller/sp_crew/proc/closes_lockers()
	return TRUE

/// How many things we take from one locker.
/datum/ai_controller/sp_crew/proc/rummage_take_limit()
	return SP_RUMMAGE_TAKE_LIMIT

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

/// Being seen out of medbay (sp_see_out()): for a while our route may go through its doors.
/datum/ai_controller/sp_crew/get_access()
	. = ..()
	if(blackboard[BB_SP_SHOWN_OUT_UNTIL] > world.time)
		var/list/ours = islist(.) ? . : list()
		. = ours | SSid_access.get_region_access_list(list(REGION_MEDBAY))

/datum/ai_controller/sp_crew/UnpossessPawn(destroy)
	forget_conversation()
	if(!isnull(pawn))
		REMOVE_TRAIT(pawn, TRAIT_NOHUNGER, SP_CREW_TRAIT)
		UnregisterSignal(pawn, list(COMSIG_ATOM_WAS_ATTACKED, COMSIG_MOVABLE_PRE_HEAR, COMSIG_MOVABLE_BUMP, COMSIG_ATOM_EXAMINE, COMSIG_MOB_INCAPACITATE_CHANGED, COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED))
	return ..()

/**
 * Walked into something. A closed firelock is pushed open, the way a crew member would, so we can keep going;
 * an animal that will not let us past is stepped round.
 */
/datum/ai_controller/sp_crew/proc/on_bump(datum/source, atom/bumped)
	SIGNAL_HANDLER
	var/obj/machinery/door/firedoor/firelock = bumped
	if(istype(firelock))
		if(firelock.density && !firelock.welded)
			INVOKE_ASYNC(firelock, TYPE_PROC_REF(/obj/machinery/door, open))
		return
	var/obj/machinery/door/airlock/airlock = bumped
	if(istype(airlock) && sp_buzz_through(pawn, airlock))
		return
	var/mob/living/animal = bumped
	if(isliving(animal) && !ishuman(animal) && sp_animal_in_the_way(animal))
		sp_step_past(pawn, animal)

/**
 * An animal that is only in the way: one TG will not swap places with (it is in combat mode, as basic mobs
 * are), not fixed in place, and not after anybody. The HoS's giant spider sits beside the desk, in the one
 * gap between the tables and the security consoles, and the pathfinder, which ignores mobs, plans straight
 * through it; the HoS bumped into their own pet until every walk gave up, all shift. People step round a pet
 * that will not budge.
 */
/proc/sp_animal_in_the_way(mob/living/animal)
	if(animal.stat == DEAD || animal.anchored || animal.buckled || animal.has_buckled_mobs())
		return FALSE
	if(!animal.combat_mode && !HAS_TRAIT(animal, TRAIT_NOMOBSWAP))
		return FALSE // TG swaps places with it by itself, and would only swap us straight back
	return isnull(animal.ai_controller?.blackboard[BB_CURRENT_TARGET])

/// Swaps places with an animal in the way, the way mobs swap places when neither minds.
/proc/sp_step_past(mob/living/walker, mob/living/animal)
	var/turf/ours = get_turf(walker)
	var/turf/theirs = get_turf(animal)
	if(isnull(ours) || isnull(theirs) || get_dist(ours, theirs) != 1)
		return FALSE
	animal.forceMove(ours)
	walker.forceMove(theirs)
	sp_record("crew.stepped_past")
	log_sp("[walker.real_name] stepped past [animal] in [get_area_name(theirs)]")
	return TRUE

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
	forget_conversation()

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
			// An order from the head of security rides the same rails. Each order is acted on once per listener,
			// keyed by when it was issued: the first thing heard from the issuer afterwards is the order line itself.
			// Anything else they say while it is still fresh falls through to the incident, distress and conversation
			// checks below. Before this, every word from the HoS for five seconds after an order was swallowed as that
			// order -- attacks they reported included. Matching the spoken text instead would fail for an injured
			// speaker, whose line say() cuts short with an ellipsis.
			var/list/order = other.blackboard[BB_SP_LAST_ORDER]
			if(length(order) && world.time - order[SP_ORDER_TIME] < SP_ORDER_FRESH && blackboard[BB_SP_LAST_ORDER_HEARD] != order[SP_ORDER_TIME])
				set_blackboard_key(BB_SP_LAST_ORDER_HEARD, order[SP_ORDER_TIME])
				on_heard_order(human_speaker, order)
				return
			var/list/incident = other.blackboard[BB_SP_LAST_INCIDENT]
			if(length(incident) && world.time - incident[SP_INCIDENT_TIME] < 5 SECONDS)
				on_heard_incident(human_speaker, incident)
				return
	// A player calling for help. AI crew report trouble through the structured incident above, which returns
	// before this, so their ordinary talk must never be read for distress words: "I'd kill for a decent meal"
	// sent every officer in earshot to the scene, and "All security staff, on me" did the same to a briefing.
	if(isliving(real_speaker) && !istype(real_speaker.ai_controller, /datum/ai_controller/sp_crew) && sp_message_is_distress(raw_message))
		on_heard_distress(real_speaker, raw_message, is_radio)

	if(is_radio || !isliving(real_speaker) || real_speaker == pawn)
		return
	consider_conversation(real_speaker, raw_message)

/**
 * Decides whether something said nearby was meant for us, and what to do about it.
 *
 * Crew talk to each other through written threads, which say both sides' lines themselves, so a crew member's
 * line is never ours to answer, and nor is anything a player says to somebody they are already talking to.
 * A player's line is ours when they use our name, or say something plainly aimed at a person and we are the
 * nearest crew member free to take it (sp_first_to_answer()). A line that opens a written conversation starts
 * one; anything else gets a line back; our name and nothing more gets a look up.
 */
/datum/ai_controller/sp_crew/proc/consider_conversation(mob/living/speaker, raw_message)
	if(istype(speaker.ai_controller, /datum/ai_controller/sp_crew))
		return
	// Somebody mid-conversation is answering it, unless they have turned to us by name: a player with an
	// introduction still pending from one crew member used to be ignored by everybody else until it lapsed.
	if(sp_in_any_thread(speaker) && !sp_named(sp_words(raw_message), pawn))
		return
	if(!free_to_talk(speaker))
		brush_off(speaker, raw_message)
		return
	var/list/words = sp_words(raw_message)
	sp_notice_id(src, speaker)
	if(sp_introduces_self(words, speaker))
		sp_learn_name(src, speaker)
	var/intent = sp_speech_intent(words)
	if(sp_named(words, pawn))
		if(isnull(intent))
			set_blackboard_key(BB_SP_GREET_COOLDOWN, world.time + SP_REPLY_GAP)
			set_blackboard_key(BB_SP_CHAT_ASKED_AT, world.time)
			set_blackboard_key(BB_SP_ATTENTION_TARGET, speaker)
			return
	else if(isnull(intent) || !sp_first_to_answer(pawn, speaker, words))
		return
	var/mob/living/carbon/human/human_pawn = pawn
	var/mob/living/carbon/human/human_speaker = speaker
	if(istype(human_pawn) && istype(human_speaker))
		var/datum/sp_dialogue/opened = sp_pick_dialogue(human_pawn, human_speaker, intent)
		if(!isnull(sp_start_thread(src, opened, human_pawn, human_speaker)))
			set_blackboard_key(BB_SP_GREET_COOLDOWN, world.time + SP_REPLY_GAP)
			return
	queue_reply(speaker, raw_message)

/**
 * Whether we could take up something said to us right now. A line we have already taken up -- as an answer
 * owed or a conversation started -- still leaves us free for that same line from that same speaker, because
 * listeners decide one after another (sp_first_to_answer()).
 */
/datum/ai_controller/sp_crew/proc/free_to_talk(mob/living/speaker)
	var/mob/living/carbon/human/human_pawn = pawn
	if(!istype(human_pawn) || human_pawn.stat != STABLE || human_pawn.client || busy_with_work())
		return FALSE
	if(blackboard_key_exists(BB_SP_IN_THREAD))
		return FALSE
	var/owed = blackboard[BB_SP_CHAT_REPLY_DUE] || blackboard[BB_SP_ATTENTION_TARGET]
	var/datum/sp_dialogue_thread/thread = blackboard[BB_SP_THREAD]
	if(!isnull(thread))
		owed = sp_dialogue_other(thread, pawn)
	if(!isnull(owed))
		return owed == speaker && blackboard[BB_SP_CHAT_ASKED_AT] == world.time
	var/ready_at = blackboard[BB_SP_GREET_COOLDOWN]
	return isnull(ready_at) || ready_at <= world.time

/**
 * Too busy to talk, but not too busy to say so. A crew member mid-job does not stop for a chat -- that rule is
 * why a medic keeps walking a patient to the table -- but a player met with silence cannot tell busy from
 * broken. The stand-in found exactly that on its first visit: a chemist on a delivery, greeted by name, and
 * nothing. So a player who names somebody busy gets a word over the shoulder, once in a while, and the job
 * carries on untouched.
 */
/datum/ai_controller/sp_crew/proc/brush_off(mob/living/speaker, raw_message)
	var/mob/living/carbon/human/human_pawn = pawn
	if(!istype(human_pawn) || human_pawn.stat != STABLE || human_pawn.client || !sp_is_playing(speaker))
		return
	if(!sp_named(sp_words(raw_message), pawn))
		return
	if(!busy_with_work() && !blackboard_key_exists(BB_SP_THREAD) && !blackboard_key_exists(BB_SP_IN_THREAD))
		return // only between answers, not busy: the next line will be taken up
	var/said_at = blackboard[BB_SP_BRUSHED_OFF_AT]
	if(!isnull(said_at) && world.time - said_at < SP_BRUSH_OFF_GAP)
		return
	set_blackboard_key(BB_SP_BRUSHED_OFF_AT, world.time)
	var/their_name = sp_knows_name(src, speaker) ? sp_first_name(speaker) : sp_dialogue_stranger(human_pawn)
	human_pawn.face_atom(speaker)
	sp_crew_speak(human_pawn, pick(
		"Bit busy, [their_name]. Give me a minute.",
		"Can't stop, sorry.",
		"In the middle of something, [their_name]. Catch me after?",
		"One thing at a time, [their_name].",
	))
	sp_record("talk.brushed_off")

/// Owes `speaker` a one-line answer to `raw_message`.
/datum/ai_controller/sp_crew/proc/queue_reply(mob/living/speaker, raw_message)
	set_blackboard_key(BB_SP_GREET_COOLDOWN, world.time + SP_REPLY_GAP)
	set_blackboard_key(BB_SP_CHAT_ASKED_AT, world.time)
	set_blackboard_key(BB_SP_CHAT_HEARD, raw_message)
	set_blackboard_key(BB_SP_CHAT_REPLY_DUE, speaker)

/// Drops every conversation in hand: a thread we are running, and anything we owed somebody an answer to.
/datum/ai_controller/sp_crew/proc/forget_conversation()
	var/datum/sp_dialogue_thread/thread = blackboard[BB_SP_THREAD]
	if(!isnull(thread))
		sp_end_dialogue(src, thread)
	var/static/list/chat_keys = list(BB_SP_CHAT_PARTNER, BB_SP_CHAT_REPLY_DUE, BB_SP_CHAT_HEARD, BB_SP_CHAT_ASKED_AT, BB_SP_ATTENTION_TARGET)
	for(var/key in chat_keys)
		clear_blackboard_key(key)

/**
 * Whether we are in the middle of a job that a chat should not pull us off. A reply outranks the job
 * subtrees and aborts them, and an async job — a brew, an operation — keeps running after the abort while
 * the tree starts it over, so it can end up running twice at the same bench. In the third live round the
 * CMO stopped walking a patient to the table to answer a doctor's idle question. Base crew are never busy.
 */
/datum/ai_controller/sp_crew/proc/busy_with_work()
	return FALSE

/// A player has taken our job and we are going off shift (sp_send_off_shift): let go of anything held for work.
/datum/ai_controller/sp_crew/proc/on_sent_off_shift()
	return

/// Somebody gave an order over the radio. Most of the crew are not in anybody's department and ignore it.
/datum/ai_controller/sp_crew/proc/on_heard_order(mob/living/carbon/human/issuer, list/order)
	return

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
		/area/station/medical/cryo,
		// Every map names its operating theatres differently; the ones missing from this one are skipped.
		/area/station/medical/surgery,
		/area/station/medical/surgery/fore,
		/area/station/medical/surgery/aft,
		/area/station/medical/surgery/theatre,
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

/**
 * Keeps an eye on a cryo tube we put somebody in. The tube lets them out by itself once they are mended
 * (or dead, or the gas runs out), and this is how the round's tally hears about it.
 */
/datum/ai_controller/sp_crew/medical/proc/watch_cryo(obj/machinery/cryo_cell/cryo)
	RegisterSignal(cryo, COMSIG_ATOM_EXITED, PROC_REF(on_cryo_exited), override = TRUE)

/datum/ai_controller/sp_crew/medical/proc/on_cryo_exited(obj/machinery/cryo_cell/source, atom/movable/gone, direction)
	SIGNAL_HANDLER
	var/mob/living/carbon/patient = gone
	// The beaker leaving counts as an exit too.
	if(!iscarbon(patient))
		return
	UnregisterSignal(source, COMSIG_ATOM_EXITED)
	sp_release_patient(patient, pawn)
	sp_record(patient.stat == DEAD ? "med.cryo_lost" : "med.cryo_discharged")
	log_sp("[patient.real_name] came out of [source.name] at [round(sp_patch_damage(patient), 1)] brute and burn[patient.stat == DEAD ? ", dead" : ""]")

/**
 * A medic with a patient has their hands full. Only the patient counts: sp_find_patient clears it whenever
 * there is nobody to see, where a cryo setup job can be left set by a walk that failed, which would keep the
 * medic "busy" all shift. A setup job is a few quick clicks, and one started over does no harm.
 */
/datum/ai_controller/sp_crew/medical/busy_with_work()
	return blackboard_key_exists(BB_SP_PATIENT)

/// Going off shift with a patient: they are unstrapped from the table and no longer told to wait for us.
/datum/ai_controller/sp_crew/medical/on_sent_off_shift()
	var/mob/living/carbon/patient = blackboard[BB_SP_PATIENT]
	if(!istype(patient))
		return
	if(istype(patient.buckled, /obj/structure/table/optable))
		patient.buckled.unbuckle_mob(patient)
	sp_release_patient(patient, pawn)

/// Chemists: brew medicine for medbay and keep the cryo tubes in cryoxadone; otherwise medical staff like the rest.
/datum/ai_controller/sp_crew/medical/chemist
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_chemist.bt.json"

/datum/ai_controller/sp_crew/medical/chemist/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	var/static/list/lab_areas = list(
		/area/station/medical/chemistry,
		/area/station/medical/pharmacy,
	)
	set_blackboard_key(BB_SP_WANDER_AREAS, lab_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Nobody touch the dispenser.",
			"Who left a beaker of acid on the bench?",
			"If it's glowing, don't drink it.",
			"Patches are in the chem fridge.",
		),
		BB_EMOTE_SEE = list("holds a beaker up to the light.", "writes out a label."),
	))

/// TG hands a chemist a dropper and a bottle of buffer, and nothing to brew in.
/datum/ai_controller/sp_crew/medical/chemist/equip_extra_gear(mob/living/carbon/human/human_pawn)
	for(var/beaker_type in list(/obj/item/reagent_containers/cup/beaker/large, /obj/item/reagent_containers/cup/beaker))
		human_pawn.equip_to_storage(new beaker_type(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)

/// A chemist with an order in hand is at the bench, or on the way to it.
/datum/ai_controller/sp_crew/medical/chemist/busy_with_work()
	return ..() || blackboard_key_exists(BB_SP_CHEM_PRODUCT)

/**
 * Assistants: no department, no work, and the whole shift to fill. Everything the rest of the crew do, plus a
 * trip to tool storage for gloves and a tool, lockers left hanging open, cheekier grumbling at locked doors,
 * and a little harmless mischief now and then (sp_greytide.dm). Greytide, gently.
 */
/datum/ai_controller/sp_crew/assistant
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_assistant.bt.json"

/datum/ai_controller/sp_crew/assistant/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	set_blackboard_key(BB_SP_WANDER_AREAS, sp_greytide_haunts())
	override_blackboard_key(BB_SP_INTERESTS, sp_greytide_interests())
	// Some of them have a bit of an edge, and will break a light where the harmless lot only draw on the floor.
	// Logged either way: without it, a round with no vandalism in it reads the same whether nobody was in the
	// mood or nobody had the streak to begin with, and that is exactly the silence the tally exists to break.
	if(prob(SP_TROUBLEMAKER_CHANCE))
		set_blackboard_key(BB_SP_TROUBLEMAKER, TRUE)
		log_sp("[human_pawn.real_name] has a bit of an edge to them: a troublemaker")
	else
		log_sp("[human_pawn.real_name] is the harmless sort of assistant")
	// The first prank waits until they have had a look round and been to tool storage.
	set_blackboard_key(BB_SP_MISCHIEF_NEXT, world.time + rand(2 MINUTES, 4 MINUTES))
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Anyone got a spare pair of insuls?",
			"I'm not loitering. I'm waiting.",
			"What does this button do?",
			"HoP, any chance of all access?",
			"Maintenance is the best part of the station.",
			"I'm basically an engineer.",
		),
		BB_EMOTE_SEE = list("fidgets with a crayon.", "looks around for something to do.", "whistles innocently."),
	))

/// Every assistant brings a crayon, and about half of them a horn or a rubber duck as well.
/datum/ai_controller/sp_crew/assistant/equip_extra_gear(mob/living/carbon/human/human_pawn)
	var/static/list/crayons = list(
		/obj/item/toy/crayon/red,
		/obj/item/toy/crayon/orange,
		/obj/item/toy/crayon/yellow,
		/obj/item/toy/crayon/green,
		/obj/item/toy/crayon/blue,
		/obj/item/toy/crayon/purple,
	)
	var/list/extras = list(pick(crayons))
	if(prob(50))
		extras += pick(/obj/item/bikehorn, /obj/item/bikehorn/rubberducky)
	for(var/extra_type in extras)
		human_pawn.equip_to_storage(new extra_type(human_pawn), ITEM_SLOT_BACK, indirect_action = TRUE, del_on_fail = TRUE)

/datum/ai_controller/sp_crew/assistant/closes_lockers()
	return FALSE

/datum/ai_controller/sp_crew/assistant/rummage_take_limit()
	return SP_GREYTIDE_TAKE_LIMIT

/// A prank under way is not dropped for a chat: the lights have to come back on.
/datum/ai_controller/sp_crew/assistant/busy_with_work()
	return blackboard_key_exists(BB_SP_PRANKING)

/// Assistants do not grass on each other, or on anybody else.
/datum/ai_controller/sp_crew/assistant/reports_crimes()
	return FALSE

/datum/ai_controller/sp_crew/assistant/on_door_denied(obj/machinery/door/airlock/door)
	var/mob/living/carbon/human/human_pawn = pawn
	var/quiet_until = blackboard[BB_SP_NOSY_SPEAK_COOLDOWN] || 0
	if(!istype(human_pawn) || world.time < quiet_until)
		return
	set_blackboard_key(BB_SP_NOSY_SPEAK_COOLDOWN, world.time + 45 SECONDS)
	sp_crew_speak(human_pawn, pick(
		"Aw, come on. I only want a look.",
		"One of these days I'm getting in there.",
		"What are they hiding in there, anyway?",
		"Rude.",
	))

/// Security: patrol hallways and the brig, respond to reports, subdue and cuff attackers.
/datum/ai_controller/sp_crew/security
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_security.bt.json"

/**
 * The belt from their own locker (ACCESS_BRIG, eleven of them on MetaStation), because the baton is inside
 * it and the officer outfit has none -- sp_equip_item/baton has been failing since the fork began, which is
 * why an officer who empties a disabler ends up punching people.
 */
/datum/ai_controller/sp_crew/security/kit_wanted()
	return list(/obj/item/storage/belt/security = /obj/structure/closet/secure_closet/security/sec)

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

/**
 * An officer is on duty while any of this is in hand. Answers sit below security work in the tree, so a chat
 * cannot interrupt an arrest -- but one taken up now would only be given once the arrest was over.
 */
/datum/ai_controller/sp_crew/security/busy_with_work()
	var/static/list/duty_keys = list(BB_SP_INCIDENT_TARGET, BB_SP_INCIDENT_LOCATION, BB_SP_SUSPECT, BB_SP_PRISONER, BB_SP_ARM_ORDER)
	for(var/key in duty_keys)
		if(blackboard_key_exists(key))
			return TRUE
	return blackboard[BB_SP_MEETING_UNTIL] > world.time

/**
 * Officers, the warden and the detective answer to the head of security.
 *
 * Only the orders are taken here; acting on them is the tree's business. An order to arm or to go lethal
 * outlives the briefing on purpose -- it is stood down, not forgotten, so a red shift stays a red shift.
 */
/datum/ai_controller/sp_crew/security/on_heard_order(mob/living/carbon/human/issuer, list/order)
	if(issuer == pawn)
		return
	var/kind = order[SP_ORDER_KIND]
	switch(kind)
		if(SP_ORDER_MEETING)
			var/turf/where = order[SP_ORDER_WHERE]
			if(isnull(where))
				return
			set_blackboard_key(BB_SP_MEETING_SPOT, where)
			set_blackboard_key(BB_SP_MEETING_UNTIL, world.time + SP_MEETING_TIME)
		if(SP_ORDER_ARM)
			set_blackboard_key(BB_SP_ARM_ORDER, TRUE)
		if(SP_ORDER_LETHAL)
			set_blackboard_key(BB_SP_USE_LETHALS, TRUE)
		if(SP_ORDER_STAND_DOWN)
			// Only the heavy weapon is put away. BB_SP_ARM_ORDER has come to mean "fetch what you lack" and ends
			// itself once nothing is wanted; clearing it here cancelled every officer's belt trip at the first
			// briefing, which the HoS gives on their very first tick.
			clear_blackboard_key(BB_SP_USE_LETHALS)
		else
			return
	sp_record("sec.order_heard")
	log_sp("[pawn?.name] took [kind] from [issuer.real_name]")

/datum/ai_controller/sp_crew/security/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	if(reporter == pawn)
		return
	var/datum/weakref/attacker_ref = incident[SP_INCIDENT_ATTACKER]
	var/mob/living/attacker = attacker_ref?.resolve()
	var/turf/where = incident[SP_INCIDENT_TURF]
	// Somebody being taken in calls it in as an attack, and they are not wrong: the officer did hit them.
	// Acting on it turns one arrest into a brawl. In a live round an officer moved in, the suspect radioed
	// it, every other officer took the arresting officer for an attacker, and four of them fought each other
	// in the aft hallway while the suspect wandered off to try the mech bay door.
	if(ishuman(attacker) && sp_is_authority(attacker) && sp_is_arresting(attacker, reporter))
		return
	if(!isnull(attacker) && attacker != pawn)
		set_blackboard_key(BB_SP_INCIDENT_TARGET, attacker)
	if(!isnull(where))
		set_blackboard_key(BB_SP_INCIDENT_LOCATION, where)
	// Nobody is being hit: somebody took something, or broke something, and a witness named them. That is worth
	// a word and a note on their record, not a baton — the arrest ladder is in sp_confront_suspect().
	if(isnull(attacker))
		var/datum/weakref/suspect_ref = incident[SP_INCIDENT_SUSPECT]
		var/mob/living/suspect = suspect_ref?.resolve()
		if(!isnull(suspect) && suspect != pawn)
			set_blackboard_key(BB_SP_SUSPECT, suspect)
			set_blackboard_key(BB_SP_SUSPECT_CRIME, incident[SP_INCIDENT_CRIME])
	acknowledge_report()

/datum/ai_controller/sp_crew/security/on_heard_distress(mob/living/speaker, raw_message, is_radio)
	if(speaker == pawn || blackboard_key_exists(BB_SP_INCIDENT_TARGET))
		return
	// Shouting for help while being taken in is not an emergency for the rest of the department.
	if(sp_wanted_for_arrest(speaker))
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

/**
 * Somebody asking botany for a plant, over the radio or across the room: remember what and where, so the
 * next load goes to them rather than the kitchen. Medbay asks for aloe when they run out of burn cream.
 */
/datum/ai_controller/sp_crew/botanist/on_pre_hear(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	. = ..()
	var/mob/living/carbon/human/human_pawn = pawn
	var/atom/movable/speaker = hearing_args[HEARING_SPEAKER]
	var/raw_message = hearing_args[HEARING_RAW_MESSAGE]
	if(!istype(human_pawn) || QDELETED(speaker) || speaker == human_pawn || !istext(raw_message))
		return
	var/plant = sp_plant_asked_for(raw_message)
	if(isnull(plant))
		return
	var/atom/movable/real_speaker = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/virtual = speaker
		real_speaker = virtual.source || speaker
	var/area/where = get_area(real_speaker)
	if(isnull(where))
		return
	set_blackboard_key(BB_SP_PLANT_REQUEST, plant)
	// Where they said to send it, if they said ("up to medbay"); otherwise wherever they are standing.
	var/deliver_to = sp_named_delivery_area(raw_message) || where.type
	set_blackboard_key(BB_SP_PLANT_REQUEST_AREA, deliver_to)
	if(ismob(real_speaker))
		set_blackboard_key(BB_SP_PLANT_REQUESTER, real_speaker)
	else
		clear_blackboard_key(BB_SP_PLANT_REQUESTER)
	log_sp("[human_pawn.real_name] took a request for [plant] from [real_speaker] in [where.name], to go to [deliver_to]")
	sp_crew_speak(human_pawn, pick(
		"[capitalize(plant)]? I will see what I have got.",
		"Someone wants [plant]. I will bring some over.",
	), RADIO_CHANNEL_COMMON)

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

/**
 * Takes an order. Anyone standing at the bar naming a drink gets it made, whether they are a player or
 * one of the crew — the bartender is not fussy about who is asking, only about what.
 */
/datum/ai_controller/sp_crew/bartender/on_pre_hear(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	. = ..()
	var/atom/movable/speaker = hearing_args[HEARING_SPEAKER]
	var/raw_message = hearing_args[HEARING_RAW_MESSAGE]
	if(QDELETED(speaker) || speaker == pawn || !istext(raw_message) || !isnull(hearing_args[HEARING_RADIO_FREQ]))
		return
	if(!isnull(blackboard[BB_SP_DRINK_ORDER]))
		return // one at a time; the glass in hand comes first
	var/datum/sp_cocktail/ordered = sp_drink_from_order(raw_message)
	if(isnull(ordered))
		return
	set_blackboard_key(BB_SP_DRINK_ORDER, ordered)
	set_blackboard_key(BB_SP_ORDER_FOR, speaker.name)
	INVOKE_ASYNC(src, PROC_REF(acknowledge_order), ordered, speaker.name)

/// Says the order back, which is half of what a bartender is for.
/datum/ai_controller/sp_crew/bartender/proc/acknowledge_order(datum/sp_cocktail/ordered, who)
	var/mob/living/carbon/human/human_pawn = pawn
	if(!istype(human_pawn))
		return
	log_sp("[human_pawn.real_name] took an order for [ordered.name] from [who]")
	sp_record("bar.ordered")
	sp_crew_speak(human_pawn, pick(
		"[ordered.name] coming up, [who].",
		"One [ordered.name] for [who].",
		"[ordered.name]? Give me a minute.",
	))

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
