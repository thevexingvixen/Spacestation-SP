// Cargo behaviour: the quartermaster's paperwork and shuttle runs, and the technicians' hauling.

/// Walk to a cargo console and put the outstanding requests on the order list.
/datum/bt_node/subtree/sp_qm_order
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_qm_order.bt.json"

/// Send the supply shuttle out and call it back.
/datum/bt_node/subtree/sp_qm_shuttle
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_qm_shuttle.bt.json"

/// Haul a crate off the shuttle, and walk requested ones to the department that asked.
/datum/bt_node/subtree/sp_cargo_haul
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_cargo_haul.bt.json"

// --- Quartermaster: ordering --------------------------------------------------------------------

/// True when there is something worth ordering and the budget can stand it.
/datum/bt_node/decorator/sp_has_orders_to_place

/datum/bt_node/decorator/sp_has_orders_to_place/check_condition(datum/ai_controller/controller)
	if(length(SSshuttle.shopping_list) >= 5)
		return FALSE // enough on this run already
	if(length(sp_pending_requests()))
		return TRUE
	// Nothing requested: only bother with the standing restock when the shuttle is home and idle.
	return sp_supply_docked_home() && !length(SSshuttle.shopping_list)

/// Finds a cargo console to do the paperwork at.
/datum/bt_node/ai_behavior/sp_find_cargo_console
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_cargo_console/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/machinery/computer/cargo/console = sp_find_cargo_console(pawn)
	if(isnull(console))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_CARGO_CONSOLE, console)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Places the orders: requests first, then a standing restock if there is nothing outstanding.
/datum/bt_node/ai_behavior/sp_place_orders

/datum/bt_node/ai_behavior/sp_place_orders/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/computer/cargo/console = controller.blackboard[BB_SP_CARGO_CONSOLE]
	if(!istype(pawn) || QDELETED(console) || !console.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(console)
	controller.clear_blackboard_key(BB_SP_CARGO_CONSOLE)

	var/list/placed_names = list()
	var/list/requests = sp_pending_requests()
	for(var/datum/sp_supply_request/request as anything in requests)
		if(length(placed_names) >= 3)
			break
		var/datum/supply_order/order = sp_place_order(request.pack, pawn, "requested by [request.requester_name]", request.area_type)
		if(isnull(order))
			continue
		request.status = SP_REQUEST_ORDERED
		request.order_id = order.id
		placed_names += request.pack.name
		sp_crew_speak(pawn, "Got your [request.pack.name] on the next run, [request.requester_name].", RADIO_CHANNEL_SUPPLY)

	// Nothing asked for: keep the shuttle earning its keep with a standing restock.
	if(!length(placed_names) && !length(SSshuttle.shopping_list))
		var/pack_type = pick(GLOB.sp_cargo_standing_order)
		var/datum/supply_pack/pack = SSshuttle.supply_packs[pack_type]
		var/datum/supply_order/order = sp_place_order(pack, pawn, "standing restock")
		if(!isnull(order))
			placed_names += pack.name

	if(!length(placed_names))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	log_sp("[pawn.real_name] placed orders: [english_list(placed_names)]")
	if(length(placed_names) > 1 || !length(requests))
		sp_crew_speak(pawn, "Orders in for [english_list(placed_names)]. Sending the shuttle shortly.", RADIO_CHANNEL_SUPPLY)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Quartermaster: the shuttle run --------------------------------------------------------------

/// True when the shuttle should be moved: orders waiting at home, or sitting idle at the depot.
/datum/bt_node/decorator/sp_shuttle_needs_moving

/datum/bt_node/decorator/sp_shuttle_needs_moving/check_condition(datum/ai_controller/controller)
	if(!sp_supply_movable())
		return FALSE
	if(sp_supply_docked_home())
		return length(SSshuttle.shopping_list) > 0
	return sp_supply_away()

/// Sends the shuttle out with the orders, or calls it back in with the goods.
/datum/bt_node/ai_behavior/sp_run_supply_shuttle

/datum/bt_node/ai_behavior/sp_run_supply_shuttle/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || !sp_supply_movable())
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	if(sp_supply_docked_home())
		if(!length(SSshuttle.shopping_list))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		SSshuttle.moveShuttle("cargo", "cargo_away", TRUE)
		log_sp("[pawn.real_name] sent the supply shuttle out with [length(SSshuttle.shopping_list)] order(s)")
		sp_crew_speak(pawn, "Shuttle's away with this run's orders.", RADIO_CHANNEL_SUPPLY)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

	if(sp_supply_away())
		SSshuttle.moveShuttle("cargo", "cargo_home", TRUE)
		log_sp("[pawn.real_name] called the supply shuttle back")
		sp_crew_speak(pawn, "Shuttle's on its way back. Someone give me a hand unloading.", RADIO_CHANNEL_SUPPLY)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

// --- Cargo technicians: hauling ------------------------------------------------------------------

/**
 * Finds a crate on the shuttle and works out where it belongs. Async for a crate somebody asked for: how close
 * to them a technician can actually get is a question for the pathfinder, and the pathfinder makes you wait.
 */
/datum/bt_node/ai_behavior/sp_find_crate
	time_between_perform = 3 SECONDS
	/// Held across the async half: the crate, the request it answers, and the spot in their department.
	VAR_PRIVATE/obj/structure/closet/crate/planned_crate
	VAR_PRIVATE/datum/sp_supply_request/planned_request
	VAR_PRIVATE/turf/planned_spot

/datum/bt_node/ai_behavior/sp_find_crate/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	// Already dragging one somewhere: finish that job. Without this, anything that interrupts a haul
	// leaves the crate stranded halfway across the station, because the search only looks on the shuttle.
	var/obj/structure/closet/crate/carrying = controller.blackboard[BB_SP_CRATE]
	var/turf/existing_destination = controller.blackboard[BB_SP_CRATE_DESTINATION]
	// Near enough counts: a dragged crate trails a tile behind the hauler, so demanding it sit exactly
	// on the destination tile would mean no haul ever finished.
	if(!QDELETED(carrying) && !isnull(existing_destination) && get_dist(get_turf(carrying), existing_destination) > 1)
		// But not forever. A haul that cannot finish would otherwise sit here running and starve the
		// quartermaster's paperwork, since a running branch outranks everything below it.
		var/deadline = controller.blackboard[BB_SP_HAUL_DEADLINE] || 0
		if(world.time < deadline)
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
		if(pawn.pulling == carrying)
			pawn.stop_pulling()
		log_sp("[pawn.real_name] gave up hauling [carrying.name] in [get_area_name(carrying)]")
		controller.clear_blackboard_key(BB_SP_CRATE_FOR)
		controller.clear_blackboard_key(BB_SP_CRATE)
		controller.clear_blackboard_key(BB_SP_CRATE_DESTINATION)
		controller.clear_blackboard_key(BB_SP_CRATE_ANNOUNCE)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/obj/structure/closet/crate/crate = sp_find_crate_on_shuttle(pawn)
	if(QDELETED(crate))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Ours from here, before the walk over, so the other technician picks a different one.
	controller.set_blackboard_key(BB_SP_CRATE, crate)

	// A crate somebody asked for goes to them; anything else just comes off the shuttle.
	var/datum/sp_supply_request/request = sp_request_for_crate(crate)
	var/turf/spot
	if(!isnull(request))
		spot = sp_find_delivery_spot(request.area_type, get_turf(crate))
	if(isnull(spot))
		return sp_start_haul(controller, sp_find_cargo_dropoff(pawn))
	planned_crate = crate
	planned_request = request
	planned_spot = spot
	return start_async()

/datum/bt_node/ai_behavior/sp_find_crate/perform_async(datum/ai_controller/controller)
	var/turf/spot = sp_reachable_drop_spot(controller.pawn, planned_spot)
	if(!async_still_valid())
		return
	if(QDELETED(planned_crate) || planned_request.status != SP_REQUEST_ORDERED)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(isnull(spot))
		// No way there even with every door open: it waits in the bay like anything else.
		finish_async(sp_start_haul(controller, sp_find_cargo_dropoff(controller.pawn)))
		return
	planned_request.status = SP_REQUEST_DELIVERED
	planned_request.crate = WEAKREF(planned_crate)
	controller.set_blackboard_key(BB_SP_CRATE_ANNOUNCE, planned_request.requester_name)
	controller.set_blackboard_key(BB_SP_CRATE_FOR, planned_request.requester_name)
	finish_async(sp_start_haul(controller, spot))

/datum/bt_node/ai_behavior/sp_find_crate/finish_action(datum/ai_controller/controller, succeeded)
	// A crate we claimed but never set off with goes back to the pool.
	if(!succeeded && !controller.blackboard[BB_SP_CRATE_DESTINATION])
		controller.clear_blackboard_key(BB_SP_CRATE)
		controller.clear_blackboard_key(BB_SP_CRATE_FOR)
		controller.clear_blackboard_key(BB_SP_CRATE_ANNOUNCE)
	planned_crate = null
	planned_request = null
	planned_spot = null
	return ..()

/// Sets a claimed crate off towards `destination`, or lets it go again if there is nowhere to take it.
/proc/sp_start_haul(datum/ai_controller/controller, turf/destination)
	if(isnull(destination))
		controller.clear_blackboard_key(BB_SP_CRATE)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_CRATE_DESTINATION, destination)
	controller.set_blackboard_key(BB_SP_HAUL_DEADLINE, world.time + SP_HAUL_TIMEOUT)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Takes hold of the crate, the way a technician drags one around.
/datum/bt_node/ai_behavior/sp_grab_crate

/datum/bt_node/ai_behavior/sp_grab_crate/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/closet/crate/crate = controller.blackboard[BB_SP_CRATE]
	if(!istype(pawn) || QDELETED(crate) || !crate.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(pawn.pulling == crate)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	// Somebody else has hold of it. Taking the pull off them only starts a tug of war that nobody wins.
	if(!isnull(crate.pulledby))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.start_pulling(crate, supress_message = TRUE)
	if(pawn.pulling != crate)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Say it now that the crate is actually in hand, rather than when it was spotted from across the station.
	var/announce_to = controller.blackboard[BB_SP_CRATE_ANNOUNCE]
	if(announce_to)
		sp_crew_speak(pawn, "Taking the [crate.name] over now, [announce_to].", RADIO_CHANNEL_SUPPLY)
		controller.clear_blackboard_key(BB_SP_CRATE_ANNOUNCE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Lets go once the crate is where it belongs.
/datum/bt_node/ai_behavior/sp_drop_crate

/datum/bt_node/ai_behavior/sp_drop_crate/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/closet/crate/crate = controller.blackboard[BB_SP_CRATE]
	if(istype(pawn) && pawn.pulling == crate)
		pawn.stop_pulling()
	if(!QDELETED(crate))
		log_sp("[pawn?.real_name] left [crate.name] in [get_area_name(crate)]")
		// Tell whoever asked where it ended up, which is short of their department when the door was not ours to open.
		var/for_whom = controller.blackboard[BB_SP_CRATE_FOR]
		if(for_whom && istype(pawn))
			sp_record("cargo.delivered")
			sp_crew_speak(pawn, "[for_whom], your [crate.name] is in [get_area_name(crate)].", RADIO_CHANNEL_COMMON)
	controller.clear_blackboard_key(BB_SP_CRATE_FOR)
	controller.clear_blackboard_key(BB_SP_CRATE)
	controller.clear_blackboard_key(BB_SP_CRATE_DESTINATION)
	controller.clear_blackboard_key(BB_SP_HAUL_DEADLINE)
	return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED
