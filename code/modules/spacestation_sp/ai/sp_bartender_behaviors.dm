// Behaviour for the AI bartender: pour a drink, put it on the bar, and go back for another glass when
// the shelf runs dry. See sp_bar.dm for the menu and the dispenser handling.

/// Put a glass under the taps and measure a drink into it.
/datum/bt_node/subtree/sp_bartender_pour
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_bartender_pour.bt.json"

/// Carry a finished drink out to the bar counter.
/datum/bt_node/subtree/sp_bartender_serve
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_bartender_serve.bt.json"

/// Fetch more glasses when there are none clean.
/datum/bt_node/subtree/sp_bartender_glasses
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_bartender_glasses.bt.json"

// --- Pouring -----------------------------------------------------------------------------------------

/**
 * Decides what to make and which tap to go to next.
 *
 * A drink half poured is kept rather than restarted: most cocktails need something from each of the two
 * dispensers, so this runs twice for one glass and the second pass finds the glass already holding the
 * gin and sends the bartender over for the tonic.
 */
/datum/bt_node/ai_behavior/sp_pick_drink
	time_between_perform = 3 SECONDS

/datum/bt_node/ai_behavior/sp_pick_drink/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/datum/sp_cocktail/drink = controller.blackboard[BB_SP_DRINK]
	var/obj/item/reagent_containers/cup/glass/drinkingglass/glass = controller.blackboard[BB_SP_GLASS]
	if(isnull(drink) || QDELETED(glass))
		var/datum/sp_cocktail/ordered = controller.blackboard[BB_SP_DRINK_ORDER]
		// An order beats the house menu, and beats a full counter: somebody asked for that one.
		if(isnull(ordered))
			var/obj/structure/table/counter = sp_find_service_counter(pawn, sp_bar_areas())
			if(!isnull(counter) && sp_counter_drinks(counter) >= SP_BAR_COUNTER_LIMIT)
				return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		glass = sp_find_clean_glass(pawn)
		if(QDELETED(glass))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		drink = ordered || pick(GLOB.sp_cocktails)

	var/list/missing = sp_missing_parts(drink, glass)
	if(sp_drink_ready(drink, glass))
		// Already made; the serving branch will take it from here.
		controller.clear_blackboard_key(BB_SP_DRINK)
		controller.clear_blackboard_key(BB_SP_GLASS)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/obj/machinery/chem_dispenser/dispenser
	for(var/dispenser_type in list(/obj/machinery/chem_dispenser/drinks/beer, /obj/machinery/chem_dispenser/drinks))
		var/obj/machinery/chem_dispenser/candidate = sp_find_bar_dispenser(pawn, dispenser_type)
		if(QDELETED(candidate))
			continue
		for(var/reagent_type in missing)
			if(reagent_type in candidate.dispensable_reagents)
				dispenser = candidate
				break
		if(dispenser)
			break
	if(QDELETED(dispenser))
		// Nothing here pours what this needs. Tip it out and pick something else next time.
		glass.reagents?.clear_reagents()
		controller.clear_blackboard_key(BB_SP_DRINK)
		controller.clear_blackboard_key(BB_SP_GLASS)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	if(!pawn.is_holding(glass))
		sp_free_hands(pawn)
		if(!pawn.put_in_hands(glass))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_DRINK, drink)
	controller.set_blackboard_key(BB_SP_GLASS, glass)
	controller.set_blackboard_key(BB_SP_DISPENSER, dispenser)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Puts the glass under the tap, measures in what this dispenser holds, and takes it back.
/datum/bt_node/ai_behavior/sp_pour_drink
	/// Snapshotted in perform() for perform_async().
	VAR_PRIVATE/obj/machinery/chem_dispenser/pour_dispenser

/datum/bt_node/ai_behavior/sp_pour_drink/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags

	var/mob/living/carbon/human/pawn = controller.pawn
	pour_dispenser = controller.blackboard[BB_SP_DISPENSER]
	controller.clear_blackboard_key(BB_SP_DISPENSER)
	if(!istype(pawn) || QDELETED(pour_dispenser) || !pour_dispenser.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(pour_dispenser)
	return start_async()

/datum/bt_node/ai_behavior/sp_pour_drink/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/chem_dispenser/dispenser = pour_dispenser
	var/datum/sp_cocktail/drink = controller.blackboard[BB_SP_DRINK]
	var/obj/item/reagent_containers/cup/glass/drinkingglass/glass = controller.blackboard[BB_SP_GLASS]
	if(isnull(drink) || QDELETED(glass))
		if(async_still_valid())
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return

	// Clicking the machine with the glass in hand slots it in, tipping out whatever was there already.
	if(!pawn.is_holding(glass))
		pawn.put_in_hands(glass)
	sp_ai_click(controller, dispenser)
	if(dispenser.beaker != glass)
		if(async_still_valid())
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return

	var/poured = 0
	for(var/reagent_type in sp_parts_from(drink, dispenser))
		poured += sp_dispense_into(dispenser, glass, reagent_type, drink.parts[reagent_type] * SP_DRINK_MEASURE)

	// Taking it back off is a right-click, and it needs a free hand to go into.
	sp_free_hands(pawn)
	sp_ai_click(controller, dispenser, list(RIGHT_CLICK = "1"))
	if(dispenser.beaker == glass)
		// It would not come out on its own; do not walk off and leave the glass in the machine.
		glass.forceMove(get_turf(pawn))
		dispenser.beaker = null
		pawn.put_in_hands(glass)

	if(!async_still_valid())
		return
	if(!poured)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!length(sp_missing_parts(drink, glass)))
		sp_record("bar.poured")
		log_sp("[pawn.real_name] mixed [drink.name]")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_pour_drink/finish_action(datum/ai_controller/controller, succeeded)
	pour_dispenser = null
	return ..()

// --- Serving -----------------------------------------------------------------------------------------

/// True when there is a finished drink to put out.
/datum/bt_node/decorator/sp_has_drink

/datum/bt_node/decorator/sp_has_drink/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return FALSE
	return !isnull(sp_find_poured_drink(pawn, controller.blackboard[BB_SP_DRINK]))

/// Takes the glass in hand and works out where the bar is.
/datum/bt_node/ai_behavior/sp_take_drink

/datum/bt_node/ai_behavior/sp_take_drink/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/glass = sp_find_poured_drink(pawn, controller.blackboard[BB_SP_DRINK])
	if(QDELETED(glass))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/structure/table/counter = sp_find_service_counter(pawn, sp_bar_areas())
	if(isnull(counter))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!pawn.is_holding(glass))
		sp_free_hands(pawn)
		if(!pawn.put_in_hands(glass))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_GLASS, glass)
	controller.set_blackboard_key(BB_SP_BAR_COUNTER, counter)
	return AI_BEHAVIOR_SUCCEEDED

/// Sets it down on the bar and calls it out.
/datum/bt_node/ai_behavior/sp_place_drink

/datum/bt_node/ai_behavior/sp_place_drink/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/item/glass = controller.blackboard[BB_SP_GLASS]
	var/obj/structure/table/counter = controller.blackboard[BB_SP_BAR_COUNTER]
	var/ordered_by = controller.blackboard[BB_SP_ORDER_FOR]
	var/mob/living/carbon/human/patron = controller.blackboard[BB_SP_ORDER_FROM]
	controller.clear_blackboard_key(BB_SP_GLASS)
	controller.clear_blackboard_key(BB_SP_BAR_COUNTER)
	controller.clear_blackboard_key(BB_SP_DRINK)
	controller.clear_blackboard_key(BB_SP_DRINK_ORDER)
	controller.clear_blackboard_key(BB_SP_ORDER_FOR)
	controller.clear_blackboard_key(BB_SP_ORDER_FROM)
	if(!istype(pawn) || QDELETED(glass) || QDELETED(counter) || !counter.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(counter)
	var/drink_name = glass.reagents?.get_master_reagent()?.name || "a drink"
	if(!pawn.transferItemToLoc(glass, get_turf(counter), silent = TRUE))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_record("bar.served")
	log_sp("[pawn.real_name] put [drink_name] on the bar in [get_area_name(counter)][ordered_by ? " for [ordered_by]" : ""]")
	if(ordered_by)
		sp_record("bar.order_filled")
		// Whoever ordered it gets a word over it, if they are still at the bar: order, comment, tip or tab.
		if(!isnull(sp_talk_about(pawn, patron, "served")))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
		sp_crew_speak(pawn, pick(
			"[ordered_by], your [drink_name] is up.",
			"One [drink_name] for [ordered_by], on the bar.",
			"[drink_name], [ordered_by]. Enjoy it.",
		))
	else
		sp_crew_speak(pawn, pick(
			"[drink_name], on the bar.",
			"There's [drink_name] up here if anyone wants it.",
			"Poured [drink_name]. Come and get it.",
			"Bar's open. [drink_name] going spare.",
		), RADIO_CHANNEL_SERVICE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Glassware ---------------------------------------------------------------------------------------

/// True when there is nothing clean left to pour into.
/datum/bt_node/decorator/sp_needs_glasses

/datum/bt_node/decorator/sp_needs_glasses/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return FALSE
	return isnull(sp_find_clean_glass(pawn))

/// Finds the dinnerware vendor, which is the only thing on the station that sells glasses.
/datum/bt_node/ai_behavior/sp_find_glass_vendor
	time_between_perform = 30 SECONDS

/datum/bt_node/ai_behavior/sp_find_glass_vendor/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/turf/origin = get_turf(pawn)
	var/obj/machinery/vending/dinnerware/best
	var/best_distance = INFINITY
	for(var/obj/machinery/vending/dinnerware/vendor as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/vending/dinnerware))
		var/turf/vendor_turf = get_turf(vendor)
		if(isnull(vendor_turf) || isnull(origin) || vendor_turf.z != origin.z || !vendor.is_operational)
			continue
		var/distance = get_dist(origin, vendor_turf)
		if(distance < best_distance)
			best = vendor
			best_distance = distance
	if(isnull(best))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_DISPENSER, best)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Buys a couple of glasses out of their own wages.
/datum/bt_node/ai_behavior/sp_buy_glasses

/datum/bt_node/ai_behavior/sp_buy_glasses/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/vending/vendor = controller.blackboard[BB_SP_DISPENSER]
	controller.clear_blackboard_key(BB_SP_DISPENSER)
	if(!istype(pawn) || QDELETED(vendor) || !vendor.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(vendor)
	var/bought = 0
	for(var/i in 1 to 2)
		var/obj/item/glass = sp_vend_product(pawn, vendor, /obj/item/reagent_containers/cup/glass/drinkingglass)
		if(QDELETED(glass))
			break
		if(!pawn.back || !glass.forceMove(pawn.back))
			pawn.put_in_hands(glass)
		bought++
	if(!bought)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
