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
	// all the way there, clicks at it, and comes away with nothing. An emag in the bag breaks any lock.
	if(locker.locked && !isnull(thief) && !locker.allowed(thief) && isnull(sp_emag_carried(thief)))
		return FALSE
	return TRUE

// --- The traitor's kit ----------------------------------------------------------------------------------

/**
 * What a thief draws from the uplink before setting out: a doorjack, which hacks airlocks open and recharges,
 * and an emag, which breaks the lock on any secure closet. TG keeps the two apart -- the plain emag refuses every
 * airlock type (`type_blacklist`), the doorjack refuses everything but doors -- so a thief needs both. These are
 * the missing half of the theft funnel measured in docs/02 §8: every target was behind a door. Both are
 * contraband, so an arrest and a search take them back (sp_search.dm).
 */
/proc/sp_issue_uplink_kit(datum/ai_controller/sp_crew/controller)
	var/mob/living/carbon/human/pawn = controller?.pawn
	if(!istype(pawn))
		return FALSE
	var/list/drawn = list()
	// One of each, charged or not: a flat doorjack is recharging, not missing.
	if(isnull(sp_doorjack_owned(pawn)))
		var/obj/item/card/emag/doorjack/jack = new(pawn)
		if(pawn.equip_to_storage(jack, ITEM_SLOT_BACK, indirect_action = TRUE) || pawn.put_in_hands(jack))
			drawn += jack
		else
			qdel(jack)
	if(isnull(sp_emag_carried(pawn)))
		var/obj/item/card/emag/card = new(pawn)
		if(pawn.equip_to_storage(card, ITEM_SLOT_BACK, indirect_action = TRUE) || pawn.put_in_hands(card))
			drawn += card
		else
			qdel(card)
	if(!length(drawn))
		return FALSE
	sp_record("antag.uplink", length(drawn))
	log_sp("[pawn.real_name] drew [sp_item_names(drawn)] from the uplink")
	return TRUE

/// The doorjack somebody carries, with a charge left on it, or null.
/proc/sp_doorjack_carried(mob/living/who)
	for(var/obj/item/card/emag/doorjack/jack as anything in who?.get_all_contents_type(/obj/item/card/emag/doorjack))
		if(jack.charges > 0)
			return jack
	return null

/// The emag somebody carries, or null. A doorjack is an emag by type but opens no lockers, so it does not count.
/proc/sp_emag_carried(mob/living/who)
	for(var/obj/item/card/emag/card as anything in who?.get_all_contents_type(/obj/item/card/emag))
		if(!istype(card, /obj/item/card/emag/doorjack))
			return card
	return null

/**
 * The access the kit gives a thief: their own, and every station door while they carry a charged doorjack. This is
 * what a target is picked against (sp_reachable_steal_item()), and what the pathfinder gets on the walk to it, and
 * only on that walk (/datum/ai_controller/sp_crew/antagonist/get_access()).
 */
/proc/sp_thief_access(mob/living/thief)
	var/list/ours = thief?.get_access()
	ours = islist(ours) ? ours : list()
	if(isnull(sp_doorjack_carried(thief)))
		return ours
	return ours | SSid_access.get_region_access_list(list(REGION_ALL_STATION))

/// How a thief would walk to something: the access the walk is planned with, and how many doors on the way their own card will not open.
/datum/sp_walk_plan
	var/list/access
	var/hacks = 0

/**
 * Plans the walk to `reach`: the route, as the pathfinder would take it, and how many doors on it need the doorjack.
 * The corridors are tried before the tunnels (every station access but maintenance, then everything), because a
 * maintenance route is a locked door every few tiles: the first thief to walk with every door open went from cargo
 * to medbay through the tunnels, four hacks for a trip the corridors do in two, and stalled flat at the fourth. A
 * route that needs no hack is walked with the thief's own card, so any re-path on the way stays on doors that open
 * for them. Returns null when nothing reaches. Sleeps: it asks the pathfinder.
 */
/proc/sp_scheme_walk_plan(mob/living/carbon/human/thief, atom/reach)
	if(QDELETED(thief) || QDELETED(reach))
		return null
	var/datum/ai_movement/jps/sp_crew/movement = /datum/ai_movement/jps/sp_crew
	var/max_length = initial(movement.maximum_length)
	var/list/own = thief.get_access()
	own = islist(own) ? own : list()
	var/list/everywhere = SSid_access.get_region_access_list(list(REGION_ALL_STATION))
	for(var/list/attempt in list(own | (everywhere - ACCESS_MAINT_TUNNELS), own | everywhere))
		var/list/path = get_path_to(thief, reach, max_length, 1, attempt)
		if(!length(path))
			continue
		var/datum/sp_walk_plan/plan = new
		plan.hacks = sp_hacks_on_path(path, thief)
		plan.access = plan.hacks ? attempt : own
		return plan
	return null

/// Doors on a planned path that this thief's own card will not open: airlocks and windoors shut to them, hacked ones aside.
/proc/sp_hacks_on_path(list/path, mob/living/thief)
	var/hacks = 0
	for(var/turf/step as anything in path)
		for(var/obj/machinery/door/door in step)
			if(!sp_jackable_door(door) || !door.density || (door.obj_flags & EMAGGED) || door.allowed(thief))
				continue
			hacks++
	return hacks

/// The doorjack somebody carries, charged or flat, or null.
/proc/sp_doorjack_owned(mob/living/who)
	return locate(/obj/item/card/emag/doorjack) in who?.get_all_contents_type(/obj/item/card/emag/doorjack)

/// A door the doorjack works on: an airlock or a windoor. Firelocks are pushed open by anybody (on_bump()).
/proc/sp_jackable_door(atom/door)
	return istype(door, /obj/machinery/door/airlock) || istype(door, /obj/machinery/door/window)

/**
 * Hacks a door open with the doorjack, as the thief walks into it. The hack itself is TG's: the door opens 0.6
 * seconds on and stays open for good. Done once per door at a time (BB_SP_JACKING_DOOR), since a walk bumps the
 * same door several times a second. Somebody may see it. Sleeps for the click.
 */
/proc/sp_jack_door(datum/ai_controller/sp_crew/controller, obj/machinery/door/door)
	var/mob/living/carbon/human/pawn = controller?.pawn
	var/obj/item/card/emag/doorjack/jack = sp_doorjack_carried(pawn)
	if(!istype(pawn) || QDELETED(door) || !sp_jackable_door(door) || isnull(jack) || !door.density || (door.obj_flags & EMAGGED))
		return FALSE
	if(controller.blackboard[BB_SP_JACKING_DOOR] == door)
		return FALSE
	controller.set_blackboard_key(BB_SP_JACKING_DOOR, door)
	addtimer(CALLBACK(controller, TYPE_PROC_REF(/datum/ai_controller, clear_blackboard_key), BB_SP_JACKING_DOOR), SP_JACK_RETRY)
	if(!sp_take_in_hand(pawn, jack))
		return FALSE
	pawn.face_atom(door)
	sp_ai_click(controller, door)
	// The hack lands on a timer and the door then takes its time opening; wait for both, then put the card away.
	sleep(SP_JACK_SETTLE)
	if(QDELETED(pawn))
		return FALSE
	sp_free_hands(pawn)
	if(QDELETED(door) || !(door.obj_flags & EMAGGED))
		log_sp("[pawn.real_name] tried the doorjack on [door] in [get_area_name(door)] and it did not take")
		return FALSE
	sp_record("antag.door_jacked")
	log_sp("[pawn.real_name] hacked [door] open in [get_area_name(door)]")
	sp_crime_seen(pawn, SP_CRIME_VANDALISM, "hack [door] open", get_turf(door))
	return TRUE

/// Breaks the lock on a secure closet with the emag. Sleeps for the click. Somebody may see it.
/proc/sp_break_lock(datum/ai_controller/sp_crew/controller, obj/structure/closet/locker)
	var/mob/living/carbon/human/pawn = controller?.pawn
	var/obj/item/card/emag/card = sp_emag_carried(pawn)
	if(!istype(pawn) || QDELETED(locker) || isnull(card) || !locker.locked)
		return FALSE
	if(!sp_take_in_hand(pawn, card))
		return FALSE
	pawn.face_atom(locker)
	sp_ai_click(controller, locker)
	if(QDELETED(pawn) || QDELETED(locker) || locker.locked)
		return FALSE
	sp_record("antag.lock_broken")
	log_sp("[pawn.real_name] broke the lock on [locker] in [get_area_name(locker)]")
	sp_crime_seen(pawn, SP_CRIME_VANDALISM, "break open [locker]", get_turf(locker))
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
		// Somewhere a walk gets to, and if the walk needs hacks, no more of them than the doorjack ever holds.
		var/datum/sp_walk_plan/plan = sp_scheme_walk_plan(thief, instance)
		if(isnull(plan))
			continue
		var/obj/item/card/emag/doorjack/jack = sp_doorjack_owned(thief)
		var/within_reach = !plan.hacks || (!isnull(jack) && plan.hacks <= jack.max_charges)
		qdel(plan)
		if(within_reach)
			return instance
	return null

/proc/sp_pick_steal_target(mob/living/carbon/human/thief)
	var/list/datum/objective_item/candidates = list()
	var/thief_job = thief?.mind?.assigned_role?.title
	// Counted, so a thief with nothing to steal can say which stage of the funnel closed. "Found nothing"
	// reads the same whether the catalogue was empty, every copy was sealed in a case, or it was all
	// simply too far away, and those want three different fixes.
	var/considered = 0
	var/on_map = 0
	var/with_instance = 0
	var/list/liftable_instances = list()
	for(var/datum/objective_item/info as anything in GLOB.possible_items)
		considered++
		if(info.objective_type != OBJECTIVE_ITEM_TYPE_NORMAL || !info.exists_on_map)
			continue
		on_map++
		if(thief_job && (thief_job in info.excludefromjob))
			continue
		// Has to be a copy somebody could actually lift, on the station, not sealed in a box or worn by a head.
		var/liftable = FALSE
		var/any_instance = FALSE
		for(var/obj/item/instance as anything in GLOB.steal_item_handler?.objectives_by_path[info.targetitem])
			any_instance = TRUE
			var/turf/there = get_turf(instance)
			if(isnull(there) || !is_station_level(there.z) || !sp_can_be_lifted(instance, thief))
				continue
			liftable = TRUE
			liftable_instances += instance
			break
		if(any_instance)
			with_instance++
		if(!liftable)
			continue
		candidates += info
	// Then the expensive question, asked in a random order and only until one answers: can we get there at all?
	for(var/datum/objective_item/info as anything in shuffle(candidates))
		if(sp_reachable_steal_item(thief, info))
			return info
	log_sp("no steal target for [thief?.real_name || "a thief"]: [considered] catalogued, [on_map] on the map, [with_instance] with a copy somewhere, [length(candidates)] liftable, none of those reachable")
	// "Cannot get there" is two different faults wanting opposite fixes: too far for the path budget, or shut
	// behind doors we have no card for. Retry each one with a budget nobody could exceed and let it say which.
	var/datum/ai_movement/jps/sp_crew/movement = /datum/ai_movement/jps/sp_crew
	var/max_length = initial(movement.maximum_length)
	for(var/obj/item/instance as anything in liftable_instances)
		var/area/spot = get_area(instance)
		var/generous = length(get_path_to(thief, instance, 1000, 1, sp_thief_access(thief)))
		var/verdict
		if(generous)
			verdict = "[generous] steps at budget 1000, so the budget was the problem"
		else
			// Every station door open: if a path appears now, it was the locks, not the walls.
			var/unlocked = length(get_path_to(thief, instance, 1000, 1, SSid_access.get_region_access_list(list(REGION_ALL_STATION))))
			verdict = unlocked ? "[unlocked] steps with every door open, so it is access" : "no path even with every door open, so it is topology"
		log_sp("  out of reach: [instance.name] in [spot ? spot.name : "nowhere"], [get_dist(thief, instance)] tiles off, budget [max_length]: [verdict]")
	return null

/// Gives `controller` a scheme to steal a chosen (or picked) catalogue item. Returns the scheme, or null.
/proc/sp_make_thief(datum/ai_controller/sp_crew/controller, datum/objective_item/info)
	var/mob/living/carbon/human/pawn = controller?.pawn
	if(QDELETED(pawn))
		return null
	// The kit first: with a doorjack in the bag, what counts as reachable is most of the station.
	sp_issue_uplink_kit(controller)
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
