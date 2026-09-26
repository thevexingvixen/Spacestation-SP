/**
 * Crime, witnesses, and what happens when somebody sees.
 *
 * Shared by the greytide's malicious streak and the antagonists. Nothing here decides to commit a crime: it
 * answers the two questions anyone about to has to ask first. Who would see? And what happens if they do?
 *
 * A crime somebody sees is called out to the culprit's face, held against them, and reported to security over the
 * radio as a place to go and look rather than a name to beat. Security's baton is for people who hit people
 * (sp_security_respond.bt.json); a smashed light is not that.
 */

/// What a witness shouts at the culprit, by crime.
GLOBAL_LIST_INIT(sp_crime_callouts, list(
	SP_CRIME_THEFT = list("Hey! Put that back!", "Oi, that's not yours!", "I saw that!"),
	SP_CRIME_VANDALISM = list("Hey! Stop wrecking the place!", "Oi! What did that ever do to you?", "Someone has to fix that, you know!"),
	SP_CRIME_TRESPASS = list("You're not supposed to be in here!", "Oi! Staff only!", "How did you get in here?"),
))

/// Everyone awake who could see `culprit` right now, AI crew and players alike, other than the culprit.
/proc/sp_witnesses(mob/living/culprit, range = SP_WITNESS_RANGE)
	var/list/mob/living/carbon/human/seen_by = list()
	if(QDELETED(culprit) || !isturf(culprit.loc))
		return seen_by
	for(var/mob/living/carbon/human/other in viewers(range, culprit))
		if(other == culprit || other.stat != STABLE || other.is_blind())
			continue
		seen_by += other
	return seen_by

/**
 * The witnesses who would do something about it: any player, since a player might, and AI crew who report crimes
 * at all. Assistants do not grass on each other, and anyone with a scheme of their own keeps their head down.
 */
/proc/sp_crime_witnesses(mob/living/culprit, range = SP_WITNESS_RANGE)
	var/list/mob/living/carbon/human/would_tell = list()
	for(var/mob/living/carbon/human/other as anything in sp_witnesses(culprit, range))
		var/datum/ai_controller/sp_crew/their_ai = other.ai_controller
		if(istype(their_ai) && !their_ai.reports_crimes())
			continue
		would_tell += other
	return would_tell

/**
 * Somebody might have seen that. Each AI crew member who would tell gets a chance to notice, in no particular
 * order, and the first who does calls it out (sp_call_out_crime()). Players see it for themselves. Returns whoever
 * noticed, or null.
 *
 * * crime - SP_CRIME_*
 * * description - what they were seen doing, to follow "saw them": "smash a light", "take a stamp off the desk"
 * * where - the scene
 * * notice_chance - the chance each witness actually notices
 * * taken - for a theft, the thing taken, so an officer can ask for it back by name (sp_search.dm)
 */
/proc/sp_crime_seen(mob/living/culprit, crime, description, atom/where, notice_chance = SP_WITNESS_NOTICE_CHANCE, obj/item/taken)
	if(QDELETED(culprit))
		return null
	for(var/mob/living/carbon/human/witness as anything in shuffle(sp_crime_witnesses(culprit)))
		var/datum/ai_controller/sp_crew/their_ai = witness.ai_controller
		if(!istype(their_ai) || !prob(notice_chance))
			continue
		sp_call_out_crime(their_ai, culprit, crime, description, where, taken)
		return witness
	return null

/**
 * A witness calls out what they saw and holds it against the culprit; with a headset, they also tell security where.
 * The report names a suspect but no attacker, so officers who hear it walk over and look rather than reach for a baton.
 */
/proc/sp_call_out_crime(datum/ai_controller/sp_crew/controller, mob/living/culprit, crime, description, atom/where, obj/item/taken)
	var/mob/living/carbon/human/witness = controller.pawn
	var/area/scene = get_area(where)
	var/place = scene ? scene.name : "the station"
	sp_adjust_reputation(controller, culprit, SP_WITNESS_REPUTATION_HIT, "saw them [description]")
	sp_record("crime.[crime]_seen")
	log_sp("[witness.real_name] saw [culprit.real_name] [description] in [place]")
	// One witness does not narrate a spree: after calling one out, they keep what they see to themselves a while.
	if(world.time < (controller.blackboard[BB_SP_CRIME_CALLOUT_COOLDOWN] || 0))
		return
	controller.set_blackboard_key(BB_SP_CRIME_CALLOUT_COOLDOWN, world.time + SP_CRIME_CALLOUT_COOLDOWN)
	var/list/lines = GLOB.sp_crime_callouts[crime]
	sp_crew_speak(witness, length(lines) ? pick(lines) : "Hey! I saw that!")
	if(!istype(witness.ears, /obj/item/radio/headset))
		return
	controller.override_blackboard_key(BB_SP_LAST_INCIDENT, list(
		SP_INCIDENT_ATTACKER = null,
		SP_INCIDENT_SUSPECT = WEAKREF(culprit),
		SP_INCIDENT_VICTIM = WEAKREF(witness),
		SP_INCIDENT_TURF = get_turf(where),
		SP_INCIDENT_TIME = world.time,
		SP_INCIDENT_CRIME = crime,
		SP_INCIDENT_ITEM = QDELETED(taken) ? null : WEAKREF(taken),
	))
	sp_crew_speak(witness, "Security, I just saw [culprit.name] [description] in [place].", RADIO_CHANNEL_COMMON)

// --- The record ------------------------------------------------------------------------------------

/// What a crime is called on a security record.
GLOBAL_LIST_INIT(sp_crime_record_names, list(
	SP_CRIME_THEFT = "Theft",
	SP_CRIME_VANDALISM = "Vandalism",
	SP_CRIME_TRESPASS = "Trespass",
))

/**
 * Writes a witnessed crime onto the suspect's security record, the way an officer would at the console, and
 * hands back how many crimes they now have against their name (0 if they have no record at all — a visitor,
 * or anyone the manifest never learned about).
 *
 * The wanted status is deliberately left alone on a first offence: flagging Arrest puts every secbot on
 * the station onto somebody for a smashed light tube. Repeat offenders are escalated in sp_confront_suspect(), once
 * the record itself shows a pattern. An earlier version of this note said TG has no Suspected status; it does,
 * WANTED_SUSPECT, and whether first offences should use it is a design question rather than a gap.
 */
/proc/sp_file_crime_record(mob/living/suspect, crime, details, mob/living/officer)
	if(QDELETED(suspect))
		return 0
	var/suspect_name = suspect.real_name
	var/datum/record/crew/record = find_record(suspect_name)
	if(isnull(record))
		return 0
	var/crime_name = GLOB.sp_crime_record_names[crime] || "Misconduct"
	record.crimes += new /datum/crime(crime_name, details, officer?.real_name || "Security")
	update_matching_security_huds(suspect_name)
	sp_record("sec.recorded")
	log_sp("[officer?.real_name || "security"] filed [crime_name] against [suspect_name] ([length(record.crimes)] on record)")
	return length(record.crimes)

/// Puts somebody on the arrest list, so an officer meeting them later already knows, and the secbots too.
/proc/sp_mark_for_arrest(mob/living/suspect)
	var/datum/record/crew/record = find_record(suspect?.real_name)
	if(isnull(record) || record.wanted_status == WANTED_ARREST)
		return FALSE
	record.wanted_status = WANTED_ARREST
	update_matching_security_huds(suspect.real_name)
	sp_record("sec.arrest_ordered")
	return TRUE

// --- The cell --------------------------------------------------------------------------------------

/**
 * How long the cell door stays shut, measured by what is already on their record.
 *
 * Somebody with no record serves nothing, which is not an oversight: the ladder in sp_confront_suspect()
 * only reaches an arrest once the record shows a pattern, so by the time anyone is walked to a cell there is
 * something written down to measure. The cap sits under the door timer's own MAX_TIMER because set_timer()
 * clamps without saying so, and a sentence the machine quietly shortened would be worse than a short one.
 */
/proc/sp_sentence_time(mob/living/suspect)
	var/datum/record/crew/record = find_record(suspect?.real_name)
	var/crimes = length(record?.crimes)
	if(!crimes)
		return 0
	return min(crimes * SP_SENTENCE_PER_CRIME, SP_SENTENCE_MAX)

/// The nearest cell nobody is already serving time in. A timer that is running has an occupant behind it.
/proc/sp_free_cell(mob/living/officer)
	var/obj/machinery/status_display/door_timer/best
	var/best_dist = INFINITY
	for(var/obj/machinery/status_display/door_timer/cell as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/status_display/door_timer))
		if(cell.timing || (cell.machine_stat & (NOPOWER|BROKEN)))
			continue
		var/turf/there = get_turf(cell)
		if(isnull(there) || !is_station_level(there.z))
			continue
		// No landmark inside means no way to say where the prisoner should end up, so it is not a cell we use.
		if(!length(sp_cell_doorway(cell)))
			continue
		var/dist = get_dist(officer, cell)
		if(dist >= best_dist)
			continue
		best = cell
		best_dist = dist
	return best

/**
 * The two tiles either side of a cell's door: just inside, and just outside.
 *
 * A brig windoor blocks movement across the edge its dir faces, so its own turf and get_step(turf, dir) are the
 * two sides, and the inside is the side of that edge the cell's brig locker stands on (plain distance ties for a
 * locker level with the door). The locker's own tile is no good as a
 * destination: a closed locker is dense, so nobody can be moved onto it, which is why the first version of this
 * never jailed anyone. Returns list(inside, outside), or null for a cell with no usable door and locker.
 */
/proc/sp_cell_doorway(obj/machinery/status_display/door_timer/timer)
	var/obj/structure/closet/secure_closet/brig/locker
	for(var/datum/weakref/closet_ref as anything in timer?.closets)
		var/obj/structure/closet/secure_closet/brig/candidate = closet_ref.resolve()
		if(!QDELETED(candidate))
			locker = candidate
			break
	var/turf/locker_turf = get_turf(locker)
	if(isnull(locker_turf))
		return null
	for(var/datum/weakref/door_ref as anything in timer.doors)
		var/obj/machinery/door/window/brigdoor/door = door_ref.resolve()
		if(!istype(door))
			continue
		var/turf/here = get_turf(door)
		var/turf/beyond = get_step(here, door.dir)
		if(isnull(here) || isnull(beyond))
			continue
		// How far the locker lies along the way the door faces: past the edge, or on the door's own side of it.
		var/toward = (locker_turf.x - here.x) * (beyond.x - here.x) + (locker_turf.y - here.y) * (beyond.y - here.y)
		var/turf/inside = toward > 0 ? beyond : here
		var/turf/outside = inside == here ? beyond : here
		if(sp_cell_tile_free(inside) && sp_cell_tile_free(outside))
			return list(inside, outside)
	return null

/// Somewhere a person can stand: not a wall, and nothing dense on it other than a door or another person.
/proc/sp_cell_tile_free(turf/tile)
	if(isnull(tile) || tile.density)
		return FALSE
	for(var/atom/movable/thing as anything in tile)
		if(thing.density && !istype(thing, /obj/machinery/door) && !ismob(thing))
			return FALSE
	return TRUE

/// Whether this person's record says they are to be taken in.
/proc/sp_wanted_for_arrest(mob/living/who)
	if(QDELETED(who))
		return FALSE
	var/datum/record/crew/record = find_record(who?.real_name)
	return record?.wanted_status == WANTED_ARREST

/**
 * Whether `officer` is in the middle of arresting `who`.
 *
 * Either they are the officer's current incident, or the record says they are wanted and the officer is
 * security. Both sides of that matter: an arrest in progress is not on anybody's record until it is called,
 * and a record outlives the officer who filed it.
 */
/proc/sp_is_arresting(mob/living/officer, mob/living/who)
	if(QDELETED(officer) || QDELETED(who))
		return FALSE
	var/datum/ai_controller/sp_crew/security/theirs = officer.ai_controller
	if(istype(theirs) && theirs.blackboard[BB_SP_INCIDENT_TARGET] == who)
		return TRUE
	return sp_wanted_for_arrest(who)

