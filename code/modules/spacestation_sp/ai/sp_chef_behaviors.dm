// Behaviour for the AI chef: stock the prep table, climb the cooking tree, plate up, and shout when
// the kitchen runs dry. See sp_kitchen.dm for the helpers these lean on.

/// Carry a finished dish out to the counter.
/datum/bt_node/subtree/sp_chef_serve
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chef_serve.bt.json"

/// Craft whatever the pile on the prep table currently supports.
/datum/bt_node/subtree/sp_chef_cook
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chef_cook.bt.json"

/// Take cooked food back out of the oven and off the griddle.
/datum/bt_node/subtree/sp_chef_collect
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chef_collect.bt.json"

/// Cut, roll, grill, bake and grind raw stock into the parts recipes are made of.
/datum/bt_node/subtree/sp_chef_prep
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chef_prep.bt.json"

/// Mix dough and cheese in a bowl.
/datum/bt_node/subtree/sp_chef_mix
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chef_mix.bt.json"

/// Fetch ingredients out of the fridges and off the floor.
/datum/bt_node/subtree/sp_chef_stock
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chef_stock.bt.json"

/// Ask cargo for a food crate when the kitchen has nothing left.
/datum/bt_node/subtree/sp_chef_supply
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_chef_supply.bt.json"

// --- Shared ---------------------------------------------------------------------------------------

/// Puts something we have just made back on the prep table, where the next step can find it.
/proc/sp_stash_on_table(mob/living/carbon/human/chef, obj/structure/table/prep_table, obj/item/thing)
	if(QDELETED(prep_table) || QDELETED(thing))
		return FALSE
	return thing.forceMove(get_turf(prep_table))

/// Finds the prep table and remembers it. Everything else in the kitchen hangs off this.
/datum/bt_node/ai_behavior/sp_find_prep_table
	time_between_perform = 10 SECONDS

/datum/bt_node/ai_behavior/sp_find_prep_table/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/structure/table/known = controller.blackboard[BB_SP_PREP_TABLE]
	if(!QDELETED(known))
		return AI_BEHAVIOR_SUCCEEDED
	var/obj/structure/table/table = sp_find_prep_table(pawn)
	if(isnull(table))
		log_kitchen("[pawn.real_name] found no prep table")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_PREP_TABLE, table)
	return AI_BEHAVIOR_SUCCEEDED

// --- Serving --------------------------------------------------------------------------------------

/// True when we have something finished to put out and somewhere to put it.
/datum/bt_node/decorator/sp_has_dish

/datum/bt_node/decorator/sp_has_dish/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return FALSE
	return !isnull(sp_find_dish_to_serve(pawn))

/// Takes the dish in hand and works out which counter it is going on.
/datum/bt_node/ai_behavior/sp_take_dish

/datum/bt_node/ai_behavior/sp_take_dish/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/food/dish = sp_find_dish_to_serve(pawn)
	if(QDELETED(dish))
		log_kitchen("[pawn.real_name] has no dish to serve after all")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/structure/table/counter = sp_find_counter(pawn)
	if(isnull(counter))
		log_kitchen("[pawn.real_name] cannot find a counter for [dish]")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// A counter nobody has cleared is a counter nobody wants more food on.
	if(sp_counter_load(counter) >= SP_COUNTER_LIMIT)
		log_kitchen("[pawn.real_name] finds the counter already stacked with [sp_counter_load(counter)]")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!pawn.is_holding(dish))
		sp_free_hands(pawn)
		if(!pawn.put_in_hands(dish))
			log_kitchen("[pawn.real_name] could not pick up [dish] to serve it")
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_DISH, dish)
	controller.set_blackboard_key(BB_SP_COUNTER, counter)
	return AI_BEHAVIOR_SUCCEEDED

/// Sets the dish down on the counter and says so.
/datum/bt_node/ai_behavior/sp_plate_dish

/datum/bt_node/ai_behavior/sp_plate_dish/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/item/food/dish = controller.blackboard[BB_SP_DISH]
	var/obj/structure/table/counter = controller.blackboard[BB_SP_COUNTER]
	controller.clear_blackboard_key(BB_SP_DISH)
	controller.clear_blackboard_key(BB_SP_COUNTER)
	if(!istype(pawn) || QDELETED(dish) || QDELETED(counter) || !counter.Adjacent(pawn))
		log_kitchen("[pawn?.real_name] reached the counter without the dish still in hand")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/turf/counter_turf = get_turf(counter)
	pawn.face_atom(counter)
	var/dish_name = dish.name
	if(!pawn.transferItemToLoc(dish, counter_turf, silent = TRUE))
		log_kitchen("[pawn.real_name] could not put [dish_name] down on the counter")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_record("chef.served")
	log_sp("[pawn.real_name] served [dish_name] on the counter in [get_area_name(counter)]")
	sp_crew_speak(pawn, pick(
		"[dish_name], up on the counter. Come and get it.",
		"Fresh [dish_name] on the counter.",
		"There's [dish_name] ready if anyone's hungry.",
	), RADIO_CHANNEL_SERVICE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Cooking --------------------------------------------------------------------------------------

/// Crafts one of the things the pile on the table currently allows.
/datum/bt_node/ai_behavior/sp_cook_dish
	/// The recipe picked in perform(), for perform_async() to read.
	VAR_PRIVATE/datum/crafting_recipe/cook_recipe

/datum/bt_node/ai_behavior/sp_cook_dish/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags

	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/table/prep_table = controller.blackboard[BB_SP_PREP_TABLE]
	if(!istype(pawn) || QDELETED(prep_table) || !prep_table.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	// Crafting reads what we are holding as an ingredient, and a knife in hand is not an ingredient.
	sp_free_hands(pawn)
	pawn.face_atom(prep_table)

	var/list/datum/crafting_recipe/possible = sp_craftable_recipes(pawn)
	if(!length(possible))
		log_kitchen("[pawn.real_name] has nothing craftable from [length(sp_pantry_contents(prep_table))] item(s) on the table")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	// Prefer something that can go straight out to the crew; components are still worth making, because
	// the prep steps and the next craft will take them the rest of the way.
	var/list/datum/crafting_recipe/dishes = list()
	for(var/datum/crafting_recipe/recipe as anything in possible)
		if(sp_recipe_makes_dish(recipe))
			dishes += recipe
	cook_recipe = pick(length(dishes) ? dishes : possible)
	return start_async()

/datum/bt_node/ai_behavior/sp_cook_dish/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/crafting_recipe/recipe = cook_recipe
	var/datum/component/personal_crafting/crafting = pawn.GetComponent(/datum/component/personal_crafting)
	if(isnull(crafting) || isnull(recipe))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	var/result = crafting.construct_item(pawn, recipe)
	if(!async_still_valid())
		return
	if(istext(result))
		log_kitchen("[pawn.real_name] could not make [recipe.name][result]")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	var/obj/item/made = result
	sp_record("chef.cooked")
	log_sp("[pawn.real_name] cooked [made.name]")
	// Crafting drops the result at our feet. Anything half-made (a raw pizza, say) goes back on the pile
	// for the oven rung; a finished dish goes straight into our hands, because the next craft reads the
	// tiles around us as ingredients and would otherwise fold the dish we just made into another one.
	if(sp_is_finished_dish(made))
		sp_free_hands(pawn)
		var/in_hand = pawn.put_in_hands(made)
		if(in_hand)
			controller.set_blackboard_key(BB_SP_DISH, made)
		log_kitchen("[pawn.real_name] plated [made.name][in_hand ? "" : " but could not pick it up"]")
	else
		log_kitchen("[pawn.real_name] put [made.name] back on the pile; it is not finished yet")
		sp_stash_on_table(pawn, controller.blackboard[BB_SP_PREP_TABLE], made)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_cook_dish/finish_action(datum/ai_controller/controller, succeeded)
	cook_recipe = null
	return ..()

// --- Collecting from the machines -----------------------------------------------------------------

/// Spots an oven or griddle with something finished sitting in it.
/datum/bt_node/ai_behavior/sp_find_cooked
	time_between_perform = 3 SECONDS

/datum/bt_node/ai_behavior/sp_find_cooked/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/machinery/machine = sp_find_finished_machine(pawn)
	if(isnull(machine))
		log_kitchen("[pawn.real_name] sees nothing ready: [sp_machine_report(pawn)]")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_COOK_MACHINE, machine)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Empties the finished food out of the machine and switches it off behind us.
/datum/bt_node/ai_behavior/sp_take_cooked
	/// Snapshotted in perform() for perform_async().
	VAR_PRIVATE/obj/machinery/cook_machine

/datum/bt_node/ai_behavior/sp_take_cooked/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags

	var/mob/living/carbon/human/pawn = controller.pawn
	cook_machine = controller.blackboard[BB_SP_COOK_MACHINE]
	controller.clear_blackboard_key(BB_SP_COOK_MACHINE)
	if(!istype(pawn) || QDELETED(cook_machine) || !cook_machine.Adjacent(pawn))
		log_kitchen("[pawn?.real_name] could not reach [cook_machine] to empty it")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(cook_machine)
	return start_async()

/datum/bt_node/ai_behavior/sp_take_cooked/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/machine = cook_machine
	var/obj/machinery/oven/oven = machine
	if(istype(oven) && !oven.open)
		sp_free_hands(pawn)
		sp_ai_click(controller, oven)

	var/list/obj/item/done = sp_finished_in_machine(machine)
	var/taken = 0
	var/list/names = list()
	for(var/obj/item/cooked as anything in done)
		// Anything that came out ruined still has to come out, or it blocks the machine — but it goes
		// on the floor, not in the bag with the food.
		if(istype(cooked, /obj/item/food/badrecipe))
			cooked.forceMove(get_turf(pawn))
			taken++
			names |= cooked.name
			continue
		if(!pawn.back || !cooked.forceMove(pawn.back))
			if(!pawn.put_in_hands(cooked))
				continue
		names |= cooked.name
		taken++

	// Nothing left cooking: turn the griddle off rather than leave it burning all shift.
	var/obj/machinery/griddle/griddle = machine
	if(taken && istype(griddle) && griddle.on && !length(griddle.griddled_objects))
		sp_free_hands(pawn)
		sp_ai_click(controller, griddle)

	if(!async_still_valid())
		return
	if(!taken)
		log_kitchen("[pawn.real_name] could not get [length(done)] finished item(s) out of [machine.name]")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_record("chef.collected")
	log_sp("[pawn.real_name] took [taken] item(s) off the [machine.name]: [english_list(names)]")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_take_cooked/finish_action(datum/ai_controller/controller, succeeded)
	cook_machine = null
	return ..()

// --- Prep ----------------------------------------------------------------------------------------

/// Picks the next rung of the cooking tree to climb, and where we have to stand to climb it.
/datum/bt_node/ai_behavior/sp_find_prep_task
	time_between_perform = 2 SECONDS

/datum/bt_node/ai_behavior/sp_find_prep_task/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/table/prep_table = controller.blackboard[BB_SP_PREP_TABLE]
	if(!istype(pawn) || QDELETED(prep_table))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/found = sp_find_prep_step(pawn, prep_table)
	if(isnull(found))
		log_kitchen("[pawn.real_name] has no prep step for [length(sp_pantry_contents(prep_table))] item(s) on the table")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/datum/sp_prep_step/step = found[1]
	var/obj/item/ingredient = found[2]
	var/atom/target = prep_table
	var/list/obj/item/load = list(ingredient)
	var/machine_type = step.machine_type()
	if(machine_type)
		target = sp_find_kitchen_machine(pawn, machine_type)
		var/room = sp_machine_room(target)
		if(isnull(target) || room <= 0)
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		// One trip, one load. The oven in particular is left shut afterwards until it is empty again.
		load = sp_prep_batch(prep_table, step, ingredient, room)
	controller.set_blackboard_key(BB_SP_PREP_STEP, step)
	controller.set_blackboard_key(BB_SP_PREP_ITEM, ingredient)
	controller.set_blackboard_key(BB_SP_PREP_BATCH, load)
	controller.set_blackboard_key(BB_SP_PREP_TARGET, target)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Gets a grip on the job: the tool in hand for knife and rolling-pin work (the ingredient stays on the
 * table, which is where processing requires it), the ingredient in hand for anything going in a machine.
 */
/datum/bt_node/ai_behavior/sp_hold_for_prep

/datum/bt_node/ai_behavior/sp_hold_for_prep/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/sp_prep_step/step = controller.blackboard[BB_SP_PREP_STEP]
	var/obj/item/ingredient = controller.blackboard[BB_SP_PREP_ITEM]
	if(!istype(pawn) || isnull(step) || QDELETED(ingredient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	if(step.operation == SP_PREP_TOOL)
		if(isnull(sp_equip_from_inventory(pawn, list(step.tool_type))))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		return AI_BEHAVIOR_SUCCEEDED

	if(!ingredient.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_free_hands(pawn)
	var/list/obj/item/load = controller.blackboard[BB_SP_PREP_BATCH] || list(ingredient)
	var/carried = 0
	for(var/obj/item/thing as anything in load)
		if(QDELETED(thing) || !thing.Adjacent(pawn))
			continue
		if(!pawn.back || !thing.forceMove(pawn.back))
			if(!pawn.put_in_hands(thing))
				continue
		carried++
	if(!carried)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return AI_BEHAVIOR_SUCCEEDED

/// Does the actual cutting, rolling, grilling, baking or grinding.
/datum/bt_node/ai_behavior/sp_do_prep
	/// Snapshotted in perform() for perform_async().
	VAR_PRIVATE/datum/sp_prep_step/prep_step
	VAR_PRIVATE/obj/item/prep_item
	VAR_PRIVATE/atom/prep_target
	VAR_PRIVATE/list/obj/item/prep_load

/datum/bt_node/ai_behavior/sp_do_prep/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags

	var/mob/living/carbon/human/pawn = controller.pawn
	prep_step = controller.blackboard[BB_SP_PREP_STEP]
	prep_item = controller.blackboard[BB_SP_PREP_ITEM]
	prep_target = controller.blackboard[BB_SP_PREP_TARGET]
	prep_load = controller.blackboard[BB_SP_PREP_BATCH] || list(prep_item)
	controller.clear_blackboard_key(BB_SP_PREP_STEP)
	controller.clear_blackboard_key(BB_SP_PREP_ITEM)
	controller.clear_blackboard_key(BB_SP_PREP_BATCH)
	controller.clear_blackboard_key(BB_SP_PREP_TARGET)
	if(!istype(pawn) || isnull(prep_step) || QDELETED(prep_item) || QDELETED(prep_target))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!prep_target.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(prep_target)
	return start_async()

/datum/bt_node/ai_behavior/sp_do_prep/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/sp_prep_step/step = prep_step
	var/obj/item/ingredient = prep_item
	var/atom/target = prep_target
	var/worked = FALSE

	switch(step.operation)
		if(SP_PREP_TOOL)
			// Processing is a tool act on the ingredient itself, which has to be lying on a table.
			sp_ai_click(controller, ingredient)
			worked = QDELETED(ingredient)
		if(SP_PREP_GRILL)
			var/obj/machinery/griddle/griddle = target
			// The griddle places what you click it with wherever on the plate you clicked.
			for(var/obj/item/thing as anything in prep_load)
				if(QDELETED(thing) || !pawn.put_in_hands(thing))
					continue
				sp_ai_click(controller, griddle, list(ICON_X = "16", ICON_Y = "16"))
				if(thing in griddle.griddled_objects)
					worked = TRUE
			sp_free_hands(pawn)
			if(worked && !griddle.on)
				sp_ai_click(controller, griddle)
		if(SP_PREP_BAKE)
			var/obj/machinery/oven/oven = target
			// Hands empty first: clicking a shut oven with something in them does nothing at all.
			sp_free_hands(pawn)
			if(!oven.open)
				sp_ai_click(controller, oven)
			if(oven.open && !isnull(oven.used_tray))
				for(var/obj/item/thing as anything in prep_load)
					if(QDELETED(thing) || !pawn.put_in_hands(thing))
						continue
					sp_ai_click(controller, oven.used_tray, list(ICON_X = "16", ICON_Y = "16"))
					if(thing.loc == oven.used_tray)
						worked = TRUE
				sp_free_hands(pawn)
				if(worked)
					sp_ai_click(controller, oven) // shut the door, which starts it baking
					log_kitchen("[pawn.real_name] loaded [oven] with [length(oven.used_tray.contents)]: shut [!oven.open], baking [oven.appears_active()]")
		if(SP_PREP_PROCESS)
			var/obj/machinery/processor/processor = target
			if(!pawn.is_holding(ingredient) && !pawn.put_in_hands(ingredient))
				finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
				return
			sp_ai_click(controller, processor)
			worked = (ingredient.loc == processor)
			if(worked)
				sp_free_hands(pawn)
				sp_ai_click(controller, processor)

	if(!async_still_valid())
		return
	if(!worked)
		log_kitchen("[pawn.real_name] failed the [step.operation] step on [ingredient] at [target]")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_record("chef.prepped")
	log_sp("[pawn.real_name] prepped [step.name]")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_do_prep/finish_action(datum/ai_controller/controller, succeeded)
	prep_step = null
	prep_item = null
	prep_target = null
	prep_load = null
	return ..()

// --- Mixing --------------------------------------------------------------------------------------

/// Works out what is worth mixing, in what, and whether we need to stop at the sink on the way.
/datum/bt_node/ai_behavior/sp_find_mix_task
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_mix_task/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/table/prep_table = controller.blackboard[BB_SP_PREP_TABLE]
	if(!istype(pawn) || QDELETED(prep_table))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/obj/item/reagent_containers/cup/bowl/bowl = controller.blackboard[BB_SP_MIX_BOWL]
	var/datum/sp_kitchen_mix/mix = controller.blackboard[BB_SP_MIX]
	// A bowl that already has water in it is a mix half done; do not start a different one.
	if(QDELETED(bowl) || isnull(mix))
		bowl = sp_find_mixing_bowl(pawn, prep_table)
		if(QDELETED(bowl))
			log_kitchen("[pawn.real_name] has no empty bowl to mix in")
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		mix = sp_find_mix(pawn, prep_table, bowl)
		if(isnull(mix))
			log_kitchen("[pawn.real_name] has nothing worth mixing")
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/water_wanted = mix.reagents[/datum/reagent/water]
	var/atom/target = prep_table
	if(water_wanted && bowl.reagents?.get_reagent_amount(/datum/reagent/water) < water_wanted)
		target = sp_find_kitchen_sink(pawn)
		if(isnull(target))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	if(!pawn.is_holding(bowl))
		sp_free_hands(pawn)
		if(!pawn.put_in_hands(bowl))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_MIX, mix)
	controller.set_blackboard_key(BB_SP_MIX_BOWL, bowl)
	controller.set_blackboard_key(BB_SP_MIX_TARGET, target)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * One leg of a mix. At the sink that means running water into the bowl; at the table it means pouring
 * the dry goods in, at which point the reaction fires and drops dough or a cheese wheel at our feet.
 */
/datum/bt_node/ai_behavior/sp_work_mix

/datum/bt_node/ai_behavior/sp_work_mix/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/sp_kitchen_mix/mix = controller.blackboard[BB_SP_MIX]
	var/obj/item/reagent_containers/cup/bowl/bowl = controller.blackboard[BB_SP_MIX_BOWL]
	var/atom/target = controller.blackboard[BB_SP_MIX_TARGET]
	controller.clear_blackboard_key(BB_SP_MIX_TARGET)
	if(!istype(pawn) || isnull(mix) || QDELETED(bowl) || QDELETED(target) || !target.Adjacent(pawn))
		return sp_abandon_mix(controller)
	pawn.face_atom(target)

	if(istype(target, /obj/structure/sink))
		// Keep the bowl in hand and let the sink do the filling, as a cook would.
		controller.ai_interact(target, combat_mode = FALSE)
		if(bowl.reagents?.get_reagent_amount(/datum/reagent/water) < mix.reagents[/datum/reagent/water])
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED // another pour next tick
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

	var/obj/structure/table/prep_table = target
	for(var/reagent_type in mix.reagents)
		if(reagent_type == /datum/reagent/water)
			continue
		var/wanted = mix.reagents[reagent_type]
		if(bowl.reagents?.get_reagent_amount(reagent_type) >= wanted)
			continue
		var/obj/item/reagent_containers/source = sp_find_reagent_source(pawn, prep_table, reagent_type, wanted, bowl)
		if(QDELETED(source))
			return sp_abandon_mix(controller)
		// Measured out rather than clicked across: a condiment bottle pours a fixed dose per click and
		// these reactions want an exact amount, so a click loop would just overshoot.
		source.reagents.trans_to(bowl, wanted, target_id = reagent_type, transferred_by = pawn)

	var/made = mix.name
	controller.clear_blackboard_key(BB_SP_MIX)
	controller.clear_blackboard_key(BB_SP_MIX_BOWL)
	if(!QDELETED(bowl) && bowl.reagents?.total_volume)
		// The reaction did not fire, so something was short. Empty the bowl and start over later.
		bowl.reagents.clear_reagents()
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_record("chef.mixed")
	log_sp("[pawn.real_name] mixed [made]")
	// The reaction drops what it made on the floor under us; it belongs on the pile.
	for(var/obj/item/food/fresh in get_turf(pawn))
		if(!sp_is_finished_dish(fresh))
			sp_stash_on_table(pawn, prep_table, fresh)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Drops the current mix so the next attempt starts fresh.
/proc/sp_abandon_mix(datum/ai_controller/controller)
	controller.clear_blackboard_key(BB_SP_MIX)
	controller.clear_blackboard_key(BB_SP_MIX_BOWL)
	controller.clear_blackboard_key(BB_SP_MIX_TARGET)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

// --- Stock ---------------------------------------------------------------------------------------

/// True while there is stocking to do: an armful to put down, or a table with too little on it.
/datum/bt_node/decorator/sp_stocking_needed

/datum/bt_node/decorator/sp_stocking_needed/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return FALSE
	if(length(sp_carried_ingredients(pawn)))
		return TRUE
	var/obj/structure/table/prep_table = controller.blackboard[BB_SP_PREP_TABLE]
	if(QDELETED(prep_table))
		return TRUE
	return length(sp_pantry_contents(prep_table)) < SP_PANTRY_TARGET

/// Finds the next fridge, cabinet or pile of food to raid.
/datum/bt_node/ai_behavior/sp_find_stock
	time_between_perform = 3 SECONDS

/datum/bt_node/ai_behavior/sp_find_stock/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/table/prep_table = controller.blackboard[BB_SP_PREP_TABLE]
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/carrying = length(sp_carried_ingredients(pawn))
	var/atom/source = carrying >= SP_STOCK_ARMFUL ? null : sp_find_stock_source(pawn, prep_table)
	// Nothing more to collect, or hands full: take what we have back to the table. Doing a lap of the
	// kitchen per tomato is what a shift of walking looks like and gets nothing cooked.
	if(isnull(source))
		if(!carrying)
			log_kitchen("[pawn.real_name] can find nothing left to stock the kitchen with")
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		source = prep_table
	controller.set_blackboard_key(BB_SP_STOCK_SOURCE, source)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Ingredients the chef is carrying that belong on the prep table.
/proc/sp_carried_ingredients(mob/living/carbon/human/chef)
	var/list/obj/item/carried = list()
	for(var/obj/item/thing as anything in chef.get_all_contents_type(/obj/item))
		if(!sp_is_ingredient(thing) || sp_is_finished_dish(thing))
			continue
		if(istype(thing, /obj/item/reagent_containers/condiment) && !thing.reagents?.total_volume)
			continue
		carried += thing
	return carried

/// Takes an armful out of whatever we walked to, or unloads onto the table when that is where we are.
/datum/bt_node/ai_behavior/sp_take_stock
	/// Snapshotted in perform() for perform_async().
	VAR_PRIVATE/atom/stock_source

/datum/bt_node/ai_behavior/sp_take_stock/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags

	var/mob/living/carbon/human/pawn = controller.pawn
	stock_source = controller.blackboard[BB_SP_STOCK_SOURCE]
	controller.clear_blackboard_key(BB_SP_STOCK_SOURCE)
	if(!istype(pawn) || QDELETED(stock_source) || !stock_source.Adjacent(pawn))
		log_kitchen("[pawn?.real_name] could not reach [stock_source] to stock from")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(stock_source)
	return start_async()

/datum/bt_node/ai_behavior/sp_take_stock/finish_action(datum/ai_controller/controller, succeeded)
	stock_source = null
	return ..()

/datum/bt_node/ai_behavior/sp_take_stock/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/atom/source = stock_source
	var/obj/structure/table/prep_table = controller.blackboard[BB_SP_PREP_TABLE]

	// Standing at the table with an armful: that is the delivery half of the job.
	if(source == prep_table)
		var/turf/table_turf = get_turf(prep_table)
		var/placed = 0
		for(var/obj/item/thing as anything in sp_carried_ingredients(pawn))
			if(length(sp_pantry_contents(prep_table)) >= SP_PANTRY_TARGET + 6)
				break
			if(!thing.forceMove(table_turf))
				continue
			placed++
		if(!placed)
			log_kitchen("[pawn.real_name] had nothing to lay out")
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
			return
		log_sp("[pawn.real_name] laid [placed] ingredient(s) out on the prep table")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)
		return

	// Food lying on a table or the floor. Clear the whole tile: a botany delivery is a pile, and one
	// walk across the kitchen per tomato is not how anybody works.
	if(isitem(source))
		var/gathered = 0
		for(var/obj/item/loose in get_turf(source))
			if(!sp_is_ingredient(loose) || sp_is_finished_dish(loose))
				continue
			if(!pawn.back || !loose.forceMove(pawn.back))
				if(!pawn.put_in_hands(loose))
					continue
			gathered++
		if(!gathered)
			log_kitchen("[pawn.real_name] could not pick up [source]")
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
			return
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)
		return

	// The dinnerware vendor: buy a bowl and carry it back with everything else.
	if(istype(source, /obj/machinery/vending/dinnerware))
		var/obj/item/bought = sp_buy_bowl(pawn, source)
		if(QDELETED(bought))
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
			return
		if(!pawn.back || !bought.forceMove(pawn.back))
			pawn.put_in_hands(bought)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)
		return

	// A fridge or a cabinet. Open it the way anyone would; the chef's ID covers the locked ones.
	var/obj/structure/closet/closet = source
	if(istype(closet) && !closet.opened)
		sp_free_hands(pawn)
		// The freezers are locked, and a locked closet does not open to a plain click: unlocking one is
		// a right-click, which runs the access check against the ID we are wearing.
		if(closet.locked)
			sp_ai_click(controller, closet, list(RIGHT_CLICK = "1"))
		if(closet.locked)
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
			return
		sp_ai_click(controller, closet)
		if(!closet.opened)
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
			return

	// Opening a closet tips its contents onto the floor, so take what is in it and what just fell out.
	var/list/obj/item/available = sp_stock_in(source)
	for(var/obj/item/spilled in get_turf(source))
		if(sp_is_ingredient(spilled) && !sp_is_finished_dish(spilled))
			available |= spilled
	var/taken = 0
	for(var/obj/item/thing as anything in available)
		if(taken >= 6)
			break
		if(!pawn.back || !thing.forceMove(pawn.back))
			continue
		taken++
	if(!taken)
		log_kitchen("[pawn.real_name] took nothing out of [source.name]")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	log_sp("[pawn.real_name] took [taken] ingredient(s) from [source.name]")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)
	return

// --- Asking cargo --------------------------------------------------------------------------------

/**
 * True when the kitchen has been picked clean: the worktop is not stocked, we are not carrying an
 * armful, and there is no fridge, cabinet or pile left in the kitchen with anything in it.
 *
 * A worktop with a few things on it is not the same as a stocked one. Eight assorted items is nothing
 * to cook from — most recipes want four or five specific things — so waiting until the table is nearly
 * bare before asking cargo just means a chef who stands there with half a pantry making nothing.
 */
/datum/bt_node/decorator/sp_kitchen_needs_supplies

/datum/bt_node/decorator/sp_kitchen_needs_supplies/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return FALSE
	var/obj/structure/table/prep_table = controller.blackboard[BB_SP_PREP_TABLE]
	if(length(sp_pantry_contents(prep_table)) >= SP_PANTRY_TARGET)
		return FALSE
	if(length(sp_carried_ingredients(pawn)))
		return FALSE
	return isnull(sp_find_stock_source(pawn, prep_table))

/// Puts a food crate on cargo's list and says so on the radio.
/datum/bt_node/ai_behavior/sp_ask_for_food

/datum/bt_node/ai_behavior/sp_ask_for_food/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/datum/sp_supply_request/request = sp_request_supplies(/datum/supply_pack/organic/food, pawn, /area/station/service/kitchen)
	if(isnull(request))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_record("chef.asked_cargo")
	log_sp("[pawn.real_name] asked cargo for a food crate")
	sp_crew_speak(pawn, pick(
		"Kitchen's out of everything. Can I get a food crate down here?",
		"I need a food crate from cargo, the pantry is empty.",
		"Cargo, the kitchen needs restocking. Food crate please.",
	), RADIO_CHANNEL_SUPPLY)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
