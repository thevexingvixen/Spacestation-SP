/**
 * Bodies: who notices one, what they say, and what medbay and security do about it.
 *
 * Until now nobody noticed a corpse. A body found is called out and reported over the radio as one structured
 * incident (SP_INCIDENT_BODY) that two departments read their own way (ai/sp_body_behaviors.dm): a medic comes to it
 * and tries the defibrillator, and failing that takes it to the morgue; the head of security counts it as violence;
 * and the detective goes to look the scene over, reads what the dead and the things around them carry in
 * fingerprints, and names whoever left theirs. The antagonists' kill schemes (docs/03) are what this is for, but a
 * player who dies gets the same.
 */

/// Bodies already called out, keyed by ref, with when: one callout per body, and another only once it has lain there a while.
GLOBAL_LIST_EMPTY(sp_reported_bodies)
/// Bodies the detective has looked over, keyed by ref, with when.
GLOBAL_LIST_EMPTY(sp_investigated_bodies)
/// Bodies a medic found past reviving, keyed by ref, with when: the paddles are not tried on them again for a while.
GLOBAL_LIST_EMPTY(sp_body_verdicts)

/// A dead crew member lying somewhere, as opposed to one on a morgue tray, in a bag, or carried; monkeys are not crew.
/proc/sp_is_body(mob/living/carbon/human/who)
	return istype(who) && !ismonkey(who) && who.stat == DEAD && isturf(who.loc)

/// Whether this body wants calling out: not yet, or so long ago that it is plainly still lying there.
/proc/sp_body_unreported(mob/living/carbon/human/body)
	var/reported_at = GLOB.sp_reported_bodies[REF(body)]
	return isnull(reported_at) || world.time - reported_at > SP_BODY_REPORT_AGAIN

/**
 * A crew member has a body in sight. A medic takes it on themselves and the detective takes the scene; anybody says
 * so, and with a headset reports it (sp_body_seen()). Called every second by whoever can see it, so it has to be cheap
 * when there is nothing new to do.
 */
/proc/sp_notice_body(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/body)
	if(!istype(controller) || !sp_is_body(body))
		return
	var/datum/ai_controller/sp_crew/medical/medic = controller
	if(istype(medic))
		medic.take_body(body, null)
	var/datum/ai_controller/sp_crew/security/detective/detective = controller
	if(istype(detective))
		detective.take_scene(body)
	sp_body_seen(controller, body)

/**
 * A crew member has found a body. They say so, and with a headset report it over the radio as an incident with the
 * dead in it and nobody named, which medbay takes as a call to come and security as a scene. Returns TRUE if it was
 * reported; a body already called out is left to whoever is on their way.
 */
/proc/sp_body_seen(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/body)
	var/mob/living/carbon/human/witness = controller?.pawn
	if(!istype(witness) || witness.stat != STABLE || !sp_is_body(body) || !sp_body_unreported(body))
		return FALSE
	GLOB.sp_reported_bodies[REF(body)] = world.time
	var/area/scene = get_area(body)
	var/place = scene ? scene.name : "the station"
	sp_record("crew.body_seen")
	log_sp("[witness.real_name] found [body.real_name] dead in [place]")
	sp_station_event("body", body, body)
	if(!istype(witness.ears, /obj/item/radio/headset))
		sp_crew_speak(witness, pick("Oh no. [body.name]... somebody get help!", "[body.name]'s dead! Help!", "Is... is [body.name] breathing? Somebody!"))
		return TRUE
	controller.override_blackboard_key(BB_SP_LAST_INCIDENT, list(
		SP_INCIDENT_ATTACKER = null,
		SP_INCIDENT_SUSPECT = null,
		SP_INCIDENT_VICTIM = WEAKREF(body),
		SP_INCIDENT_BODY = WEAKREF(body),
		SP_INCIDENT_TURF = get_turf(body),
		SP_INCIDENT_TIME = world.time,
	))
	sp_crew_speak(witness, pick(
		"Medbay, security, [body.name] is dead in [place]!",
		"I need medbay in [place], [body.name] isn't breathing!",
		"Somebody get to [place], [body.name] is down and not moving!",
	), RADIO_CHANNEL_COMMON)
	return TRUE

/// A crew member by their real name, or null.
/proc/sp_crew_by_name(name)
	if(!istext(name))
		return null
	for(var/mob/living/carbon/human/person as anything in GLOB.human_list)
		if(person.real_name == name)
			return person
	return null

// --- The paddles ---------------------------------------------------------------------------------------

/// The defibrillator a medic carries, charged enough for a shock, or null.
/proc/sp_medic_defib(mob/living/carbon/human/medic)
	for(var/obj/item/defibrillator/unit as anything in medic?.get_all_contents_type(/obj/item/defibrillator))
		unit.update_power()
		if(unit.powered && !QDELETED(unit.paddles))
			return unit
	return null

/// What TG's verdict on a body means, for the log.
/proc/sp_defib_verdict(verdict)
	switch(verdict)
		if(DEFIB_POSSIBLE)
			return "revivable"
		if(DEFIB_FAIL_TISSUE_DAMAGE)
			return "tissue damage too severe"
		if(DEFIB_FAIL_HUSK)
			return "the body is a husk"
		if(DEFIB_FAIL_NO_HEART, DEFIB_FAIL_FAILING_HEART)
			return "the heart is gone or failing"
		if(DEFIB_FAIL_NO_BRAIN, DEFIB_FAIL_FAILING_BRAIN)
			return "the brain is gone or failing"
		if(DEFIB_FAIL_NO_INTELLIGENCE, DEFIB_FAIL_SUICIDE, DEFIB_FAIL_BLACKLISTED)
			return "nothing left to bring back"
		if(DEFIB_FAIL_GOLEM)
			return "inorganic"
	return "verdict [verdict]"

/**
 * One go with the paddles, the way a player does it: the paddles out of the unit, wielded in both hands, and placed on
 * the chest, which TG takes five seconds over. Only when TG itself says the body can be revived (can_defib()); on any
 * other body the paddles would only buzz, so the reason is logged and remembered instead. A body too far gone wants
 * repairing first, which is cryo or surgery on a corpse and is not written; it goes to the morgue (docs/03 §3).
 * Returns TRUE if the body came back. Sleeps.
 */
/proc/sp_try_revive(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/body)
	var/mob/living/carbon/human/medic = controller?.pawn
	if(!istype(medic) || !sp_is_body(body) || !medic.Adjacent(body))
		return FALSE
	var/verdict = body.can_defib()
	if(verdict != DEFIB_POSSIBLE)
		if(GLOB.sp_body_verdicts[REF(body)] != verdict)
			GLOB.sp_body_verdicts[REF(body)] = verdict
			sp_record("med.revive_impossible")
			log_sp("[medic.real_name] cannot revive [body.real_name]: [sp_defib_verdict(verdict)]")
		return FALSE
	var/obj/item/defibrillator/unit = sp_medic_defib(medic)
	if(isnull(unit))
		log_sp("[medic.real_name] has no charged defibrillator for [body.real_name]")
		return FALSE
	sp_free_hands(medic)
	if(!unit.on)
		unit.toggle_paddles(medic)
	var/obj/item/shockpaddles/paddles = unit.paddles
	if(QDELETED(paddles) || !medic.is_holding(paddles))
		log_sp("[medic.real_name] could not get the paddles off [unit]")
		sp_put_paddles_away(medic, unit)
		return FALSE
	if(!HAS_TRAIT(paddles, TRAIT_WIELDED))
		paddles.attack_self(medic)
	if(!HAS_TRAIT(paddles, TRAIT_WIELDED))
		log_sp("[medic.real_name] could not wield the paddles")
		sp_put_paddles_away(medic, unit)
		return FALSE
	medic.face_atom(body)
	medic.zone_selected = BODY_ZONE_CHEST
	sp_record("med.revive_tried")
	log_sp("[medic.real_name] is trying to revive [body.real_name] in [get_area_name(body)]")
	// TG's own routine from here: three seconds to place the paddles, two to charge, then the shock.
	sp_ai_click(controller, body)
	if(QDELETED(medic))
		return FALSE
	sp_put_paddles_away(medic, unit)
	if(QDELETED(body) || body.stat == DEAD)
		sp_record("med.revive_failed")
		log_sp("[medic.real_name]'s shock did not bring [body.real_name] back")
		return FALSE
	sp_record("med.revived")
	log_sp("[medic.real_name] revived [body.real_name] in [get_area_name(body)]")
	sp_crew_speak(medic, pick("[body.name]'s back with us. Stay down, I've got you.", "There we go. Don't try to get up, [body.name].", "Got a pulse. Easy now."))
	return TRUE

/// Puts the paddles back on the unit and the unit away.
/proc/sp_put_paddles_away(mob/living/carbon/human/medic, obj/item/defibrillator/unit)
	if(QDELETED(medic))
		return
	if(!QDELETED(unit) && unit.on)
		unit.toggle_paddles(medic)
	sp_free_hands(medic)

// --- The morgue -----------------------------------------------------------------------------------------

/// The nearest morgue tray on this level with nobody in it and nothing locking it, or null.
/proc/sp_find_morgue(atom/near)
	var/area/room = GLOB.areas_by_type[/area/station/medical/morgue]
	if(isnull(room) || isnull(near))
		return null
	var/obj/structure/bodycontainer/morgue/best
	for(var/turf/spot as anything in room.get_turfs_from_all_zlevels())
		if(spot.z != near.z)
			continue
		for(var/obj/structure/bodycontainer/morgue/slab in spot)
			if(slab.locked || QDELETED(slab.connected) || length(slab.get_all_contents_type(/mob/living)))
				continue
			if(isnull(best) || get_dist(near, slab) < get_dist(near, best))
				best = slab
	return best

/// The tile the tray slides out onto.
/proc/sp_morgue_tray_turf(obj/structure/bodycontainer/morgue/slab)
	return get_step(slab, slab.dir)

/**
 * An open tile to stand on beside the tray and within reach of the slab, nearest to `near`: never the tray's own
 * tile, which would take the medic in with the body, and never a tile in front of the tray, from which the slab
 * cannot be clicked (the first medic to reach the morgue stood there and could not get the tray out).
 */
/proc/sp_morgue_spot(obj/structure/bodycontainer/morgue/slab, atom/near)
	var/turf/front = sp_morgue_tray_turf(slab)
	if(isnull(front))
		return null
	var/turf/best
	for(var/turf/open/spot in range(1, front))
		if(spot == front || spot == get_turf(slab) || get_dist(spot, slab) > 1 || spot.is_blocked_turf(exclude_mobs = TRUE))
			continue
		if(isnull(best) || get_dist(near, spot) < get_dist(near, best))
			best = spot
	return best

/**
 * Puts a body on the morgue tray and shuts it: the slab opened, the body dragged onto the tray the way a player does
 * it, and the slab shut again. The medic stands beside the tray, never on it. Returns TRUE once the body is inside.
 * Sleeps.
 */
/proc/sp_store_in_morgue(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/body, obj/structure/bodycontainer/morgue/slab)
	var/mob/living/carbon/human/medic = controller?.pawn
	if(!istype(medic) || QDELETED(body) || QDELETED(slab) || QDELETED(slab.connected))
		return FALSE
	var/turf/front = sp_morgue_tray_turf(slab)
	if(isnull(front) || get_turf(medic) == front || get_dist(medic, front) > 1)
		return FALSE
	sp_free_hands(medic)
	if(slab.connected.loc == slab)
		sp_ai_click(controller, slab)
		// The slab will not shut again within a quarter second of opening; a click that fast does nothing at all.
		sleep(0.5 SECONDS)
	if(QDELETED(medic) || QDELETED(body) || QDELETED(slab))
		return FALSE
	if(slab.connected.loc != front)
		log_sp("[medic.real_name] could not get the tray out of [slab] in [get_area_name(slab)]")
		return FALSE
	if(get_turf(body) != front)
		if(medic.pulling != body && body.Adjacent(medic))
			medic.start_pulling(body)
		sp_ai_drag_onto(controller, body, slab.connected)
	if(QDELETED(medic) || QDELETED(body) || QDELETED(slab))
		return FALSE
	if(get_turf(body) != front)
		// The drag wants both ends in reach and the body is a tile behind; lift them the last step by hand.
		if(!body.Adjacent(medic))
			return FALSE
		body.forceMove(front)
		log_sp("[medic.real_name] lifted [body.real_name] onto the tray")
	if(medic.pulling == body)
		medic.stop_pulling()
	sp_ai_click(controller, slab)
	if(QDELETED(medic) || QDELETED(body))
		return FALSE
	if(body.loc != slab)
		log_sp("[medic.real_name] shut [slab] but [body.real_name] is not in it")
		return FALSE
	sp_record("med.morgue")
	log_sp("[medic.real_name] put [body.real_name] in the morgue")
	sp_crew_speak(medic, pick("I'm sorry. There was nothing to be done.", "[body.name] is in the morgue. Somebody will want to know.", "Rest easy, [body.name]."))
	return TRUE

// --- The scene ------------------------------------------------------------------------------------------

/// The prints on something, as a plain list of print strings.
/proc/sp_prints_on(atom/thing)
	var/list/prints = GET_ATOM_FINGERPRINTS(thing)
	return length(prints) ? prints.Copy() : list()

/// Crew records whose fingerprint is among these prints, as names: a print is the md5 of a DNA identity, which the manifest keeps.
/proc/sp_whose_prints(list/prints)
	var/list/names = list()
	if(!length(prints))
		return names
	for(var/datum/record/crew/record as anything in GLOB.manifest.general)
		if(record.fingerprint in prints)
			names |= record.name
	return names

/**
 * What a scene says. The dead first: whoever gripped or hit them with their hands left prints on what they wear. Then
 * whatever is lying within a few tiles, a dropped weapon above all, which carries the prints of whoever swung it. The
 * dead's own prints and the detective's are not evidence. Returns suspect name -> the things their prints were on.
 */
/proc/sp_read_scene(mob/living/carbon/human/detective, mob/living/carbon/human/body, turf/around)
	var/list/findings = list()
	if(QDELETED(detective) || QDELETED(body))
		return findings
	var/list/ignore = list(body.real_name, detective.real_name)
	var/list/atom/looked_at = list()
	// The body's clothes only while it is here to be looked at; on a tray in the morgue it is out of the scene.
	if(isturf(body.loc) && body.Adjacent(detective))
		for(var/obj/item/worn as anything in body.get_equipped_items())
			looked_at += worn
		around = get_turf(body)
	if(isnull(around))
		return findings
	for(var/obj/item/loose in range(SP_SCENE_RANGE, around))
		if(isturf(loose.loc))
			looked_at += loose
	for(var/atom/thing as anything in looked_at)
		for(var/name in sp_whose_prints(sp_prints_on(thing)) - ignore)
			if(isnull(findings[name]))
				findings[name] = list()
			findings[name] |= thing.name
	return findings

/**
 * The detective looks the scene over: the scanner on the body, for everyone to see, and then the reading above. A name
 * found goes on the arrest list and the record, and to security over the radio as an attack with a known attacker,
 * which is the baton path. Returns the suspect, or null. Sleeps.
 */
/proc/sp_investigate_scene(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/body, turf/where)
	var/mob/living/carbon/human/detective = controller?.pawn
	if(!istype(detective) || QDELETED(body))
		return null
	var/body_here = isturf(body.loc) && body.Adjacent(detective)
	if(!body_here && (isnull(where) || !where.Adjacent(detective)))
		return null
	GLOB.sp_investigated_bodies[REF(body)] = world.time
	var/obj/item/detective_scanner/scanner = locate() in detective.get_all_contents_type(/obj/item/detective_scanner)
	if(body_here && !isnull(scanner) && sp_take_in_hand(detective, scanner))
		detective.face_atom(body)
		scanner.scan(detective, body)
		sleep(2 SECONDS)
	if(QDELETED(detective) || QDELETED(body))
		return null
	sp_free_hands(detective)
	var/list/findings = sp_read_scene(detective, body, where)
	var/place = get_area_name(body_here ? body : where)
	if(!body_here)
		log_sp("[detective.real_name] found [body.real_name] already taken from [place] and read what was left there")
	sp_record("det.scene")
	if(!length(findings))
		sp_record("det.nothing")
		log_sp("[detective.real_name] looked over [body.real_name] in [place]: nothing but their own prints")
		sp_crew_speak(detective, pick(
			"Nothing to go on at [place]. Whoever did this wore gloves.",
			"Clean. No prints on [body.name] but [body.p_their()] own.",
			"No prints. I'll want to know who was last seen with [body.name].",
		), RADIO_CHANNEL_SECURITY)
		return null
	// The name on the most things; the weapon counts for as much as the body.
	var/suspect_name
	for(var/name in findings)
		if(isnull(suspect_name) || length(findings[name]) > length(findings[suspect_name]))
			suspect_name = name
	var/list/on_what = findings[suspect_name]
	log_sp("[detective.real_name] looked over [body.real_name] in [place]: [suspect_name]'s prints on [english_list(on_what)]")
	sp_record("det.suspect")
	var/mob/living/carbon/human/suspect = sp_crew_by_name(suspect_name)
	if(isnull(suspect))
		sp_crew_speak(detective, "The prints on [body.name] belong to [suspect_name], and I can't find [suspect_name] on the station.", RADIO_CHANNEL_SECURITY)
		return null
	sp_mark_for_arrest(suspect)
	sp_file_crime_record(suspect, SP_CRIME_MURDER, "Prints on [body.real_name]'s [english_list(on_what)] in [place].", detective, world.time)
	controller.override_blackboard_key(BB_SP_LAST_INCIDENT, list(
		SP_INCIDENT_ATTACKER = WEAKREF(suspect),
		SP_INCIDENT_SUSPECT = null,
		SP_INCIDENT_VICTIM = WEAKREF(body),
		SP_INCIDENT_TURF = get_turf(suspect),
		SP_INCIDENT_TIME = world.time,
		SP_INCIDENT_CRIME = SP_CRIME_MURDER,
	))
	sp_crew_speak(detective, "[suspect.name]'s prints are on [body.name][length(on_what) > 1 ? " and the [on_what[length(on_what)]]" : ""]. Bring [suspect.p_them()] in.", RADIO_CHANNEL_SECURITY)
	return suspect
