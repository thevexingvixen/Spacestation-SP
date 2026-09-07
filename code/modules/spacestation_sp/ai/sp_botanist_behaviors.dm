// Behaviour for the AI botanist: run the trays, gather the crop, deliver it to the kitchen.

/// Tend the nearest tray that wants something: harvest, clear, weed, water or plant.
/datum/bt_node/subtree/sp_botanist_tend
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_botanist_tend.bt.json"

/// Pick up produce we have knocked loose on the floor.
/datum/bt_node/subtree/sp_botanist_gather
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_botanist_gather.bt.json"

/// Carry a full satchel of produce to the kitchen, leaving a sample out on the way.
/datum/bt_node/subtree/sp_botanist_deliver
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_botanist_deliver.bt.json"

/// Refill the watering can when it runs dry.
/datum/bt_node/subtree/sp_botanist_refill
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_botanist_refill.bt.json"

// --- Tending ----------------------------------------------------------------------------------

/// Finds the nearest tray that needs work and records what it needs.
/datum/bt_node/ai_behavior/sp_find_tray
	time_between_perform = 2 SECONDS

/datum/bt_node/ai_behavior/sp_find_tray/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/found = sp_find_tray_job(pawn)
	if(isnull(found))
		controller.clear_blackboard_key(BB_SP_TRAY)
		controller.clear_blackboard_key(BB_SP_TRAY_JOB)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_TRAY, found[1])
	controller.set_blackboard_key(BB_SP_TRAY_JOB, found[2])
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Puts the right thing in our hands for the tray job we picked: nothing for harvesting and clearing,
 * the hoe for weeds, the watering can for a dry tray, a random seed packet for an empty one.
 */
/datum/bt_node/ai_behavior/sp_equip_for_tray

/datum/bt_node/ai_behavior/sp_equip_for_tray/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/job = controller.blackboard[BB_SP_TRAY_JOB]
	if(!istype(pawn) || isnull(job))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/obj/item/wanted
	switch(job)
		if(SP_TRAY_JOB_HARVEST, SP_TRAY_JOB_CLEAR)
			// Both of these are done bare-handed, so make sure the hand is actually empty.
			var/obj/item/held = pawn.get_active_held_item()
			if(held && !pawn.transferItemToLoc(held, pawn.back, silent = TRUE))
				pawn.dropItemToGround(held)
			controller.clear_blackboard_key(BB_SP_BOTANY_TOOL)
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
		if(SP_TRAY_JOB_WEED)
			wanted = locate(/obj/item/cultivator) in pawn.get_all_contents_type(/obj/item/cultivator)
		if(SP_TRAY_JOB_WATER)
			wanted = sp_botany_watering_can(pawn, TRUE)
		if(SP_TRAY_JOB_PLANT)
			wanted = sp_pick_seed(pawn)

	if(isnull(wanted))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!sp_equip_from_inventory(pawn, list(wanted.type)))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_BOTANY_TOOL, pawn.get_active_held_item())
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Works the tray with whatever is in our hands, then forgets it so the next tick re-evaluates.
/datum/bt_node/ai_behavior/sp_work_tray

/datum/bt_node/ai_behavior/sp_work_tray/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/hydroponics/tray = controller.blackboard[BB_SP_TRAY]
	var/job = controller.blackboard[BB_SP_TRAY_JOB]
	if(!istype(pawn) || QDELETED(tray))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!tray.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	pawn.face_atom(tray)
	var/plant_name = tray.myseed?.plantname
	controller.ai_interact(tray, combat_mode = FALSE)

	if(job == SP_TRAY_JOB_PLANT)
		var/obj/item/seeds/planted = tray.myseed
		if(planted)
			log_sp("[pawn.real_name] planted [planted.plantname]")
	else if(job == SP_TRAY_JOB_HARVEST && plant_name)
		log_sp("[pawn.real_name] harvested [plant_name]")

	controller.clear_blackboard_key(BB_SP_TRAY)
	controller.clear_blackboard_key(BB_SP_TRAY_JOB)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Gathering --------------------------------------------------------------------------------

/// Spots produce lying on the floor (harvesting drops it at our feet).
/datum/bt_node/ai_behavior/sp_find_produce
	time_between_perform = 1 SECONDS

/datum/bt_node/ai_behavior/sp_find_produce/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/food/grown/produce = sp_find_loose_produce(pawn)
	if(isnull(produce))
		controller.clear_blackboard_key(BB_SP_PRODUCE)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_PRODUCE, produce)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Picks the produce up and stows it, so our hands stay free for the next tray.
/datum/bt_node/ai_behavior/sp_stow_produce

/datum/bt_node/ai_behavior/sp_stow_produce/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/item/produce = controller.blackboard[BB_SP_PRODUCE]
	if(!istype(pawn) || QDELETED(produce) || !isturf(produce.loc) || !produce.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Straight into the bag; going via the hands just means dropping whatever we were holding.
	if(!pawn.back || !produce.forceMove(pawn.back))
		if(!pawn.put_in_hands(produce))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.clear_blackboard_key(BB_SP_PRODUCE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Delivery ---------------------------------------------------------------------------------

/// True once we are carrying enough produce to be worth a trip to the kitchen.
/datum/bt_node/decorator/sp_has_delivery

/datum/bt_node/decorator/sp_has_delivery/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return FALSE
	return length(sp_carried_produce(pawn)) >= SP_PRODUCE_DELIVERY_BATCH

/// Finds the kitchen table we are going to unload onto.
/datum/bt_node/ai_behavior/sp_find_kitchen
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_kitchen/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/structure/table/table = sp_find_kitchen_table(pawn)
	if(isnull(table))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_DELIVERY_TARGET, table)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Unloads the produce onto the table we are standing next to and tells the kitchen it is there.
/datum/bt_node/ai_behavior/sp_unload_produce
	/// Blackboard key holding the table.
	var/table_key = BB_SP_DELIVERY_TARGET
	/// Place at most this many; 0 means the whole load.
	var/max_place = 0
	/// Radio line to speak afterwards. "%COUNT%" and "%WHAT%" are substituted.
	var/announcement
	/// Radio channel for that line.
	var/radio_channel = RADIO_CHANNEL_SERVICE

/datum/bt_node/ai_behavior/sp_unload_produce/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/table/table = controller.blackboard[table_key]
	if(!istype(pawn) || QDELETED(table) || !table.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/list/carrying = sp_carried_produce(pawn)
	var/to_place = max_place ? min(max_place, length(carrying)) : length(carrying)
	if(to_place <= 0)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/turf/table_turf = get_turf(table)
	var/placed = 0
	var/list/names = list()
	for(var/obj/item/produce as anything in carrying)
		if(placed >= to_place)
			break
		if(!produce.forceMove(table_turf))
			continue
		names |= produce.name
		placed++
	if(!placed)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	controller.clear_blackboard_key(table_key)
	log_sp("[pawn.real_name] left [placed] produce on a table in [get_area_name(table)]")
	if(announcement)
		var/line = replacetext(announcement, "%COUNT%", "[placed]")
		line = replacetext(line, "%WHAT%", english_list(names))
		sp_crew_speak(pawn, line, radio_channel)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/datum/bt_node/ai_behavior/sp_unload_produce/kitchen
	announcement = "Dropped %COUNT% off in the kitchen: %WHAT%. Help yourself."

/// Samples left out in hydroponics for whoever wanders past.
/datum/bt_node/ai_behavior/sp_unload_produce/sample
	table_key = BB_SP_SAMPLE_TABLE
	max_place = 2
	announcement = "Put some %WHAT% out in hydroponics if anyone wants a sample."

/// Finds a table in hydroponics to leave samples on.
/datum/bt_node/ai_behavior/sp_find_sample_table
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_sample_table/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/structure/table/table = sp_find_sample_table(pawn)
	if(isnull(table))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_SAMPLE_TABLE, table)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Watering can refill ----------------------------------------------------------------------

/// True when we carry a watering can that has run dry and there is a tray that wants water.
/datum/bt_node/decorator/sp_needs_water_refill

/datum/bt_node/decorator/sp_needs_water_refill/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return FALSE
	if(isnull(sp_botany_watering_can(pawn)) || sp_botany_watering_can(pawn, TRUE))
		return FALSE // no can at all, or the one we have still has water
	for(var/obj/machinery/hydroponics/tray in oview(12, pawn))
		if(!isnull(tray.myseed) && tray.waterlevel < 30)
			return TRUE
	return FALSE

/// Finds something to refill the can from.
/datum/bt_node/ai_behavior/sp_find_water
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_water/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/structure/reagent_dispensers/source = sp_find_water_source(pawn)
	if(isnull(source))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_WATER_SOURCE, source)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Fills the can from the tank we are standing at.
/datum/bt_node/ai_behavior/sp_refill_can

/datum/bt_node/ai_behavior/sp_refill_can/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/reagent_dispensers/source = controller.blackboard[BB_SP_WATER_SOURCE]
	if(!istype(pawn) || QDELETED(source) || !source.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/reagent_containers/cup/watering_can/can = sp_botany_watering_can(pawn)
	if(isnull(can) || isnull(source.reagents) || isnull(can.reagents))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/wanted = can.reagents.maximum_volume - can.reagents.total_volume
	if(wanted <= 0 || !source.reagents.trans_to(can, wanted, transferred_by = pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.clear_blackboard_key(BB_SP_WATER_SOURCE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Seed extraction --------------------------------------------------------------------------

/// Carry produce of a species we have no seeds for to the extractor and turn it into packets.
/datum/bt_node/subtree/sp_botanist_extract
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_botanist_extract.bt.json"

/// Buy a seed variety we do not own from the MegaSeed Servitor.
/datum/bt_node/subtree/sp_botanist_shop
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_botanist_shop.bt.json"

/// Dose a growing plant with mutagen and see what it turns into.
/datum/bt_node/subtree/sp_botanist_experiment
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_botanist_experiment.bt.json"

/// Finds produce worth seeding and an extractor to do it in.
/datum/bt_node/ai_behavior/sp_find_extraction
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_extraction/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/produce = sp_produce_needing_seeds(pawn)
	if(isnull(produce))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/machinery/seed_extractor/extractor = sp_find_seed_extractor(pawn)
	if(isnull(extractor))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_EXTRACT_ITEM, produce)
	controller.set_blackboard_key(BB_SP_EXTRACTOR, extractor)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Feeds the produce into the extractor; the seeds drop out beside it for us to pick up.
/datum/bt_node/ai_behavior/sp_run_extractor

/datum/bt_node/ai_behavior/sp_run_extractor/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/seed_extractor/extractor = controller.blackboard[BB_SP_EXTRACTOR]
	var/obj/item/produce = controller.blackboard[BB_SP_EXTRACT_ITEM]
	if(!istype(pawn) || QDELETED(extractor) || QDELETED(produce) || !extractor.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!sp_equip_from_inventory(pawn, list(produce.type)))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/produce_name = produce.name
	pawn.face_atom(extractor)
	controller.ai_interact(extractor, combat_mode = FALSE)
	controller.clear_blackboard_key(BB_SP_EXTRACT_ITEM)
	controller.clear_blackboard_key(BB_SP_EXTRACTOR)
	log_sp("[pawn.real_name] extracted seeds from [produce_name]")
	sp_crew_speak(pawn, pick(
		"Got seeds off the [produce_name], that one's staying in the rotation.",
		"Seeded the [produce_name]. Should be able to grow more of those now.",
	), RADIO_CHANNEL_SERVICE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Buying seeds -----------------------------------------------------------------------------

/// Finds a seed vendor worth visiting.
/datum/bt_node/ai_behavior/sp_find_seed_vendor
	time_between_perform = 10 SECONDS

/datum/bt_node/ai_behavior/sp_find_seed_vendor/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/machinery/vending/hydroseeds/vendor = sp_find_seed_vendor(pawn)
	if(isnull(vendor))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_SEED_VENDOR, vendor)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Buys one packet of something we have never grown, out of our own wages.
/datum/bt_node/ai_behavior/sp_buy_seeds

/datum/bt_node/ai_behavior/sp_buy_seeds/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/vending/hydroseeds/vendor = controller.blackboard[BB_SP_SEED_VENDOR]
	if(!istype(pawn) || QDELETED(vendor) || !vendor.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(vendor)
	var/obj/item/bought = sp_buy_seed_packet(pawn, vendor)
	controller.clear_blackboard_key(BB_SP_SEED_VENDOR)
	if(isnull(bought))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_crew_speak(pawn, pick(
		"Picked up some [bought.name], never grown those before.",
		"Trying [bought.name] this shift. We'll see how it takes.",
	), RADIO_CHANNEL_SERVICE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Mutation experiments ---------------------------------------------------------------------

/// Finds a growing plant that could mutate into something else, and mutagen to push it along.
/datum/bt_node/ai_behavior/sp_find_experiment
	time_between_perform = 10 SECONDS

/datum/bt_node/ai_behavior/sp_find_experiment/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || isnull(sp_find_mutagen(pawn)))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	// Stick with the plant we already started on. Instability only pays off near 60, so a botanist who
	// dosed whichever tray happened to be nearest would never actually finish an experiment.
	var/obj/machinery/hydroponics/tray = controller.blackboard[BB_SP_EXPERIMENT_TRAY]
	if(!sp_is_mutation_candidate(tray))
		tray = sp_find_mutation_candidate(pawn)
		controller.set_blackboard_key(BB_SP_EXPERIMENT_TRAY, tray)
	if(isnull(tray))
		controller.clear_blackboard_key(BB_SP_EXPERIMENT_TRAY)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_MUTATE_TRAY, tray)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Pours mutagen into the tray. That raises the plant's instability, and an unstable plant has a
 * chance every growth cycle to mutate into another species from its own mutation list.
 */
/datum/bt_node/ai_behavior/sp_apply_mutagen

/datum/bt_node/ai_behavior/sp_apply_mutagen/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/hydroponics/tray = controller.blackboard[BB_SP_MUTATE_TRAY]
	if(!istype(pawn) || QDELETED(tray) || !tray.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/reagent_containers/cup/bottle/mutagen = sp_find_mutagen(pawn)
	if(isnull(mutagen) || isnull(tray.myseed))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!sp_equip_from_inventory(pawn, list(mutagen.type)))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/plant_name = tray.myseed.plantname
	// Dial the container up to pour everything in one go. Instability only pays off near 60, and the
	// default 5-10 unit splash would never get a plant anywhere near that.
	mutagen.amount_per_transfer_from_this = mutagen.reagents.total_volume
	pawn.face_atom(tray)
	controller.ai_interact(tray, combat_mode = FALSE)
	controller.clear_blackboard_key(BB_SP_MUTATE_TRAY)
	log_sp("[pawn.real_name] dosed [plant_name] with mutagen (instability now [tray.myseed?.instability])")
	sp_crew_speak(pawn, pick(
		"Dosing the [plant_name] with mutagen. Let's see what it turns into.",
		"Running an experiment on the [plant_name]. Might get something new.",
	), RADIO_CHANNEL_SERVICE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
