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

/datum/sp_cocktail/New(name, list/parts, result)
	src.name = name
	src.parts = parts
	src.result = result

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

/// How many units each part of a recipe is worth. A drinking glass holds fifty.
#define SP_DRINK_MEASURE 8

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
		var/wanted = drink.parts[reagent_type] * SP_DRINK_MEASURE
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
