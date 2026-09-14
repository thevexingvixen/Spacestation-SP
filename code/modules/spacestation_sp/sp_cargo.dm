/**
 * Cargo.
 *
 * The quartermaster runs the paperwork and the shuttle: they take requests from the rest of the
 * station, put them on the order list against the cargo budget, send the shuttle out and call it
 * back. Cargo technicians do the physical half, hauling the crates off the shuttle and walking the
 * ones that were requested to the department that asked for them.
 *
 * Requests are the point of the department, so they are a first-class thing here rather than an
 * afterthought: any AI crew member (the chef, shortly) can call `sp_request_supplies()` and the
 * quartermaster will notice it, order it, and have it walked over.
 */

/// One department asking cargo for something.
/datum/sp_supply_request
	/// The supply pack wanted.
	var/datum/supply_pack/pack
	/// Who asked.
	var/datum/weakref/requester
	/// Their name, kept for the radio traffic once they are gone.
	var/requester_name = "someone"
	/// Where the crate should end up.
	var/area_type
	/// pending -> ordered -> delivered.
	var/status = SP_REQUEST_PENDING
	/// The supply order once it has been placed, so we can match the crate that comes back.
	var/order_id
	/// The crate once a technician has it, so whoever asked can go and find it wherever it was left.
	var/datum/weakref/crate
	/// When it was raised.
	var/made_at = 0

/datum/sp_supply_request/New(datum/supply_pack/pack, mob/living/requester, area_type)
	src.pack = pack
	src.area_type = area_type
	made_at = world.time
	if(!QDELETED(requester))
		src.requester = WEAKREF(requester)
		requester_name = requester.real_name

/**
 * Asks cargo for a crate. This is the entry point for every other department.
 *
 * * pack_type - the /datum/supply_pack wanted
 * * requester - who is asking
 * * area_type - where it should be delivered; defaults to the requester's current area
 */
/proc/sp_request_supplies(pack_type, mob/living/requester, area_type)
	if(!ispath(pack_type, /datum/supply_pack))
		return null
	var/datum/supply_pack/pack = SSshuttle.supply_packs[pack_type]
	if(isnull(pack))
		return null
	// One outstanding request per pack is plenty; departments should not spam the queue.
	for(var/datum/sp_supply_request/existing as anything in SSspacestation_sp.supply_requests)
		if(existing.pack?.type == pack_type && existing.status != SP_REQUEST_DELIVERED)
			return existing
	if(isnull(area_type))
		var/area/here = get_area(requester)
		area_type = here?.type
	var/datum/sp_supply_request/request = new(pack, requester, area_type)
	SSspacestation_sp.supply_requests += request
	log_sp("[requester?.real_name || "someone"] requested [pack.name] from cargo")
	return request

/// Whether cargo already has this pack on the way: asked for, and not yet delivered.
/proc/sp_supplies_on_order(pack_type)
	for(var/datum/sp_supply_request/request as anything in SSspacestation_sp.supply_requests)
		if(request.pack?.type == pack_type && request.status != SP_REQUEST_DELIVERED)
			return TRUE
	return FALSE

/// Requests cargo has not ordered yet.
/proc/sp_pending_requests()
	var/list/pending = list()
	for(var/datum/sp_supply_request/request as anything in SSspacestation_sp.supply_requests)
		if(request.status == SP_REQUEST_PENDING)
			pending += request
	return pending

/**
 * What the quartermaster orders when nobody has asked for anything: a small standing restock so the
 * shuttle is not making empty runs and the station has consumables coming in.
 */
GLOBAL_LIST_INIT(sp_cargo_standing_order, list(
	/datum/supply_pack/organic/food,
	/datum/supply_pack/medical/supplies,
	/datum/supply_pack/engineering/engiequipment,
	/datum/supply_pack/service/janitor,
	/datum/supply_pack/organic/hydroponics,
))

/// The cargo budget.
/proc/sp_cargo_account()
	return SSeconomy.get_dep_account(ACCOUNT_CAR)

/**
 * Puts a pack on the order list, paid from the cargo budget, exactly as the console would.
 * Returns the order, or null if cargo cannot afford it.
 */
/proc/sp_place_order(datum/supply_pack/pack, mob/living/carbon/human/orderer, reason, area_type)
	if(isnull(pack) || QDELETED(orderer))
		return null
	var/datum/bank_account/budget = sp_cargo_account()
	if(isnull(budget) || !budget.has_money(pack.get_cost()))
		return null
	var/datum/supply_order/order = new(
		pack,
		orderer.real_name,
		orderer.mind?.assigned_role?.title || "Quartermaster",
		null,
		reason,
	)
	SSshuttle.shopping_list += order
	log_sp("[orderer.real_name] ordered [pack.name] ([pack.get_cost()] credits)[area_type ? " for [area_type]" : ""]")
	return order

/// Is the supply shuttle sitting at the station?
/proc/sp_supply_docked_home()
	return !isnull(SSshuttle.supply) && SSshuttle.supply.getDockedId() == "cargo_home"

/// Is the supply shuttle away at the depot?
/proc/sp_supply_away()
	return !isnull(SSshuttle.supply) && SSshuttle.supply.getDockedId() == "cargo_away"

/// Can we order the shuttle around right now?
/proc/sp_supply_movable()
	return !isnull(SSshuttle.supply) && SSshuttle.supply.canMove() && !SSshuttle.supply_blocked

/**
 * The nearest working supply console. Deliberately not an oview() search: oview is sight-limited, so a
 * console one room away behind a wall is invisible and the quartermaster would never find their own desk.
 */
/proc/sp_find_cargo_console(mob/living/carbon/human/who)
	var/turf/origin = get_turf(who)
	if(isnull(origin))
		return null
	var/obj/machinery/computer/cargo/best
	var/best_distance = INFINITY
	for(var/obj/machinery/computer/cargo/console as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/computer/cargo))
		if(console.machine_stat & (BROKEN|NOPOWER))
			continue
		var/turf/console_turf = get_turf(console)
		if(isnull(console_turf) || console_turf.z != origin.z)
			continue
		var/distance = get_dist(origin, console_turf)
		if(distance < best_distance)
			best = console
			best_distance = distance
	return best

/// Every turf the supply shuttle occupies, so we can find what has just been delivered.
/proc/sp_supply_shuttle_turfs()
	if(isnull(SSshuttle.supply))
		return list()
	return SSshuttle.supply.return_turfs()

/**
 * A crate still sitting on the supply shuttle that nobody else has hold of.
 * Two technicians grabbing at the same crate just steal the pull off each other and neither finishes,
 * so anything somebody already has hold of, or is on their way over to, is left to them.
 */
/proc/sp_find_crate_on_shuttle(mob/living/asking)
	// Only while it is docked here. Away at CentCom its deck is another z-level entirely, and a technician who
	// picked the mail crate off it stood in the cargo bay for two minutes, unable to walk there, before giving up.
	if(!sp_supply_docked_home())
		return null
	for(var/turf/deck as anything in sp_supply_shuttle_turfs())
		for(var/obj/structure/closet/crate/crate in deck)
			if(!sp_crate_claimed(crate, asking))
				return crate
	return null

/**
 * Whether somebody other than `asking` already has this crate: dragging it, or on their way over to. Checking
 * only who was dragging left a gap the length of the walk to the shuttle, and two technicians who picked the
 * same crate inside it took the pull off each other all the way across the station until both gave up.
 */
/proc/sp_crate_claimed(obj/structure/closet/crate/crate, mob/living/asking)
	if(!isnull(crate.pulledby) && crate.pulledby != asking)
		return TRUE
	for(var/mob/living/carbon/human/other as anything in SSspacestation_sp.ai_crew)
		if(other == asking)
			continue
		var/datum/ai_controller/their_ai = other.ai_controller
		if(!isnull(their_ai) && their_ai.blackboard[BB_SP_CRATE] == crate)
			return TRUE
	return FALSE

/// Somewhere in the cargo bay to leave a crate that nobody asked for.
/proc/sp_find_cargo_dropoff(mob/living/carbon/human/who)
	var/turf/origin = get_turf(who)
	if(isnull(origin))
		return null
	var/static/list/bay_areas = list(/area/station/cargo/storage, /area/station/cargo/warehouse, /area/station/cargo/office, /area/station/cargo/sorting)
	var/list/shuttle_turfs = sp_supply_shuttle_turfs()
	for(var/area_type in bay_areas)
		var/list/candidates = get_area_turfs(area_type, origin.z)
		if(!length(candidates))
			continue
		for(var/i in 1 to 25)
			var/turf/candidate = pick(candidates)
			if(candidate in shuttle_turfs)
				continue
			if(candidate.density || candidate.is_blocked_turf(exclude_mobs = TRUE))
				continue
			// The bay abuts the dock on most maps, so insist on a few tiles of clearance. Otherwise a
			// crate still sitting on the shuttle counts as delivered and never actually gets unloaded.
			var/too_close = FALSE
			for(var/turf/deck as anything in shuttle_turfs)
				if(get_dist(candidate, deck) <= 2)
					too_close = TRUE
					break
			if(too_close)
				continue
			return candidate
	return null

/**
 * A spot inside `area_type` to leave a delivery. Picks the closest clear tile rather than a random
 * one, so a technician dragging a crate across the station stops at the door rather than walking it
 * into the far corner of the department.
 */
/proc/sp_find_delivery_spot(area_type, turf/origin)
	if(isnull(area_type) || isnull(origin))
		return null
	var/list/candidates = get_area_turfs(area_type, origin.z)
	if(!length(candidates))
		return null
	var/turf/best
	var/best_distance = INFINITY
	var/turf/fallback
	var/fallback_distance = INFINITY
	for(var/turf/candidate as anything in candidates)
		if(candidate.density || candidate.is_blocked_turf(exclude_mobs = TRUE))
			continue
		var/distance = get_dist(origin, candidate)
		// Clear of the doorway with room to walk round beats the tile just inside the door.
		if(sp_good_drop_spot(candidate))
			if(distance < best_distance)
				best = candidate
				best_distance = distance
		else if(distance < fallback_distance)
			fallback = candidate
			fallback_distance = distance
	return best || fallback

/**
 * The request a delivered crate belongs to. The supply shuttle ends every ordered crate's name with
 * " - #<order number>", and the quartermaster keeps that number on the request, so the match is exact.
 * Matching on the pack's name was not: a pack and its crate are often called different things, and the
 * Medical Supplies Crate medbay asked for arrived as a "DeForest Medical crate", matched nothing, and was
 * left in the cargo bay as if nobody wanted it.
 */
/proc/sp_request_for_crate(obj/structure/closet/crate/crate)
	if(QDELETED(crate))
		return null
	for(var/datum/sp_supply_request/request as anything in SSspacestation_sp.supply_requests)
		if(request.status != SP_REQUEST_ORDERED || isnull(request.order_id))
			continue
		var/suffix = " - #[request.order_id]"
		var/suffix_at = length(crate.name) - length(suffix) + 1
		if(suffix_at >= 1 && findtext(crate.name, suffix, suffix_at))
			return request
	return null

/// Crates cargo has brought over for this pack and handed off, wherever they ended up.
/proc/sp_delivered_crates(pack_type)
	var/list/obj/structure/closet/crate/crates = list()
	for(var/datum/sp_supply_request/request as anything in SSspacestation_sp.supply_requests)
		if(request.status != SP_REQUEST_DELIVERED || request.pack?.type != pack_type)
			continue
		var/obj/structure/closet/crate/crate = request.crate?.resolve()
		if(!QDELETED(crate))
			crates += crate
	return crates

/**
 * Somewhere a delivery can sit without being in the way: open floor with room to walk round it, and neither
 * in a doorway, where it jams the door, nor right in front of one, where everybody has to squeeze past it.
 */
/proc/sp_good_drop_spot(turf/spot)
	if(isnull(spot) || spot.density || spot.is_blocked_turf(exclude_mobs = TRUE))
		return FALSE
	if(locate(/obj/machinery/door) in spot)
		return FALSE
	var/open_sides = 0
	for(var/direction in GLOB.cardinals)
		var/turf/beside = get_step(spot, direction)
		if(isnull(beside))
			continue
		if(locate(/obj/machinery/door) in beside)
			return FALSE
		if(!beside.density && !beside.is_blocked_turf(exclude_mobs = TRUE))
			open_sides++
	return open_sides >= 3

/**
 * Where somebody carrying a delivery can actually leave it, on the way to `destination`. Sleeps: it asks the
 * pathfinder, and the pathfinder makes you wait.
 *
 * A request is addressed to wherever the asker was standing, and that is often behind a door the person
 * delivering cannot open: a doctor in the operating theatre, a chef in the kitchen. Planned with our own ID
 * there is no route at all, so the walk fails on the spot, over and over, until the haul times out in the
 * cargo bay. What a technician does instead is bring it as far as they can and leave it at the door: so plan
 * the route as if every door opened, follow it up to the first one ours does not, and stop a little short.
 *
 * `min_distance` is how near counts as there: 1 for a table, which nobody stands on.
 *
 * Returns `destination` when we can get there, a spot short of it when we cannot, and null when there is no
 * way there even with every door open.
 */
/proc/sp_reachable_drop_spot(mob/living/walker, turf/destination, min_distance = 0)
	var/turf/start = get_turf(walker)
	if(isnull(start) || isnull(destination))
		return null
	if(get_dist(start, destination) <= min_distance)
		return destination
	var/datum/ai_movement/jps/sp_crew/movement = /datum/ai_movement/jps/sp_crew
	var/max_length = initial(movement.maximum_length)
	var/list/own_access = walker.get_access()
	if(length(get_path_to(walker, destination, max_length, min_distance, access = own_access)))
		return destination
	var/list/path = get_path_to(walker, destination, max_length, min_distance, access = SSid_access.get_region_access_list(list(REGION_ALL_STATION)))
	if(QDELETED(walker) || !length(path))
		return null
	var/datum/can_pass_info/pass_info = new(walker, own_access)
	var/list/turf/walked = list(start)
	var/turf/last = start
	for(var/turf/next as anything in path)
		if(last.LinkBlockedWithAccess(next, pass_info))
			break
		walked += next
		last = next
	for(var/i in length(walked) to max(1, length(walked) - SP_DROP_STEP_BACK) step -1)
		var/turf/spot = walked[i]
		if(sp_good_drop_spot(spot))
			return spot
	return last
