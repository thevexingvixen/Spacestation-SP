/**
 * Spacestation SP tests.
 *
 * The SP crew are emergent, which makes them miserable to test by playing: you start a round, wait, and
 * grep the log hoping for a line, and silence tells you nothing about whether the behaviour is broken or
 * merely has not come up yet. Every bug that has actually bitten this module, though, has lived in
 * ordinary deterministic logic — is a sandwich finished, does that reagent come out of that tap, does
 * this prep step name a real tool — so that is what these assert, in milliseconds, with a verdict.
 */

/// The rule that decides whether the chef carries something out to the counter or puts it back on the pile.
/datum/unit_test/sp_finished_dish

/datum/unit_test/sp_finished_dish/Run()
	var/turf/spot = run_loc_floor_bottom_left

	// A sandwich is dinner. It is also grillable — that is how you get a grilled cheese — and it has a
	// bakeable component, because every food in the game has one, defaulting to a burned mess. Reading
	// either of those as "unfinished" is what kept the counter empty for an entire session.
	var/obj/item/food/sandwich/cheese/sandwich = allocate(/obj/item/food/sandwich/cheese, spot)
	TEST_ASSERT(sp_is_finished_dish(sandwich), "a cheese sandwich should be worth serving")
	TEST_ASSERT(!sp_bakes_into_something(sandwich), "a cheese sandwich should not read as half-baked")

	// Dough is not. The oven turns it into bread, and that is a positive bake.
	var/obj/item/food/dough/dough = allocate(/obj/item/food/dough, spot)
	TEST_ASSERT(sp_bakes_into_something(dough), "dough should read as half-baked")
	TEST_ASSERT(!sp_is_finished_dish(dough), "dough should not be served to the crew")

	// A component the chef deliberately makes is not a dish either, however cooked it is.
	var/obj/item/food/breadslice/plain/slice = allocate(/obj/item/food/breadslice/plain, spot)
	TEST_ASSERT(!sp_is_finished_dish(slice), "a plain bread slice is an ingredient, not a dish")

	// Raw meat fails on the RAW foodtype before anything else gets a look in.
	var/obj/item/food/meat/slab/monkey/raw = allocate(/obj/item/food/meat/slab/monkey, spot)
	TEST_ASSERT(!sp_is_finished_dish(raw), "a raw meat slab is not a dish")

/// The prep-step table is data, and data with a typo in it fails silently at three in the morning.
/datum/unit_test/sp_prep_steps

/datum/unit_test/sp_prep_steps/Run()
	TEST_ASSERT(length(GLOB.sp_kitchen_prep_steps), "the chef has no prep steps at all")
	for(var/datum/sp_prep_step/step as anything in GLOB.sp_kitchen_prep_steps)
		TEST_ASSERT(ispath(step.source, /obj/item), "prep step '[step.name]' has a bad source: [step.source]")
		TEST_ASSERT(!isnull(step.result) || step.operation == SP_PREP_BAKE, "prep step '[step.name]' has no result and is not the catch-all bake")
		if(!isnull(step.result))
			TEST_ASSERT(ispath(step.result, /obj/item), "prep step '[step.name]' has a bad result: [step.result]")
		switch(step.operation)
			if(SP_PREP_TOOL)
				TEST_ASSERT(ispath(step.tool_type, /obj/item), "prep step '[step.name]' names no tool")
				var/obj/item/tool = step.tool_type
				TEST_ASSERT_NOTNULL(initial(tool.tool_behaviour), "prep step '[step.name]' uses [step.tool_type], which is not a tool")
			if(SP_PREP_GRILL, SP_PREP_BAKE, SP_PREP_PROCESS)
				TEST_ASSERT(ispath(step.machine_type(), /obj/machinery), "prep step '[step.name]' resolves to no machine")
			else
				TEST_FAIL("prep step '[step.name]' has an unknown operation: [step.operation]")

/// Both kitchen mixes have to be reachable from things a kitchen actually holds.
/datum/unit_test/sp_kitchen_mixes

/datum/unit_test/sp_kitchen_mixes/Run()
	TEST_ASSERT(length(GLOB.sp_kitchen_mixes), "the chef has no mixes")
	for(var/datum/sp_kitchen_mix/mix as anything in GLOB.sp_kitchen_mixes)
		TEST_ASSERT(length(mix.reagents), "mix '[mix.name]' needs nothing, which cannot be right")
		TEST_ASSERT(ispath(mix.result, /obj/item), "mix '[mix.name]' has a bad result: [mix.result]")
		for(var/reagent_type in mix.reagents)
			TEST_ASSERT(ispath(reagent_type, /datum/reagent), "mix '[mix.name]' wants a bad reagent: [reagent_type]")
			TEST_ASSERT(mix.reagents[reagent_type] > 0, "mix '[mix.name]' wants no [reagent_type]")

/**
 * Every drink on the bar menu has to come out of the two dispensers behind the bar.
 *
 * A reagent that neither tap holds is a bartender who walks to one machine, finds nothing to pour,
 * tips the glass out and starts again — forever, and silently.
 */
/datum/unit_test/sp_cocktails

/datum/unit_test/sp_cocktails/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/obj/machinery/chem_dispenser/drinks/soda = allocate(/obj/machinery/chem_dispenser/drinks, spot)
	var/obj/machinery/chem_dispenser/drinks/beer/booze = allocate(/obj/machinery/chem_dispenser/drinks/beer, spot)

	TEST_ASSERT(length(GLOB.sp_cocktails), "the bar has no menu")
	for(var/datum/sp_cocktail/drink as anything in GLOB.sp_cocktails)
		TEST_ASSERT(length(drink.parts), "'[drink.name]' is made of nothing")
		var/total = 0
		for(var/reagent_type in drink.parts)
			TEST_ASSERT(ispath(reagent_type, /datum/reagent), "'[drink.name]' wants a bad reagent: [reagent_type]")
			var/pourable = (reagent_type in soda.dispensable_reagents) || (reagent_type in booze.dispensable_reagents)
			TEST_ASSERT(pourable, "'[drink.name]' wants [reagent_type], which neither bar dispenser holds")
			total += drink.parts[reagent_type] * SP_DRINK_MEASURE
		var/obj/item/reagent_containers/cup/glass/drinkingglass/glass = allocate(/obj/item/reagent_containers/cup/glass/drinkingglass, spot)
		TEST_ASSERT(total <= glass.reagents.maximum_volume, "'[drink.name]' comes to [total] units and a glass holds [glass.reagents.maximum_volume]")

/**
 * Every drink on the menu, poured for real out of real dispensers.
 *
 * This is the test that caught the bartender pouring forever: the reaction consumes the gin and the
 * tonic to make the gin and tonic, so a glass that has just been made correctly reads as "still short
 * of gin" unless you ask the question the right way round.
 */
/datum/unit_test/sp_pour_a_drink

/datum/unit_test/sp_pour_a_drink/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/obj/machinery/chem_dispenser/drinks/soda = allocate(/obj/machinery/chem_dispenser/drinks, spot)
	var/obj/machinery/chem_dispenser/drinks/beer/booze = allocate(/obj/machinery/chem_dispenser/drinks/beer, spot)

	for(var/datum/sp_cocktail/drink as anything in GLOB.sp_cocktails)
		var/obj/item/reagent_containers/cup/glass/drinkingglass/glass = allocate(/obj/item/reagent_containers/cup/glass/drinkingglass, spot)
		TEST_ASSERT(!sp_drink_ready(drink, glass), "an empty glass should not count as '[drink.name]'")

		// One trip per dispenser, which is the shape the behaviour tree walks.
		for(var/obj/machinery/chem_dispenser/dispenser in list(booze, soda))
			var/list/here = sp_parts_from(drink, dispenser)
			for(var/reagent_type in here)
				var/poured = sp_dispense_into(dispenser, glass, reagent_type, here[reagent_type] * SP_DRINK_MEASURE)
				TEST_ASSERT(poured > 0, "[dispenser] poured no [reagent_type] for '[drink.name]'")

		TEST_ASSERT(sp_drink_ready(drink, glass), "'[drink.name]' did not come together after both taps")
		if(drink.result)
			TEST_ASSERT(glass.reagents.has_reagent(drink.result), "'[drink.name]' left no [drink.result] in the glass")
			TEST_ASSERT(!length(sp_missing_parts(drink, glass)), "'[drink.name]' still reads as short of something after it was made")

/**
 * Drinks made to order, worked out from /tg/'s own reactions rather than a list somebody typed.
 *
 * The catalogue is only worth having if it is right, and "right" here means every entry can actually be
 * poured from the two taps and comes out as the thing it claims to be. So this pours the whole book.
 */
/datum/unit_test/sp_drink_catalogue

/datum/unit_test/sp_drink_catalogue/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/obj/machinery/chem_dispenser/drinks/soda = allocate(/obj/machinery/chem_dispenser/drinks, spot)
	var/obj/machinery/chem_dispenser/drinks/beer/booze = allocate(/obj/machinery/chem_dispenser/drinks/beer, spot)

	var/list/datum/sp_cocktail/catalogue = sp_drink_catalogue()
	TEST_ASSERT(length(catalogue) >= length(GLOB.sp_cocktails), "the catalogue should be at least as big as the house menu, got [length(catalogue)]")

	var/made = 0
	var/list/failures = list()
	for(var/datum/sp_cocktail/drink as anything in catalogue)
		var/obj/item/reagent_containers/cup/glass/drinkingglass/glass = allocate(/obj/item/reagent_containers/cup/glass/drinkingglass, spot)
		for(var/obj/machinery/chem_dispenser/dispenser in list(booze, soda))
			// Top the cell up between drinks. A real bar recharges across a shift; pouring the whole book
			// back to back would run both machines flat and blame the recipes for it.
			dispenser.cell.charge = dispenser.cell.maxcharge
			for(var/reagent_type in sp_parts_from(drink, dispenser))
				sp_dispense_into(dispenser, glass, reagent_type, drink.units_of(reagent_type))
		if(sp_drink_ready(drink, glass))
			made++
		else
			var/list/ended_up_with = list()
			for(var/datum/reagent/left as anything in glass.reagents.reagent_list)
				ended_up_with += "[left.name] [round(left.volume, 0.1)]"
			var/list/wanted = list()
			for(var/reagent_type in drink.parts)
				wanted += "[reagent_type] [round(drink.units_of(reagent_type), 0.1)]"
			failures += "[drink.name] (wanted [jointext(wanted, " + ")], got [length(ended_up_with) ? jointext(ended_up_with, " + ") : "nothing"])"
	TEST_ASSERT(!length(failures), "[length(failures)] of [length(catalogue)] catalogue drinks did not come together: [english_list(failures)]")
	TEST_ASSERT(made > 0, "the catalogue poured nothing at all")

/// An order has to be recognised from what somebody actually says.
/datum/unit_test/sp_drink_orders

/datum/unit_test/sp_drink_orders/Run()
	var/turf/spot = run_loc_floor_bottom_left
	allocate(/obj/machinery/chem_dispenser/drinks, spot)
	allocate(/obj/machinery/chem_dispenser/drinks/beer, spot)

	var/datum/sp_cocktail/asked = sp_drink_from_order("could I get a gin and tonic please")
	TEST_ASSERT_NOTNULL(asked, "a gin and tonic should be recognised from a sentence")
	TEST_ASSERT_EQUAL(asked.result, /datum/reagent/consumable/ethanol/gintonic, "recognised the wrong drink: [asked.name]")

	// The longest match wins, or every vodka martini gets served as a martini.
	var/datum/sp_cocktail/specific = sp_drink_from_order("one vodka martini")
	TEST_ASSERT_NOTNULL(specific, "a vodka martini should be recognised")
	TEST_ASSERT_EQUAL(specific.result, /datum/reagent/consumable/ethanol/vodkamartini, "a vodka martini was heard as [specific.name]")

	TEST_ASSERT_NULL(sp_drink_from_order("has anyone seen the clown"), "ordinary chatter should not read as an order")

/// The chef's whole pipeline, from a pile of components to something worth serving.
/datum/unit_test/sp_cook_a_dish

/datum/unit_test/sp_cook_a_dish/Run()
	var/turf/spot = run_loc_floor_bottom_left
	allocate(/obj/structure/table, spot)
	for(var/i in 1 to 2)
		allocate(/obj/item/food/breadslice/plain, spot)
		allocate(/obj/item/food/cheese/wedge, spot)

	var/mob/living/carbon/human/chef = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/list/datum/crafting_recipe/possible = sp_craftable_recipes(chef)
	TEST_ASSERT(length(possible), "a chef stood beside bread and cheese could craft nothing")

	var/datum/crafting_recipe/cheese_sandwich
	for(var/datum/crafting_recipe/recipe as anything in possible)
		if(recipe.result == /obj/item/food/sandwich/cheese)
			cheese_sandwich = recipe
			break
	TEST_ASSERT_NOTNULL(cheese_sandwich, "two bread slices and two cheese wedges should make a cheese sandwich")
	TEST_ASSERT(sp_recipe_makes_dish(cheese_sandwich), "a cheese sandwich recipe should count as making a dish")

	var/datum/component/personal_crafting/crafting = chef.GetComponent(/datum/component/personal_crafting)
	TEST_ASSERT_NOTNULL(crafting, "the chef has no crafting component")
	var/result = crafting.construct_item(chef, cheese_sandwich)
	TEST_ASSERT(!istext(result), "the craft failed: [result]")
	var/obj/item/made = result
	allocated += made
	TEST_ASSERT(sp_is_finished_dish(made), "[made.name] came out of a recipe and should be servable")

/// What a nosy crew member will and will not walk off with.
/datum/unit_test/sp_curiosity

/datum/unit_test/sp_curiosity/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/list/rolled = sp_roll_interests()
	TEST_ASSERT_EQUAL(length(rolled), SP_INTEREST_COUNT, "a character should roll [SP_INTEREST_COUNT] interests")
	TEST_ASSERT_EQUAL(length(rolled), length(unique_list(rolled)), "a character rolled the same interest twice")

	// Possessing the pawn rolls the tastes, which proves the controller can write a list there at all —
	// it cannot with set_blackboard_key, which CRASHes over a list and once left every crew member with
	// no tastes and so nothing worth taking.
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/datum/ai_controller/sp_crew/controller = new(crew)
	TEST_ASSERT(length(controller.blackboard[BB_SP_INTERESTS]), "possessing a pawn should have rolled some tastes")
	controller.override_blackboard_key(BB_SP_INTERESTS, list(/obj/item/clothing/head))

	var/obj/item/clothing/head/costume/nursehat/hat = allocate(/obj/item/clothing/head/costume/nursehat, spot)
	TEST_ASSERT(controller.wants_item(hat), "someone who likes hats should want a hat")

	var/obj/item/pen/pen = allocate(/obj/item/pen, spot)
	TEST_ASSERT(!controller.wants_item(pen), "someone who only likes hats should leave the pen")

	// Nobody pockets an ID, whatever their tastes.
	controller.override_blackboard_key(BB_SP_INTERESTS, list(/obj/item))
	var/obj/item/card/id/card = allocate(/obj/item/card/id, spot)
	TEST_ASSERT(!controller.wants_item(card), "an ID card should never be taken")
	qdel(controller)

/// Every SP controller has to point at a behaviour tree that was actually compiled.
/datum/unit_test/sp_behaviour_trees

/datum/unit_test/sp_behaviour_trees/Run()
	for(var/controller_type in typesof(/datum/ai_controller/sp_crew))
		var/datum/ai_controller/sp_crew/controller = controller_type
		var/json = initial(controller.behavior_tree_json)
		TEST_ASSERT_NOTNULL(json, "[controller_type] has no behaviour tree")
		TEST_ASSERT(fexists(BT_COMPILED_PATH(json)), "[controller_type] points at [json], which has not been compiled")
