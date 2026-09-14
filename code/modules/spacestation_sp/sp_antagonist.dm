/**
 * The antagonist foundation.
 *
 * An antagonist is an ordinary AI crew member carrying a scheme: a goal at odds with the rest of the
 * station, and the score-keeping for it. The behaviour tree (ai/sp_antagonist_behaviors.dm) is how the
 * scheme is pursued; this file is the scheme itself.
 *
 * Deliberately not /datum/objective. Those assume a client — an assassinate objective against a clientless
 * NPC completes on the spot, because a mob with no client reads as AFK, and the round-end report prints a
 * blank key for a keyless mob. A scheme needs no client and makes no round-end noise. Where an antagonist
 * should also be a "real" traitor (counted, codewords, round-end), a silent traitor datum can be attached
 * on top; see the plan, docs/02-antagonist-plan.md. That bridge is off by default.
 */

/datum/sp_scheme
	/// Shown in logs and the admin panel.
	var/name = "a vague sense of mischief"
	/// TRUE once the goal is met; latched, so completing it once is enough.
	var/complete = FALSE

/// Re-checks the goal against the pawn and latches `complete`. Returns the (possibly updated) state.
/datum/sp_scheme/proc/check_progress(datum/ai_controller/sp_crew/controller)
	if(!complete && evaluate(controller))
		complete = TRUE
		on_complete(controller)
	return complete

/// The actual test, overridden per scheme. Returns TRUE when the goal is met.
/datum/sp_scheme/proc/evaluate(datum/ai_controller/sp_crew/controller)
	return FALSE

/// Logged and tallied when the goal is first met. Deliberately quiet: no radio, nothing the crew hear.
/datum/sp_scheme/proc/on_complete(datum/ai_controller/sp_crew/controller)
	var/mob/living/pawn = controller?.pawn
	sp_record("antag.scheme_done")
	log_sp("[pawn?.real_name || "someone"] pulled off their scheme: [name]")

/// The atom the pawn should be heading for right now, or null when there is nothing to go to.
/datum/sp_scheme/proc/current_goal_atom(datum/ai_controller/sp_crew/controller)
	return null

// --- Steal a thing --------------------------------------------------------------------------------

/**
 * Get hold of one particular item and hang on to it. The target comes from TG's own steal-objective
 * catalogue (/datum/objective_item), so it is a thing the game already knows is worth stealing and
 * confirms is on the map — the captain's medal, the CMO's hypospray — without taking on the objective or
 * uplink machinery around it.
 */
/datum/sp_scheme/steal
	/// The catalogue entry (/datum/objective_item) we picked.
	var/datum/objective_item/target_info
	/// Cached typepath of the item we want, so the scheme reads even if the catalogue entry goes away.
	var/target_type
	/// The particular copy we proved we could reach when the scheme was handed out.
	var/datum/weakref/target_ref

/datum/sp_scheme/steal/proc/set_target(datum/objective_item/info)
	target_info = info
	target_type = info?.targetitem
	name = info ? "steal [info.name]" : "steal something worth taking"

/datum/sp_scheme/steal/evaluate(datum/ai_controller/sp_crew/controller)
	var/mob/living/pawn = controller?.pawn
	if(QDELETED(pawn) || isnull(target_type))
		return FALSE
	// Carrying it anywhere on our person counts, the same test TG's steal objective uses.
	return length(pawn.get_all_contents_type(target_type)) > 0

/datum/sp_scheme/steal/current_goal_atom(datum/ai_controller/sp_crew/controller)
	var/mob/living/pawn = controller?.pawn
	if(QDELETED(pawn) || isnull(target_type))
		return null
	// Already have it: nothing to walk to.
	if(length(pawn.get_all_contents_type(target_type)))
		return null
	// The copy we know we can get to, while it is still there to get. Going for whichever is nearest instead
	// means changing our mind every time we round a corner: a bitrunner sent after a hand teleporter spent the
	// shift walking between the one in the teleporter room and the one in the captain's quarters, reaching neither.
	var/obj/item/known = target_ref?.resolve()
	if(!QDELETED(known) && sp_can_be_lifted(known, pawn))
		return known
	return sp_nearest_steal_item(pawn, target_type)

/**
 * The nearest instance of `target_type` on the pawn's z-level that is out in the world (not already in
 * somebody's pockets). Uses TG's steal-item handler, which tracks every registered instance on the
 * station, so it finds the item wherever it was mapped without an oview sweep.
 */
/proc/sp_nearest_steal_item(mob/living/thief, target_type)
	var/turf/origin = get_turf(thief)
	if(isnull(origin))
		return null
	var/obj/item/best
	var/best_distance = INFINITY
	for(var/obj/item/candidate as anything in GLOB.steal_item_handler?.objectives_by_path[target_type])
		var/turf/there = get_turf(candidate)
		if(isnull(there) || there.z != origin.z || !sp_can_be_lifted(candidate, thief))
			continue
		var/distance = get_dist(origin, there)
		if(distance < best_distance)
			best = candidate
			best_distance = distance
	return best

/**
 * Whether a thief could actually walk up to this and take it: lying out in the open, or shut in a closet we
 * can open. Not something nested in a box, and not something being worn or carried.
 *
 * The first antagonist of the first round was a mime told to steal the medal of captaincy, which spawns inside
 * a locked lockbox in the captain's quarters, with the only other copy pinned to the captain's uniform. It was
 * picked because it existed, not because it could be had, and the mime spent the shift with nothing to do.
 */
/proc/sp_can_be_lifted(obj/item/candidate, mob/living/thief)
	if(QDELETED(candidate))
		return FALSE
	var/atom/where = candidate.loc
	if(isturf(where))
		return TRUE
	var/obj/structure/closet/locker = where
	if(!istype(locker))
		return FALSE
	// A closet we can open. A locked one we have no key to is the lockbox problem one layer down: the thief walks
	// all the way there, clicks at it, and comes away with nothing.
	if(locker.locked && !isnull(thief) && !locker.allowed(thief))
		return FALSE
	return TRUE

/**
 * Picks a steal target for an antagonist: an on-the-map, normal-type catalogue item this crew member is
 * not the owner of, that actually has a locatable instance right now. Returns the /datum/objective_item, or
 * null if nothing suitable exists (an empty test map, say).
 */
/**
 * The copy of `info` this thief could actually walk up to and lift, with their own ID and no help, or null if
 * there is none. Sleeps: it asks the pathfinder.
 *
 * The layer under `sp_can_be_lifted()`. A cook was sent after an ablative trenchcoat, which sits out on a
 * shelf — perfectly liftable, in the armory, behind a door no cook opens, and she stood in the brig telling
 * the log about it. Checking the container is not enough; the room has to be ours as well.
 */
/proc/sp_reachable_steal_item(mob/living/carbon/human/thief, datum/objective_item/info)
	var/datum/ai_movement/jps/sp_crew/movement = /datum/ai_movement/jps/sp_crew
	var/max_length = initial(movement.maximum_length)
	// Only the one question: can we get to it? Whether it is on the station at all was settled by the cheap
	// filter in sp_pick_steal_target() before we got here.
	for(var/obj/item/instance as anything in GLOB.steal_item_handler?.objectives_by_path[info.targetitem])
		if(!sp_can_be_lifted(instance, thief))
			continue
		if(length(get_path_to(thief, instance, max_length, 1, thief.get_access())))
			return instance
	return null

/proc/sp_pick_steal_target(mob/living/carbon/human/thief)
	var/list/datum/objective_item/candidates = list()
	var/thief_job = thief?.mind?.assigned_role?.title
	for(var/datum/objective_item/info as anything in GLOB.possible_items)
		if(info.objective_type != OBJECTIVE_ITEM_TYPE_NORMAL || !info.exists_on_map)
			continue
		if(thief_job && (thief_job in info.excludefromjob))
			continue
		// Has to be a copy somebody could actually lift, on the station, not sealed in a box or worn by a head.
		var/liftable = FALSE
		for(var/obj/item/instance as anything in GLOB.steal_item_handler?.objectives_by_path[info.targetitem])
			var/turf/there = get_turf(instance)
			if(isnull(there) || !is_station_level(there.z) || !sp_can_be_lifted(instance, thief))
				continue
			liftable = TRUE
			break
		if(!liftable)
			continue
		candidates += info
	// Then the expensive question, asked in a random order and only until one answers: can we get there at all?
	for(var/datum/objective_item/info as anything in shuffle(candidates))
		if(sp_reachable_steal_item(thief, info))
			return info
	return null

/// Gives `controller` a scheme to steal a chosen (or picked) catalogue item. Returns the scheme, or null.
/proc/sp_make_thief(datum/ai_controller/sp_crew/controller, datum/objective_item/info)
	var/mob/living/carbon/human/pawn = controller?.pawn
	if(QDELETED(pawn))
		return null
	if(isnull(info))
		info = sp_pick_steal_target(pawn)
	if(isnull(info))
		return null
	var/datum/sp_scheme/steal/scheme = new()
	scheme.set_target(info)
	// Remember which copy we checked, so the walk goes to that one rather than whichever looks nearest later.
	scheme.target_ref = WEAKREF(sp_reachable_steal_item(pawn, info))
	controller.set_blackboard_key(BB_SP_SCHEME, scheme)
	log_sp("[pawn.real_name] ([pawn.mind?.assigned_role?.title || "crew"]) is now up to something: [scheme.name]")
	return scheme
