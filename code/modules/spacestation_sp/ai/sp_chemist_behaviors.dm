// Behaviour-tree leaves and subtrees for the chemist.

/// Chemist: pick what medbay needs, walk to a bench, and brew it — into patches, or a beaker for the cryo tubes.
/datum/bt_node/subtree/sp_chemist_work
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chemist_work.bt.json"

/// Chemist: take finished medicine where it is wanted — patches into the chemistry fridge, cryoxadone to cryo.
/datum/bt_node/subtree/sp_chemist_deliver
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chemist_deliver.bt.json"

/// Picks the next thing to make (sp_next_chem_order) and the bench to make it at.
/datum/bt_node/ai_behavior/sp_pick_chem_order
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_pick_chem_order/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	// A product left over from an order that never reached the bench would count as work in hand.
	controller.clear_blackboard_key(BB_SP_CHEM_PRODUCT)
	controller.clear_blackboard_key(BB_SP_CHEM_FORM)
	if(!istype(pawn) || world.time < (controller.blackboard[BB_SP_CHEM_IDLE_UNTIL] || 0))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/bench = sp_find_chem_bench(pawn)
	var/list/order = isnull(bench) ? null : sp_next_chem_order(pawn, bench)
	if(isnull(order) || isnull(bench))
		// Medbay has what it needs, or there is nowhere to brew it. Look again in a minute.
		controller.set_blackboard_key(BB_SP_CHEM_IDLE_UNTIL, world.time + SP_CHEM_IDLE_TIME)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_CHEM_PRODUCT, order[1])
	controller.set_blackboard_key(BB_SP_CHEM_FORM, order[2])
	controller.set_blackboard_key(BB_SP_CHEM_BENCH, bench[1])
	controller.set_blackboard_key(BB_SP_CHEM_DISPENSER, bench[2])
	controller.set_blackboard_key(BB_SP_CHEM_HEATER, bench[3])
	controller.set_blackboard_key(BB_SP_CHEM_MASTER, bench[4])
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Standing at the bench: brews the order (sp_make_medicine), printing it into patches if that is its form.
/datum/bt_node/ai_behavior/sp_brew_order

/datum/bt_node/ai_behavior/sp_brew_order/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || get_turf(pawn) != controller.blackboard[BB_SP_CHEM_BENCH])
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_brew_order/perform_async(datum/ai_controller/controller)
	var/made = sp_make_medicine(
		controller,
		controller.blackboard[BB_SP_CHEM_PRODUCT],
		controller.blackboard[BB_SP_CHEM_FORM],
		controller.blackboard[BB_SP_CHEM_DISPENSER],
		controller.blackboard[BB_SP_CHEM_HEATER],
		controller.blackboard[BB_SP_CHEM_MASTER],
	)
	if(!async_still_valid())
		return
	controller.clear_blackboard_key(BB_SP_CHEM_PRODUCT)
	controller.clear_blackboard_key(BB_SP_CHEM_FORM)
	if(!made)
		// Whatever went wrong, do not stand at the bench trying it again every few seconds.
		controller.set_blackboard_key(BB_SP_CHEM_IDLE_UNTIL, world.time + SP_CHEM_IDLE_TIME)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/// Passes while we carry finished medicine with somewhere to go.
/datum/bt_node/decorator/sp_has_chem_delivery

/datum/bt_node/decorator/sp_has_chem_delivery/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || world.time < (controller.blackboard[BB_SP_CHEM_DELIVER_COOLDOWN] || 0))
		return FALSE
	return !isnull(sp_next_chem_drop(pawn))

/**
 * Picks where the medicine we carry goes into BB_SP_CHEM_DROP. It also sets a short wait before the next try,
 * which a delivery that lands clears again: a fridge that cannot be reached is not walked at every tick, but
 * a successful run goes straight on to the next, rather than sitting out a pause while the order board
 * sends the chemist back to the bench.
 */
/datum/bt_node/ai_behavior/sp_pick_chem_drop

/datum/bt_node/ai_behavior/sp_pick_chem_drop/perform(seconds_per_tick, datum/ai_controller/controller)
	var/list/drop = sp_next_chem_drop(controller.pawn)
	if(isnull(drop))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_CHEM_DROP, drop[1])
	controller.set_blackboard_key(BB_SP_CHEM_DELIVER_COOLDOWN, world.time + 20 SECONDS)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Drops the medicine off: every patch we carry into the chemistry fridge, or the cryoxadone onto the table in
 * the cryo room, where the medics' own cryo setup will find it when a tube runs low. Says so on medical.
 */
/datum/bt_node/ai_behavior/sp_drop_off_chems
	/// Where it is going, held across the async half.
	var/atom/drop

/datum/bt_node/ai_behavior/sp_drop_off_chems/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	drop = controller.blackboard[BB_SP_CHEM_DROP]
	if(!istype(pawn) || QDELETED(drop) || !pawn.Adjacent(drop))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_drop_off_chems/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/delivered = 0
	var/list/names = list()
	if(istype(drop, /obj/machinery/smartfridge))
		for(var/obj/item/reagent_containers/applicator/patch/patch as anything in pawn.get_all_contents_type(/obj/item/reagent_containers/applicator/patch))
			if(!sp_take_in_hand(pawn, patch))
				continue
			sp_ai_click(controller, drop)
			if(patch.loc == drop)
				delivered++
				names |= patch.name
	else
		var/obj/item/reagent_containers/cup/beaker = sp_carried_cryoxadone(pawn)
		if(beaker && sp_take_in_hand(pawn, beaker))
			// Clicking a table with something in hand puts it down there.
			sp_ai_click(controller, drop)
			if(isturf(beaker.loc))
				delivered = 1
				names |= "[round(sp_cryoxadone_units(beaker))]u of cryoxadone"
	if(!async_still_valid())
		return
	controller.clear_blackboard_key(BB_SP_CHEM_DROP)
	if(!delivered)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	controller.clear_blackboard_key(BB_SP_CHEM_DELIVER_COOLDOWN)
	if(istype(drop, /obj/machinery/smartfridge))
		sp_record("chem.stocked", delivered)
		sp_crew_speak(pawn, "[capitalize(english_list(names))] in the chem fridge.", RADIO_CHANNEL_MEDICAL)
	else
		sp_record("chem.cryoxadone")
		sp_crew_speak(pawn, "Fresh cryoxadone on the table in cryo.", RADIO_CHANNEL_MEDICAL)
	log_sp("[pawn.real_name] delivered [delivered] x [english_list(names)] to [drop.name] at [AREACOORD(drop)]")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)
