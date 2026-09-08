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
 * so anything already being dragged is left to whoever has it.
 */
/proc/sp_find_crate_on_shuttle(mob/living/asking)
	for(var/turf/deck as anything in sp_supply_shuttle_turfs())
		for(var/obj/structure/closet/crate/crate in deck)
			var/taken = FALSE
			for(var/mob/living/carbon/human/other as anything in SSspacestation_sp.ai_crew)
				if(other != asking && other.pulling == crate)
					taken = TRUE
					break
			if(!taken)
				return crate
	return null

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
	for(var/turf/candidate as anything in candidates)
		if(candidate.density || candidate.is_blocked_turf(exclude_mobs = TRUE))
			continue
		var/distance = get_dist(origin, candidate)
		if(distance < best_distance)
			best = candidate
			best_distance = distance
	return best

/// The request a delivered crate belongs to, matched on the pack that made it.
/proc/sp_request_for_crate(obj/structure/closet/crate/crate)
	if(QDELETED(crate))
		return null
	for(var/datum/sp_supply_request/request as anything in SSspacestation_sp.supply_requests)
		if(request.status != SP_REQUEST_ORDERED || isnull(request.pack))
			continue
		// Crates are named after the pack that produced them.
		if(findtext(crate.name, request.pack.name) || crate.name == request.pack.name)
			return request
	return null
