/**
 * Spacestation SP — the kitchen.
 *
 * /tg/'s cooking is a tech tree rather than a list of recipes: raw stock is cut, ground, mixed, baked
 * and grilled into components, and only then assembled on a table into something you would serve. The
 * chef here works the same tree with the same interactions a player uses, from the bottom up:
 *
 *   stock   - carry ingredients out of the fridges, cabinets and off the floor onto one prep table
 *   mix     - flour and water in a bowl become dough; milk and enzyme become a cheese wheel
 *   prep    - a knife, a rolling pin, the oven, the griddle and the processor turn stock into parts
 *   cook    - anything /tg/ can craft from what is piled on that table gets crafted
 *   serve   - the finished dish goes out on the counter, and the crew are told over the service radio
 *
 * Nothing here hardcodes a menu. The chef reads the crafting recipes at the table and makes whatever
 * the pile currently supports, so what comes out depends on what botany grew and what cargo delivered.
 */

/// Areas the chef works in.
/proc/sp_kitchen_areas()
	var/static/list/areas = list(
		/area/station/service/kitchen,
		/area/station/service/kitchen/diner,
		/area/station/service/kitchen/coldroom,
		/area/station/service/kitchen/kitchen_backroom,
	)
	return areas

/// Every turf of the kitchen on this z-level.
/proc/sp_kitchen_turfs(z_level)
	var/list/turf/turfs = list()
	for(var/area_type in sp_kitchen_areas())
		turfs += get_area_turfs(area_type, z_level)
	return turfs

/// TRUE if this atom is standing in the kitchen.
/proc/sp_in_kitchen(atom/thing)
	var/area/where = get_area(thing)
	if(isnull(where))
		return FALSE
	return where.type in sp_kitchen_areas()

/**
 * The table the chef prepares food on: the kitchen table with the most cooking machinery around it.
 *
 * This matters more than it looks. Crafting only sees what is within one tile of the crafter, so the
 * table the ingredients are piled on decides which recipes are possible at all — and a table wedged
 * between the ovens puts them in reach too, which is what makes the baked recipes work.
 */
/proc/sp_find_prep_table(mob/living/carbon/human/chef)
	var/turf/origin = get_turf(chef)
	if(isnull(origin))
		return null
	var/obj/structure/table/best
	var/best_score = -1
	var/best_distance = INFINITY
	for(var/turf/candidate as anything in sp_kitchen_turfs(origin.z))
		var/obj/structure/table/table = locate() in candidate
		if(isnull(table))
			continue
		var/score = 0
		for(var/turf/neighbour as anything in RANGE_TURFS(1, candidate))
			for(var/obj/machinery/machine in neighbour)
				if(istype(machine, /obj/machinery/oven) || istype(machine, /obj/machinery/griddle) || istype(machine, /obj/machinery/processor))
					score++
		var/distance = get_dist(origin, table)
		if(score > best_score || (score == best_score && distance < best_distance))
			best = table
			best_score = score
			best_distance = distance
	return best

/**
 * The counter: a kitchen table with an open tile on the other side that is not the kitchen. That is
 * the serving hatch on every map that has one, and the crew sit on the far side of it.
 */
/proc/sp_find_counter(mob/living/carbon/human/chef)
	var/turf/origin = get_turf(chef)
	if(isnull(origin))
		return null
	var/obj/structure/table/best
	var/best_distance = INFINITY
	for(var/turf/candidate as anything in sp_kitchen_turfs(origin.z))
		var/obj/structure/table/table = locate() in candidate
		if(isnull(table))
			continue
		var/faces_out = FALSE
		for(var/direction in GLOB.cardinals)
			var/turf/beyond = get_step(candidate, direction)
			if(!isopenturf(beyond) || isspaceturf(beyond))
				continue
			var/area/beyond_area = get_area(beyond)
			if(beyond_area && !(beyond_area.type in sp_kitchen_areas()))
				faces_out = TRUE
				break
		if(!faces_out)
			continue
		var/distance = get_dist(origin, table)
		if(distance < best_distance)
			best = table
			best_distance = distance
	return best

/// The nearest working machine of this type inside the kitchen.
/proc/sp_find_kitchen_machine(mob/living/carbon/human/chef, machine_type)
	var/turf/origin = get_turf(chef)
	if(isnull(origin))
		return null
	var/obj/machinery/best
	var/best_distance = INFINITY
	for(var/obj/machinery/machine as anything in SSmachines.get_machines_by_type_and_subtypes(machine_type))
		if(machine.machine_stat & (BROKEN|NOPOWER))
			continue
		var/turf/machine_turf = get_turf(machine)
		if(isnull(machine_turf) || machine_turf.z != origin.z || !sp_in_kitchen(machine))
			continue
		var/distance = get_dist(origin, machine_turf)
		if(distance < best_distance)
			best = machine
			best_distance = distance
	return best

/// Everything piled on the prep table, which is what the crafting code will see from beside it.
/proc/sp_pantry_contents(obj/structure/table/prep_table)
	var/list/obj/item/pile = list()
	var/turf/table_turf = get_turf(prep_table)
	if(isnull(table_turf))
		return pile
	for(var/obj/item/thing in table_turf)
		pile += thing
	return pile

/// How many things of this type are on the prep table already.
/proc/sp_pantry_count(obj/structure/table/prep_table, wanted_type)
	var/count = 0
	for(var/obj/item/thing as anything in sp_pantry_contents(prep_table))
		if(istype(thing, wanted_type))
			count++
	return count

// --- Prep steps -----------------------------------------------------------------------------------

/**
 * One rung of the cooking tree: an ingredient, what you do to it, and what you get.
 *
 * /tg/ hangs these transformations off elements and components on the ingredients themselves, so they
 * cannot be enumerated from the item. Rather than have the chef poke every ingredient with every tool
 * to find out, the rungs worth climbing are written down here. `result` is only used to know when to
 * stop: once `max_result` of them are on the table there is no sense making more.
 */
/datum/sp_prep_step
	/// Human-readable, for the log and the radio.
	var/name
	/// The ingredient this step consumes.
	var/source
	/// Subtypes of `source` this step must not touch.
	var/list/source_blacklist
	/// One of the SP_PREP_* operations.
	var/operation = SP_PREP_TOOL
	/// For SP_PREP_TOOL: what has to be in the chef's hand.
	var/tool_type
	/// What comes out. Null means the step is judged by the ingredient alone.
	var/result
	/// Stop once this many results are on the prep table.
	var/max_result = 4

/datum/sp_prep_step/New(name, source, operation, result, tool_type, max_result)
	src.name = name
	src.source = source
	src.operation = operation
	src.result = result
	src.tool_type = tool_type
	if(!isnull(max_result))
		src.max_result = max_result

/// The machine this step needs, or null when it is done by hand at the table.
/datum/sp_prep_step/proc/machine_type()
	switch(operation)
		if(SP_PREP_GRILL)
			return /obj/machinery/griddle
		if(SP_PREP_BAKE)
			return /obj/machinery/oven
		if(SP_PREP_PROCESS)
			return /obj/machinery/processor
	return null

/**
 * The rungs the chef knows, roughly in the order a shift climbs them.
 *
 * Between them these produce cutlets and patties, bread and buns, cheese wedges, boiled eggs and cut
 * produce — which is most of what /tg/'s craftable dishes are actually assembled from. Raw meat, for
 * instance, is worth nothing on its own but becomes a burger four rungs later.
 */
GLOBAL_LIST_INIT(sp_kitchen_prep_steps, list(
	// Meat.
	new /datum/sp_prep_step("cutlets", /obj/item/food/meat/slab, SP_PREP_TOOL, /obj/item/food/meat/rawcutlet, /obj/item/knife, 4),
	new /datum/sp_prep_step("grilled cutlets", /obj/item/food/meat/rawcutlet, SP_PREP_GRILL, /obj/item/food/meat/cutlet, null, 4),
	new /datum/sp_prep_step("mince", /obj/item/food/meat/slab, SP_PREP_PROCESS, /obj/item/food/raw_meatball, null, 3),
	new /datum/sp_prep_step("patties", /obj/item/food/raw_meatball, SP_PREP_TOOL, /obj/item/food/raw_patty, /obj/item/kitchen/rollingpin, 3),
	new /datum/sp_prep_step("grilled patties", /obj/item/food/raw_patty, SP_PREP_GRILL, /obj/item/food/patty, null, 3),
	// Dough and bread.
	new /datum/sp_prep_step("flat dough", /obj/item/food/dough, SP_PREP_TOOL, /obj/item/food/flatdough, /obj/item/kitchen/rollingpin, 2),
	new /datum/sp_prep_step("dough slices", /obj/item/food/flatdough, SP_PREP_TOOL, /obj/item/food/doughslice, /obj/item/knife, 3),
	new /datum/sp_prep_step("buns", /obj/item/food/doughslice, SP_PREP_BAKE, /obj/item/food/bun, null, 3),
	// Plain bread only. Bread with something in it — meatbread, cheesy bread — is a dish in its own
	// right, and a chef who slices those up never puts one on the counter.
	new /datum/sp_prep_step("bread", /obj/item/food/dough, SP_PREP_BAKE, /obj/item/food/bread/plain, null, 2),
	new /datum/sp_prep_step("bread slices", /obj/item/food/bread/plain, SP_PREP_TOOL, /obj/item/food/breadslice/plain, /obj/item/knife, 4),
	// Cheese, eggs and produce.
	new /datum/sp_prep_step("cheese wedges", /obj/item/food/cheese/wheel, SP_PREP_TOOL, /obj/item/food/cheese/wedge, /obj/item/knife, 4),
	new /datum/sp_prep_step("boiled eggs", /obj/item/food/egg, SP_PREP_BAKE, /obj/item/food/boiledegg, null, 3),
	new /datum/sp_prep_step("sliced onion", /obj/item/food/grown/onion, SP_PREP_TOOL, /obj/item/food/onion_slice, /obj/item/knife, 4),
	new /datum/sp_prep_step("sliced apple", /obj/item/food/grown/apple, SP_PREP_TOOL, /obj/item/food/appleslice, /obj/item/knife, 4),
	new /datum/sp_prep_step("sliced melon", /obj/item/food/grown/melonlike, SP_PREP_TOOL, /obj/item/food/watermelonslice, /obj/item/knife, 4),
	// Anything a recipe leaves half-finished — a raw pizza, a raw calzone — goes back in the oven.
	new /datum/sp_prep_step("the oven", /obj/item/food, SP_PREP_BAKE, null, null, null),
))

/**
 * Picks the next prep step: a rung of the tree we can climb, and the ingredient on the table to climb
 * it with. Returns list(step, item), or null when there is nothing worth doing.
 */
/proc/sp_find_prep_step(mob/living/carbon/human/chef, obj/structure/table/prep_table)
	if(QDELETED(prep_table) || QDELETED(chef))
		return null
	var/list/obj/item/pile = sp_pantry_contents(prep_table)
	if(!length(pile))
		return null
	var/list/candidates = list()
	for(var/datum/sp_prep_step/step as anything in GLOB.sp_kitchen_prep_steps)
		// The catch-all oven rung has no result to count; it fires on anything still holding a bakeable
		// component, which is /tg/'s way of saying "this is not finished yet".
		if(step.result && sp_pantry_count(prep_table, step.result) >= step.max_result)
			continue
		if(step.operation == SP_PREP_TOOL && isnull(sp_kitchen_tool(chef, step.tool_type)))
			continue
		var/machine_type = step.machine_type()
		if(machine_type && sp_machine_room(sp_find_kitchen_machine(chef, machine_type)) <= 0)
			continue
		for(var/obj/item/thing as anything in pile)
			if(QDELETED(thing) || !istype(thing, step.source))
				continue
			if(step.source_blacklist && is_type_in_list(thing, step.source_blacklist))
				continue
			if(!sp_prep_step_applies(step, thing))
				continue
			candidates += list(list(step, thing))
			break
	if(!length(candidates))
		return null
	return pick(candidates)

/**
 * Would the oven turn this into something better than it is now?
 *
 * Not simply "does it have a bakeable component": /tg/ gives *every* food one, defaulting to a burned
 * mess, so the component alone says nothing. What matters is whether the bake is a positive one — that
 * is the difference between dough, which is half-made, and a sandwich, which is dinner.
 */
/proc/sp_bakes_into_something(obj/item/thing)
	if(QDELETED(thing))
		return FALSE
	var/datum/component/bakeable/bakeable = thing.GetComponent(/datum/component/bakeable)
	if(isnull(bakeable) || !bakeable.positive_result)
		return FALSE
	return !ispath(bakeable.bake_result, /obj/item/food/badrecipe)

/// The same question for the griddle.
/proc/sp_grills_into_something(obj/item/thing)
	if(QDELETED(thing))
		return FALSE
	var/datum/component/grillable/grillable = thing.GetComponent(/datum/component/grillable)
	if(isnull(grillable))
		return FALSE
	return !ispath(grillable.cook_result, /obj/item/food/badrecipe)

/**
 * Guards the rungs whose applicability is a property of the item rather than its type. The component is
 * dropped once something is cooked, so these also answer "is this still raw?".
 */
/proc/sp_prep_step_applies(datum/sp_prep_step/step, obj/item/thing)
	switch(step.operation)
		if(SP_PREP_BAKE)
			return sp_bakes_into_something(thing)
		if(SP_PREP_GRILL)
			return sp_grills_into_something(thing)
	return TRUE

/**
 * How many more things this machine will take on one trip, and whether it should be disturbed at all.
 *
 * The oven is the awkward one: baking only counts while the door is shut, and the default bake is two
 * minutes. A chef who opens it every time they have one more thing to put in resets nothing but stops
 * the clock over and over, and nothing ever comes out. So the oven is loaded in one go and then left
 * alone until it is empty again.
 */
/proc/sp_machine_room(obj/machinery/machine)
	if(QDELETED(machine))
		return 0
	var/obj/machinery/oven/oven = machine
	if(istype(oven))
		if(isnull(oven.used_tray) || oven.appears_active())
			return 0
		return oven.used_tray.max_items - length(oven.used_tray.contents)
	var/obj/machinery/griddle/griddle = machine
	if(istype(griddle))
		return griddle.max_items - length(griddle.griddled_objects)
	return 1

/// Everything else on the table this same step would take, up to what the machine will hold.
/proc/sp_prep_batch(obj/structure/table/prep_table, datum/sp_prep_step/step, obj/item/first, room)
	var/list/obj/item/load = list(first)
	if(room <= 1)
		return load
	for(var/obj/item/thing as anything in sp_pantry_contents(prep_table))
		if(length(load) >= room)
			break
		if(thing == first || QDELETED(thing) || !istype(thing, step.source))
			continue
		if(!sp_prep_step_applies(step, thing))
			continue
		load += thing
	return load

/// A kitchen tool of this type the chef is carrying.
/proc/sp_kitchen_tool(mob/living/carbon/human/chef, tool_type)
	if(isnull(tool_type) || QDELETED(chef))
		return null
	var/list/carried = chef.get_all_contents_type(tool_type)
	return length(carried) ? carried[1] : null

// --- Mixing ---------------------------------------------------------------------------------------

/**
 * Something made by pouring reagents into a bowl. /tg/ handles these as chemical reactions rather than
 * crafting recipes, so they are the one part of the tree the crafting code cannot reach — and without
 * them the chef has no dough and no cheese, which means no bread, no buns and no sandwiches.
 */
/datum/sp_kitchen_mix
	var/name
	/// Reagent type -> units that have to end up in the bowl.
	var/list/reagents
	/// What the reaction drops out, used to know when to stop.
	var/result
	var/max_result = 2

/datum/sp_kitchen_mix/New(name, list/reagents, result, max_result)
	src.name = name
	src.reagents = reagents
	src.result = result
	if(!isnull(max_result))
		src.max_result = max_result

GLOBAL_LIST_INIT(sp_kitchen_mixes, list(
	new /datum/sp_kitchen_mix("dough", list(/datum/reagent/consumable/flour = 15, /datum/reagent/water = 10), /obj/item/food/dough, 2),
	new /datum/sp_kitchen_mix("a cheese wheel", list(/datum/reagent/consumable/milk = 40, /datum/reagent/consumable/enzyme = 5), /obj/item/food/cheese/wheel, 1),
))

/// A bowl the chef can mix in: empty, and either carried or sitting on the prep table.
/proc/sp_find_mixing_bowl(mob/living/carbon/human/chef, obj/structure/table/prep_table)
	for(var/obj/item/reagent_containers/cup/bowl/bowl as anything in chef.get_all_contents_type(/obj/item/reagent_containers/cup/bowl))
		if(!length(bowl.contents) && !bowl.reagents?.total_volume)
			return bowl
	for(var/obj/item/thing as anything in sp_pantry_contents(prep_table))
		var/obj/item/reagent_containers/cup/bowl/bowl = thing
		if(istype(bowl) && !length(bowl.contents) && !bowl.reagents?.total_volume)
			return bowl
	return null

/// A container within reach holding at least `amount` of this reagent.
/proc/sp_find_reagent_source(mob/living/carbon/human/chef, obj/structure/table/prep_table, reagent_type, amount, obj/item/exclude)
	var/list/obj/item/searching = chef.get_all_contents_type(/obj/item/reagent_containers) + sp_pantry_contents(prep_table)
	for(var/obj/item/reagent_containers/container as anything in searching)
		if(!istype(container) || container == exclude || QDELETED(container))
			continue
		if(!container.is_drainable())
			continue
		if(container.reagents?.get_reagent_amount(reagent_type) >= amount)
			return container
	return null

/**
 * Picks a mix worth making. Water is deliberately not searched for: the kitchen sink is the only
 * sensible source and the chef has to walk to it, which the behaviour tree handles as its own leg.
 */
/proc/sp_find_mix(mob/living/carbon/human/chef, obj/structure/table/prep_table, obj/item/reagent_containers/cup/bowl/bowl)
	if(QDELETED(prep_table) || QDELETED(bowl))
		return null
	for(var/datum/sp_kitchen_mix/mix as anything in shuffle(GLOB.sp_kitchen_mixes))
		if(sp_pantry_count(prep_table, mix.result) >= mix.max_result)
			continue
		var/possible = TRUE
		for(var/reagent_type in mix.reagents)
			if(reagent_type == /datum/reagent/water)
				continue // comes from the sink
			if(isnull(sp_find_reagent_source(chef, prep_table, reagent_type, mix.reagents[reagent_type], bowl)))
				possible = FALSE
				break
		if(possible)
			return mix
	return null

/// The nearest kitchen sink, for the water half of a mix.
/proc/sp_find_kitchen_sink(mob/living/carbon/human/chef)
	var/turf/origin = get_turf(chef)
	if(isnull(origin))
		return null
	var/obj/structure/sink/best
	var/best_distance = INFINITY
	for(var/turf/candidate as anything in sp_kitchen_turfs(origin.z))
		var/obj/structure/sink/sink = locate() in candidate
		if(isnull(sink) || !sink.reagents?.total_volume)
			continue
		var/distance = get_dist(origin, candidate)
		if(distance < best_distance)
			best = sink
			best_distance = distance
	return best

// --- Cooking --------------------------------------------------------------------------------------

/// Every food recipe anyone can craft without having read a cookbook first, built once.
/proc/sp_cooking_recipes()
	var/static/list/datum/crafting_recipe/recipes
	if(!isnull(recipes))
		return recipes
	recipes = list()
	for(var/datum/crafting_recipe/recipe as anything in GLOB.cooking_recipes_default)
		if(recipe.non_craftable || !length(recipe.reqs) || !ispath(recipe.result, /obj/item))
			continue
		recipes += recipe
	return recipes

/**
 * Everything the chef could craft standing where they are. This runs /tg/'s own checks, so if it says
 * yes the craft will go through.
 */
/proc/sp_craftable_recipes(mob/living/carbon/human/chef)
	var/datum/component/personal_crafting/crafting = chef.GetComponent(/datum/component/personal_crafting)
	if(isnull(crafting))
		return list()
	var/list/found = list()
	var/list/surroundings = crafting.get_surroundings(chef)
	for(var/datum/crafting_recipe/recipe as anything in sp_cooking_recipes())
		if(!crafting.check_contents(chef, recipe, surroundings))
			continue
		if(!crafting.check_tools(chef, recipe, surroundings))
			continue
		found += recipe
	return found

/**
 * Would this recipe produce something the crew could eat, rather than another component?
 *
 * Judged from the typepath alone, because this runs over every recipe before anything is made. A result
 * that is itself an ingredient in one of the prep steps is the chef restocking their own worktop, which
 * is worth doing but should lose to actually assembling a meal.
 */
/proc/sp_recipe_makes_dish(datum/crafting_recipe/recipe)
	if(!ispath(recipe.result, /obj/item/food))
		return FALSE
	var/obj/item/food/result = recipe.result
	if(initial(result.crafting_complexity) <= 0)
		return FALSE
	for(var/datum/sp_prep_step/step as anything in GLOB.sp_kitchen_prep_steps)
		if(step.result && ispath(recipe.result, step.result))
			return FALSE
		// The catch-all oven rung takes any food at all, so it says nothing about this recipe.
		if(step.source != /obj/item/food && ispath(recipe.result, step.source))
			return FALSE
	return TRUE

/**
 * A dish worth carrying out to the counter: something cooked, that is not itself an ingredient in one
 * of the chef's prep steps, and that the game does not still consider raw.
 */
/proc/sp_is_finished_dish(obj/item/food/dish)
	if(!istype(dish) || QDELETED(dish))
		return FALSE
	if(dish.crafting_complexity <= 0)
		return FALSE
	if(dish.foodtypes & RAW)
		return FALSE
	// Something the oven would improve is still unfinished: dough, batter, a raw pizza. Note that this
	// is not "has a bakeable component" — every food has one of those. Grillable is deliberately not
	// disqualifying either, because grilling is usually an upgrade rather than a requirement: a cheese
	// sandwich is a cheese sandwich whether or not somebody later makes it a grilled cheese.
	if(sp_bakes_into_something(dish))
		return FALSE
	for(var/datum/sp_prep_step/step as anything in GLOB.sp_kitchen_prep_steps)
		if(step.result && istype(dish, step.result))
			return FALSE
	return TRUE

/**
 * A finished dish the chef is carrying, standing on, or has left within arm's reach.
 *
 * Crafting drops what it makes at the crafter's feet, so the surrounding tiles matter: without them a
 * dish the chef stepped away from before the serving branch got a turn would sit on the floor for the
 * rest of the shift, because nothing else picks finished food up.
 */
/proc/sp_find_dish_to_serve(mob/living/carbon/human/chef)
	for(var/obj/item/food/dish as anything in chef.get_all_contents_type(/obj/item/food))
		if(sp_is_finished_dish(dish))
			return dish
	var/turf/standing = get_turf(chef)
	if(isnull(standing))
		return null
	for(var/turf/nearby as anything in RANGE_TURFS(1, standing))
		for(var/obj/item/food/dish in nearby)
			if(sp_is_finished_dish(dish))
				return dish
	return null

/// How much is already waiting on the counter, so the chef stops before burying it.
/proc/sp_counter_load(obj/structure/table/counter)
	var/count = 0
	var/turf/counter_turf = get_turf(counter)
	if(isnull(counter_turf))
		return 0
	for(var/obj/item/food/dish in counter_turf)
		if(sp_is_finished_dish(dish))
			count++
	return count

// --- Stock ----------------------------------------------------------------------------------------

/// Things the chef should never pile on the prep table or cook with.
GLOBAL_LIST_INIT(sp_kitchen_stock_blacklist, typecacheof(list(
	/obj/item/food/badrecipe,
	/obj/item/food/meat/slab/human,
	/obj/item/food/meat/rawcutlet/plain/human,
	/obj/item/reagent_containers/cup/soup_pot,
)))

/// TRUE when this is an ingredient the chef would carry to the prep table.
/proc/sp_is_ingredient(obj/item/thing)
	if(QDELETED(thing) || is_type_in_typecache(thing, GLOB.sp_kitchen_stock_blacklist))
		return FALSE
	if(istype(thing, /obj/item/food) || istype(thing, /obj/item/reagent_containers/condiment))
		return TRUE
	return istype(thing, /obj/item/reagent_containers/cup/bowl)

/**
 * Where the next armful of ingredients is coming from: a fridge or cabinet with food in it, or food
 * somebody left lying around the kitchen, which is how botany's deliveries arrive.
 */
/proc/sp_find_stock_source(mob/living/carbon/human/chef, obj/structure/table/prep_table)
	var/turf/origin = get_turf(chef)
	if(isnull(origin))
		return null
	var/turf/prep_turf = get_turf(prep_table)
	var/atom/best = sp_find_bowl_vendor(chef, prep_table)
	if(!isnull(best))
		return best
	var/best_distance = INFINITY
	for(var/turf/candidate as anything in sp_kitchen_turfs(origin.z))
		if(candidate == prep_turf)
			continue
		// Finished dishes are skipped, which is what keeps the chef from carrying their own cooking
		// back off the counter and into the pile.
		for(var/obj/item/thing in candidate)
			if(!sp_is_ingredient(thing) || sp_is_finished_dish(thing))
				continue
			var/loose_distance = get_dist(origin, candidate)
			if(loose_distance < best_distance)
				best = thing
				best_distance = loose_distance
			break
		for(var/atom/movable/store in candidate)
			if(!sp_worth_opening(store))
				continue
			var/store_distance = get_dist(origin, candidate)
			if(store_distance < best_distance)
				best = store
				best_distance = store_distance
	return best

/**
 * Is this fridge or cabinet worth a trip?
 *
 * A closet that has never been opened reads as empty: /tg/ only calls PopulateContents() the first
 * time somebody opens one. So an unopened closet always counts — the chef has to go and look, the way
 * anyone would at the start of a shift — and once it is open we can tell whether anything is left.
 */
/proc/sp_worth_opening(atom/movable/store)
	if(istype(store, /obj/machinery/smartfridge))
		return length(sp_stock_in(store)) > 0
	var/obj/structure/closet/closet = store
	if(!istype(closet) || closet.broken)
		return FALSE
	if(!closet.opened && !closet.contents_initialized)
		return TRUE
	return length(sp_stock_in(closet)) > 0

/**
 * The dinnerware vendor, when the kitchen is short of bowls. A great many recipes want one and each is
 * consumed by the dish it goes into, so a chef who cannot restock them runs out of half the menu after
 * a few plates.
 */
/proc/sp_find_bowl_vendor(mob/living/carbon/human/chef, obj/structure/table/prep_table)
	if(sp_pantry_count(prep_table, /obj/item/reagent_containers/cup/bowl) >= 2)
		return null
	if(length(chef.get_all_contents_type(/obj/item/reagent_containers/cup/bowl)))
		return null
	var/obj/machinery/vending/dinnerware/vendor = sp_find_kitchen_machine(chef, /obj/machinery/vending/dinnerware)
	if(QDELETED(vendor))
		return null
	for(var/datum/data/vending_product/record as anything in vendor.product_records)
		if(record.product_path == /obj/item/reagent_containers/cup/bowl && record.amount > 0)
			return vendor
	return null

/// Buys one bowl out of the chef's own wages, the way the botanist buys seeds.
/proc/sp_buy_bowl(mob/living/carbon/human/chef, obj/machinery/vending/dinnerware/vendor)
	if(QDELETED(vendor) || QDELETED(chef))
		return null
	var/datum/data/vending_product/chosen
	for(var/datum/data/vending_product/record as anything in vendor.product_records)
		if(record.product_path == /obj/item/reagent_containers/cup/bowl && record.amount > 0)
			chosen = record
			break
	if(isnull(chosen))
		return null
	var/price = vendor.all_products_free ? 0 : (chosen.price || vendor.default_price)
	if(price > 0)
		var/obj/item/card/id/id_card = chef.get_idcard(hand_first = FALSE)
		var/datum/bank_account/account = id_card?.registered_account
		if(isnull(account) || !account.adjust_money(-price, "Vending: [chosen.name]"))
			return null
	var/obj/item/bought = vendor.dispense(chosen, get_turf(chef))
	if(isnull(bought))
		return null
	log_sp("[chef.real_name] bought a bowl from the dinnerware vendor for [price] credits")
	return bought

/// The ingredients inside a fridge, cabinet or smartfridge.
/proc/sp_stock_in(atom/store)
	var/list/obj/item/found = list()
	if(QDELETED(store))
		return found
	for(var/obj/item/thing in store.contents)
		if(sp_is_ingredient(thing))
			found += thing
	return found

/// A cooking machine in the kitchen holding something that has finished cooking.
/proc/sp_find_finished_machine(mob/living/carbon/human/chef)
	var/turf/origin = get_turf(chef)
	if(isnull(origin))
		return null
	for(var/machine_type in list(/obj/machinery/griddle, /obj/machinery/oven))
		for(var/obj/machinery/machine as anything in SSmachines.get_machines_by_type_and_subtypes(machine_type))
			var/turf/machine_turf = get_turf(machine)
			if(isnull(machine_turf) || machine_turf.z != origin.z || !sp_in_kitchen(machine))
				continue
			if(length(sp_finished_in_machine(machine)))
				return machine
	return null

/**
 * What inside a griddle or oven is cooked and ready to come out.
 *
 * Read off the machine's own list of what it is cooking, never its contents: a machine's contents are
 * also where its circuit board and stock parts live, and a chef who empties those out has dismantled
 * the griddle rather than cleared it.
 */
/proc/sp_finished_in_machine(obj/machinery/machine)
	var/list/obj/item/done = list()
	if(QDELETED(machine))
		return done
	var/list/obj/item/holding = list()
	if(istype(machine, /obj/machinery/oven))
		var/obj/machinery/oven/oven = machine
		if(isnull(oven.used_tray))
			return done
		holding = oven.used_tray.contents
	else if(istype(machine, /obj/machinery/griddle))
		var/obj/machinery/griddle/griddle = machine
		holding = griddle.griddled_objects
	for(var/obj/item/food/thing as anything in holding)
		if(!istype(thing) || QDELETED(thing))
			continue
		if(isnull(thing.GetComponent(/datum/component/bakeable)) && isnull(thing.GetComponent(/datum/component/grillable)))
			done += thing
	return done

#ifdef SP_KITCHEN_DEBUG
/// One-line state of every cooking machine in the kitchen, for the debug log.
/proc/sp_machine_report(mob/living/carbon/human/chef)
	var/list/lines = list()
	for(var/machine_type in list(/obj/machinery/griddle, /obj/machinery/oven))
		for(var/obj/machinery/machine as anything in SSmachines.get_machines_by_type_and_subtypes(machine_type))
			if(!sp_in_kitchen(machine))
				continue
			var/obj/machinery/oven/oven = machine
			if(istype(oven))
				lines += "[oven] open=[oven.open] active=[oven.appears_active()] tray=[oven.used_tray ? length(oven.used_tray.contents) : "none"] done=[length(sp_finished_in_machine(oven))]"
				continue
			var/obj/machinery/griddle/griddle = machine
			lines += "[griddle] on=[griddle.on] items=[length(griddle.griddled_objects)] done=[length(sp_finished_in_machine(griddle))]"
	return jointext(lines, " | ")
#endif
