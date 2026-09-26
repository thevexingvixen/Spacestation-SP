/**
 * Searches and confiscation: what security take off somebody, and where it goes.
 *
 * An officer pats down whoever they arrest (sp_search_prisoner, ai/sp_search_behaviors.dm) and takes what they should
 * not have: the thing a witness saw them take, contraband, a weapon on somebody who is neither security nor command,
 * and anything off TG's steal catalogue that their job does not own. A reported thief is asked for it first, at the
 * word stage (sp_confront_suspect()), and searched if they keep it. What is taken is evidence: it goes to the brig's
 * evidence closet, filed by whoever can open it (on this TG an officer's own trim can), handed to the warden or the
 * head of security by anybody who cannot, or failing that locked in a security locker. Either way a thief stops
 * keeping the loot.
 */

/// Whether an officer would take this off `who`. Never the card on their chest, never the headset.
/proc/sp_is_loot(obj/item/thing, mob/living/carbon/human/who, obj/item/reported)
	if(QDELETED(thing) || (thing.item_flags & (ABSTRACT|DROPDEL)) || HAS_TRAIT(thing, TRAIT_NODROP))
		return FALSE
	if(istype(thing, /obj/item/card/id) || istype(thing, /obj/item/radio/headset) || istype(thing, /obj/item/implant))
		return FALSE
	if(thing == reported)
		return TRUE
	if(thing.is_contraband())
		return TRUE
	if((istype(thing, /obj/item/gun) || istype(thing, /obj/item/melee/baton)) && istype(who) && !sp_is_authority(who))
		return TRUE
	return sp_is_somebody_elses(thing, who)

/**
 * Whether an item is on the steal catalogue and this is not one of the jobs it belongs to. The catalogue is what
 * antagonists steal from (sp_antagonist.dm), and what it lists is by definition somebody's: the captain keeps their
 * medal, and a cook found with it has some explaining to do.
 */
/proc/sp_is_somebody_elses(obj/item/thing, mob/living/carbon/human/who)
	var/job = who?.mind?.assigned_role?.title
	for(var/datum/objective_item/info as anything in GLOB.possible_items)
		if(!istype(thing, info.targetitem))
			continue
		if(job && ((job in info.item_owner) || (job in info.excludefromjob)))
			return FALSE
		return TRUE
	return FALSE

/// Everything on somebody an officer would take: worn, in their hands, and in their bag.
/proc/sp_loot_on(mob/living/carbon/human/who, obj/item/reported)
	var/list/loot = list()
	if(!istype(who))
		return loot
	for(var/obj/item/thing as anything in who.get_all_gear())
		if(sp_is_loot(thing, who, reported))
			loot += thing
	return loot

/// Takes one thing off somebody and into the officer's keeping: their bag, their hands, or at their feet.
/proc/sp_take_from_person(mob/living/carbon/human/officer, mob/living/carbon/human/from, obj/item/thing)
	if(QDELETED(thing) || QDELETED(officer))
		return FALSE
	if(thing.loc == from && !from.temporarilyRemoveItemFromInventory(thing, force = TRUE))
		return FALSE
	if(officer.back && thing.forceMove(officer.back))
		return TRUE
	if(officer.put_in_hands(thing))
		return TRUE
	return thing.forceMove(get_turf(officer))

/// Adds to what we are carrying as evidence. A list value has to go in with override_blackboard_key.
/proc/sp_hold_evidence(datum/ai_controller/sp_crew/controller, list/items)
	if(!istype(controller))
		return
	var/list/held = controller.blackboard[BB_SP_EVIDENCE]
	var/list/all = islist(held) ? held.Copy() : list()
	for(var/obj/item/thing as anything in items)
		if(!QDELETED(thing))
			all |= thing
	controller.override_blackboard_key(BB_SP_EVIDENCE, all)

/// What we are carrying as evidence that is still on us.
/proc/sp_evidence_carried(datum/ai_controller/sp_crew/controller)
	var/list/carried = list()
	var/mob/living/pawn = controller?.pawn
	for(var/obj/item/thing as anything in controller?.blackboard[BB_SP_EVIDENCE])
		if(!QDELETED(thing) && get(thing, /mob) == pawn)
			carried += thing
	return carried

/**
 * Pats somebody down and takes what they should not have. Sleeps for the search itself. Returns what was taken,
 * which is now the officer's to file (BB_SP_EVIDENCE).
 */
/proc/sp_search_person(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/suspect, obj/item/reported)
	var/list/taken = list()
	var/mob/living/carbon/human/pawn = controller?.pawn
	if(!istype(pawn) || !istype(suspect) || !suspect.Adjacent(pawn))
		return taken
	pawn.face_atom(suspect)
	sp_record("sec.searched")
	var/list/loot = sp_loot_on(suspect, reported)
	if(!length(loot))
		log_sp("[pawn.real_name] searched [suspect.real_name] and found nothing to take")
		return taken
	if(!do_after(pawn, SP_SEARCH_TIME, suspect, timed_action_flags = IGNORE_HELD_ITEM))
		return taken
	for(var/obj/item/thing as anything in loot)
		if(QDELETED(thing) || get(thing, /mob) != suspect)
			continue
		if(sp_take_from_person(pawn, suspect, thing))
			taken += thing
	if(!length(taken))
		return taken
	sp_hold_evidence(controller, taken)
	var/names = sp_item_names(taken)
	sp_record("sec.confiscated", length(taken))
	log_sp("[pawn.real_name] took [names] off [suspect.real_name] in [get_area_name(pawn)]")
	sp_crew_speak(pawn, "I'll be taking [names].")
	return taken

/// A thief handing over what they were asked for, rather than being searched for it. Returns what was given.
/proc/sp_hand_over_loot(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/suspect, list/loot)
	var/list/given = list()
	var/mob/living/carbon/human/pawn = controller?.pawn
	if(!istype(pawn) || !istype(suspect))
		return given
	for(var/obj/item/thing as anything in loot)
		if(!QDELETED(thing) && get(thing, /mob) == suspect && sp_take_from_person(pawn, suspect, thing))
			given += thing
	if(!length(given))
		return given
	sp_hold_evidence(controller, given)
	sp_record("sec.handed_over", length(given))
	log_sp("[suspect.real_name] handed [sp_item_names(given)] over to [pawn.real_name]")
	sp_crew_speak(suspect, pick("Fine. Take it.", "Alright, alright. Here.", "I was going to give it back."))
	return given

/// Whether somebody told to hand something over will: crew with nothing to hide do, and a schemer never does.
/proc/sp_hands_over(mob/living/carbon/human/suspect)
	var/datum/ai_controller/sp_crew/theirs = suspect?.ai_controller
	return istype(theirs) && isnull(theirs.blackboard[BB_SP_SCHEME])

/// "a baton and a medal", from a list of items.
/proc/sp_item_names(list/items)
	var/list/names = list()
	for(var/obj/item/thing as anything in items)
		if(!QDELETED(thing))
			names |= thing.name
	return english_list(names)

// --- Where evidence goes -------------------------------------------------------------------------------

/// The nearest closet of `closet_type` on our level that we could open (sp_arm_locker_usable()).
/proc/sp_nearest_openable_closet(mob/living/carbon/human/who, closet_type)
	var/obj/structure/closet/best
	var/best_dist = INFINITY
	for(var/obj/structure/closet/candidate as anything in GLOB.roundstart_station_closets)
		if(!istype(candidate, closet_type) || !sp_arm_locker_usable(candidate, who))
			continue
		var/dist = get_dist(who, candidate)
		if(dist < best_dist)
			best = candidate
			best_dist = dist
	return best

/// Somebody on duty who can open the evidence closet and is not us: the warden first, then the head of security.
/proc/sp_evidence_keeper(mob/living/carbon/human/officer)
	var/mob/living/carbon/human/hos
	for(var/mob/living/carbon/human/crew as anything in SSspacestation_sp.ai_crew)
		if(crew == officer || QDELETED(crew) || crew.stat != STABLE || crew.z != officer.z)
			continue
		if(istype(crew.ai_controller, /datum/ai_controller/sp_crew/security/warden))
			return crew
		if(istype(crew.ai_controller, /datum/ai_controller/sp_crew/security/hos))
			hos = crew
	return hos

/**
 * Where what we are carrying as evidence goes: the evidence closet if our card opens it; otherwise whoever's does, to
 * hand it to; otherwise -- or once the walk to them has come to nothing too often -- a security locker we can open.
 */
/proc/sp_evidence_home(datum/ai_controller/sp_crew/controller)
	var/mob/living/carbon/human/pawn = controller?.pawn
	if(!istype(pawn))
		return null
	var/obj/structure/closet/evidence = sp_nearest_openable_closet(pawn, /obj/structure/closet/secure_closet/evidence)
	if(evidence)
		return evidence
	if((controller.blackboard[BB_SP_EVIDENCE_TRIES] || 0) < SP_EVIDENCE_MAX_TRIES)
		var/mob/living/carbon/human/keeper = sp_evidence_keeper(pawn)
		if(keeper)
			return keeper
	return sp_nearest_openable_closet(pawn, /obj/structure/closet/secure_closet/security/sec)
