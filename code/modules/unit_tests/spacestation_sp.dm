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
	TEST_ASSERT(!sp_test_owes_answer(doctor_ai), "a doctor with a patient should not stop to answer chatter")
	doctor_ai.clear_blackboard_key(BB_SP_PATIENT)
	doctor_ai.consider_conversation(speaker, "Kaleb, have you got a minute?")
	TEST_ASSERT(sp_test_owes_answer(doctor_ai), "a doctor with nobody to see should answer when spoken to by name")

	chemist_ai.set_blackboard_key(BB_SP_CHEM_PRODUCT, /datum/reagent/medicine/c2/libital)
	chemist_ai.consider_conversation(speaker, "Allegra, have you got a minute?")
	TEST_ASSERT(!sp_test_owes_answer(chemist_ai), "a chemist with an order in hand should not stop to answer chatter")
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

/**
 * A crime reported with a suspect and no attacker sends security to have a word, not to swing a baton.
 *
 * Security's existing response is for people who hit people. Routing a smashed light tube through it would
 * have an officer beating an assistant senseless, which is the disproportion this branch exists to avoid.
 */
/datum/unit_test/sp_security_confronts_suspect

/datum/unit_test/sp_security_confronts_suspect/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/reporter = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/mob/living/carbon/human/culprit = allocate(/mob/living/carbon/human/consistent, get_step(spot, WEST))
	var/datum/ai_controller/sp_crew/security/officer_ai = new(officer)
	officer_ai.set_ai_status(AI_STATUS_OFF)

	// A witnessed theft: a suspect and a place, but nobody being hit.
	officer_ai.on_heard_incident(reporter, list(
		SP_INCIDENT_ATTACKER = null,
		SP_INCIDENT_SUSPECT = WEAKREF(culprit),
		SP_INCIDENT_VICTIM = WEAKREF(reporter),
		SP_INCIDENT_TURF = get_turf(culprit),
		SP_INCIDENT_TIME = world.time,
		SP_INCIDENT_CRIME = SP_CRIME_THEFT,
	))
	TEST_ASSERT_EQUAL(officer_ai.blackboard[BB_SP_SUSPECT], culprit, "a named suspect is somebody to go and speak to")
	TEST_ASSERT_EQUAL(officer_ai.blackboard[BB_SP_SUSPECT_CRIME], SP_CRIME_THEFT, "and what they are said to have done is remembered")
	TEST_ASSERT_NULL(officer_ai.blackboard[BB_SP_INCIDENT_TARGET], "but a suspect is not a target for the baton")

	// Somebody actually being attacked still is.
	officer_ai.on_heard_incident(reporter, list(
		SP_INCIDENT_ATTACKER = WEAKREF(culprit),
		SP_INCIDENT_VICTIM = WEAKREF(reporter),
		SP_INCIDENT_TURF = get_turf(culprit),
		SP_INCIDENT_TIME = world.time,
	))
	TEST_ASSERT_EQUAL(officer_ai.blackboard[BB_SP_INCIDENT_TARGET], culprit, "an attacker is still stopped the old way")
	qdel(officer_ai)

/// Crimes go on the record, and a pattern on the record is what turns the next word into an arrest.
/datum/unit_test/sp_crime_record_escalates

/datum/unit_test/sp_crime_record_escalates/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/culprit = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	culprit.real_name = "Testy McSuspect"

	// Nobody the manifest knows about has no record to write on, and that is not an error.
	TEST_ASSERT_EQUAL(sp_file_crime_record(culprit, SP_CRIME_THEFT, "no record", officer), 0, "somebody with no record is left alone")

	var/datum/record/crew/record = new(name = "Testy McSuspect")
	GLOB.manifest.general += record
	TEST_ASSERT_EQUAL(sp_file_crime_record(culprit, SP_CRIME_THEFT, "took a stamp", officer), 1, "the first crime goes on the record")
	TEST_ASSERT_EQUAL(record.wanted_status, WANTED_NONE, "one offence is a word, not an arrest")
	TEST_ASSERT_EQUAL(sp_file_crime_record(culprit, SP_CRIME_VANDALISM, "smashed a light", officer), 2, "so does the second")
	TEST_ASSERT_EQUAL(record.wanted_status, WANTED_NONE, "still not an arrest")
	TEST_ASSERT_EQUAL(sp_file_crime_record(culprit, SP_CRIME_TRESPASS, "let themselves in", officer), 3, "and the third")
	TEST_ASSERT(3 > SP_CRIMES_BEFORE_ARREST, "three crimes should be past the threshold")
	TEST_ASSERT(sp_mark_for_arrest(culprit), "a pattern on the record is an arrest")
	TEST_ASSERT_EQUAL(record.wanted_status, WANTED_ARREST, "and it says so on the record")
	TEST_ASSERT(!sp_mark_for_arrest(culprit), "and marking them twice changes nothing")
	GLOB.manifest.general -= record

/// An order from the head of security reaches whoever hears it, and changes only what it names.
/datum/unit_test/sp_order_relay

/datum/unit_test/sp_order_relay/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/boss = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/security/officer_ai = new(officer)
	officer_ai.set_ai_status(AI_STATUS_OFF)

	// Told where to be: the place and the hour it ends both land.
	officer_ai.on_heard_order(boss, list(SP_ORDER_KIND = SP_ORDER_MEETING, SP_ORDER_TIME = world.time, SP_ORDER_WHERE = spot, SP_ORDER_ISSUER = WEAKREF(boss)))
	TEST_ASSERT_EQUAL(officer_ai.blackboard[BB_SP_MEETING_SPOT], spot, "an officer called to a briefing knows where it is")
	TEST_ASSERT(officer_ai.blackboard[BB_SP_MEETING_UNTIL] > world.time, "and that it does not last forever")

	// Arming and lethal force are separate orders on purpose: one is not permission for the other.
	officer_ai.clear_blackboard_key(BB_SP_ARM_ORDER) // set as they came on shift to fetch their kit; the order must set it itself
	officer_ai.on_heard_order(boss, list(SP_ORDER_KIND = SP_ORDER_ARM, SP_ORDER_TIME = world.time, SP_ORDER_ISSUER = WEAKREF(boss)))
	TEST_ASSERT(officer_ai.blackboard[BB_SP_ARM_ORDER], "an officer told to arm remembers it")
	TEST_ASSERT_NULL(officer_ai.blackboard[BB_SP_USE_LETHALS], "but being armed is not being told to kill")
	officer_ai.on_heard_order(boss, list(SP_ORDER_KIND = SP_ORDER_LETHAL, SP_ORDER_TIME = world.time, SP_ORDER_ISSUER = WEAKREF(boss)))
	TEST_ASSERT(officer_ai.blackboard[BB_SP_USE_LETHALS], "lethal force takes an order of its own")

	// Standing down puts the lethal weapon away and nothing else. An order to arm now means fetching what you lack,
	// and it ends by itself: clearing it here cancelled every officer's belt trip at the HoS's first briefing.
	officer_ai.on_heard_order(boss, list(SP_ORDER_KIND = SP_ORDER_STAND_DOWN, SP_ORDER_TIME = world.time, SP_ORDER_ISSUER = WEAKREF(boss)))
	TEST_ASSERT_NULL(officer_ai.blackboard[BB_SP_USE_LETHALS], "standing down ends lethal force")
	TEST_ASSERT(officer_ai.blackboard[BB_SP_ARM_ORDER], "but a trip to fetch missing kit carries on")

	// Nobody is their own chain of command: hearing yourself say it is not being told.
	var/datum/ai_controller/sp_crew/security/self_ai = new(boss)
	self_ai.set_ai_status(AI_STATUS_OFF)
	self_ai.on_heard_order(boss, list(SP_ORDER_KIND = SP_ORDER_LETHAL, SP_ORDER_TIME = world.time, SP_ORDER_ISSUER = WEAKREF(boss)))
	TEST_ASSERT_NULL(self_ai.blackboard[BB_SP_USE_LETHALS], "an officer does not take orders from themselves")
	qdel(self_ai)
	qdel(officer_ai)

/// The whole point of fetching a belt: the baton is inside it, and a deep search is what finds it.
/datum/unit_test/sp_arming_finds_nested_baton

/datum/unit_test/sp_arming_finds_nested_baton/Run()
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(!length(officer.get_all_contents_type(/obj/item/melee/baton/security)), "an officer starts the shift with no baton at all")

	// One belt, carried. Nothing is worn and nothing is unpacked: this is exactly what sp_take_arm_kit leaves
	// behind, and if it is not enough then arming an officer quietly achieves nothing.
	var/obj/item/storage/belt/security/full/belt = new(officer)
	TEST_ASSERT_NOTNULL(belt, "the belt exists")
	TEST_ASSERT(length(officer.get_all_contents_type(/obj/item/melee/baton/security)), "the baton inside the belt is found by a search that walks into containers")
	var/obj/item/found = sp_equip_from_inventory(officer, list(/obj/item/melee/baton/security, /obj/item/melee/baton))
	TEST_ASSERT_NOTNULL(found, "and the officer can get that baton into their hand without unpacking anything")

	// The sidearm they already had should be reachable the same way.
	var/obj/item/gun/energy/disabler/sidearm = new(officer)
	var/obj/item/drawn = sp_equip_from_inventory(officer, list(/obj/item/gun/energy/e_gun, /obj/item/gun/energy/disabler))
	TEST_ASSERT_EQUAL(drawn, sidearm, "and the disabler every officer carries is what the sidearm list finds")

/// A sentence is measured off the record, and never longer than the door timer would actually hold.
/datum/unit_test/sp_sentence_escalates

/datum/unit_test/sp_sentence_escalates/Run()
	var/mob/living/carbon/human/culprit = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	culprit.real_name = "Testy McConvict"
	TEST_ASSERT_EQUAL(sp_sentence_time(culprit), 0, "somebody the manifest never heard of serves nothing")

	var/datum/record/crew/record = new(name = "Testy McConvict")
	GLOB.manifest.general += record
	record.crimes += new /datum/crime("Theft", "the first", "Security")
	TEST_ASSERT_EQUAL(sp_sentence_time(culprit), SP_SENTENCE_PER_CRIME, "one crime, one stretch")
	record.crimes += new /datum/crime("Vandalism", "the second", "Security")
	TEST_ASSERT_EQUAL(sp_sentence_time(culprit), 2 * SP_SENTENCE_PER_CRIME, "two crimes, twice as long")

	// A rap sheet does not earn a sentence the brig timer would silently clamp.
	for(var/i in 1 to 20)
		record.crimes += new /datum/crime("Theft", "and again", "Security")
	TEST_ASSERT_EQUAL(sp_sentence_time(culprit), SP_SENTENCE_MAX, "a long record is capped, not unbounded")
	TEST_ASSERT(SP_SENTENCE_MAX < (15 MINUTES), "and the cap is short of MAX_TIMER, which clamps without saying so")
	GLOB.manifest.general -= record

/// A cell's inside is the side of its door's edge that the cell's locker stands on, whatever plain distance says.
/datum/unit_test/sp_cell_doorway_faces_the_locker

/datum/unit_test/sp_cell_doorway_faces_the_locker/Run()
	var/turf/door_turf = run_loc_floor_bottom_left
	var/turf/north_side = get_step(door_turf, NORTH)
	var/turf/east_side = get_step(door_turf, EAST)
	// A bare timer skips its own linkage scan (it only runs when id is set), so nothing is attached to it.
	var/obj/machinery/status_display/door_timer/timer = allocate(/obj/machinery/status_display/door_timer, east_side)
	TEST_ASSERT_NULL(sp_cell_doorway(null), "no timer at all is not a cell")
	TEST_ASSERT_NULL(sp_cell_doorway(timer), "a timer with nothing linked has no door to speak of")

	var/obj/machinery/door/window/brigdoor/door = allocate(/obj/machinery/door/window/brigdoor, door_turf)
	door.setDir(NORTH)
	timer.doors += WEAKREF(door)
	var/obj/structure/closet/secure_closet/brig/locker = allocate(/obj/structure/closet/secure_closet/brig, get_step(north_side, NORTH))
	timer.closets += WEAKREF(locker)
	var/list/doorway = sp_cell_doorway(timer)
	TEST_ASSERT_EQUAL(doorway?[1], north_side, "a locker past the door's edge puts the cell on that side")
	TEST_ASSERT_EQUAL(doorway?[2], door_turf, "which leaves the door's own tile outside")

	// Level with the door, the locker is on the door's own side of its edge. Plain distance calls that a tie.
	locker.forceMove(east_side)
	doorway = sp_cell_doorway(timer)
	TEST_ASSERT_EQUAL(doorway?[1], door_turf, "a locker on the door's own side puts the cell there")
	TEST_ASSERT_EQUAL(doorway?[2], north_side, "and the tile past the edge outside")

	// Somewhere nobody can stand is no doorway: the first version sent prisoners onto the locker itself.
	var/obj/structure/closet/crate = allocate(/obj/structure/closet, north_side)
	TEST_ASSERT_NULL(sp_cell_doorway(timer), "a doorway with something solid in it is not one")
	qdel(crate)

/// A closed closet is empty until somebody opens it, which is why the locker search cannot trust its contents.
/datum/unit_test/sp_closed_closet_is_empty

/datum/unit_test/sp_closed_closet_is_empty/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/obj/structure/closet/secure_closet/security/sec/locker = allocate(/obj/structure/closet/secure_closet/security/sec, spot)
	TEST_ASSERT(!locker.contents_initialized, "a closet nobody has opened has not populated itself")
	TEST_ASSERT(!length(locker.get_all_contents_type(/obj/item/storage/belt/security)), "so looking inside finds nothing at all, belt or otherwise")

	// Opening is what fills it. sp_find_arm_locker leans on this: it may only trust an opened closet's
	// contents, because an unopened one looks bare whether or not the kit is really in there.
	locker.dump_contents()
	TEST_ASSERT(locker.contents_initialized, "opening it is what populates it")
	TEST_ASSERT(length(spot.get_all_contents_type(/obj/item/storage/belt/security)), "and the belt was in there all along")

// --- Conversation (dialogue plan M0) --------------------------------------------------------------

/// Whether a crew member owes someone an answer, or a look up.
/proc/sp_test_owes_answer(datum/ai_controller/sp_crew/ai)
	return ai.blackboard_key_exists(BB_SP_CHAT_REPLY_DUE) || ai.blackboard_key_exists(BB_SP_ATTENTION_TARGET) || ai.blackboard_key_exists(BB_SP_THREAD)

/// Who a crew member is answering: somebody owed a line, somebody they looked up at, or their partner in a thread.
/proc/sp_test_answering(datum/ai_controller/sp_crew/ai)
	var/datum/sp_dialogue_thread/thread = ai.blackboard[BB_SP_THREAD]
	if(!isnull(thread))
		return sp_dialogue_other(thread, ai.pawn)
	return ai.blackboard[BB_SP_CHAT_REPLY_DUE] || ai.blackboard[BB_SP_ATTENTION_TARGET]

/// Lets a crew member be spoken to afresh. A test runs inside one tick, where "this same line" (free_to_talk())
/// would otherwise cover every line said in it.
/proc/sp_test_hush(datum/ai_controller/sp_crew/ai)
	ai.forget_conversation()
	ai.clear_blackboard_key(BB_SP_GREET_COOLDOWN)

/// A compiled behaviour tree, as nested lists.
/proc/sp_test_tree(json_path)
	var/static/list/trees = list()
	if(!(json_path in trees))
		trees[json_path] = json_decode(file2text(BT_COMPILED_PATH(json_path)))
	return trees[json_path]

/// Whether a node of type `wanted` can be reached in a compiled tree, following subtrees into their own trees,
/// along a path through no node of type `not_under`.
/proc/sp_test_tree_has(list/node, wanted, not_under)
	if(!islist(node))
		return FALSE
	var/node_type = text2path(node["type"])
	if(ispath(node_type, wanted))
		return TRUE
	if(not_under && ispath(node_type, not_under))
		return FALSE
	if(ispath(node_type, /datum/bt_node/subtree))
		var/datum/bt_node/subtree/subtree = node_type
		return sp_test_tree_has(sp_test_tree(initial(subtree.behavior_tree_json)), wanted, not_under)
	var/list/children = node["children"]
	if(!islist(children))
		return FALSE
	for(var/list/child in children)
		if(sp_test_tree_has(child, wanted, not_under))
			return TRUE
	return FALSE

/**
 * Every crew member can be answered, looks up at their name and starts chats, and a newcomer's hello never waits
 * on the chat cooldown. Base crew had no chat at all, security answered nobody, and greetings shared a cooldown
 * with failed partner searches.
 */
/datum/unit_test/sp_trees_talk

/datum/unit_test/sp_trees_talk/Run()
	for(var/controller_type in typesof(/datum/ai_controller/sp_crew))
		var/datum/ai_controller/sp_crew/controller = controller_type
		var/list/tree = sp_test_tree(initial(controller.behavior_tree_json))
		TEST_ASSERT(sp_test_tree_has(tree, /datum/bt_node/subtree/sp_crew_respond), "[controller_type] never answers anybody")
		TEST_ASSERT(sp_test_tree_has(tree, /datum/bt_node/subtree/sp_crew_social), "[controller_type] never looks up at their name")
		TEST_ASSERT(sp_test_tree_has(tree, /datum/bt_node/subtree/sp_crew_chatter), "[controller_type] never starts a chat")
	var/list/chatter = sp_test_tree("code/modules/spacestation_sp/ai/sp_crew_chatter.bt.json")
	TEST_ASSERT(sp_test_tree_has(chatter, /datum/bt_node/ai_behavior/sp_greet_newcomer, /datum/bt_node/decorator/cooldown), "greeting a newcomer waits on a cooldown")

/// Speech is read in whole words: "hey" is not in "they", "Tom" is not in "tomorrow", and a bare "hi" is a greeting.
/datum/unit_test/sp_speech_whole_words

/datum/unit_test/sp_speech_whole_words/Run()
	TEST_ASSERT_EQUAL(sp_speech_intent(sp_words("hi")), SP_INTENT_GREETING, "a bare hi is a greeting")
	TEST_ASSERT_EQUAL(sp_speech_intent(sp_words("Hey!")), SP_INTENT_GREETING, "and so is hey")
	TEST_ASSERT_NULL(sp_speech_intent(sp_words("They went that way.")), "they is not hey")
	TEST_ASSERT_NULL(sp_speech_intent(sp_words("This is it.")), "this is not hi")
	TEST_ASSERT_EQUAL(sp_speech_intent(sp_words("Don&#39;t, you idiot")), SP_INTENT_INSULT, "an escaped apostrophe breaks words like any other mark")
	TEST_ASSERT_EQUAL(sp_speech_intent(sp_words("Hi, can you follow me?")), SP_INTENT_FOLLOW, "the most specific request wins")
	TEST_ASSERT_EQUAL(sp_speech_intent(sp_words("Where do you work?")), SP_INTENT_WHERE_WORK, "asked where they work")
	TEST_ASSERT_EQUAL(sp_speech_intent(sp_words("Where is the bar?")), SP_INTENT_WHERE, "asked the way")

	var/mob/living/carbon/human/tom = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	tom.real_name = "Tom Hartley"
	TEST_ASSERT(sp_named(sp_words("Tom, over here"), tom), "a first name addresses its owner")
	TEST_ASSERT(sp_named(sp_words("Is that Tom&#39;s coat?"), tom), "so does its possessive")
	TEST_ASSERT(!sp_named(sp_words("See you tomorrow"), tom), "tomorrow is not Tom")
	TEST_ASSERT(!sp_named(sp_words("Atom"), tom), "nor is atom")

/// A player's call for help is urgent or violent, and a calm request is neither.
/datum/unit_test/sp_distress_needs_urgency

/datum/unit_test/sp_distress_needs_urgency/Run()
	var/list/calls = list(
		"help",
		"HELP",
		"Help me.",
		"Someone help",
		"Security!",
		"Call security",
		"Security, there&#39;s a man with a knife",
		"He&#39;s attacking me",
		"I&#39;ve been stabbed",
		"Can you help me? He&#39;s trying to kill me",
	)
	for(var/line in calls)
		TEST_ASSERT(sp_message_is_distress(line), "'[line]' should be a call for help")
	var/list/not_calls = list(
		"Can you help",
		"Could you help me find the bar?",
		"Thanks for the help",
		"That&#39;s helpful",
		"I&#39;ll help you",
		"Is security around?",
		"Hello",
		"The patient is stable",
		"I feel helpless",
	)
	for(var/line in not_calls)
		TEST_ASSERT(!sp_message_is_distress(line), "'[line]' should not be a call for help")

/// Standing moves once for each line answered, a name on its own gets a look up, and a late answer is dropped.
/datum/unit_test/sp_answer_once

/datum/unit_test/sp_answer_once/Run()
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	crew.real_name = "Kaleb Siegrist"
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_say_reply/reply = new

	crew_ai.consider_conversation(player, "Thanks.")
	TEST_ASSERT_EQUAL(crew_ai.blackboard[BB_SP_CHAT_REPLY_DUE], player, "thanks wants an answer")
	TEST_ASSERT_EQUAL(sp_reputation(crew_ai, player), 0, "deciding to answer moves nothing")
	TEST_ASSERT(reply.perform(1, crew_ai) & AI_BEHAVIOR_SUCCEEDED, "the answer is given")
	TEST_ASSERT_EQUAL(sp_reputation(crew_ai, player), 2, "and the thanks counts once")
	TEST_ASSERT(!sp_test_owes_answer(crew_ai), "with nothing left owing")

	sp_test_hush(crew_ai)
	crew_ai.consider_conversation(player, "Kaleb?")
	TEST_ASSERT_EQUAL(crew_ai.blackboard[BB_SP_ATTENTION_TARGET], player, "a name on its own gets a look up")
	TEST_ASSERT(!crew_ai.blackboard_key_exists(BB_SP_CHAT_REPLY_DUE), "rather than an answer to nothing")

	sp_test_hush(crew_ai)
	crew_ai.consider_conversation(player, "How are you?")
	crew_ai.set_blackboard_key(BB_SP_CHAT_ASKED_AT, world.time - SP_REPLY_STALE - 1)
	TEST_ASSERT(reply.perform(1, crew_ai) & AI_BEHAVIOR_FAILED, "an answer this late is not given")
	TEST_ASSERT(!sp_test_owes_answer(crew_ai), "and is forgotten")
	TEST_ASSERT_EQUAL(sp_reputation(crew_ai, player), 2, "without moving standing")
	qdel(reply)
	qdel(crew_ai)

/// Two crew hold a written conversation end to end: it starts, runs line by line, and lets both of them go.
/datum/unit_test/sp_crew_exchange

/datum/unit_test/sp_crew_exchange/Run()
	var/mob/living/carbon/human/opener = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/listener = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	opener.real_name = "Ada Quill"
	listener.real_name = "Bram Tully"
	var/datum/ai_controller/sp_crew/opener_ai = new(opener)
	opener_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/listener_ai = new(listener)
	listener_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_start_chat/start = new
	var/datum/bt_node/ai_behavior/sp_run_dialogue/run = new

	TEST_ASSERT(start.perform(1, opener_ai) & AI_BEHAVIOR_SUCCEEDED, "a free crew member alongside is someone to talk to")
	var/datum/sp_dialogue_thread/thread = opener_ai.blackboard[BB_SP_THREAD]
	TEST_ASSERT_NOTNULL(thread, "and a conversation starts")
	TEST_ASSERT_EQUAL(listener_ai.blackboard[BB_SP_IN_THREAD], thread, "with the other one in it")
	TEST_ASSERT(!listener_ai.free_to_talk(opener), "who is not free for anybody else meanwhile")
	var/turns = 0
	while(opener_ai.blackboard_key_exists(BB_SP_THREAD) && turns < 30)
		var/datum/sp_dialogue_thread/running = opener_ai.blackboard[BB_SP_THREAD]
		running.next_due = world.time // no waiting between lines in a test
		run.perform(1, opener_ai)
		turns++
	TEST_ASSERT(!opener_ai.blackboard_key_exists(BB_SP_THREAD), "the conversation came to an end")
	TEST_ASSERT(!listener_ai.blackboard_key_exists(BB_SP_IN_THREAD), "and let the other one go")
	TEST_ASSERT(!opener_ai.blackboard_key_exists(BB_SP_CHAT_PARTNER), "leaving nobody holding a partner")
	TEST_ASSERT(!sp_in_any_thread(opener) && !sp_in_any_thread(listener), "or counted as mid-conversation")

	// Whoever speaks to them next is answered for what they said.
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, NORTH))
	sp_test_hush(listener_ai)
	listener_ai.consider_conversation(player, "Bram, who are you?")
	TEST_ASSERT_EQUAL(sp_test_answering(listener_ai), player, "a player is answered after a conversation")
	qdel(start)
	qdel(run)
	qdel(opener_ai)
	qdel(listener_ai)

/// A line naming nobody gets one answer, from the nearest crew member free to give it; a line naming someone else
/// is left to them.
/datum/unit_test/sp_one_answer_per_line

/datum/unit_test/sp_one_answer_per_line/Run()
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/near = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	var/mob/living/carbon/human/far = allocate(/mob/living/carbon/human/consistent, run_loc_floor_top_right)
	near.real_name = "Nell Ashby"
	far.real_name = "Fitz Moreau"
	TEST_ASSERT(get_dist(far, player) > get_dist(near, player), "the test room is too small to tell near from far")
	var/datum/ai_controller/sp_crew/near_ai = new(near)
	near_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/far_ai = new(far)
	far_ai.set_ai_status(AI_STATUS_OFF)

	// Whichever of them hears it first, only the nearer one answers.
	near_ai.consider_conversation(player, "Hello")
	far_ai.consider_conversation(player, "Hello")
	TEST_ASSERT_EQUAL(sp_test_answering(near_ai), player, "the nearest crew member answers a hello")
	TEST_ASSERT(!sp_test_owes_answer(far_ai), "and nobody else does")
	sp_test_hush(near_ai)
	sp_test_hush(far_ai)
	far_ai.consider_conversation(player, "Hello")
	near_ai.consider_conversation(player, "Hello")
	TEST_ASSERT_EQUAL(sp_test_answering(near_ai), player, "the nearest answers, whoever heard it first")
	TEST_ASSERT(!sp_test_owes_answer(far_ai), "and the other leaves it to them")

	// Named, the line is theirs however far away they are.
	sp_test_hush(near_ai)
	sp_test_hush(far_ai)
	near_ai.consider_conversation(player, "Hello Fitz")
	far_ai.consider_conversation(player, "Hello Fitz")
	TEST_ASSERT(!sp_test_owes_answer(near_ai), "a hello for somebody else is not answered")
	TEST_ASSERT_EQUAL(sp_test_answering(far_ai), player, "the one it was for answers")

	// The nearest already owes somebody else an answer, so it falls to the next.
	sp_test_hush(near_ai)
	sp_test_hush(far_ai)
	near_ai.set_blackboard_key(BB_SP_CHAT_REPLY_DUE, far)
	near_ai.consider_conversation(player, "Hello")
	far_ai.consider_conversation(player, "Hello")
	TEST_ASSERT_EQUAL(near_ai.blackboard[BB_SP_CHAT_REPLY_DUE], far, "a crew member owing an answer does not take on another")
	TEST_ASSERT_EQUAL(sp_test_answering(far_ai), player, "so the next nearest answers")
	qdel(near_ai)
	qdel(far_ai)

/// Officers answer people when they are free, and not in the middle of an arrest.
/datum/unit_test/sp_security_answers

/datum/unit_test/sp_security_answers/Run()
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	officer.real_name = "Mara Voss"
	var/datum/ai_controller/sp_crew/security/officer_ai = new(officer)
	officer_ai.set_ai_status(AI_STATUS_OFF)
	officer_ai.clear_blackboard_key(BB_SP_ARM_ORDER) // fetching missing kit is work too; this officer has theirs

	officer_ai.set_blackboard_key(BB_SP_INCIDENT_TARGET, player)
	officer_ai.consider_conversation(player, "Mara, where do you work?")
	TEST_ASSERT(!sp_test_owes_answer(officer_ai), "an officer in the middle of an arrest does not stop to chat")
	officer_ai.clear_blackboard_key(BB_SP_INCIDENT_TARGET)
	officer_ai.consider_conversation(player, "Mara, where do you work?")
	TEST_ASSERT_EQUAL(officer_ai.blackboard[BB_SP_CHAT_REPLY_DUE], player, "a free officer answers")
	qdel(officer_ai)

// --- Security, the rungs that had no test of their own --------------------------------------------

/**
 * The one move that puts a prisoner in a cell: the officer swaps out past them, or drags them the last step
 * when they are lying down and there is nothing to swap with. An escort under way also holds its branch
 * against a fresh report, which used to swap the target out from under the officer mid-walk.
 */
/datum/unit_test/sp_cell_swap_puts_them_in

/datum/unit_test/sp_cell_swap_puts_them_in/Run()
	var/turf/outside = run_loc_floor_bottom_left
	var/turf/inside = get_step(outside, NORTH)
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, inside)
	var/mob/living/carbon/human/prisoner = allocate(/mob/living/carbon/human/consistent, outside)
	prisoner.set_handcuffed(new /obj/item/restraints/handcuffs(prisoner))
	prisoner.update_handcuffed()
	TEST_ASSERT(HAS_TRAIT(prisoner, TRAIT_RESTRAINED), "the prisoner is cuffed")
	TEST_ASSERT(officer.start_pulling(prisoner, supress_message = TRUE), "and the officer has hold of them")

	TEST_ASSERT(sp_swap_into_cell(officer, prisoner, inside, outside), "standing, the pair swap places")
	TEST_ASSERT_EQUAL(get_turf(prisoner), inside, "which leaves the prisoner inside")
	TEST_ASSERT_EQUAL(get_turf(officer), outside, "and the officer outside, where timer_start() shuts the door between them")

	// Lying down they are not dense, so there is nothing to swap with: they are dragged the last step instead.
	officer.forceMove(inside)
	prisoner.forceMove(outside)
	prisoner.Knockdown(10 SECONDS)
	TEST_ASSERT(!prisoner.density, "a mob lying down is not dense")
	TEST_ASSERT(officer.start_pulling(prisoner, supress_message = TRUE), "the officer still has hold of them")
	TEST_ASSERT(sp_swap_into_cell(officer, prisoner, inside, outside), "lying down, they are dragged in")
	TEST_ASSERT_EQUAL(get_turf(prisoner), inside, "the prisoner ends up inside either way")
	TEST_ASSERT_EQUAL(get_turf(officer), outside, "and the officer outside either way")

	var/datum/ai_controller/sp_crew/security/officer_ai = new(officer)
	officer_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/decorator/sp_target_secured/secured = new
	officer_ai.set_blackboard_key(BB_SP_PRISONER, prisoner)
	officer_ai.set_blackboard_key(BB_SP_INCIDENT_TARGET, officer) // a fresh report, naming somebody unrestrained
	TEST_ASSERT(secured.check_condition(officer_ai), "an escort under way is not interrupted by a new report")
	qdel(secured)
	qdel(officer_ai)

/// A baton comes out of the belt switched off, and an inactive one is a club: the hit falls through to brute.
/datum/unit_test/sp_baton_switched_on

/datum/unit_test/sp_baton_switched_on/Run()
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/obj/item/storage/belt/security/full/belt = new(officer)
	TEST_ASSERT_NOTNULL(belt, "the officer carries a security belt")
	var/obj/item/melee/baton/security/baton = locate() in officer.get_all_contents_type(/obj/item/melee/baton/security)
	TEST_ASSERT_NOTNULL(baton, "with a baton in it")
	TEST_ASSERT(!baton.active, "which starts switched off")
	TEST_ASSERT_NOTNULL(baton.cell, "and loaded")

	var/datum/ai_controller/sp_crew/security/officer_ai = new(officer)
	officer_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_equip_item/baton/draw = new
	TEST_ASSERT(draw.perform(1, officer_ai) & AI_BEHAVIOR_SUCCEEDED, "the officer draws it")
	TEST_ASSERT_EQUAL(officer.get_active_held_item(), baton, "into their hand")
	TEST_ASSERT(baton.active, "switched on, so an arrest is a stun rather than a beating")
	qdel(draw)
	qdel(officer_ai)

/// Lethal force is for threats, not for a smashed light tube: a petty arrest stays on stun at any alert level.
/datum/unit_test/sp_petty_arrest_stays_nonlethal

/datum/unit_test/sp_petty_arrest_stays_nonlethal/Run()
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/suspect = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/gun/energy/e_gun/gun = allocate(/obj/item/gun/energy/e_gun, run_loc_floor_bottom_left)
	officer.put_in_active_hand(gun)
	TEST_ASSERT(length(gun.ammo_type) >= 2, "the gun has both a stun and a lethal setting")
	var/datum/ai_controller/sp_crew/security/officer_ai = new(officer)
	officer_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_set_fire_mode/fire_mode = new

	officer_ai.set_blackboard_key(BB_SP_INCIDENT_TARGET, suspect)
	officer_ai.set_blackboard_key(BB_SP_USE_LETHALS, TRUE)
	fire_mode.perform(1, officer_ai)
	TEST_ASSERT(sp_casing_is_lethal(gun.ammo_type[gun.select]), "under standing orders the gun is set to kill")

	officer_ai.set_blackboard_key(BB_SP_ARREST_NONLETHAL, suspect)
	fire_mode.perform(1, officer_ai)
	TEST_ASSERT(!sp_casing_is_lethal(gun.ammo_type[gun.select]), "but not at somebody being arrested for petty crime")
	qdel(fire_mode)
	qdel(officer_ai)

/// Somewhere to draw a kit from has to be somewhere this officer can actually open.
/datum/unit_test/sp_arm_locker_usable

/datum/unit_test/sp_arm_locker_usable/Run()
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/obj/structure/closet/secure_closet/security/sec/locker = allocate(/obj/structure/closet/secure_closet/security/sec, get_step(run_loc_floor_bottom_left, EAST))
	TEST_ASSERT(locker.locked, "a security locker starts locked")
	TEST_ASSERT(!sp_arm_locker_usable(locker, officer), "and an officer with no ID on them cannot open it")
	locker.locked = FALSE
	TEST_ASSERT(sp_arm_locker_usable(locker, officer), "unlocked, it is somewhere to draw from")
	locker.welded = TRUE
	TEST_ASSERT(!sp_arm_locker_usable(locker, officer), "welded shut, it is not")
	locker.welded = FALSE
	TEST_ASSERT(!sp_arm_locker_usable(null, officer), "and neither is a locker that is not there")

/**
 * An order is acted on once per listener. Before this, every word from the head of security for five seconds
 * after an order was swallowed as that order, attacks they reported included.
 */
/datum/unit_test/sp_order_acted_on_once

/datum/unit_test/sp_order_acted_on_once/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/boss = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/security/hos/boss_ai = new(boss)
	boss_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/security/officer_ai = new(officer)
	officer_ai.set_ai_status(AI_STATUS_OFF)

	// Written the way sp_issue_order() writes it, without the speech: the order rides alongside the line, and
	// the listener reads it off the issuer's blackboard as they hear them speak.
	boss_ai.override_blackboard_key(BB_SP_LAST_ORDER, list(
		SP_ORDER_KIND = SP_ORDER_LETHAL,
		SP_ORDER_TIME = world.time,
		SP_ORDER_ISSUER = WEAKREF(boss),
	))
	officer_ai.on_pre_hear(officer, list(boss, null, "Lethal force is authorised.", null))
	TEST_ASSERT(officer_ai.blackboard[BB_SP_USE_LETHALS], "the order is taken the first time it is heard")

	officer_ai.clear_blackboard_key(BB_SP_USE_LETHALS)
	officer_ai.on_pre_hear(officer, list(boss, null, "Two of them, heading for the bar.", null))
	TEST_ASSERT_NULL(officer_ai.blackboard[BB_SP_USE_LETHALS], "and not again from the next thing they say")
	qdel(boss_ai)
	qdel(officer_ai)

// --- The janitor ----------------------------------------------------------------------------------

/// A mop lying on a floor is one to pick up; a mop somebody else is holding is not.
/datum/unit_test/sp_janitor_finds_a_mop

/datum/unit_test/sp_janitor_finds_a_mop/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/janitor = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/somebody = allocate(/mob/living/carbon/human/consistent, get_step(spot, NORTH))
	var/obj/item/mop/carried = allocate(/obj/item/mop, spot)
	somebody.put_in_hands(carried)
	var/datum/ai_controller/sp_crew/janitor/janitor_ai = new(janitor)
	janitor_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_find_mop/find = new

	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_FAILED, "a mop in somebody else's hands is not lying about")
	var/obj/item/mop/loose = allocate(/obj/item/mop, get_step(spot, EAST))
	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_SUCCEEDED, "one on the floor is")
	TEST_ASSERT_EQUAL(janitor_ai.blackboard[BB_SP_MOP], loose, "and it is the one they set off for")

	var/datum/bt_node/ai_behavior/sp_take_mop/take = new
	janitor.forceMove(get_turf(loose))
	TEST_ASSERT(take.perform(1, janitor_ai) & AI_BEHAVIOR_SUCCEEDED, "they pick it up")
	TEST_ASSERT_EQUAL(sp_carried_mop(janitor), loose, "and are carrying it")
	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_FAILED, "a janitor with a mop does not want another")
	qdel(find)
	qdel(take)
	qdel(janitor_ai)

/// A dry mop cleans nothing, so it is filled first: at a bucket, a cart or a sink.
/datum/unit_test/sp_janitor_keeps_the_mop_wet

/datum/unit_test/sp_janitor_keeps_the_mop_wet/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/janitor = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/mop/mop = allocate(/obj/item/mop, spot)
	janitor.put_in_hands(mop)
	var/obj/structure/mop_bucket/bucket = allocate(/obj/structure/mop_bucket, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/janitor/janitor_ai = new(janitor)
	janitor_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/decorator/sp_needs_supplies/needs = new

	TEST_ASSERT(!sp_mop_is_wet(mop), "a mop starts dry")
	TEST_ASSERT(needs.check_condition(janitor_ai), "which is something the janitor needs to see to")
	var/datum/bt_node/ai_behavior/sp_find_water/find = new
	// Every bucket and cart on the map starts the round empty, the janitor's own cart included.
	TEST_ASSERT(!sp_holds_water(bucket), "a bucket starts dry")
	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_FAILED, "and an empty bucket is not worth the walk")
	bucket.reagents.add_reagent(/datum/reagent/water, 60)
	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_SUCCEEDED, "a filled one is")
	TEST_ASSERT_EQUAL(janitor_ai.blackboard[BB_SP_WATER], bucket, "the bucket beside them")

	var/datum/bt_node/ai_behavior/sp_wet_mop/wet = new
	wet.owning_controller = janitor_ai
	wet.perform(1, janitor_ai)
	sleep(3 SECONDS)
	TEST_ASSERT(sp_mop_is_wet(mop), "and after dipping it, the mop is wet")
	TEST_ASSERT(!needs.check_condition(janitor_ai), "so there is nothing left to fetch")
	qdel(needs)
	qdel(find)
	qdel(wet)
	qdel(janitor_ai)

/// The nearest mess wins, except in maintenance, which waits: the crew see the hallways.
/datum/unit_test/sp_janitor_leaves_maintenance_for_last

/datum/unit_test/sp_janitor_leaves_maintenance_for_last/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/janitor = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/mop/mop = allocate(/obj/item/mop, spot)
	janitor.put_in_hands(mop)
	mop.reagents.add_reagent(/datum/reagent/water, 10)
	var/datum/ai_controller/sp_crew/janitor/janitor_ai = new(janitor)
	janitor_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_find_mess/find = new

	var/turf/near_turf = get_step(spot, EAST)
	var/turf/far_turf = get_step(near_turf, EAST)
	var/obj/effect/decal/cleanable/dirt/nearby = allocate(/obj/effect/decal/cleanable/dirt, near_turf)
	var/obj/effect/decal/cleanable/dirt/further = allocate(/obj/effect/decal/cleanable/dirt, far_turf)
	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_SUCCEEDED, "there is a mess to clean")
	TEST_ASSERT_EQUAL(janitor_ai.blackboard[BB_SP_MESS], nearby, "and the nearest one is taken first")

	// Put the near one in maintenance, and the further one wins instead.
	var/area/station/maintenance/aft/tunnel = new
	tunnel.contents += near_turf
	TEST_ASSERT_EQUAL(get_area(nearby), tunnel, "the test moved the tile into maintenance")
	TEST_ASSERT(sp_mess_priority(nearby, janitor) > sp_mess_priority(further, janitor), "maintenance goes to the back of the queue")
	find.perform(1, janitor_ai)
	TEST_ASSERT_EQUAL(janitor_ai.blackboard[BB_SP_MESS], further, "so the hallway is cleaned first")
	qdel(find)
	qdel(janitor_ai)

/// Mopping actually removes the mess, through TG's own cleaning.
/datum/unit_test/sp_janitor_mops_it_up

/datum/unit_test/sp_janitor_mops_it_up/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/janitor = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/mop/mop = allocate(/obj/item/mop, spot)
	janitor.put_in_hands(mop)
	mop.reagents.add_reagent(/datum/reagent/water, 10)
	var/obj/effect/decal/cleanable/dirt/mess = allocate(/obj/effect/decal/cleanable/dirt, spot)
	var/datum/ai_controller/sp_crew/janitor/janitor_ai = new(janitor)
	janitor_ai.set_ai_status(AI_STATUS_OFF)
	janitor_ai.set_blackboard_key(BB_SP_MESS, mess)

	var/datum/bt_node/ai_behavior/sp_mop_mess/mopping = new
	mopping.owning_controller = janitor_ai
	mopping.perform(1, janitor_ai)
	sleep(4 SECONDS)
	TEST_ASSERT(QDELETED(mess), "the mess is mopped up")
	TEST_ASSERT(!janitor_ai.blackboard_key_exists(BB_SP_MESS), "and forgotten about")
	qdel(mopping)
	qdel(janitor_ai)

/// A banana peel is picked up rather than mopped, which is what the clown leaves behind.
/datum/unit_test/sp_janitor_picks_up_a_peel

/datum/unit_test/sp_janitor_picks_up_a_peel/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/janitor = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/grown/bananapeel/peel = allocate(/obj/item/grown/bananapeel, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/janitor/janitor_ai = new(janitor)
	janitor_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_find_litter/find = new

	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_SUCCEEDED, "a peel on the floor is litter")
	TEST_ASSERT_EQUAL(janitor_ai.blackboard[BB_SP_LITTER], peel, "and it is what they set off for")
	var/datum/bt_node/ai_behavior/sp_take_litter/take = new
	janitor.forceMove(get_turf(peel))
	TEST_ASSERT(take.perform(1, janitor_ai) & AI_BEHAVIOR_SUCCEEDED, "they pick it up")
	TEST_ASSERT(!isturf(peel.loc), "so nobody slips on it")
	qdel(find)
	qdel(take)
	qdel(janitor_ai)

// --- The clown ------------------------------------------------------------------------------------

/// A peel goes down in the hallways, not in medbay: somebody going over on the way to a patient is not a joke.
/datum/unit_test/sp_clown_peels_in_public

/datum/unit_test/sp_clown_peels_in_public/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/area/station/hallway/primary/central/hallway = new
	hallway.contents += spot
	TEST_ASSERT(sp_clown_prank_spot(spot), "a hallway is somewhere to leave a peel")
	var/area/station/medical/medbay/central/ward = new
	ward.contents += spot
	TEST_ASSERT(!sp_clown_prank_spot(spot), "medbay is not")

/// The banana becomes a peel on the floor, which is the whole point of the banana.
/datum/unit_test/sp_clown_drops_a_peel

/datum/unit_test/sp_clown_drops_a_peel/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/area/station/hallway/primary/central/hallway = new
	hallway.contents += spot
	var/mob/living/carbon/human/clown = allocate(/mob/living/carbon/human/consistent, spot)
	var/datum/ai_controller/sp_crew/clown/clown_ai = new(clown)
	clown_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_clown_peel/prank = new

	TEST_ASSERT(prank.perform(1, clown_ai) & AI_BEHAVIOR_FAILED, "a clown with no banana has nothing to drop")
	var/obj/item/food/grown/banana/banana = new(clown)
	TEST_ASSERT_EQUAL(sp_carried_banana(clown), banana, "the clown is carrying a banana")
	TEST_ASSERT(prank.perform(1, clown_ai) & AI_BEHAVIOR_SUCCEEDED, "and leaves the skin behind")
	TEST_ASSERT(QDELETED(banana), "the banana is gone")
	var/obj/item/grown/bananapeel/peel = locate() in spot
	TEST_ASSERT_NOTNULL(peel, "and a peel is on the floor where they stood")
	qdel(prank)
	qdel(clown_ai)

/// Honking wants an audience, and takes the horn out of the clown's pocket to do it.
/datum/unit_test/sp_clown_honks_at_people

/datum/unit_test/sp_clown_honks_at_people/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/clown = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/bikehorn/horn = new(clown)
	var/datum/ai_controller/sp_crew/clown/clown_ai = new(clown)
	clown_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_clown_honk/honk = new

	TEST_ASSERT(honk.perform(1, clown_ai) & AI_BEHAVIOR_FAILED, "there is no point honking at an empty corridor")
	var/mob/living/carbon/human/audience = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	TEST_ASSERT_NOTNULL(audience, "somebody walks past")
	TEST_ASSERT(honk.perform(1, clown_ai) & AI_BEHAVIOR_SUCCEEDED, "so the clown honks")
	TEST_ASSERT_EQUAL(clown.get_active_held_item(), horn, "with the horn in hand")
	qdel(honk)
	qdel(clown_ai)

/// Out of bananas, the clown asks botany, in words botany actually listens for.
/datum/unit_test/sp_clown_asks_botany

/datum/unit_test/sp_clown_asks_botany/Run()
	var/mob/living/carbon/human/clown = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/datum/ai_controller/sp_crew/clown/clown_ai = new(clown)
	clown_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/bt_node/ai_behavior/sp_clown_restock/ask = new

	TEST_ASSERT_EQUAL(sp_plant_asked_for("Botany, bananas please."), "banana", "botany takes a request for bananas")
	TEST_ASSERT(ask.perform(1, clown_ai) & AI_BEHAVIOR_SUCCEEDED, "a clown with no bananas asks for some")
	var/obj/item/food/grown/banana/banana = new(clown)
	TEST_ASSERT_NOTNULL(banana, "then somebody sends one")
	TEST_ASSERT(ask.perform(1, clown_ai) & AI_BEHAVIOR_FAILED, "and a clown who has one does not ask again")
	qdel(ask)
	qdel(clown_ai)

// --- Written dialogue -----------------------------------------------------------------------------

/// Every dialogue we ship loads and hangs together, and a broken one is refused rather than half-run.
/datum/unit_test/sp_dialogue_files_are_sound

/datum/unit_test/sp_dialogue_files_are_sound/Run()
	var/list/all = sp_all_dialogues()
	TEST_ASSERT(length(all) >= 4, "the dialogue files loaded: [length(all)] of them")
	for(var/file_name in flist(SP_DIALOGUE_PATH))
		if(!findtext(file_name, ".json"))
			continue
		var/list/problems = list()
		TEST_ASSERT_NOTNULL(sp_read_dialogue(SP_DIALOGUE_PATH + file_name, problems), "[file_name] did not load: [problems.Join("; ")]")

	// One that leads somewhere that is not there is refused, and says which node and where.
	var/path = "data/sp_dialogue_unit_test.json"
	fdel(path)
	var/list/broken = list(
		"id" = "broken",
		"roles" = list("a" = list(), "b" = list()),
		"start" = "one",
		"nodes" = list("one" = list("speaker" = "a", "lines" = list("Hello."), "next" = list(list("to" = "two")))),
	)
	text2file(json_encode(broken), path)
	var/list/problems = list()
	TEST_ASSERT_NULL(sp_read_dialogue(path, problems), "a dialogue leading nowhere is refused")
	TEST_ASSERT(length(problems), "and says what was wrong with it")
	fdel(path)

/// Roles are cast by job, whichever of the two walked over.
/datum/unit_test/sp_dialogue_casts_by_job

/datum/unit_test/sp_dialogue_casts_by_job/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/cleaner = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/passer_by = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/cleaner_ai = new(cleaner)
	cleaner_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/passer_ai = new(passer_by)
	passer_ai.set_ai_status(AI_STATUS_OFF)
	var/list/all = sp_all_dialogues()
	var/datum/sp_dialogue/wet_floor = all["janitor_wet_floor"]
	TEST_ASSERT_NOTNULL(wet_floor, "the wet floor dialogue is one of ours")
	TEST_ASSERT_NULL(sp_cast_dialogue(wet_floor, cleaner, passer_by), "with no janitor about, nobody can play it")

	cleaner.mind_initialize()
	cleaner.mind.assigned_role = SSjob.get_job_type(/datum/job/janitor)
	var/list/cast = sp_cast_dialogue(wet_floor, cleaner, passer_by)
	TEST_ASSERT_NOTNULL(cast, "with one, it can be cast")
	TEST_ASSERT_EQUAL(cast["janitor"], cleaner, "and the janitor plays the janitor")
	cast = sp_cast_dialogue(wet_floor, passer_by, cleaner)
	TEST_ASSERT_EQUAL(cast["janitor"], cleaner, "whichever of them walked over")
	qdel(cleaner_ai)
	qdel(passer_ai)

/// A thread runs line by line to an end, moves standing on the way, and is not had twice in a row.
/datum/unit_test/sp_dialogue_thread_runs

/datum/unit_test/sp_dialogue_thread_runs/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/asker = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	asker.real_name = "Ada Quill"
	other.real_name = "Bram Tully"
	var/datum/ai_controller/sp_crew/asker_ai = new(asker)
	asker_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/other_ai = new(other)
	other_ai.set_ai_status(AI_STATUS_OFF)

	// A chain built here rather than a shipped one: the written dialogues branch on the dice, so counting
	// their lines would be testing the odds. This counts the runtime.
	var/datum/sp_dialogue/chain = new
	chain.id = "unit_test_chain"
	chain.roles = list("a" = list(), "b" = list())
	chain.start = "one"
	chain.nodes = list(
		"one" = list("speaker" = "a", "lines" = list("One."), "next" = list(list("to" = "two"))),
		"two" = list("speaker" = "b", "lines" = list("Two."), "next" = list(list("to" = "three"))),
		"three" = list("speaker" = "a", "lines" = list("Three, %B_FIRST%."), "next" = list(list("to" = "four"))),
		"four" = list("speaker" = "b", "lines" = list("Four."), "next" = list(list("to" = SP_DIALOGUE_END)),
			"effects" = list(list("standing" = list("b->a" = 2)))),
	)
	var/datum/sp_dialogue_thread/chained = sp_begin_dialogue(chain, asker, other)
	TEST_ASSERT_NOTNULL(chained, "a thread starts between two crew with no job between them")
	var/turns = 0
	while(chained.advance() && turns < SP_DIALOGUE_MAX_LINES)
		turns++
	TEST_ASSERT_EQUAL(chained.lines_said, 4, "every node in the chain was said")
	TEST_ASSERT_NULL(chained.current, "and the thread reached its end")
	TEST_ASSERT_EQUAL(sp_reputation(other_ai, asker), 2, "the effect on the last node was applied")
	qdel(chained)

	var/datum/sp_dialogue/shift = sp_all_dialogues()["shift_talk"]
	TEST_ASSERT_NOTNULL(shift, "two crew with nothing in common can still talk about the shift")
	var/datum/sp_dialogue_thread/thread = sp_begin_dialogue(shift, asker, other)
	TEST_ASSERT_NOTNULL(thread, "so a thread starts")
	turns = 0
	while(thread.advance() && turns < SP_DIALOGUE_MAX_LINES)
		turns++
	// Shipped dialogue branches, so the shortest way through shift_talk is an opener and an answer.
	TEST_ASSERT(thread.lines_said >= 2, "a thread is at least a line and an answer: [thread.lines_said] said")
	TEST_ASSERT_NULL(thread.current, "and it reaches an end rather than stopping")
	sp_dialogue_remember(thread)
	TEST_ASSERT(("shift_talk" in sp_memory_recent(asker_ai, other)), "both of them remember having had it")
	TEST_ASSERT(("shift_talk" in sp_memory_recent(other_ai, asker)), "the other one too")
	for(var/i in 1 to 20)
		var/datum/sp_dialogue/again = sp_pick_dialogue(asker, other)
		TEST_ASSERT(again?.id != "shift_talk", "so it is not picked again straight afterwards")
	qdel(thread)

	// The janitor's one moves standing whichever way it branches: thanked or given cheek.
	asker.mind_initialize()
	asker.mind.assigned_role = SSjob.get_job_type(/datum/job/janitor)
	var/datum/sp_dialogue/wet_floor = sp_all_dialogues()["janitor_wet_floor"]
	var/datum/sp_dialogue_thread/second = sp_begin_dialogue(wet_floor, asker, other)
	TEST_ASSERT_NOTNULL(second, "the janitor has something to say about the floor")
	turns = 0
	while(second.advance() && turns < SP_DIALOGUE_MAX_LINES)
		turns++
	// Both of the second nodes in that dialogue move standing, so two lines said means standing moved. The
	// counts are in the messages because a thread that stops early is the interesting failure, not the sum.
	TEST_ASSERT(second.lines_said >= 2, "the janitor got an answer about the floor: [second.lines_said] lines said")
	TEST_ASSERT(sp_reputation(asker_ai, other) != 0, "and it moved what they think of them ([second.lines_said] lines said)")
	qdel(second)
	qdel(asker_ai)
	qdel(other_ai)

/**
 * A person being arrested shouting that the officer attacked them is not a crime report.
 *
 * Without this one arrest becomes a brawl: seen in a live round, where the suspect radioed it in, every
 * officer took the arresting officer for an attacker, and four of them fought each other in a hallway while
 * the suspect walked away.
 */
/datum/unit_test/sp_arrest_is_not_an_attack

/datum/unit_test/sp_arrest_is_not_an_attack/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/officer = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/colleague = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/mob/living/carbon/human/suspect = allocate(/mob/living/carbon/human/consistent, get_step(spot, NORTH))
	officer.real_name = "Margaret Beck"
	suspect.real_name = "Addison Earl"
	officer.mind_initialize()
	officer.mind.assigned_role = SSjob.get_job_type(/datum/job/security_officer)
	var/datum/ai_controller/sp_crew/security/officer_ai = new(officer)
	officer_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/security/colleague_ai = new(colleague)
	colleague_ai.set_ai_status(AI_STATUS_OFF)

	officer_ai.set_blackboard_key(BB_SP_INCIDENT_TARGET, suspect)
	TEST_ASSERT(sp_is_arresting(officer, suspect), "the officer is in the middle of arresting them")
	var/list/incident = list(
		SP_INCIDENT_ATTACKER = WEAKREF(officer),
		SP_INCIDENT_VICTIM = WEAKREF(suspect),
		SP_INCIDENT_TURF = get_turf(suspect),
		SP_INCIDENT_TIME = world.time,
	)
	colleague_ai.on_heard_incident(suspect, incident)
	TEST_ASSERT(!colleague_ai.blackboard_key_exists(BB_SP_INCIDENT_TARGET), "their colleague is not treated as an attacker")

	// Somebody else attacking the same officer still is one.
	var/mob/living/carbon/human/thug = allocate(/mob/living/carbon/human/consistent, get_step(spot, SOUTH))
	var/list/real_attack = list(
		SP_INCIDENT_ATTACKER = WEAKREF(thug),
		SP_INCIDENT_VICTIM = WEAKREF(officer),
		SP_INCIDENT_TURF = get_turf(officer),
		SP_INCIDENT_TIME = world.time,
	)
	colleague_ai.on_heard_incident(officer, real_attack)
	TEST_ASSERT_EQUAL(colleague_ai.blackboard[BB_SP_INCIDENT_TARGET], thug, "an actual attacker still gets answered")
	qdel(officer_ai)
	qdel(colleague_ai)

/// A room the janitor cannot get into is left alone as a room, not one stain at a time.
/datum/unit_test/sp_janitor_leaves_shut_rooms_alone

/datum/unit_test/sp_janitor_leaves_shut_rooms_alone/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/turf/away = get_step(get_step(spot, EAST), EAST)
	var/mob/living/carbon/human/janitor = allocate(/mob/living/carbon/human/consistent, spot)
	var/obj/item/mop/mop = allocate(/obj/item/mop, spot)
	janitor.put_in_hands(mop)
	mop.reagents.add_reagent(/datum/reagent/water, 10)
	var/datum/ai_controller/sp_crew/janitor/janitor_ai = new(janitor)
	janitor_ai.set_ai_status(AI_STATUS_OFF)

	var/area/station/engineering/atmos/shut = new
	shut.contents += away
	var/obj/effect/decal/cleanable/dirt/unreachable = allocate(/obj/effect/decal/cleanable/dirt, away)
	TEST_ASSERT_EQUAL(get_area(unreachable), shut, "the test put that tile in a room of its own")
	var/datum/bt_node/ai_behavior/sp_find_mess/find = new
	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_SUCCEEDED, "the mess is worth walking to at first")

	// The walk failed, so the room is what gets remembered.
	janitor_ai.set_blackboard_key(BB_SP_MESS, unreachable)
	var/datum/bt_node/ai_behavior/sp_mess_unreachable/give_up = new
	TEST_ASSERT(give_up.perform(1, janitor_ai) & AI_BEHAVIOR_FAILED, "giving up is a note, not a job")
	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_FAILED, "and every stain in that room is left alone")

	// A mess somewhere else is still worth doing.
	var/obj/effect/decal/cleanable/dirt/nearby = allocate(/obj/effect/decal/cleanable/dirt, get_step(spot, NORTH))
	TEST_ASSERT(find.perform(1, janitor_ai) & AI_BEHAVIOR_SUCCEEDED, "a mess in a room they can walk into is not")
	TEST_ASSERT_EQUAL(janitor_ai.blackboard[BB_SP_MESS], nearby, "and it is the one they set off for")
	qdel(find)
	qdel(give_up)
	qdel(janitor_ai)

// --- Dialogue: memory, the vocabulary, and the player's side ----------------------------------------

/// A made-up dialogue for tests, with a player in it when asked for.
/proc/sp_test_dialogue(with_player = FALSE)
	var/datum/sp_dialogue/made = new
	made.id = "unit_test_[with_player ? "player" : "crew"]"
	made.title = with_player ? "A test" : null
	made.roles = list("a" = list(), "b" = with_player ? list("player" = TRUE) : list())
	made.start = "one"
	made.nodes = list("one" = list("speaker" = "a", "lines" = list("One."), "next" = list(list("to" = SP_DIALOGUE_END))))
	return made

/// Writes a dialogue to a scratch file and reads it back, for the loader's checks.
/proc/sp_test_read(list/definition, list/problems)
	var/path = "data/sp_dialogue_unit_test.json"
	fdel(path)
	text2file(json_encode(definition), path)
	var/datum/sp_dialogue/read = sp_read_dialogue(path, problems)
	fdel(path)
	return read

/// Crew know each other and learn a player's name; facts are kept; a player is known by mind, not by body.
/datum/unit_test/sp_dialogue_memory

/datum/unit_test/sp_dialogue_memory/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/colleague = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, NORTH))
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/colleague_ai = new(colleague)
	colleague_ai.set_ai_status(AI_STATUS_OFF)
	player.mind_initialize()

	TEST_ASSERT(sp_knows_name(crew_ai, colleague), "crew know each other")
	TEST_ASSERT(!sp_knows_name(crew_ai, player), "but not a stranger")
	TEST_ASSERT(sp_learn_name(crew_ai, player), "until they are told")
	TEST_ASSERT(sp_knows_name(crew_ai, player), "after which they know")
	sp_remember_fact(crew_ai, player, "offered_help")
	TEST_ASSERT(sp_remembers(crew_ai, player, "offered_help"), "facts are kept")
	sp_forget_fact(crew_ai, player, "offered_help")
	TEST_ASSERT(!sp_remembers(crew_ai, player, "offered_help"), "and can be let go of")

	// Filed under the mind: a new body is the same person to them.
	var/mob/living/carbon/human/new_body = allocate(/mob/living/carbon/human/consistent, get_step(spot, SOUTH))
	player.mind.transfer_to(new_body)
	TEST_ASSERT(sp_knows_name(crew_ai, new_body), "a player in a new body is still somebody they know")
	qdel(crew_ai)
	qdel(colleague_ai)

/// Every condition a file can ask about answers both ways.
/datum/unit_test/sp_dialogue_conditions

/datum/unit_test/sp_dialogue_conditions/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/first_ai = new(first)
	first_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/second_ai = new(second)
	second_ai.set_ai_status(AI_STATUS_OFF)
	first.mind_initialize()
	first.mind.assigned_role = SSjob.get_job_type(/datum/job/janitor)
	var/datum/sp_dialogue_thread/thread = sp_begin_dialogue(sp_test_dialogue(), first, second)
	TEST_ASSERT_NOTNULL(thread, "two crew can be cast in the test dialogue")

	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("random" = 0)), "a nought per cent roll fails")
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("random" = 100)), "a certain one does not")
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("job" = list("a" = list("Janitor")))), "the janitor is a janitor")
	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("job" = list("a" = list("Clown")))), "and not a clown")
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("department" = list("a" = list("Service")))), "a janitor is service")
	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("department" = list("a" = list("Security")))), "not security")

	sp_adjust_reputation(first_ai, second, 5, "test")
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("standing" = list("a->b" = ">=4"))), "standing is compared")
	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("standing" = list("a->b" = "<0"))), "both ways")
	sp_remember_fact(first_ai, second, "owes_me")
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("memory" = list("a->b" = "owes_me"))), "a remembered fact holds")
	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("memory" = list("a->b" = "!owes_me"))), "and its negation does not")
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("knows_name" = list("a->b" = TRUE))), "crew know crew by name")

	var/area/station/hallway/primary/central/hallway = new
	hallway.contents += spot
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("place" = list("hallway"))), "the hallway is the hallway")
	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("place" = list("medbay"))), "and not medbay")

	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("hurt" = list("b" = FALSE))), "somebody healthy is not hurt")
	second.apply_damage(60, BRUTE)
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("hurt" = list("b" = TRUE))), "and somebody bleeding is")

	var/obj/item/mop/mop = allocate(/obj/item/mop, spot)
	first.put_in_hands(mop)
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("holding" = list("a" = "/obj/item/mop"))), "a mop in hand is held")
	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("holding" = list("b" = "/obj/item/mop"))), "and not by the other one")

	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("time_into_shift" = ">=0")), "the shift has started")
	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("time_into_shift" = "<0")), "and has not not started")

	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("recent_event" = "graffiti")), "nothing has happened yet")
	sp_station_event("graffiti", first)
	TEST_ASSERT(sp_dialogue_conditions_hold(thread, list("recent_event" = "graffiti")), "and then something has")
	TEST_ASSERT_EQUAL(thread.event?[SP_EVENT_TAG], "graffiti", "which the thread keeps, for a rumour to name")
	TEST_ASSERT(!sp_dialogue_conditions_hold(thread, list("nonsense" = TRUE)), "a condition nobody knows is false")
	qdel(thread)
	qdel(first_ai)
	qdel(second_ai)

/// Every effect a file can have does what it says, and a gift is only ever something the giver carries.
/datum/unit_test/sp_dialogue_effects

/datum/unit_test/sp_dialogue_effects/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)
	player.mind_initialize()
	var/datum/sp_dialogue_thread/thread = sp_begin_dialogue(sp_test_dialogue(with_player = TRUE), crew, player)
	TEST_ASSERT_NOTNULL(thread, "a crew member and a player can be cast")

	sp_dialogue_effect(thread, list("standing" = list("a->b" = 2)))
	TEST_ASSERT_EQUAL(sp_reputation(crew_ai, player), 2, "standing moves")
	sp_dialogue_effect(thread, list("remember" = list("a->b" = "was_kind")))
	TEST_ASSERT(sp_remembers(crew_ai, player, "was_kind"), "a fact is remembered")
	sp_dialogue_effect(thread, list("learn_name" = list("a->b" = TRUE)))
	TEST_ASSERT(sp_knows_name(crew_ai, player), "a name is learned")
	sp_dialogue_effect(thread, list("event" = "gossip"))
	TEST_ASSERT_NOTNULL(sp_recent_event("gossip"), "an event is recorded")

	sp_dialogue_effect(thread, list("give" = list("from" = "a", "to" = "b", "item" = "/obj/item/mop")))
	TEST_ASSERT(!length(player.get_all_contents_type(/obj/item/mop)), "nothing is conjured: no mop, no gift")
	var/obj/item/mop/mop = new(crew)
	sp_dialogue_effect(thread, list("give" = list("from" = "a", "to" = "b", "item" = "/obj/item/mop")))
	TEST_ASSERT(mop in player.get_all_contents_type(/obj/item/mop), "a mop the giver carries changes hands")
	qdel(thread)
	qdel(crew_ai)

/// The loader refuses what it cannot run, and says why.
/datum/unit_test/sp_dialogue_validation

/datum/unit_test/sp_dialogue_validation/Run()
	var/list/problems = list()
	var/list/nodes = list(
		"one" = list("speaker" = "a", "lines" = list("One."), "next" = list(list("to" = SP_DIALOGUE_END))),
		"island" = list("speaker" = "b", "lines" = list("Nobody gets here."), "next" = list(list("to" = SP_DIALOGUE_END))),
	)
	TEST_ASSERT_NULL(sp_test_read(list("id" = "t", "roles" = list("a" = list(), "b" = list()), "start" = "one", "nodes" = nodes), problems), "a node nothing leads to is refused")
	TEST_ASSERT(findtext(problems.Join(" "), "never be reached"), "and it says so: [problems.Join("; ")]")

	problems = list()
	nodes = list("one" = list("speaker" = "b", "timeout_to" = SP_DIALOGUE_END))
	TEST_ASSERT_NULL(sp_test_read(list("id" = "t", "title" = "T", "roles" = list("a" = list(), "b" = list("player" = TRUE)), "start" = "one", "nodes" = nodes), problems), "a player's turn with no replies is refused")

	problems = list()
	nodes = list("one" = list("speaker" = "a", "lines" = list("One."), "next" = list(list("to" = SP_DIALOGUE_END, "if" = list("moon_phase" = 3)))))
	TEST_ASSERT_NULL(sp_test_read(list("id" = "t", "roles" = list("a" = list(), "b" = list()), "start" = "one", "nodes" = nodes), problems), "a condition nobody knows is refused")

	problems = list()
	nodes = list("one" = list("speaker" = "a", "lines" = list("Hello %NOBODY_FIRST%."), "next" = list(list("to" = SP_DIALOGUE_END))))
	TEST_ASSERT_NULL(sp_test_read(list("id" = "t", "roles" = list("a" = list(), "b" = list()), "start" = "one", "nodes" = nodes), problems), "a placeholder nobody fills is refused")

	problems = list()
	nodes = list("one" = list("speaker" = "a", "lines" = list("One."), "next" = list(list("to" = SP_DIALOGUE_END))))
	TEST_ASSERT_NULL(sp_test_read(list("id" = "t", "roles" = list("a" = list(), "b" = list("player" = TRUE)), "start" = "one", "nodes" = nodes), problems), "a dialogue with a player in it needs a title to be offered by")

/// A player's turn: replies on offer, nobody else can take them, and silence goes where the file says.
/datum/unit_test/sp_player_replies

/datum/unit_test/sp_player_replies/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/sp_dialogue/asked = sp_test_dialogue(with_player = TRUE)
	asked.nodes = list(
		"one" = list("speaker" = "a", "lines" = list("Well?"), "next" = list(list("to" = "reply"))),
		"reply" = list("speaker" = "b", "options" = list(list("text" = "Yes.", "to" = "yes"), list("text" = "No.", "to" = SP_DIALOGUE_END)), "timeout_to" = "huh"),
		"yes" = list("speaker" = "a", "lines" = list("Good."), "next" = list(list("to" = SP_DIALOGUE_END))),
		"huh" = list("speaker" = "a", "lines" = list("...Right."), "next" = list(list("to" = SP_DIALOGUE_END))),
	)
	var/datum/sp_dialogue_thread/thread = sp_begin_dialogue(asked, crew, player)
	TEST_ASSERT_NOTNULL(thread, "the crew member and the player are cast")
	TEST_ASSERT(thread.advance(), "the crew member says their line")
	TEST_ASSERT(thread.advance(), "and then it is the player's turn")
	TEST_ASSERT_EQUAL(length(thread.pending_options), 2, "with both replies on offer")
	TEST_ASSERT(!thread.choose(crew, 1), "nobody else can answer for them")
	TEST_ASSERT(!thread.choose(player, 3), "and there is no third reply to pick")
	TEST_ASSERT(thread.choose(player, 1), "the player picks one")
	TEST_ASSERT_EQUAL(thread.current, "yes", "and the conversation goes where that reply leads")

	thread.current = "reply"
	TEST_ASSERT(thread.advance(), "offered again")
	thread.options_expire = world.time - 1
	TEST_ASSERT(!thread.choose(player, 1), "an offer that has lapsed is refused")
	thread.expire()
	TEST_ASSERT_EQUAL(thread.current, "huh", "and the silence goes where the file says")
	qdel(thread)
	qdel(crew_ai)

/// A stranger saying hello is introduced; somebody they know gets a hello back; saying your name teaches it.
/datum/unit_test/sp_player_speech_opens_dialogue

/datum/unit_test/sp_player_speech_opens_dialogue/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	player.real_name = "Tom Hartley"
	player.mind_initialize()
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)

	crew_ai.consider_conversation(player, "Hello")
	var/datum/sp_dialogue_thread/thread = crew_ai.blackboard[BB_SP_THREAD]
	TEST_ASSERT_EQUAL(thread?.dialogue?.id, "introductions", "a stranger saying hello gets introduced")
	sp_test_hush(crew_ai)

	crew_ai.consider_conversation(player, "I'm Tom, by the way.")
	TEST_ASSERT(sp_knows_name(crew_ai, player), "saying your name teaches it")
	sp_test_hush(crew_ai)
	crew_ai.consider_conversation(player, "Hello")
	TEST_ASSERT(!crew_ai.blackboard_key_exists(BB_SP_THREAD), "somebody they know is not introduced twice")
	TEST_ASSERT_EQUAL(crew_ai.blackboard[BB_SP_CHAT_REPLY_DUE], player, "they just get a hello back")
	qdel(crew_ai)

/// A name is read off an ID from beside somebody, and not from across a room.
/datum/unit_test/sp_id_read_up_close

/datum/unit_test/sp_id_read_up_close/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(get_step(spot, EAST), EAST))
	player.mind_initialize()
	// An ID clips to a jumpsuit, so the test dresses them first: a bare body has nowhere to wear one.
	player.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(player), ITEM_SLOT_ICLOTHING)
	var/obj/item/card/id/advanced/card = new(player)
	card.registered_name = player.real_name
	TEST_ASSERT(player.equip_to_slot_if_possible(card, ITEM_SLOT_ID), "the test put the ID on them")
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)

	TEST_ASSERT(!sp_notice_id(crew_ai, player), "an ID two tiles off cannot be read")
	player.forceMove(get_step(spot, EAST))
	TEST_ASSERT(sp_notice_id(crew_ai, player), "one right beside you can")
	TEST_ASSERT(sp_knows_name(crew_ai, player), "and then they know the name")
	qdel(crew_ai)

/// How a crew member regards you shows on examine at the extremes, and not in between.
/datum/unit_test/sp_standing_on_examine

/datum/unit_test/sp_standing_on_examine/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)

	var/list/seen = list()
	SEND_SIGNAL(crew, COMSIG_ATOM_EXAMINE, player, seen)
	TEST_ASSERT(!length(seen), "a stranger reads nothing into them")
	sp_adjust_reputation(crew_ai, player, 5, "test")
	seen = list()
	SEND_SIGNAL(crew, COMSIG_ATOM_EXAMINE, player, seen)
	TEST_ASSERT(findtext(jointext(seen, " "), "like you"), "somebody who likes you shows it")
	sp_adjust_reputation(crew_ai, player, -12, "test")
	seen = list()
	SEND_SIGNAL(crew, COMSIG_ATOM_EXAMINE, player, seen)
	TEST_ASSERT(findtext(jointext(seen, " "), "wary"), "and somebody who does not shows that")
	qdel(crew_ai)

/// The Talk to list offers what fits the two of you now, and nothing that does not.
/datum/unit_test/sp_talk_offers_what_fits

/datum/unit_test/sp_talk_offers_what_fits/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	player.mind_initialize()
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)

	var/list/choices = sp_dialogues_for_talk(crew, player)
	TEST_ASSERT(("Introduce yourself" in choices), "a stranger can introduce themselves")
	TEST_ASSERT(("Ask what they do" in choices), "and ask what they do")
	sp_learn_name(crew_ai, player)
	choices = sp_dialogues_for_talk(crew, player)
	TEST_ASSERT(!("Introduce yourself" in choices), "but not introduce themselves twice")
	TEST_ASSERT(!length(sp_dialogues_for_talk(crew, crew)), "and nobody talks to themselves")
	qdel(crew_ai)

/// The seven keyword topics are dialogue files now, alongside the rest.
/datum/unit_test/sp_topics_are_files

/datum/unit_test/sp_topics_are_files/Run()
	var/list/all = sp_all_dialogues()
	for(var/id in list("shift_talk", "food_talk", "gossip_talk", "engineering_talk", "medical_talk", "security_quiet", "botany_talk"))
		TEST_ASSERT(!isnull(all[id]), "the [id] topic is a dialogue file")

/**
 * A reply link leads back to its conversation, and a click only counts from the player it was offered to:
 * the whole of what happens server-side when a player clicks one, from the link's own text.
 */
/datum/unit_test/sp_reply_link_round_trip

/datum/unit_test/sp_reply_link_round_trip/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)
	TEST_ASSERT(!sp_is_playing(player), "a body with no client is nobody's player")
	ADD_TRAIT(player, TRAIT_SP_STAND_IN, SP_TRAIT_SOURCE)
	TEST_ASSERT(sp_is_playing(player), "until the stand-in takes their place")

	var/datum/sp_dialogue/asked = sp_test_dialogue(with_player = TRUE)
	asked.nodes = list(
		"one" = list("speaker" = "a", "lines" = list("Well?"), "next" = list(list("to" = "reply"))),
		"reply" = list("speaker" = "b", "options" = list(list("text" = "Yes.", "to" = "yes"), list("text" = "No.", "to" = SP_DIALOGUE_END))),
		"yes" = list("speaker" = "a", "lines" = list("Good."), "next" = list(list("to" = SP_DIALOGUE_END))),
	)
	var/datum/sp_dialogue_thread/thread = sp_begin_dialogue(asked, crew, player)
	thread.advance()
	thread.advance()
	var/list/links = sp_stand_in_links(sp_dialogue_offer_html(thread, player))
	TEST_ASSERT_EQUAL(length(links), 2, "both replies are links")
	var/list/first = links[1]
	TEST_ASSERT_EQUAL(first[2], "Yes.", "labelled with what the player will say")
	var/list/params = params2list(first[1])
	var/datum/target = locate(params["src"])
	TEST_ASSERT_EQUAL(target, thread, "a link leads back to the conversation it belongs to")
	usr = crew
	target.Topic(first[1], params)
	TEST_ASSERT_EQUAL(thread.current, "reply", "a click from anybody else is not taken")
	usr = player
	target.Topic(first[1], params)
	TEST_ASSERT_EQUAL(thread.current, "yes", "a click from the player is")
	qdel(thread)
	qdel(crew_ai)

/// Somebody busy with work says so when a player names them, and carries on with the job.
/datum/unit_test/sp_busy_crew_say_so

/datum/unit_test/sp_busy_crew_say_so/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/doctor = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, get_step(spot, NORTH))
	doctor.real_name = "Kaleb Siegrist"
	ADD_TRAIT(player, TRAIT_SP_STAND_IN, SP_TRAIT_SOURCE)
	var/datum/ai_controller/sp_crew/medical/doctor_ai = new(doctor)
	doctor_ai.set_ai_status(AI_STATUS_OFF)
	doctor_ai.set_blackboard_key(BB_SP_PATIENT, patient)

	doctor_ai.consider_conversation(player, "Kaleb, have you got a minute?")
	TEST_ASSERT(doctor_ai.blackboard_key_exists(BB_SP_BRUSHED_OFF_AT), "a busy doctor named by a player says so")
	TEST_ASSERT(!sp_test_owes_answer(doctor_ai), "without taking anything up")
	TEST_ASSERT_EQUAL(doctor_ai.blackboard[BB_SP_PATIENT], patient, "or letting go of the patient")
	var/said_at = doctor_ai.blackboard[BB_SP_BRUSHED_OFF_AT]
	doctor_ai.consider_conversation(player, "Kaleb? Kaleb!")
	TEST_ASSERT_EQUAL(doctor_ai.blackboard[BB_SP_BRUSHED_OFF_AT], said_at, "and says it once, not to every line")

	// A line not naming them is somebody else's to answer, busy or not.
	doctor_ai.clear_blackboard_key(BB_SP_BRUSHED_OFF_AT)
	doctor_ai.consider_conversation(player, "Hello")
	TEST_ASSERT(!doctor_ai.blackboard_key_exists(BB_SP_BRUSHED_OFF_AT), "a line not aimed at them gets nothing")
	qdel(doctor_ai)

/**
 * A conversation does not start between two people too far apart to keep it going, and a player calling out
 * from over there is answered with a line instead. Found by the stand-in: a hello heard from seven tiles started
 * an introduction that died on its first line, and the player got silence.
 */
/datum/unit_test/sp_no_conversation_out_of_reach

/datum/unit_test/sp_no_conversation_out_of_reach/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, spot)
	player.forceMove(locate(spot.x + SP_DIALOGUE_RANGE + 2, spot.y, spot.z))
	crew.real_name = "Nell Ashby"
	var/datum/ai_controller/sp_crew/crew_ai = new(crew)
	crew_ai.set_ai_status(AI_STATUS_OFF)
	TEST_ASSERT(get_dist(crew, player) > SP_DIALOGUE_RANGE, "the test put them out of reach")
	TEST_ASSERT_NULL(sp_begin_dialogue(sp_all_dialogues()["introductions"], crew, player), "no conversation starts out of reach")
	crew_ai.consider_conversation(player, "Hello, Nell.")
	TEST_ASSERT(!crew_ai.blackboard_key_exists(BB_SP_THREAD), "so a hello from over there does not start one")
	TEST_ASSERT_EQUAL(crew_ai.blackboard[BB_SP_CHAT_REPLY_DUE], player, "but it is answered with a line")
	qdel(crew_ai)

/**
 * One conversation at a time for a player: nobody starts a second introduction with somebody already talking,
 * but a player who turns to somebody by name is taken up whatever else is pending.
 */
/datum/unit_test/sp_one_conversation_at_a_time

/datum/unit_test/sp_one_conversation_at_a_time/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human/consistent, get_step(spot, NORTH))
	var/mob/living/carbon/human/player = allocate(/mob/living/carbon/human/consistent, get_step(spot, EAST))
	first.real_name = "Ada Quill"
	second.real_name = "Bram Tully"
	ADD_TRAIT(player, TRAIT_SP_STAND_IN, SP_TRAIT_SOURCE)
	var/datum/ai_controller/sp_crew/first_ai = new(first)
	first_ai.set_ai_status(AI_STATUS_OFF)
	var/datum/ai_controller/sp_crew/second_ai = new(second)
	second_ai.set_ai_status(AI_STATUS_OFF)

	var/datum/sp_dialogue_thread/pending = sp_start_thread(first_ai, sp_all_dialogues()["introductions"], first, player)
	TEST_ASSERT_NOTNULL(pending, "the first crew member introduces themselves")
	var/datum/bt_node/ai_behavior/sp_greet_newcomer/greet = new
	greet.perform(1, second_ai)
	TEST_ASSERT(!second_ai.blackboard_key_exists(BB_SP_THREAD), "the second greets somebody already talking with a line, not another introduction")

	second_ai.consider_conversation(player, "Hello")
	TEST_ASSERT(!sp_test_owes_answer(second_ai), "a line naming nobody is a reply to the conversation they are in")
	second_ai.consider_conversation(player, "Hello, Bram.")
	TEST_ASSERT_EQUAL(sp_test_answering(second_ai), player, "but turning to somebody by name is theirs to take up")
	qdel(greet)
	sp_end_dialogue(first_ai, pending)
	sp_test_hush(second_ai)
	qdel(first_ai)
	qdel(second_ai)
