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
 */
/proc/sp_crime_seen(mob/living/culprit, crime, description, atom/where, notice_chance = SP_WITNESS_NOTICE_CHANCE)
	if(QDELETED(culprit))
		return null
	for(var/mob/living/carbon/human/witness as anything in shuffle(sp_crime_witnesses(culprit)))
		var/datum/ai_controller/sp_crew/their_ai = witness.ai_controller
		if(!istype(their_ai) || !prob(notice_chance))
			continue
		sp_call_out_crime(their_ai, culprit, crime, description, where)
		return witness
	return null

/**
 * A witness calls out what they saw and holds it against the culprit; with a headset, they also tell security where.
 * The report names a suspect but no attacker, so officers who hear it walk over and look rather than reach for a baton.
 */
/proc/sp_call_out_crime(datum/ai_controller/sp_crew/controller, mob/living/culprit, crime, description, atom/where)
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
	controller.set_blackboard_key(BB_SP_LAST_INCIDENT, list(
		SP_INCIDENT_ATTACKER = null,
		SP_INCIDENT_SUSPECT = WEAKREF(culprit),
		SP_INCIDENT_VICTIM = WEAKREF(witness),
		SP_INCIDENT_TURF = get_turf(where),
		SP_INCIDENT_TIME = world.time,
		SP_INCIDENT_CRIME = crime,
	))
	sp_crew_speak(witness, "Security, I just saw [culprit.name] [description] in [place].", RADIO_CHANNEL_COMMON)
