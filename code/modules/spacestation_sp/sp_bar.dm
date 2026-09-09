/**
 * Spacestation SP — the bar.
 *
 * Drinks are easier than food. /tg/ makes a cocktail out of a chemical reaction rather than a crafting
 * recipe, and the bar's two dispensers between them hold every base spirit and mixer, so there is no
 * tech tree to climb: pick a drink, put a glass under the tap, measure the parts in, and the reaction
 * does the rest. What takes the walking is that a gin and tonic needs both dispensers — the gin from
 * one and the tonic from the other — so most drinks are two trips across the bar.
 *
 * The rest mirrors the kitchen: finished drinks go out on the counter with a line on the service
 * channel, and `sp_find_service_counter()` picks the counter the same way it picks the kitchen's.
 */

/// Areas the bartender works in.
/proc/sp_bar_areas()
	var/static/list/areas = list(
		/area/station/service/bar,
		/area/station/service/bar/atrium,
		/area/station/service/bar/backroom,
	)
	return areas

/// TRUE if this atom is behind the bar.
/proc/sp_in_bar(atom/thing)
	var/area/where = get_area(thing)
	if(isnull(where))
		return FALSE
	return where.type in sp_bar_areas()

/// The nearest working dispenser of this type in the bar.
/proc/sp_find_bar_dispenser(mob/living/carbon/human/bartender, dispenser_type)
	var/turf/origin = get_turf(bartender)
	if(isnull(origin))
		return null
	var/obj/machinery/chem_dispenser/best
	var/best_distance = INFINITY
	for(var/obj/machinery/chem_dispenser/dispenser as anything in SSmachines.get_machines_by_type_and_subtypes(dispenser_type))
		// The soda dispenser is a parent of the booze one, so an exact-type test keeps them apart.
		if(dispenser.type != dispenser_type || !dispenser.is_operational || !sp_in_bar(dispenser))
			continue
		var/turf/dispenser_turf = get_turf(dispenser)
		if(isnull(dispenser_turf) || dispenser_turf.z != origin.z)
			continue
		var/distance = get_dist(origin, dispenser_turf)
		if(distance < best_distance)
			best = dispenser
			best_distance = distance
	return best

// --- The menu ---------------------------------------------------------------------------------------

/**
 * One drink: the parts that go in the glass, in the ratio /tg/'s reaction wants.
 *
 * `parts` are multiplied up by SP_DRINK_MEASURE so a glass comes out full rather than holding a
 * thimbleful, and the reaction scales with them. Everything here is mixed from the two bar dispensers
 * and nothing else, so the bartender never runs out of anything.
 */
/datum/sp_cocktail
	var/name
	/// Reagent typepath -> parts.
	var/list/parts
	/**
	 * What the glass ends up holding, for the drinks that are a reaction rather than just a mix.
	 *
	 * This matters more than it looks. The reaction consumes the gin and the tonic to make the gin and
	 * tonic, so once it fires the glass no longer contains a drop of either — and asking "is it still
	 * short of gin?" answers yes forever. Null means the drink is only a mix and is done when all the
	 * parts are in.
	 */
	var/result

	/// TRUE when `parts` are already absolute units rather than a ratio to be multiplied up.
	var/absolute = FALSE

/datum/sp_cocktail/New(name, list/parts, result, absolute = FALSE)
	src.name = name
	src.parts = parts
	src.result = result
	src.absolute = absolute

/// How many units of this reagent the drink wants in the glass.
/datum/sp_cocktail/proc/units_of(reagent_type)
	var/amount = parts[reagent_type]
	return absolute ? amount : amount * SP_DRINK_MEASURE

GLOBAL_LIST_INIT(sp_cocktails, list(
	new /datum/sp_cocktail("a gin and tonic", list(/datum/reagent/consumable/ethanol/gin = 1, /datum/reagent/consumable/tonic = 2), /datum/reagent/consumable/ethanol/gintonic),
	new /datum/sp_cocktail("a rum and coke", list(/datum/reagent/consumable/ethanol/rum = 1, /datum/reagent/consumable/space_cola = 2), /datum/reagent/consumable/ethanol/rum_coke),
	new /datum/sp_cocktail("a whiskey cola", list(/datum/reagent/consumable/ethanol/whiskey = 1, /datum/reagent/consumable/space_cola = 2), /datum/reagent/consumable/ethanol/whiskey_cola),
	new /datum/sp_cocktail("a screwdriver", list(/datum/reagent/consumable/ethanol/vodka = 1, /datum/reagent/consumable/orangejuice = 2), /datum/reagent/consumable/ethanol/screwdrivercocktail),
	new /datum/sp_cocktail("a martini", list(/datum/reagent/consumable/ethanol/gin = 2, /datum/reagent/consumable/ethanol/vermouth = 1), /datum/reagent/consumable/ethanol/martini),
	new /datum/sp_cocktail("a vodka martini", list(/datum/reagent/consumable/ethanol/vodka = 2, /datum/reagent/consumable/ethanol/vermouth = 1), /datum/reagent/consumable/ethanol/vodkamartini),
	new /datum/sp_cocktail("a brave bull", list(/datum/reagent/consumable/ethanol/tequila = 2, /datum/reagent/consumable/ethanol/kahlua = 1), /datum/reagent/consumable/ethanol/brave_bull),
	new /datum/sp_cocktail("a bloody mary", list(/datum/reagent/consumable/ethanol/vodka = 1, /datum/reagent/consumable/tomatojuice = 2, /datum/reagent/consumable/limejuice = 1), /datum/reagent/consumable/ethanol/bloody_mary),
	new /datum/sp_cocktail("a tequila sunrise", list(/datum/reagent/consumable/ethanol/tequila = 2, /datum/reagent/consumable/orangejuice = 2, /datum/reagent/consumable/grenadine = 1), /datum/reagent/consumable/ethanol/tequila_sunrise),
	new /datum/sp_cocktail("an iced tea", list(/datum/reagent/consumable/icetea = 2, /datum/reagent/consumable/lemonjuice = 1)),
	new /datum/sp_cocktail("a coffee", list(/datum/reagent/consumable/coffee = 3, /datum/reagent/consumable/cream = 1)),
))


// --- Making anything, not just the house menu ---------------------------------------------------------

/**
 * Everything the bar could actually mix, worked out from /tg/'s own drink reactions.
 *
 * The house menu above is what a bartender pours when nobody has asked for anything in particular. This
 * is the rest of the book: for every drink reaction in the game, walk its ingredients back until they
 * are all things one of the two taps holds, and if that works out, the bartender can make it to order.
 *
 * The walk is recursive because plenty of drinks are made of other drinks — a cuba libre is a rum and
 * coke with lime in it — and the reactions cascade on their own once everything is in the glass, so
 * pouring the flattened base spirits in the right proportions gets there.
 */
/proc/sp_drink_catalogue()
	var/static/list/datum/sp_cocktail/catalogue
	if(!isnull(catalogue))
		return catalogue
	catalogue = list()
	var/list/base = sp_bar_base_reagents()
	if(!length(base))
		return catalogue
	for(var/reaction_type in GLOB.chemical_reactions_list)
		var/datum/chemical_reaction/reaction = GLOB.chemical_reactions_list[reaction_type]
		if(!istype(reaction, /datum/chemical_reaction/drink) || length(reaction.results) != 1)
			continue
		var/result_type = reaction.results[1]
		if(!ispath(result_type, /datum/reagent/consumable))
			continue
		var/list/on_the_way = list()
		var/list/recipe = sp_expand_drink(result_type, SP_DRINK_SERVING, base, on_the_way = on_the_way)
		if(!length(recipe) || sp_recipe_is_ambiguous(recipe, result_type, on_the_way))
			continue
		var/datum/reagent/result_reagent = result_type
		catalogue += new /datum/sp_cocktail(initial(result_reagent.name), recipe, result_type, TRUE)
	return catalogue

/**
 * Would something else form in the glass instead?
 *
 * Everything goes into one glass here, and the reagent system fires whichever reaction it can — so a
 * recipe that happens to contain vodka and orange juice makes a screwdriver on the way past, whatever
 * it was supposed to be making. A drink whose ingredients can form some *other* drink is not one this
 * bartender can be trusted with, so it stays off the list. Reactions on the intended path are fine:
 * those are how a cuba libre becomes a cuba libre.
 */
/proc/sp_recipe_is_ambiguous(list/parts, target, list/on_the_way)
	for(var/reaction_type in GLOB.chemical_reactions_list)
		var/datum/chemical_reaction/reaction = GLOB.chemical_reactions_list[reaction_type]
		if(!istype(reaction, /datum/chemical_reaction/drink) || length(reaction.results) != 1)
			continue
		var/makes = reaction.results[1]
		if(makes == target || (makes in on_the_way))
			continue
		var/satisfiable = length(reaction.required_reagents) > 0
		for(var/ingredient in reaction.required_reagents)
			if(!(ingredient in parts))
				satisfiable = FALSE
				break
		if(satisfiable)
			return TRUE
	return FALSE

/// The reagents the bar's own taps hold between them.
/proc/sp_bar_base_reagents()
	var/static/list/base
	if(!isnull(base))
		return base
	base = list()
	for(var/dispenser_type in list(/obj/machinery/chem_dispenser/drinks, /obj/machinery/chem_dispenser/drinks/beer))
		for(var/obj/machinery/chem_dispenser/dispenser as anything in SSmachines.get_machines_by_type_and_subtypes(dispenser_type))
			if(dispenser.type != dispenser_type || !sp_in_bar(dispenser))
				continue
			base |= dispenser.dispensable_reagents
	if(!length(base))
		base = null // no bar on this map yet; try again later rather than caching nothing
	return base || list()

/**
 * How much of each tap reagent it takes to end up with `want` units of this drink.
 *
 * Returns null when the drink cannot be got to from the taps at all — which is most of them, because
 * half of /tg/'s drinks want fruit somebody has to grow or a bottle somebody has to buy.
 */
/proc/sp_expand_drink(reagent_type, want, list/base, list/seen, depth = 0, list/on_the_way)
	if(want <= 0 || depth > SP_DRINK_MAX_DEPTH)
		return null
	if(reagent_type in base)
		var/list/leaf_only = list()
		leaf_only[reagent_type] = want
		return leaf_only
	seen = seen?.Copy() || list()
	if(reagent_type in seen)
		return null // a drink made of itself, somewhere down the line
	seen += reagent_type

	for(var/reaction_type in GLOB.chemical_reactions_list)
		var/datum/chemical_reaction/reaction = GLOB.chemical_reactions_list[reaction_type]
		if(length(reaction.results) != 1 || reaction.results[1] != reagent_type)
			continue
		// Catalysts have to be sitting in the glass too, and the taps do not pour most of them.
		var/possible = TRUE
		for(var/catalyst in reaction.required_catalysts)
			if(!(catalyst in base))
				possible = FALSE
				break
		if(!possible || reaction.is_cold_recipe || reaction.required_temp > SP_DRINK_POUR_TEMP)
			continue

		var/made = reaction.results[reagent_type]
		if(made <= 0)
			continue
		var/multiplier = want / made
		var/list/total = list()
		if(!isnull(on_the_way) && depth > 0)
			on_the_way |= reagent_type
		for(var/ingredient in reaction.required_reagents)
			var/needed = reaction.required_reagents[ingredient] * multiplier
			var/list/part = sp_expand_drink(ingredient, needed, base, seen, depth + 1, on_the_way)
			if(!length(part))
				possible = FALSE
				break
			for(var/leaf in part)
				total[leaf] += part[leaf]
		for(var/catalyst in reaction.required_catalysts)
			total[catalyst] += reaction.required_catalysts[catalyst]
		if(possible && length(total))
			return total
	return null

/// Finds a drink somebody has just asked for by name.
/proc/sp_drink_from_order(text)
	if(!istext(text) || !length(text))
		return null
	var/needle = lowertext(text)
	var/datum/sp_cocktail/best
	for(var/datum/sp_cocktail/drink as anything in sp_drink_catalogue())
		var/drink_name = lowertext(drink.name)
		if(!length(drink_name) || !findtext(needle, drink_name))
			continue
		// Longest match wins, so "vodka martini" does not get served as a martini.
		if(isnull(best) || length(drink_name) > length(best.name))
			best = drink
	return best

/// Which of a drink's parts come out of this particular dispenser.
/proc/sp_parts_from(datum/sp_cocktail/drink, obj/machinery/chem_dispenser/dispenser)
	var/list/here = list()
	if(isnull(drink) || QDELETED(dispenser))
		return here
	for(var/reagent_type in drink.parts)
		if(reagent_type in dispenser.dispensable_reagents)
			here[reagent_type] = drink.parts[reagent_type]
	return here

/// Is this drink made? Either the reaction has fired, or every part of a plain mix is in the glass.
/proc/sp_drink_ready(datum/sp_cocktail/drink, obj/item/reagent_containers/glass)
	if(isnull(drink) || QDELETED(glass) || isnull(glass.reagents))
		return FALSE
	if(drink.result)
		return glass.reagents.has_reagent(drink.result)
	return !length(sp_missing_parts(drink, glass))

/// What is still missing from the glass before the drink will come together.
/proc/sp_missing_parts(datum/sp_cocktail/drink, obj/item/reagent_containers/glass)
	var/list/missing = list()
	if(isnull(drink) || QDELETED(glass))
		return missing
	// Once the reaction has fired there is nothing left to add; the ingredients are gone by design.
	if(drink.result && glass.reagents?.has_reagent(drink.result))
		return missing
	for(var/reagent_type in drink.parts)
		var/wanted = drink.units_of(reagent_type)
		if(glass.reagents?.get_reagent_amount(reagent_type) < wanted)
			missing[reagent_type] = wanted
	return missing

/**
 * Puts reagent in the glass, the way the dispenser's own interface would.
 *
 * The interface is a TGUI window and there is no clientless route through it, so this reproduces what
 * pressing the button does — including spending the cell charge, which is what stops a bartender
 * pouring out of an unpowered machine all shift.
 */
/proc/sp_dispense_into(obj/machinery/chem_dispenser/dispenser, obj/item/reagent_containers/glass, reagent_type, amount)
	if(QDELETED(dispenser) || QDELETED(glass) || !dispenser.is_operational || QDELETED(dispenser.cell))
		return 0
	if(!(reagent_type in dispenser.dispensable_reagents))
		return 0
	var/datum/reagents/holder = glass.reagents
	if(isnull(holder))
		return 0
	var/to_dispense = max(0, min(amount, holder.maximum_volume - holder.total_volume))
	if(!to_dispense || !dispenser.cell.use(to_dispense * dispenser.power_cost))
		return 0
	holder.add_reagent(reagent_type, to_dispense, reagtemp = dispenser.dispensed_temperature, added_purity = dispenser.base_reagent_purity)
	return to_dispense

// --- Glassware --------------------------------------------------------------------------------------

/// An empty glass the bartender could pour into.
/proc/sp_find_clean_glass(mob/living/carbon/human/bartender)
	for(var/obj/item/reagent_containers/cup/glass/drinkingglass/glass as anything in bartender.get_all_contents_type(/obj/item/reagent_containers/cup/glass/drinkingglass))
		if(!glass.reagents?.total_volume)
			return glass
	return null

/// A drink standing on the counter already, so the bartender knows when to stop pouring.
/proc/sp_counter_drinks(obj/structure/table/counter)
	var/count = 0
	var/turf/counter_turf = get_turf(counter)
	if(isnull(counter_turf))
		return 0
	for(var/obj/item/reagent_containers/cup/glass/drinkingglass/glass in counter_turf)
		if(glass.reagents?.total_volume)
			count++
	return count

/// A poured drink the bartender is carrying, ready to go out.
/proc/sp_find_poured_drink(mob/living/carbon/human/bartender, datum/sp_cocktail/drink)
	for(var/obj/item/reagent_containers/cup/glass/drinkingglass/glass as anything in bartender.get_all_contents_type(/obj/item/reagent_containers/cup/glass/drinkingglass))
		if(!glass.reagents?.total_volume)
			continue
		// A glass that still needs something from the other dispenser is a drink in progress, not one
		// to put out: half a gin and tonic is just gin.
		if(!isnull(drink) && !sp_drink_ready(drink, glass))
			continue
		return glass
	return null
