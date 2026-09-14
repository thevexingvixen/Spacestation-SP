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

/// What the medic decides once a patient has been looked over.
/datum/unit_test/sp_triage

/datum/unit_test/sp_triage/Run()
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(sp_triage(patient, cryo_ready = TRUE), SP_TRIAGE_NONE, "somebody with nothing wrong with them should be sent on their way")
	patient.apply_damage(25, BRUTE, BODY_ZONE_L_ARM, wound_bonus = CANT_WOUND)
	TEST_ASSERT_EQUAL(sp_triage(patient, cryo_ready = TRUE), SP_TRIAGE_TREAT, "a cut arm is a job for the medkit, cryo or no cryo")
	patient.apply_damage(45, BURN, BODY_ZONE_CHEST, wound_bonus = CANT_WOUND)
	TEST_ASSERT_EQUAL(sp_triage(patient, cryo_ready = TRUE), SP_TRIAGE_CRYO, "seventy brute and burn should go in the cryo tube when one is ready")
	TEST_ASSERT_EQUAL(sp_triage(patient, cryo_ready = FALSE), SP_TRIAGE_TREAT, "with no tube ready, a serious case should still get the medkit")

/// Which limb the medic aims at, and with what. The first AI medic only ever aimed at the chest.
/datum/unit_test/sp_pick_treatment

/datum/unit_test/sp_pick_treatment/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/doctor = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/stack/medical/suture/suture = allocate(/obj/item/stack/medical/suture, spot)
	var/obj/item/stack/medical/mesh/mesh = allocate(/obj/item/stack/medical/mesh, spot)
	doctor.put_in_hands(suture)
	doctor.put_in_hands(mesh)
	TEST_ASSERT(!mesh.is_open, "a full stack of mesh should start sealed; that is part of what is being tested")

	var/mob/living/carbon/human/cut = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	TEST_ASSERT_NULL(sp_pick_treatment(doctor, cut), "there should be nothing to treat on somebody unhurt")
	cut.apply_damage(25, BRUTE, BODY_ZONE_L_ARM, wound_bonus = CANT_WOUND)
	var/list/choice = sp_pick_treatment(doctor, cut)
	TEST_ASSERT_NOTNULL(choice, "a cut arm and a suture in hand, and nothing picked")
	TEST_ASSERT_EQUAL(choice[1], suture, "brute on an arm wants the suture")
	TEST_ASSERT_EQUAL(choice[2], BODY_ZONE_L_ARM, "the medic should aim at the arm that is hurt, not the chest")

	var/mob/living/carbon/human/burned = allocate(/mob/living/carbon/human/consistent, get_step(spot, NORTH))
	burned.apply_damage(20, BURN, BODY_ZONE_R_LEG, wound_bonus = CANT_WOUND)
	choice = sp_pick_treatment(doctor, burned)
	TEST_ASSERT_NOTNULL(choice, "a burned leg and mesh in hand, and nothing picked")
	TEST_ASSERT_EQUAL(choice[1], mesh, "a burn wants the mesh, whether or not its packet is open yet")
	TEST_ASSERT_EQUAL(choice[2], BODY_ZONE_R_LEG, "the medic should aim at the leg that is burned")

/// A round of treatment through the medic's own code, clicks and all: aim, reach for the right thing, apply it.
/datum/unit_test/sp_treat_a_patient

/datum/unit_test/sp_treat_a_patient/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/doctor = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/medical/controller = new(doctor)
	// Left running, the medic's own tree would go looking for work in the middle of the test.
	controller.set_ai_status(AI_STATUS_OFF)
	var/obj/item/stack/medical/mesh/mesh = allocate(/obj/item/stack/medical/mesh, spot)
	doctor.put_in_hands(mesh)
	patient.apply_damage(20, BURN, BODY_ZONE_L_LEG, wound_bonus = CANT_WOUND)

	var/used = sp_treat_round(controller, patient)
	TEST_ASSERT_EQUAL(used, /obj/item/stack/medical/mesh, "the medic should have used the mesh")
	TEST_ASSERT(mesh.is_open, "the medic should have torn the mesh packet open first")
	var/obj/item/bodypart/leg = patient.get_bodypart(BODY_ZONE_L_LEG)
	TEST_ASSERT_EQUAL(leg.burn_dam, 0, "two pieces of mesh should have closed twenty burn on the leg")
	qdel(controller)

/// Putting a beaker in a cryo tube and a patient after it, the way a doctor does: open it, drag them on, shut it.
/datum/unit_test/sp_cryo_loading

/datum/unit_test/sp_cryo_loading/Run()
	var/turf/spot = run_loc_floor_bottom_left
	// The tube just north of the patient and the doctor beside them both, which is how a medic ends up after
	// walking somebody over.
	var/obj/machinery/cryo_cell/cryo = allocate(/obj/machinery/cryo_cell, get_step(spot, NORTH))
	var/mob/living/carbon/human/doctor = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, spot)
	var/datum/ai_controller/sp_crew/medical/controller = new(doctor)
	controller.set_ai_status(AI_STATUS_OFF)

	var/obj/item/reagent_containers/cup/beaker/cryoxadone/beaker = allocate(/obj/item/reagent_containers/cup/beaker/cryoxadone, get_step(spot, EAST))
	doctor.put_in_hands(beaker)
	TEST_ASSERT(sp_do_cryo_job(controller, SP_CRYO_TASK_LOAD_BEAKER, cryo), "the medic could not put a cryoxadone beaker in the tube")
	TEST_ASSERT_EQUAL(cryo.beaker, beaker, "the tube should be holding the medic's beaker")
	TEST_ASSERT(sp_cryo_has_medicine(cryo), "a fresh cryoxadone beaker should count as medicine in the tube")

	TEST_ASSERT(doctor.start_pulling(patient), "the medic could not take hold of the patient")
	var/how = sp_load_into_cryo(controller, patient, cryo)
	TEST_ASSERT_EQUAL(patient.loc, cryo, "the patient should be inside the tube")
	TEST_ASSERT_EQUAL(how, "dragged", "a conscious patient should go in the way a doctor does it: dragged onto the open tube and shut in")
	qdel(controller)

/// Setting the freezer by hand: alt-click steps its target temperature, ctrl-click turns it on.
/datum/unit_test/sp_cryo_freezer

/datum/unit_test/sp_cryo_freezer/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer = allocate(/obj/machinery/atmospherics/components/unary/thermomachine/freezer, get_step(spot, NORTH))
	var/mob/living/carbon/human/doctor = allocate(/mob/living/carbon/human/consistent, spot)
	var/datum/ai_controller/sp_crew/medical/controller = new(doctor)
	controller.set_ai_status(AI_STATUS_OFF)
	TEST_ASSERT(!freezer.on, "a fresh freezer starts off, which is the case being tested")
	TEST_ASSERT(sp_do_cryo_job(controller, SP_CRYO_TASK_FREEZER, freezer), "the medic could not set the freezer")
	TEST_ASSERT(freezer.on, "the freezer should be on")
	TEST_ASSERT_EQUAL(freezer.target_temperature, freezer.min_temperature, "the freezer should be set as cold as it goes")
	qdel(controller)

/// The operation plan, worked out afresh from the patient's limbs each step: incise, repair, close, and then nothing.
/datum/unit_test/sp_surgery_plan

/datum/unit_test/sp_surgery_plan/Run()
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(sp_next_operation(patient), "an unhurt patient should need no operation")
	var/obj/item/bodypart/arm = patient.get_bodypart(BODY_ZONE_L_ARM)
	var/datum/wound/blunt/bone/severe/fracture = new
	fracture.apply_wound(arm)
	TEST_ASSERT(sp_needs_surgery(patient), "a hairline fracture should need surgery")
	TEST_ASSERT(sp_only_needs_surgery(patient), "a fracture and nothing else is a job for the surgeon alone")
	patient.apply_damage(25, BRUTE, BODY_ZONE_R_ARM, wound_bonus = CANT_WOUND)
	TEST_ASSERT(!sp_only_needs_surgery(patient), "a broken arm and a cut on the other is something any medic can start on")

	var/list/next_step = sp_next_operation(patient)
	TEST_ASSERT_EQUAL(next_step[1], /datum/surgery_operation/limb/incise_skin, "a hairline fracture starts with an incision")
	TEST_ASSERT_EQUAL(next_step[2], BODY_ZONE_L_ARM, "the incision goes on the broken arm")
	arm.add_surgical_state(SURGERY_SKIN_CUT)
	next_step = sp_next_operation(patient)
	TEST_ASSERT_EQUAL(next_step[1], /datum/surgery_operation/limb/repair_hairline, "once the skin is cut, the fracture gets repaired")
	qdel(fracture)
	next_step = sp_next_operation(patient)
	TEST_ASSERT_EQUAL(next_step[1], /datum/surgery_operation/limb/close_skin, "with the bone mended, the incision gets closed")
	arm.remove_surgical_state(SURGERY_SKIN_CUT)
	TEST_ASSERT_NULL(sp_next_operation(patient), "closed up, there should be nothing left to do")

/**
 * A whole operation through the surgeon's own code: strapped to the table, the jumpsuit rolled out of the
 * way, incision, repair and closure, then dressed and let up.
 */
/datum/unit_test/sp_surgery_hairline

/datum/unit_test/sp_surgery_hairline/Run()
	var/turf/spot = run_loc_floor_bottom_left
	// Table, surgeon and patient in a line, which is how they end up after the walk over: the patient in tow
	// trails a tile behind the surgeon and two from the table. TG only straps down somebody standing beside
	// the table, and the first live round failed exactly here.
	var/turf/surgeon_turf = get_step(spot, NORTH)
	var/obj/structure/table/optable/table = allocate(/obj/structure/table/optable, get_step(surgeon_turf, NORTH))
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human/consistent, surgeon_turf)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, spot)
	var/datum/ai_controller/sp_crew/medical/controller = new(surgeon)
	controller.set_ai_status(AI_STATUS_OFF)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	surgeon.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	for(var/tool_type in list(/obj/item/scalpel, /obj/item/bonesetter, /obj/item/cautery))
		var/obj/item/tool = allocate(tool_type)
		tool.forceMove(bag)
	var/obj/item/clothing/under/color/grey/jumpsuit = allocate(/obj/item/clothing/under/color/grey)
	patient.equip_to_slot_or_del(jumpsuit, ITEM_SLOT_ICLOTHING)
	var/obj/item/bodypart/arm = patient.get_bodypart(BODY_ZONE_L_ARM)
	var/datum/wound/blunt/bone/severe/fracture = new
	fracture.apply_wound(arm)

	TEST_ASSERT(sp_surgery_feasible(surgeon, patient), "a scalpel, a bonesetter and a cautery should be enough for a hairline fracture")
	TEST_ASSERT_EQUAL(sp_triage(patient, cryo_ready = FALSE, can_operate = TRUE), SP_TRIAGE_SURGERY, "a broken bone should go to the table when there is a surgeon")
	TEST_ASSERT(!patient.is_location_accessible(BODY_ZONE_L_ARM, IGNORED_OPERATION_CLOTHING_SLOTS), "the jumpsuit should cover the arm; that is part of what is being tested")

	TEST_ASSERT(surgeon.start_pulling(patient), "the surgeon could not take hold of the patient")
	var/operations = sp_do_surgery(controller, patient, table)
	TEST_ASSERT(operations >= 3, "incise, repair and close should be three operations, not [operations]")
	TEST_ASSERT(!sp_needs_surgery(patient), "the fracture should be mended")
	TEST_ASSERT(!LIMB_HAS_ANY_SURGERY_STATE(arm, ALL_SURGERY_SKIN_STATES), "the incision should be closed")
	TEST_ASSERT_EQUAL(patient.w_uniform, jumpsuit, "the patient should still be wearing their jumpsuit")
	TEST_ASSERT_EQUAL(jumpsuit.adjusted, NORMAL_STYLE, "the jumpsuit should be rolled back up")
	TEST_ASSERT_NULL(patient.buckled, "the patient should be off the table")
	qdel(controller)

/// The chemist's plans, worked out from /tg/'s own reactions down to what the dispenser pours.
/datum/unit_test/sp_brew_plans

/datum/unit_test/sp_brew_plans/Run()
	var/obj/machinery/chem_dispenser/dispenser = allocate(/obj/machinery/chem_dispenser, run_loc_floor_bottom_left)
	var/list/expected_stages = list(
		/datum/reagent/medicine/c2/libital = 3,
		/datum/reagent/medicine/c2/aiuri = 2,
		/datum/reagent/medicine/cryoxadone = 4,
		/datum/reagent/reaction_agent/basic_buffer = 2,
		/datum/reagent/reaction_agent/acidic_buffer = 1,
	)
	for(var/product in expected_stages)
		var/datum/sp_brew/brew = sp_plan_brew(product, dispenser.dispensable_reagents, 50, dispenser.dispensed_temperature)
		if(isnull(brew))
			TEST_FAIL("[product] could not be planned: [sp_explain_brew(product, dispenser.dispensable_reagents, dispenser.dispensed_temperature)]")
			continue
		TEST_ASSERT_EQUAL(length(brew.stages), expected_stages[product], "[product] was planned in the wrong number of stages")
		TEST_ASSERT(brew.peak_volume <= 50, "[product] overflows a 50u beaker at [brew.peak_volume]u")
		for(var/datum/sp_brew_stage/stage as anything in brew.stages)
			for(var/reagent in stage.additions)
				TEST_ASSERT(reagent in dispenser.dispensable_reagents, "[product] wants [reagent], which the dispenser does not pour")
				TEST_ASSERT_EQUAL(stage.additions[reagent], round(stage.additions[reagent], 1), "[product] wants a fraction of a unit of [reagent]")

/**
 * Real brews through the machines, stage by stage, with the amount and purity that come out of them. Libital
 * needs the heater and sours as it forms; aiuri overheats five degrees past its best; cryoxadone takes four
 * stages and must not meet its own ingredients in the wrong order.
 */
/datum/unit_test/sp_brew

/datum/unit_test/sp_brew/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/turf/bench = get_step(spot, EAST)
	var/obj/machinery/chem_dispenser/dispenser = allocate(/obj/machinery/chem_dispenser, spot)
	var/obj/machinery/chem_heater/withbuffer/heater = allocate(/obj/machinery/chem_heater/withbuffer, get_step(spot, NORTH))
	var/mob/living/carbon/human/chemist = allocate(/mob/living/carbon/human/consistent, bench)
	var/datum/ai_controller/sp_crew/medical/chemist/controller = new(chemist)
	controller.set_ai_status(AI_STATUS_OFF)
	for(var/product in list(/datum/reagent/medicine/c2/libital, /datum/reagent/medicine/c2/aiuri, /datum/reagent/medicine/cryoxadone))
		var/obj/item/reagent_containers/cup/beaker/beaker = allocate(/obj/item/reagent_containers/cup/beaker, bench)
		chemist.put_in_hands(beaker)
		var/datum/sp_brew/brew = sp_plan_brew(product, dispenser.dispensable_reagents, beaker.volume, dispenser.dispensed_temperature)
		if(isnull(brew))
			TEST_FAIL("[product] could not be planned: [sp_explain_brew(product, dispenser.dispensable_reagents, dispenser.dispensed_temperature)]")
			continue
		var/basic_before = heater.reagents.get_reagent_amount(/datum/reagent/reaction_agent/basic_buffer)
		var/acidic_before = heater.reagents.get_reagent_amount(/datum/reagent/reaction_agent/acidic_buffer)
		var/made = sp_run_brew(controller, brew, beaker, dispenser, heater)
		var/purity = sp_reagent_purity(beaker, product)
		var/basic_used = basic_before - heater.reagents.get_reagent_amount(/datum/reagent/reaction_agent/basic_buffer)
		var/acidic_used = acidic_before - heater.reagents.get_reagent_amount(/datum/reagent/reaction_agent/acidic_buffer)
		log_world("sp_brew: [product] [round(made, 0.1)]u of [brew.amount]u at [round(purity * 100)]% purity, pH [round(beaker.reagents.ph, 0.1)], buffer used [round(basic_used, 0.1)]u basic and [round(acidic_used, 0.1)]u acidic")
		TEST_ASSERT(made >= brew.amount * 0.9, "[product]: only [made]u of [brew.amount]u came out (pH [beaker.reagents.ph], [beaker.reagents.chem_temp] K)")
		TEST_ASSERT(purity >= 0.6, "[product] came out at [round(purity * 100)]% purity")
		chemist.dropItemToGround(beaker)
	qdel(controller)

/// Patches printed at the ChemMaster, the rest of the beaker poured away, and the patches picked up.
/datum/unit_test/sp_chem_print

/datum/unit_test/sp_chem_print/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/obj/machinery/chem_master/master = allocate(/obj/machinery/chem_master, get_step(spot, EAST))
	var/mob/living/carbon/human/chemist = allocate(/mob/living/carbon/human/consistent, spot)
	var/datum/ai_controller/sp_crew/medical/chemist/controller = new(chemist)
	controller.set_ai_status(AI_STATUS_OFF)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	chemist.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/obj/item/reagent_containers/cup/beaker/beaker = allocate(/obj/item/reagent_containers/cup/beaker, spot)
	beaker.reagents.add_reagent(/datum/reagent/medicine/c2/libital, 27)
	beaker.reagents.add_reagent(/datum/reagent/water, 5)
	chemist.put_in_hands(beaker)

	var/list/obj/item/patches = sp_print_patches(controller, master, beaker, /datum/reagent/medicine/c2/libital)
	allocated += patches
	TEST_ASSERT_EQUAL(length(patches), 3, "27u of libital should print three 9u patches")
	for(var/obj/item/reagent_containers/applicator/patch/patch as anything in patches)
		TEST_ASSERT_EQUAL(round(patch.reagents.get_reagent_amount(/datum/reagent/medicine/c2/libital), 1), 9, "each patch should hold 9u of libital")
		TEST_ASSERT(patch in chemist.get_all_contents(), "the chemist should have picked [patch] up")
	TEST_ASSERT(!beaker.reagents.total_volume, "the water left in the beaker should have gone down the ChemMaster")
	qdel(controller)

/**
 * A heater with no buffer left gets some before anything else is brewed at it: each buffer brewed from the
 * dispenser, drawn into the heater's store, and the rest of the batch poured away.
 */
/datum/unit_test/sp_chem_buffer

/datum/unit_test/sp_chem_buffer/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/turf/bench = get_step(spot, EAST)
	var/obj/machinery/chem_dispenser/dispenser = allocate(/obj/machinery/chem_dispenser, spot)
	var/obj/machinery/chem_heater/heater = allocate(/obj/machinery/chem_heater, get_step(spot, NORTH))
	var/obj/machinery/chem_master/master = allocate(/obj/machinery/chem_master, get_step(bench, EAST))
	var/mob/living/carbon/human/chemist = allocate(/mob/living/carbon/human/consistent, bench)
	var/datum/ai_controller/sp_crew/medical/chemist/controller = new(chemist)
	controller.set_ai_status(AI_STATUS_OFF)
	var/list/order = sp_next_chem_order(chemist, list(bench, dispenser, heater, master))
	TEST_ASSERT_EQUAL(LAZYACCESS(order, 1), /datum/reagent/reaction_agent/basic_buffer, "an empty heater should get basic buffer before anything is brewed at it")
	TEST_ASSERT_EQUAL(LAZYACCESS(order, 2), SP_CHEM_FORM_HEATER, "buffer should go into the heater")
	for(var/buffer in sp_chem_buffers())
		var/obj/item/reagent_containers/cup/beaker/beaker = allocate(/obj/item/reagent_containers/cup/beaker, bench)
		chemist.put_in_hands(beaker)
		TEST_ASSERT(sp_make_medicine(controller, buffer, SP_CHEM_FORM_HEATER, dispenser, heater, master), "[buffer] was not brewed into the heater")
		var/amount = heater.reagents.get_reagent_amount(buffer)
		log_world("sp_chem_buffer: [buffer] [round(amount, 0.1)]u in the heater")
		TEST_ASSERT(amount >= 40, "only [amount]u of [buffer] reached the heater")
		TEST_ASSERT(!beaker.reagents.total_volume, "what was left of the batch should have gone down the ChemMaster")
		chemist.dropItemToGround(beaker)
	TEST_ASSERT_NULL(sp_chem_buffer_wanted(heater, dispenser), "a topped-up heater should not want more buffer")
	qdel(controller)

/**
 * A surgery tray in a corner, with a table on one side and the operating table on the other, is reached from
 * the one diagonal tile left open, and that is where the doctor is sent to stand.
 */
/datum/unit_test/sp_surgery_tray_reach

/datum/unit_test/sp_surgery_tray_reach/Run()
	var/turf/corner = get_step(run_loc_floor_bottom_left, NORTHEAST)
	allocate(/obj/structure/table, corner)
	var/obj/item/surgery_tray/tray = allocate(/obj/item/surgery_tray, corner)
	for(var/direction in list(NORTH, SOUTH, EAST, WEST, SOUTHWEST, SOUTHEAST, NORTHWEST))
		allocate(/obj/structure/table, get_step(corner, direction))
	var/turf/open_corner = get_step(corner, NORTHEAST)
	TEST_ASSERT_EQUAL(sp_reach_spot(tray, run_loc_floor_bottom_left), open_corner, "the only tile the tray can be reached from is the open diagonal")
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human/consistent, open_corner)
	TEST_ASSERT(surgeon.Adjacent(tray), "a surgeon on the diagonal should reach the tray across the tables")

/// The pathfinder should not plan a standing crew member through plastic flaps they cannot walk through.
/datum/unit_test/sp_flaps_pathing

/datum/unit_test/sp_flaps_pathing/Run()
	var/obj/structure/plasticflaps/flaps = allocate(/obj/structure/plasticflaps, get_step(run_loc_floor_bottom_left, EAST))
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(!flaps.CanAllowThrough(crew, WEST), "a standing human should not fit through plastic flaps")
	TEST_ASSERT(!flaps.CanAStarPass(EAST, new /datum/can_pass_info(crew, list())), "the pathfinder should not route a standing human through plastic flaps")

/**
 * A doctor with a patient and a chemist with an order do not stop to answer chatter. The reply would pull them
 * off the job, and a brew or an operation left running while the tree starts it again would run twice.
 */
/datum/unit_test/sp_busy_ignores_chatter

/datum/unit_test/sp_busy_ignores_chatter/Run()
	var/mob/living/carbon/human/speaker = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/doctor = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, NORTH))
	var/mob/living/carbon/human/chemist = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, NORTHEAST))
	doctor.real_name = "Kaleb Siegrist"
	chemist.real_name = "Allegra Poley"
	var/datum/ai_controller/sp_crew/medical/doctor_ai = new(doctor)
	doctor_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/medical/chemist/chemist_ai = new(chemist)
	chemist_ai.set_ai_status(AI_STATUS_OFF)

	doctor_ai.set_blackboard_key(BB_SP_PATIENT, patient)
	doctor_ai.consider_conversation(speaker, "Kaleb, have you got a minute?")
	TEST_ASSERT(!doctor_ai.blackboard_key_exists(BB_SP_CHAT_REPLY_DUE), "a doctor with a patient should not stop to answer chatter")
	doctor_ai.clear_blackboard_key(BB_SP_PATIENT)
	doctor_ai.consider_conversation(speaker, "Kaleb, have you got a minute?")
	TEST_ASSERT(doctor_ai.blackboard_key_exists(BB_SP_CHAT_REPLY_DUE), "a doctor with nobody to see should answer when spoken to by name")

	chemist_ai.set_blackboard_key(BB_SP_CHEM_PRODUCT, /datum/reagent/medicine/c2/libital)
	chemist_ai.consider_conversation(speaker, "Allegra, have you got a minute?")
	TEST_ASSERT(!chemist_ai.blackboard_key_exists(BB_SP_CHAT_REPLY_DUE), "a chemist with an order in hand should not stop to answer chatter")
	qdel(doctor_ai)
	qdel(chemist_ai)

/**
 * A job the AI crew fill is open to a joining player. A dead holder's place is freed without moving the body;
 * a living holder goes off shift, off the manifest, bank account closed, and out of the round.
 */
/datum/unit_test/sp_role_takeover

/datum/unit_test/sp_role_takeover/Run()
	var/datum/job/job = SSjob.get_job_type(/datum/job/chief_medical_officer)
	var/total_before = job.total_positions
	var/current_before = job.current_positions
	job.total_positions = job.current_positions + 2
	var/mob/living/carbon/human/alive = sp_spawn_crew_member(job, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/dead = sp_spawn_crew_member(job, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(alive, "the first AI crew member should spawn")
	TEST_ASSERT_NOTNULL(dead, "the second AI crew member should spawn")
	alive.ai_controller.set_ai_status(AI_STATUS_OFF)
	dead.ai_controller.set_ai_status(AI_STATUS_OFF)
	TEST_ASSERT_EQUAL(job.current_positions, job.total_positions, "the two AI crew members should fill the job")
	// The manifest writes its records asynchronously.
	sleep(2 SECONDS)

	dead.death()
	var/list/holders = sp_ai_crew_in_job(job)
	TEST_ASSERT_EQUAL(length(holders), 2, "both AI crew members should be holding the job")
	TEST_ASSERT_EQUAL(holders[1], dead, "a dead holder should give up their place first")
	TEST_ASSERT(sp_free_slot_from_ai(job), "the dead holder's place should be freed")
	TEST_ASSERT_EQUAL(job.current_positions, job.total_positions - 1, "freeing a place should open the slot")
	TEST_ASSERT(!QDELETED(dead), "the body should stay where it is")

	var/name = alive.real_name
	var/account_id = alive.account_id
	TEST_ASSERT_NOTNULL(find_record(name), "the living crew member should be on the manifest before going off shift")
	TEST_ASSERT(sp_free_slot_from_ai(job), "the living holder's place should be freed")
	TEST_ASSERT_EQUAL(job.current_positions, job.total_positions - 2, "both places should now be open")
	TEST_ASSERT_NULL(find_record(name), "they should be off the manifest")
	TEST_ASSERT_NULL(find_record(name, locked_only = TRUE), "and off the locked records")
	TEST_ASSERT_NULL(SSeconomy.bank_accounts_by_id["[account_id]"], "their bank account should be closed")
	TEST_ASSERT(!sp_free_slot_from_ai(job), "with nobody left in the job there is no place to free")
	sleep(3 SECONDS)
	TEST_ASSERT(QDELETED(alive), "they should be gone from the round")

	qdel(dead)
	job.total_positions = total_before
	job.current_positions = current_before

/// An assistant draws one of the friendly designs on the floor with the crayon they carry.
/datum/unit_test/sp_greytide_graffiti

/datum/unit_test/sp_greytide_graffiti/Run()
	var/mob/living/carbon/human/assistant = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/datum/ai_controller/sp_crew/assistant/controller = new(assistant)
	controller.set_ai_status(AI_STATUS_OFF)
	var/obj/item/toy/crayon/red/crayon = allocate(/obj/item/toy/crayon/red, run_loc_floor_bottom_left)
	assistant.put_in_hands(crayon)
	// The test room's floor is indestructible, which a crayon will not mark. The station's hallways are iron.
	var/turf/canvas = get_step(run_loc_floor_bottom_left, EAST)
	var/original_type = canvas.type
	canvas = canvas.ChangeTurf(/turf/open/floor/iron)
	TEST_ASSERT(sp_prank_graffiti(controller, canvas), "the assistant should have drawn on the floor")
	var/obj/effect/decal/cleanable/crayon/drawing = locate() in canvas
	TEST_ASSERT_NOTNULL(drawing, "a crayon drawing should be on the floor")
	TEST_ASSERT(crayon.drawtype in GLOB.sp_graffiti_designs, "the design should be one of the friendly ones, not [crayon.drawtype]")
	qdel(drawing)
	canvas.ChangeTurf(original_type)
	qdel(controller)

/// An assistant rings a desk bell, more than once.
/datum/unit_test/sp_greytide_bell

/datum/unit_test/sp_greytide_bell/Run()
	var/obj/structure/desk_bell/bell = allocate(/obj/structure/desk_bell, get_step(run_loc_floor_bottom_left, EAST))
	var/mob/living/carbon/human/assistant = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/datum/ai_controller/sp_crew/assistant/controller = new(assistant)
	controller.set_ai_status(AI_STATUS_OFF)
	TEST_ASSERT(sp_prank_bell(controller, bell), "the bell should have rung")
	TEST_ASSERT(bell.times_rang >= 2, "it should have rung more than once, not [bell.times_rang] times")
	qdel(controller)

/// Lights out in a room with somebody else in it, and back on again: the joke never leaves the room dark.
/datum/unit_test/sp_greytide_lights

/datum/unit_test/sp_greytide_lights/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/obj/machinery/light_switch/light_switch = allocate(/obj/machinery/light_switch, get_step(spot, EAST))
	var/mob/living/carbon/human/assistant = allocate(/mob/living/carbon/human/consistent, spot)
	allocate(/mob/living/carbon/human/consistent, get_step(spot, NORTH))
	var/datum/ai_controller/sp_crew/assistant/controller = new(assistant)
	controller.set_ai_status(AI_STATUS_OFF)
	var/area/room = light_switch.area
	light_switch.set_lights(TRUE)
	TEST_ASSERT(sp_people_in_area(room, assistant) >= 1, "somebody else should be in the room for the joke to land")
	TEST_ASSERT(sp_prank_lights(controller, light_switch), "the room should have gone dark")
	TEST_ASSERT(room.lightswitch, "the lights should be back on afterwards")
	qdel(controller)

/// Tool storage: budget insulated gloves go on, a crowbar goes in the bag, and then there is nothing more to want.
/datum/unit_test/sp_greytide_gear

/datum/unit_test/sp_greytide_gear/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/assistant = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	assistant.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/datum/ai_controller/sp_crew/assistant/controller = new(assistant)
	controller.set_ai_status(AI_STATUS_OFF)
	TEST_ASSERT_EQUAL(sp_controller_for_job(SSjob.get_job_type(/datum/job/assistant)), /datum/ai_controller/sp_crew/assistant, "assistants should get the assistant controller")
	TEST_ASSERT(!controller.closes_lockers(), "assistants leave lockers open")
	TEST_ASSERT_EQUAL(controller.rummage_take_limit(), SP_GREYTIDE_TAKE_LIMIT, "assistants take more from a locker")
	var/obj/item/clothing/gloves/color/fyellow/gloves = allocate(/obj/item/clothing/gloves/color/fyellow, get_step(spot, EAST))
	var/obj/item/crowbar/crowbar = allocate(/obj/item/crowbar, get_step(spot, EAST))
	TEST_ASSERT_EQUAL(length(sp_gear_wanted(assistant)), 2, "a new assistant wants gloves and a tool")
	TEST_ASSERT(sp_take_gear_item(assistant, gloves), "the gloves should be taken")
	TEST_ASSERT_EQUAL(assistant.gloves, gloves, "the gloves should be worn")
	TEST_ASSERT(sp_take_gear_item(assistant, crowbar), "the crowbar should be taken")
	TEST_ASSERT(crowbar in assistant.get_all_contents(), "the crowbar should be in the bag")
	TEST_ASSERT(!length(sp_gear_wanted(assistant)), "with gloves and a tool there is nothing more to want")
	qdel(controller)

/**
 * A crew member who walks into a pet that will not swap places steps round it. The HoS's giant spider, in
 * combat mode like every basic mob, once kept them behind their own desk all shift.
 */
/datum/unit_test/sp_step_past_pets

/datum/unit_test/sp_step_past_pets/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/beyond = get_step(start, EAST)
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, start)
	var/datum/ai_controller/sp_crew/controller = new(crew)
	controller.set_ai_status(AI_STATUS_OFF)
	var/mob/living/basic/spider/giant/sgt_araneus/araneus = allocate(/mob/living/basic/spider/giant/sgt_araneus, beyond)
	araneus.set_combat_mode(TRUE)
	TEST_ASSERT(sp_animal_in_the_way(araneus), "a spider in combat mode, after nobody, is only in the way")
	crew.Move(beyond, EAST)
	TEST_ASSERT_EQUAL(get_turf(crew), beyond, "the crew member should have stepped past the spider")
	TEST_ASSERT_EQUAL(get_turf(araneus), start, "and the spider should be where they were standing")
	qdel(controller)

/// A monkey with a baton is only a monkey until it starts swinging it. A person holding one is still a worry.
/datum/unit_test/sp_armed_monkeys

/datum/unit_test/sp_armed_monkeys/Run()
	var/mob/living/carbon/human/species/monkey/monkey = allocate(/mob/living/carbon/human/species/monkey, run_loc_floor_bottom_left)
	monkey.put_in_hands(allocate(/obj/item/melee/baton))
	monkey.set_combat_mode(FALSE)
	TEST_ASSERT(sp_is_armed(monkey), "the monkey should count as armed")
	TEST_ASSERT(!sp_armed_threat(monkey), "an armed monkey minding its own business is no threat")
	monkey.set_combat_mode(TRUE)
	TEST_ASSERT(sp_armed_threat(monkey), "a monkey spoiling for a fight is")
	var/mob/living/carbon/human/person = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	person.put_in_hands(allocate(/obj/item/melee/baton))
	TEST_ASSERT(sp_armed_threat(person), "a person holding a baton is still a worry")

/// Every SP controller has to point at a behaviour tree that was actually compiled.
/datum/unit_test/sp_behaviour_trees

/datum/unit_test/sp_behaviour_trees/Run()
	for(var/controller_type in typesof(/datum/ai_controller/sp_crew))
		var/datum/ai_controller/sp_crew/controller = controller_type
		var/json = initial(controller.behavior_tree_json)
		TEST_ASSERT_NOTNULL(json, "[controller_type] has no behaviour tree")
		TEST_ASSERT(fexists(BT_COMPILED_PATH(json)), "[controller_type] points at [json], which has not been compiled")

/// Crew pick things up off the floor, but leave what somebody has set out on a table.
/datum/unit_test/sp_pocket_from_floor

/datum/unit_test/sp_pocket_from_floor/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	crew.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/datum/ai_controller/sp_crew/controller = new(crew)
	controller.set_ai_status(AI_STATUS_OFF)
	controller.override_blackboard_key(BB_SP_INTERESTS, list(/obj/item/toy))
	// One set out on a table right beside them, one lying on the floor further off.
	var/turf/table_spot = get_step(spot, EAST)
	allocate(/obj/structure/table, table_spot)
	var/obj/item/toy/crayon/red/on_table = allocate(/obj/item/toy/crayon/red, table_spot)
	var/obj/item/toy/crayon/blue/on_floor = allocate(/obj/item/toy/crayon/blue, get_step(get_step(spot, NORTH), NORTH))
	TEST_ASSERT_EQUAL(sp_find_loose_item(crew, controller, null), on_floor, "the one on the floor is the one to take")
	TEST_ASSERT(sp_pocket_loose_item(controller, on_floor), "they should pick it up")
	TEST_ASSERT(on_floor in crew.get_all_contents(), "and have it on them afterwards")
	TEST_ASSERT_EQUAL(on_table.loc, table_spot, "what was set out on the table should be left alone")
	qdel(controller)

/// A medic who has run out empties the nearest medical crate, and stops counting as low.
/datum/unit_test/sp_medic_restock

/datum/unit_test/sp_medic_restock/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	medic.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/datum/ai_controller/sp_crew/medical/controller = new(medic)
	controller.set_ai_status(AI_STATUS_OFF)
	TEST_ASSERT(sp_medic_low_on_supplies(medic), "a medic carrying nothing is low")
	var/obj/structure/closet/crate/medical/crate = allocate(/obj/structure/closet/crate/medical, get_step(spot, EAST))
	var/obj/item/stack/medical/suture/sutures = allocate(/obj/item/stack/medical/suture)
	sutures.forceMove(crate)
	var/obj/item/stack/medical/mesh/mesh = allocate(/obj/item/stack/medical/mesh)
	mesh.forceMove(crate)
	TEST_ASSERT_EQUAL(length(sp_supplies_inside(crate)), 2, "both stacks are worth taking")
	TEST_ASSERT_EQUAL(sp_find_supply_store(medic, null), crate, "the crate beside them is the one to open")
	var/taken = sp_restock_from(controller, crate)
	TEST_ASSERT(taken >= 2, "they should take both stacks, took [taken] (crate open: [crate.opened], left inside: [length(sp_supplies_inside(crate))], on them: [length(medic.get_all_contents_type(/obj/item/stack/medical))], bag: [medic.back])")
	TEST_ASSERT(!sp_medic_low_on_supplies(medic), "and not be low any more")
	qdel(controller)

/// Botany takes a request for aloe off the radio, and knows the aloe they carry is what was asked for.
/datum/unit_test/sp_botany_request

/datum/unit_test/sp_botany_request/Run()
	TEST_ASSERT_EQUAL(sp_plant_asked_for("Botany, could you send some aloe up to medbay?"), "aloe", "that is a request")
	TEST_ASSERT_NULL(sp_plant_asked_for("I could murder an aloe smoothie"), "a passing mention is not a request")
	TEST_ASSERT_NULL(sp_plant_asked_for("Botany, how are the tomatoes coming along?"), "and nor is a plant we take no requests for")
	var/mob/living/carbon/human/botanist = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/datum/ai_controller/sp_crew/botanist/controller = new(botanist)
	controller.set_ai_status(AI_STATUS_OFF)
	var/obj/item/food/grown/aloe/aloe = allocate(/obj/item/food/grown/aloe)
	botanist.put_in_hands(aloe)
	TEST_ASSERT_NULL(sp_requested_produce(botanist, controller), "nobody has asked for anything yet")
	controller.set_blackboard_key(BB_SP_PLANT_REQUEST, "aloe")
	TEST_ASSERT_EQUAL(sp_requested_produce(botanist, controller), aloe, "the aloe they carry is what was asked for")
	qdel(controller)


/// Rummaging takes things. A closet tips its contents onto the floor as it opens, and reading the
/// contents afterwards found an empty box, so crew opened lockers all shift and took nothing.
/datum/unit_test/sp_rummage_takes

/datum/unit_test/sp_rummage_takes/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	crew.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/datum/ai_controller/sp_crew/controller = new(crew)
	controller.set_ai_status(AI_STATUS_OFF)
	controller.override_blackboard_key(BB_SP_INTERESTS, list(/obj/item/toy))
	var/obj/structure/closet/locker = allocate(/obj/structure/closet, get_step(spot, EAST))
	var/obj/item/toy/crayon/red/prize = allocate(/obj/item/toy/crayon/red)
	prize.forceMove(locker)
	var/list/names = sp_rummage_container(controller, locker)
	TEST_ASSERT(length(names), "they should have taken something out of the locker")
	TEST_ASSERT(prize in crew.get_all_contents(), "and have it on them afterwards")
	TEST_ASSERT(!locker.opened, "an ordinary crew member shuts the locker again")
	qdel(controller)

/// Medics do not ask twice: a crate already on order, or aloe botany is already after, keeps them quiet.
/datum/unit_test/sp_restock_asks_once

/datum/unit_test/sp_restock_asks_once/Run()
	sp_forget_requests(/datum/supply_pack/medical/supplies)
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(!sp_supplies_on_order(/datum/supply_pack/medical/supplies), "nothing should be on order to begin with")
	var/datum/sp_supply_request/request = sp_request_supplies(/datum/supply_pack/medical/supplies, medic)
	TEST_ASSERT_NOTNULL(request, "the request should go in")
	TEST_ASSERT(sp_supplies_on_order(/datum/supply_pack/medical/supplies), "and count as on order")
	request.status = SP_REQUEST_DELIVERED
	TEST_ASSERT(!sp_supplies_on_order(/datum/supply_pack/medical/supplies), "a delivered crate is no longer on order")
	SSspacestation_sp.supply_requests -= request

	var/mob/living/carbon/human/botanist = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	var/datum/ai_controller/sp_crew/botanist/controller = new(botanist)
	controller.set_ai_status(AI_STATUS_OFF)
	SSspacestation_sp.register_crew(botanist)
	TEST_ASSERT(!sp_plant_requested("aloe"), "nobody has asked botany for aloe yet")
	controller.set_blackboard_key(BB_SP_PLANT_REQUEST, "aloe")
	TEST_ASSERT(sp_plant_requested("aloe"), "a botanist with the request in hand counts")
	SSspacestation_sp.ai_crew -= botanist
	qdel(controller)

/// Clears out requests for a pack, so a test that failed halfway and left one behind does not fail the next test too.
/datum/unit_test/proc/sp_forget_requests(pack_type)
	for(var/datum/sp_supply_request/stale as anything in SSspacestation_sp.supply_requests.Copy())
		if(stale.pack?.type == pack_type)
			SSspacestation_sp.supply_requests -= stale

/// A crate is matched to its request on the order number the shuttle stamps on it, not on the pack's name:
/// medbay's Medical Supplies Crate arrives as a DeForest Medical crate, and sat unclaimed in the cargo bay.
/datum/unit_test/sp_crate_matches_order

/datum/unit_test/sp_crate_matches_order/Run()
	sp_forget_requests(/datum/supply_pack/medical/supplies)
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/datum/sp_supply_request/request = sp_request_supplies(/datum/supply_pack/medical/supplies, medic)
	TEST_ASSERT_NOTNULL(request, "the request should go in")
	request.status = SP_REQUEST_ORDERED
	request.order_id = 3029
	var/obj/structure/closet/crate/ours = allocate(/obj/structure/closet/crate, run_loc_floor_bottom_left)
	ours.name = "DeForest Medical crate - #3029"
	var/obj/structure/closet/crate/longer_number = allocate(/obj/structure/closet/crate, run_loc_floor_bottom_left)
	longer_number.name = "DeForest Medical crate - #13029"
	var/obj/structure/closet/crate/pack_name = allocate(/obj/structure/closet/crate, run_loc_floor_bottom_left)
	pack_name.name = "Medical Supplies Crate"
	TEST_ASSERT_EQUAL(sp_request_for_crate(ours), request, "the crate with the order number is the one medbay asked for")
	TEST_ASSERT_NULL(sp_request_for_crate(longer_number), "an order number that only ends the same way belongs to somebody else")
	TEST_ASSERT_NULL(sp_request_for_crate(pack_name), "and a crate without the number is not matched on the pack's name")
	SSspacestation_sp.supply_requests -= request

/// One technician per crate. Two who picked the same one took the pull off each other across the station and
/// both gave up, so a crate somebody is already on their way to is left to them.
/datum/unit_test/sp_crate_claims

/datum/unit_test/sp_crate_claims/Run()
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, NORTH))
	var/datum/ai_controller/sp_crew/second_ai = new(second)
	second_ai.set_ai_status(AI_STATUS_OFF)
	SSspacestation_sp.register_crew(second)
	var/obj/structure/closet/crate/crate = allocate(/obj/structure/closet/crate, get_step(run_loc_floor_bottom_left, EAST))
	TEST_ASSERT(!sp_crate_claimed(crate, first), "nobody has this crate yet")
	second_ai.set_blackboard_key(BB_SP_CRATE, crate)
	TEST_ASSERT(sp_crate_claimed(crate, first), "a crate the other technician is heading for is theirs")
	TEST_ASSERT(!sp_crate_claimed(crate, second), "and still fair game for the one heading for it")
	SSspacestation_sp.ai_crew -= second
	qdel(second_ai)

/**
 * A delivery for a room the courier cannot get into is left short of the first door they cannot open, rather
 * than walked at that door until the haul times out. With access to the door, it goes all the way.
 */
/datum/unit_test/sp_drop_spot_short_of_door

/datum/unit_test/sp_drop_spot_short_of_door/Run()
	var/turf/corner = run_loc_floor_bottom_left
	var/turf/doorway = locate(corner.x + 2, corner.y + 2, corner.z)
	for(var/offset in list(0, 1, 3, 4))
		allocate(/obj/structure/window/reinforced/fulltile, locate(corner.x + 2, corner.y + offset, corner.z))
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, doorway)
	door.req_access = list(ACCESS_CAPTAIN)
	var/mob/living/carbon/human/courier = allocate(/mob/living/carbon/human/consistent, corner)
	var/turf/destination = locate(corner.x + 4, corner.y + 2, corner.z)

	var/turf/spot = sp_reachable_drop_spot(courier, destination)
	TEST_ASSERT_NOTNULL(spot, "a door we cannot open should still leave us somewhere to put the delivery")
	TEST_ASSERT(spot.x < doorway.x, "the delivery should be left on our side of the door, not at [spot.x - corner.x],[spot.y - corner.y]")
	TEST_ASSERT(!(locate(/obj/machinery/door) in spot), "and not in the doorway")

	var/obj/item/clothing/under/color/grey/jumpsuit = allocate(/obj/item/clothing/under/color/grey)
	courier.equip_to_slot_or_del(jumpsuit, ITEM_SLOT_ICLOTHING)
	var/obj/item/card/id/advanced/card = allocate(/obj/item/card/id/advanced)
	card.access = list(ACCESS_CAPTAIN)
	courier.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	TEST_ASSERT(ACCESS_CAPTAIN in courier.get_access(), "the test courier should be carrying the access for the door")
	TEST_ASSERT_EQUAL(sp_reachable_drop_spot(courier, destination), destination, "with access to the door the delivery goes all the way")

/// Whoever unlocks a locker to rummage in it locks it again, rather than leaving a head's locker open to anybody.
/datum/unit_test/sp_rummage_relocks

/datum/unit_test/sp_rummage_relocks/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	crew.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/datum/ai_controller/sp_crew/controller = new(crew)
	controller.set_ai_status(AI_STATUS_OFF)
	controller.override_blackboard_key(BB_SP_INTERESTS, list(/obj/item/toy))
	var/obj/structure/closet/secure_closet/locker = allocate(/obj/structure/closet/secure_closet, get_step(spot, EAST))
	locker.req_access = list()
	locker.req_one_access = list()
	TEST_ASSERT(locker.locked, "the locker should start out locked")
	var/obj/item/toy/crayon/red/prize = allocate(/obj/item/toy/crayon/red)
	prize.forceMove(locker)
	var/list/names = sp_rummage_container(controller, locker)
	TEST_ASSERT(length(names), "they should have unlocked the locker and taken something")
	TEST_ASSERT(!locker.opened, "and shut it again")
	TEST_ASSERT(locker.locked, "and locked it again, having been the ones to unlock it")
	qdel(controller)

/// A crate cargo delivered for medbay is found wherever the technician managed to leave it, in sight or not.
/datum/unit_test/sp_medic_finds_delivery

/datum/unit_test/sp_medic_finds_delivery/Run()
	sp_forget_requests(/datum/supply_pack/medical/supplies)
	var/turf/corner = run_loc_floor_bottom_left
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human/consistent, corner)
	for(var/list/offset in list(list(3, 4), list(3, 3), list(4, 3)))
		allocate(/obj/structure/falsewall, locate(corner.x + offset[1], corner.y + offset[2], corner.z))
	var/obj/structure/closet/crate/crate = allocate(/obj/structure/closet/crate, locate(corner.x + 4, corner.y + 4, corner.z))
	var/obj/item/stack/medical/suture/sutures = allocate(/obj/item/stack/medical/suture)
	sutures.forceMove(crate)
	TEST_ASSERT(!(crate in oview(SP_MEDIC_SIGHT, medic)), "the crate should be out of sight, or this test proves nothing")
	TEST_ASSERT_NULL(sp_find_supply_store(medic), "a crate out of sight that nobody delivered for us is not ours to find")
	var/datum/sp_supply_request/request = sp_request_supplies(/datum/supply_pack/medical/supplies, medic)
	TEST_ASSERT_NOTNULL(request, "the request should go in")
	request.status = SP_REQUEST_DELIVERED
	request.crate = WEAKREF(crate)
	TEST_ASSERT_EQUAL(sp_find_supply_store(medic), crate, "a crate cargo delivered for medbay should be found wherever it was left")
	SSspacestation_sp.supply_requests -= request

/// Botany cooks the aloe medbay asked for into the burn cream they wanted, in a real microwave.
/datum/unit_test/sp_botany_cooks_request

/datum/unit_test/sp_botany_cooks_request/Run()
	var/mob/living/carbon/human/botanist = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	botanist.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/datum/ai_controller/sp_crew/botanist/controller = new(botanist)
	controller.set_ai_status(AI_STATUS_OFF)
	var/obj/machinery/microwave/microwave = allocate(/obj/machinery/microwave, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/food/grown/aloe/aloe = allocate(/obj/item/food/grown/aloe)
	aloe.forceMove(bag)
	TEST_ASSERT(!length(sp_request_needs_cooking(botanist, controller)), "nothing needs cooking before anybody asks")
	controller.set_blackboard_key(BB_SP_PLANT_REQUEST, "aloe")
	TEST_ASSERT_EQUAL(length(sp_request_needs_cooking(botanist, controller)), 1, "the aloe wants cooking once medbay has asked for it")
	TEST_ASSERT(sp_microwave_usable(microwave), "the test microwave should be ready to use")
	var/list/made = sp_cook_in_microwave(controller, microwave, sp_request_needs_cooking(botanist, controller), /obj/item/stack/medical/aloe)
	TEST_ASSERT(length(made), "cooking the aloe should make burn cream")
	TEST_ASSERT(QDELETED(aloe), "and use the aloe up")
	TEST_ASSERT(istype(sp_requested_produce(botanist, controller), /obj/item/stack/medical/aloe), "the cream is the delivery now")
	TEST_ASSERT(!length(sp_request_needs_cooking(botanist, controller)), "and there is nothing left to cook")
	qdel(controller)

/// Supplies left for a medic by name are found wherever they were put down, and picked up.
/datum/unit_test/sp_medic_takes_left_supplies

/datum/unit_test/sp_medic_takes_left_supplies/Run()
	sp_forget_requests(/datum/supply_pack/medical/supplies)
	var/turf/corner = run_loc_floor_bottom_left
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human/consistent, corner)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	medic.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/datum/ai_controller/sp_crew/medical/controller = new(medic)
	controller.set_ai_status(AI_STATUS_OFF)
	for(var/list/offset in list(list(3, 4), list(3, 3), list(4, 3)))
		allocate(/obj/structure/falsewall, locate(corner.x + offset[1], corner.y + offset[2], corner.z))
	var/turf/hidden = locate(corner.x + 4, corner.y + 4, corner.z)
	var/obj/item/stack/medical/aloe/cream = allocate(/obj/item/stack/medical/aloe, hidden)
	TEST_ASSERT_NULL(sp_find_supply_store(medic, null, controller), "cream out of sight that nobody left for us is not ours to find")
	sp_leave_for(medic, list(cream))
	TEST_ASSERT_EQUAL(sp_find_supply_store(medic, null, controller), cream, "cream left for us by name should be found wherever it was put down")
	medic.forceMove(hidden)
	TEST_ASSERT(sp_pick_up_left_supplies(controller, cream), "and picked up once we are beside it")
	TEST_ASSERT(cream in medic.get_all_contents(), "into our bag or our hands")
	TEST_ASSERT(!length(controller.blackboard[BB_SP_LEFT_FOR_ME]), "and crossed off the list")
	qdel(controller)

/// A request that says where to send it goes there, and medbay's asks go to medbay, not wherever the medic stood.
/datum/unit_test/sp_request_names_destination

/datum/unit_test/sp_request_names_destination/Run()
	TEST_ASSERT(ispath(sp_named_delivery_area("Botany, could you send some aloe up to medbay?"), /area/station/medical), "a request for medbay should be delivered to medbay")
	TEST_ASSERT(ispath(sp_named_delivery_area("Any aloe going spare, botany? Medbay could use it."), /area/station/medical), "however it is put")
	TEST_ASSERT_NULL(sp_named_delivery_area("Botany, any aloe going spare?"), "a request that names nowhere leaves it to where the asker is standing")
	TEST_ASSERT(ispath(sp_medbay_delivery_area(), /area/station/medical), "medbay's own asks for supplies should be addressed to medbay")

/// A patient let go inside medbay is buzzed back out through its doors for a while, and through nobody else's.
/datum/unit_test/sp_patient_shown_out

/datum/unit_test/sp_patient_shown_out/Run()
	var/turf/corner = run_loc_floor_bottom_left
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, corner)
	var/datum/ai_controller/sp_crew/controller = new(patient)
	controller.set_ai_status(AI_STATUS_OFF)
	var/obj/machinery/door/airlock/medbay_door = allocate(/obj/machinery/door/airlock, get_step(corner, EAST))
	medbay_door.req_access = list(ACCESS_MEDICAL)
	var/obj/machinery/door/airlock/vault_door = allocate(/obj/machinery/door/airlock, get_step(corner, NORTH))
	vault_door.req_access = list(ACCESS_VAULT)
	sp_see_out(patient)
	TEST_ASSERT(!controller.blackboard[BB_SP_SHOWN_OUT_UNTIL], "nobody is seen out of a room that is not medbay")
	TEST_ASSERT(!(ACCESS_MEDICAL in controller.get_access()), "a patient has no medbay access of their own")
	TEST_ASSERT(!sp_buzz_through(patient, medbay_door), "and nobody buzzes them through before they have been seen")
	controller.set_blackboard_key(BB_SP_SHOWN_OUT_UNTIL, world.time + SP_SHOWN_OUT_TIME)
	TEST_ASSERT(ACCESS_MEDICAL in controller.get_access(), "a patient being seen out may route through medbay's doors")
	TEST_ASSERT(!sp_buzz_through(patient, vault_door), "but not through anybody else's")
	TEST_ASSERT(sp_buzz_through(patient, medbay_door), "and medbay's own door opens for them")
	qdel(controller)

/// A seed somebody asked for goes into the next free tray ahead of routine work, unless it is already growing.
/datum/unit_test/sp_requested_seed_first

/datum/unit_test/sp_requested_seed_first/Run()
	var/turf/corner = run_loc_floor_bottom_left
	var/mob/living/carbon/human/botanist = allocate(/mob/living/carbon/human/consistent, corner)
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack)
	botanist.equip_to_slot_or_del(bag, ITEM_SLOT_BACK)
	var/obj/item/reagent_containers/cup/watering_can/can = allocate(/obj/item/reagent_containers/cup/watering_can)
	can.reagents.add_reagent(/datum/reagent/water, 50)
	can.forceMove(bag)
	var/obj/item/seeds/aloe/packet = allocate(/obj/item/seeds/aloe)
	packet.forceMove(bag)
	var/obj/machinery/hydroponics/constructable/thirsty = allocate(/obj/machinery/hydroponics/constructable, get_step(corner, EAST))
	thirsty.myseed = new /obj/item/seeds/tomato(thirsty)
	thirsty.waterlevel = 0
	var/obj/machinery/hydroponics/constructable/empty = allocate(/obj/machinery/hydroponics/constructable, locate(corner.x + 3, corner.y, corner.z))
	var/list/found = sp_find_tray_job(botanist)
	TEST_ASSERT_EQUAL(found?[1], thirsty, "with nothing asked for, the nearer tray that needs water comes first")
	found = sp_find_tray_job(botanist, preferred_species = "aloe")
	TEST_ASSERT_EQUAL(found?[1], empty, "a seed somebody asked for goes into the empty tray first")
	TEST_ASSERT_EQUAL(found?[2], SP_TRAY_JOB_PLANT, "as a planting job")
	var/list/recently = list()
	recently[empty] = world.time + 1 MINUTES
	found = sp_find_tray_job(botanist, preferred_species = "aloe", ignored = recently)
	TEST_ASSERT_EQUAL(found?[1], thirsty, "a tray picked too recently is passed over")
	QDEL_NULL(thirsty.myseed)
	thirsty.myseed = new /obj/item/seeds/aloe(thirsty)
	found = sp_find_tray_job(botanist, preferred_species = "aloe")
	TEST_ASSERT_EQUAL(found?[1], thirsty, "once it is growing, the request no longer jumps the queue")

/// A steal scheme reads incomplete until the pawn is carrying the target, and complete once they are.
/datum/unit_test/sp_scheme_steal

/datum/unit_test/sp_scheme_steal/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/thief = allocate(/mob/living/carbon/human/consistent, spot)
	var/datum/ai_controller/sp_crew/antagonist/controller = new(thief)
	controller.set_ai_status(AI_STATUS_OFF)
	var/datum/sp_scheme/steal/scheme = new()
	scheme.target_type = /obj/item/toy/crayon/red
	scheme.name = "steal a red crayon"
	controller.set_blackboard_key(BB_SP_SCHEME, scheme)
	var/obj/item/toy/crayon/red/prize = allocate(/obj/item/toy/crayon/red, get_step(spot, EAST))
	TEST_ASSERT(!scheme.evaluate(controller), "the scheme should read incomplete before the prize is taken")
	TEST_ASSERT_EQUAL(sp_reachable_item(thief, /obj/item/toy/crayon/red), prize, "the crayon a step away is not reachable until we are beside it")
	prize.forceMove(thief)
	TEST_ASSERT_EQUAL(sp_reachable_item(thief, /obj/item/toy/crayon/red), prize, "a carried target counts as reachable")
	TEST_ASSERT(scheme.evaluate(controller), "carrying the prize should complete the scheme")
	TEST_ASSERT(scheme.check_progress(controller), "and check_progress should latch it")
	TEST_ASSERT(scheme.complete, "the scheme stays complete once met")
	// A schemer keeps their head down: they do not report crimes while a scheme is on the go.
	TEST_ASSERT(!controller.reports_crimes(), "a crew member with a scheme does not grass on anyone")
	qdel(controller)

/**
 * Who counts as a witness to a crime, and what a callout does: assistants and schemers keep quiet, an
 * ordinary crew member calls it out, thinks less of the culprit, and (with a headset) files a suspect.
 */
/datum/unit_test/sp_crime_witnesses

/datum/unit_test/sp_crime_witnesses/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/culprit = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/onlooker = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/onlooker_ai = new(onlooker)
	onlooker_ai.set_ai_status(AI_STATUS_OFF)

	TEST_ASSERT(culprit in sp_witnesses(onlooker), "the onlooker can see the culprit a tile away")
	TEST_ASSERT(onlooker in sp_crime_witnesses(culprit), "an ordinary crew member would tell")

	// An assistant looks the other way.
	var/mob/living/carbon/human/tider = allocate(/mob/living/carbon/human/consistent, get_step(spot, WEST))
	var/datum/ai_controller/sp_crew/assistant/tider_ai = new(tider)
	tider_ai.set_ai_status(AI_STATUS_OFF)
	TEST_ASSERT(!(tider in sp_crime_witnesses(culprit)), "an assistant does not grass")

	// So does a crew member running their own scheme.
	var/mob/living/carbon/human/schemer = allocate(/mob/living/carbon/human/consistent, get_step(spot, NORTH))
	var/datum/ai_controller/sp_crew/schemer_ai = new(schemer)
	schemer_ai.set_ai_status(AI_STATUS_OFF)
	schemer_ai.set_blackboard_key(BB_SP_SCHEME, new /datum/sp_scheme())
	TEST_ASSERT(!(schemer in sp_crime_witnesses(culprit)), "a schemer keeps their head down")

	// The callout itself: reputation drops, and a headset files a suspect incident with no attacker.
	var/obj/item/radio/headset/radio = allocate(/obj/item/radio/headset)
	onlooker.equip_to_slot_or_del(radio, ITEM_SLOT_EARS)
	sp_call_out_crime(onlooker_ai, culprit, SP_CRIME_THEFT, "take a stamp", spot)
	TEST_ASSERT(sp_reputation(onlooker_ai, culprit) < 0, "a witness thinks less of a thief")
	var/list/incident = onlooker_ai.blackboard[BB_SP_LAST_INCIDENT]
	TEST_ASSERT_NOTNULL(incident, "a witness with a headset files an incident")
	TEST_ASSERT_EQUAL(incident[SP_INCIDENT_CRIME], SP_CRIME_THEFT, "recorded as the right crime")
	var/datum/weakref/suspect_ref = incident[SP_INCIDENT_SUSPECT]
	TEST_ASSERT_EQUAL(suspect_ref?.resolve(), culprit, "with the culprit as the suspect")
	TEST_ASSERT_NULL(incident[SP_INCIDENT_ATTACKER], "and no attacker, so security investigates rather than batons")
	qdel(onlooker_ai)
	qdel(tider_ai)
	qdel(schemer_ai)

/// Breaking a light tube leaves it dark. The malicious greytide's one built behaviour, at the point it acts.
/datum/unit_test/sp_break_light

/datum/unit_test/sp_break_light/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/tider = allocate(/mob/living/carbon/human/consistent, spot)
	var/datum/ai_controller/sp_crew/assistant/controller = new(tider)
	controller.set_ai_status(AI_STATUS_OFF)
	var/obj/machinery/light/light = allocate(/obj/machinery/light, get_step(spot, EAST))
	light.status = LIGHT_OK
	light.on = TRUE
	TEST_ASSERT(sp_prank_vandalism(controller, light), "smashing a lit tube should succeed")
	TEST_ASSERT_EQUAL(light.status, LIGHT_BROKEN, "and leave the tube broken")
	qdel(controller)

/**
 * A steal target has to be something a thief could actually walk up to and lift.
 *
 * The first antagonist of the first live round was a mime sent after the medal of captaincy, which spawns
 * inside a locked lockbox in the captain's quarters, with the only other copy pinned to the captain's uniform.
 * It was chosen because it existed on the map, not because anybody could have it, and the mime spent the shift
 * with nothing to do and nothing in the log to say why.
 */
/datum/unit_test/sp_steal_target_liftable

/datum/unit_test/sp_steal_target_liftable/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/obj/item/toy/crayon/red/loose = allocate(/obj/item/toy/crayon/red, spot)
	TEST_ASSERT(sp_can_be_lifted(loose), "something lying on the floor can be picked up")

	var/obj/structure/closet/locker = allocate(/obj/structure/closet, get_step(spot, EAST))
	var/obj/item/toy/crayon/red/in_locker = allocate(/obj/item/toy/crayon/red)
	in_locker.forceMove(locker)
	TEST_ASSERT(sp_can_be_lifted(in_locker), "a closet opens, so what is shut in it still counts")

	var/obj/item/storage/box/carton = allocate(/obj/item/storage/box, spot)
	var/obj/item/toy/crayon/red/in_box = allocate(/obj/item/toy/crayon/red)
	in_box.forceMove(carton)
	TEST_ASSERT(!sp_can_be_lifted(in_box), "something sealed in a box is not worth sending anybody after")

	var/mob/living/carbon/human/owner = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/toy/crayon/red/carried = allocate(/obj/item/toy/crayon/red)
	carried.forceMove(owner)
	TEST_ASSERT(!sp_can_be_lifted(carried), "and neither is something somebody is already carrying")

/**
 * A thief only takes on a target they can actually walk to with their own ID.
 *
 * A cook was sent after an ablative trenchcoat on an armory shelf: liftable, on the station, and behind a door
 * no cook opens. She reported it honestly from the brig and never moved. Being able to lift a thing and being
 * able to reach it are two different questions.
 */
/datum/unit_test/sp_steal_target_reachable

/datum/unit_test/sp_steal_target_reachable/Run()
	var/turf/corner = run_loc_floor_bottom_left
	var/mob/living/carbon/human/thief = allocate(/mob/living/carbon/human/consistent, corner)
	var/datum/objective_item/reachable = new /datum/objective_item()
	reachable.targetitem = /obj/item/toy/crayon/red
	var/obj/item/toy/crayon/red/prize = allocate(/obj/item/toy/crayon/red, locate(corner.x + 3, corner.y, corner.z))
	GLOB.steal_item_handler.objectives_by_path[/obj/item/toy/crayon/red] = list(prize)
	TEST_ASSERT(sp_reachable_steal_item(thief, reachable), "a crayon across an open room can be walked to")

	// Wall it off completely: liftable as ever, and now no way in.
	for(var/offset in list(0, 1, 2, 3, 4))
		allocate(/obj/structure/window/reinforced/fulltile, locate(corner.x + 2, corner.y + offset, corner.z))
	TEST_ASSERT(sp_can_be_lifted(prize, thief), "it is still lying out in the open")
	TEST_ASSERT(!sp_reachable_steal_item(thief, reachable), "but a target we cannot get to is not a target")
	GLOB.steal_item_handler.objectives_by_path[/obj/item/toy/crayon/red] = list()
