/**
 * Botany helpers.
 *
 * The AI botanist runs a full crop cycle: plant an empty tray, keep it watered and weeded, pull the
 * dead plants, harvest what is ready, then carry the produce to the kitchen so the chef has something
 * to cook with. Everything is done through the same interactions a player uses, so trays, seeds and
 * produce behave exactly as they normally would.
 */

/// Seeds an SP botanist starts with. Weighted towards things the chef can actually cook, with a few
/// oddities so the garden is not the same every round. What they plant is picked at random from here.
GLOBAL_LIST_INIT(sp_botany_seed_pool, list(
	// Kitchen staples: the chef needs these.
	/obj/item/seeds/tomato = 3,
	/obj/item/seeds/potato = 3,
	/obj/item/seeds/carrot = 3,
	/obj/item/seeds/wheat = 3,
	/obj/item/seeds/corn = 2,
	/obj/item/seeds/cabbage = 2,
	/obj/item/seeds/onion = 2,
	/obj/item/seeds/chili = 2,
	/obj/item/seeds/soya = 2,
	/obj/item/seeds/apple = 2,
	/obj/item/seeds/banana = 1,
	/obj/item/seeds/berry = 2,
	/obj/item/seeds/watermelon = 1,
	/obj/item/seeds/pumpkin = 1,
	/obj/item/seeds/eggplant = 1,
	/obj/item/seeds/garlic = 1,
	// Botanist's own interests. Whether any of this is legal is Security's problem, not botany's.
	/obj/item/seeds/ambrosia = 1,
	/obj/item/seeds/sunflower = 1,
	/obj/item/seeds/poppy = 1,
	/obj/item/seeds/cannabis = 1,
	/obj/item/seeds/tobacco = 1,
	/obj/item/seeds/tea = 1,
	/obj/item/seeds/coffee = 1,
	/obj/item/seeds/glowshroom = 1,
))

/// Below this water level a tray is worth topping up.
#define SP_TRAY_WATER_THRESHOLD 30
/// Above this weed level a tray is worth hoeing.
#define SP_TRAY_WEED_THRESHOLD 2

/// Areas the botanist works in.
/proc/sp_botany_areas()
	var/static/list/areas = list(
		/area/station/service/hydroponics,
		/area/station/service/hydroponics/upper,
		/area/station/service/hydroponics/garden,
	)
	return areas

/// What, if anything, this tray needs from us right now. Null when it is fine or we cannot help.
/proc/sp_tray_job(obj/machinery/hydroponics/tray, mob/living/carbon/human/botanist)
	if(QDELETED(tray))
		return null
	if(tray.plant_status == HYDROTRAY_PLANT_HARVESTABLE)
		return SP_TRAY_JOB_HARVEST
	if(tray.plant_status == HYDROTRAY_PLANT_DEAD)
		return SP_TRAY_JOB_CLEAR
	if(tray.weedlevel > SP_TRAY_WEED_THRESHOLD && length(botanist.get_all_contents_type(/obj/item/cultivator)))
		return SP_TRAY_JOB_WEED
	if(!isnull(tray.myseed) && tray.waterlevel < SP_TRAY_WATER_THRESHOLD && sp_botany_watering_can(botanist, TRUE))
		return SP_TRAY_JOB_WATER
	if(isnull(tray.myseed) && length(botanist.get_all_contents_type(/obj/item/seeds)))
		return SP_TRAY_JOB_PLANT
	return null

/// The botanist's watering can. Pass TRUE to require that it still holds water.
/proc/sp_botany_watering_can(mob/living/carbon/human/botanist, needs_water = FALSE)
	for(var/obj/item/reagent_containers/cup/watering_can/can as anything in botanist.get_all_contents_type(/obj/item/reagent_containers/cup/watering_can))
		if(!needs_water || can.reagents?.has_reagent(/datum/reagent/water, 5))
			return can
	return null

/// The nearest tray in view that wants attention, along with the job it wants. Returns a list(tray, job).
/proc/sp_find_tray_job(mob/living/carbon/human/botanist, range = 12)
	var/obj/machinery/hydroponics/best_tray
	var/best_job
	var/best_distance = INFINITY
	for(var/obj/machinery/hydroponics/tray in oview(range, botanist))
		var/job = sp_tray_job(tray, botanist)
		if(isnull(job))
			continue
		var/distance = get_dist(botanist, tray)
		// Harvesting beats everything else at equal distance: ripe plants rot and block the tray.
		if(job == SP_TRAY_JOB_HARVEST)
			distance -= 6
		if(distance >= best_distance)
			continue
		best_tray = tray
		best_job = job
		best_distance = distance
	if(isnull(best_tray))
		return null
	return list(best_tray, best_job)

/// A seed to plant, picked at random from what the botanist is carrying.
/proc/sp_pick_seed(mob/living/carbon/human/botanist)
	var/list/seeds = botanist.get_all_contents_type(/obj/item/seeds)
	// Grafts and other seed subtypes that are not plantable packets would just fail on the tray.
	for(var/obj/item/seeds/candidate in seeds)
		if(isnull(candidate.plantname))
			seeds -= candidate
	return length(seeds) ? pick(seeds) : null

/**
 * Produce or seed packets lying loose on the floor near the botanist, nearest first.
 * Harvesting drops produce at their feet and the seed extractor spits packets out beside it, so this
 * is how both get collected.
 */
/proc/sp_find_loose_produce(mob/living/carbon/human/botanist, range = 4)
	var/obj/item/best
	var/best_distance = INFINITY
	for(var/obj/item/loose in oview(range, botanist))
		if(!isturf(loose.loc))
			continue
		if(!istype(loose, /obj/item/food/grown) && !istype(loose, /obj/item/seeds))
			continue
		var/distance = get_dist(botanist, loose)
		if(distance < best_distance)
			best = loose
			best_distance = distance
	return best

/// How much produce the botanist is carrying.
/proc/sp_carried_produce(mob/living/carbon/human/botanist)
	return botanist.get_all_contents_type(/obj/item/food/grown)

/// A table in the kitchen to leave produce on, or null if we cannot find one on our z-level.
/proc/sp_find_kitchen_table(mob/living/carbon/human/botanist)
	var/turf/origin = get_turf(botanist)
	if(isnull(origin))
		return null
	var/static/list/kitchen_areas = list(/area/station/service/kitchen, /area/station/service/kitchen/diner)
	var/obj/structure/table/best
	var/best_distance = INFINITY
	for(var/area_type in kitchen_areas)
		for(var/turf/candidate as anything in get_area_turfs(area_type, origin.z))
			var/obj/structure/table/table = locate() in candidate
			if(isnull(table))
				continue
			var/distance = get_dist(origin, table)
			if(distance < best_distance)
				best = table
				best_distance = distance
	return best

/// A table in hydroponics to display sample produce on.
/proc/sp_find_sample_table(mob/living/carbon/human/botanist)
	var/turf/origin = get_turf(botanist)
	if(isnull(origin))
		return null
	var/obj/structure/table/best
	var/best_distance = INFINITY
	for(var/area_type in sp_botany_areas())
		for(var/turf/candidate as anything in get_area_turfs(area_type, origin.z))
			var/obj/structure/table/table = locate() in candidate
			if(isnull(table))
				continue
			var/distance = get_dist(origin, table)
			if(distance < best_distance)
				best = table
				best_distance = distance
	return best

/// The nearest thing we can refill a watering can from.
/proc/sp_find_water_source(mob/living/carbon/human/botanist, range = 20)
	var/obj/structure/reagent_dispensers/best
	var/best_distance = INFINITY
	for(var/obj/structure/reagent_dispensers/source in oview(range, botanist))
		if(!source.reagents?.has_reagent(/datum/reagent/water, 10))
			continue
		var/distance = get_dist(botanist, source)
		if(distance < best_distance)
			best = source
			best_distance = distance
	return best


// --- Seeds, extraction and experimentation ----------------------------------------------------

/// Seed typepaths the botanist is carrying packets of.
/proc/sp_carried_seed_types(mob/living/carbon/human/botanist)
	var/list/types = list()
	for(var/obj/item/seeds/packet as anything in botanist.get_all_contents_type(/obj/item/seeds))
		types |= packet.type
	return types

/**
 * Produce worth turning into seeds: something we are carrying whose species we have no packet of.
 * This is how a botanist locks in a mutation they just grew, so it is worth a walk to the extractor.
 */
/proc/sp_produce_needing_seeds(mob/living/carbon/human/botanist)
	var/list/have = sp_carried_seed_types(botanist)
	var/list/carrying = sp_carried_produce(botanist)
	for(var/obj/item/food/grown/produce as anything in carrying)
		var/obj/item/seeds/its_seed = produce.get_plant_seed()
		if(isnull(its_seed) || (its_seed.type in have))
			continue
		return produce
	// Running out of packets: seed whatever we have rather than leaving trays empty.
	if(length(have) < 3 && length(carrying))
		for(var/obj/item/food/grown/produce as anything in carrying)
			if(!isnull(produce.get_plant_seed()))
				return produce
	return null

/// The nearest seed extractor. Not sight-limited, for the same reason as the cargo console.
/proc/sp_find_seed_extractor(mob/living/carbon/human/botanist)
	var/turf/origin = get_turf(botanist)
	if(isnull(origin))
		return null
	var/obj/machinery/seed_extractor/best
	var/best_distance = INFINITY
	for(var/obj/machinery/seed_extractor/extractor as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/seed_extractor))
		var/turf/spot = get_turf(extractor)
		if(isnull(spot) || spot.z != origin.z)
			continue
		var/distance = get_dist(origin, spot)
		if(distance < best_distance)
			best = extractor
			best_distance = distance
	return best

/// The nearest working MegaSeed Servitor. Not sight-limited.
/proc/sp_find_seed_vendor(mob/living/carbon/human/botanist)
	var/turf/origin = get_turf(botanist)
	if(isnull(origin))
		return null
	var/obj/machinery/vending/hydroseeds/best
	var/best_distance = INFINITY
	for(var/obj/machinery/vending/hydroseeds/vendor as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/vending/hydroseeds))
		if(vendor.machine_stat & (BROKEN|NOPOWER))
			continue
		var/turf/spot = get_turf(vendor)
		if(isnull(spot) || spot.z != origin.z)
			continue
		var/distance = get_dist(origin, spot)
		if(distance < best_distance)
			best = vendor
			best_distance = distance
	return best

/**
 * Buys one packet of a seed the botanist does not already carry, paid for out of their own wages.
 * Returns the seed, or null. Botanists earn a paycheck at spawn, so a few packets a shift is affordable.
 */
/proc/sp_buy_seed_packet(mob/living/carbon/human/botanist, obj/machinery/vending/hydroseeds/vendor)
	if(QDELETED(vendor) || QDELETED(botanist))
		return null
	var/obj/item/card/id/id_card = botanist.get_idcard(hand_first = FALSE)
	var/datum/bank_account/account = id_card?.registered_account
	if(isnull(account))
		return null

	var/list/have = sp_carried_seed_types(botanist)
	var/list/datum/data/vending_product/affordable = list()
	for(var/datum/data/vending_product/record as anything in vendor.product_records)
		if(record.amount <= 0 || !ispath(record.product_path, /obj/item/seeds))
			continue
		if(record.product_path in have)
			continue
		var/price = record.price || vendor.default_price
		if(!account.has_money(price))
			continue
		affordable += record
	if(!length(affordable))
		return null

	var/datum/data/vending_product/chosen = pick(affordable)
	var/price = chosen.price || vendor.default_price
	if(!account.adjust_money(-price, "Vending: [chosen.name]"))
		return null
	var/obj/item/bought = vendor.dispense(chosen, get_turf(botanist))
	if(isnull(bought))
		return null
	log_sp("[botanist.real_name] bought [bought.name] from the seed vendor for [price] credits")
	return bought

/**
 * A tray worth dosing with mutagen: growing, not already unstable, and of a species that has
 * somewhere to mutate to. This is the botanist deliberately trying to breed something new.
 */
/// Is this tray still a plant worth pushing towards a mutation?
/proc/sp_is_mutation_candidate(obj/machinery/hydroponics/tray)
	if(QDELETED(tray))
		return FALSE
	var/obj/item/seeds/growing = tray.myseed
	if(isnull(growing) || tray.plant_status == HYDROTRAY_PLANT_DEAD)
		return FALSE
	if(!LAZYLEN(growing.mutatelist))
		return FALSE
	return growing.instability < SP_MUTAGEN_INSTABILITY_TARGET

/proc/sp_find_mutation_candidate(mob/living/carbon/human/botanist, range = 12)
	var/obj/machinery/hydroponics/best
	var/best_instability = -1
	for(var/obj/machinery/hydroponics/tray in oview(range, botanist))
		var/obj/item/seeds/growing = tray.myseed
		if(isnull(growing) || tray.plant_status == HYDROTRAY_PLANT_DEAD)
			continue
		if(!LAZYLEN(growing.mutatelist))
			continue
		if(growing.instability >= SP_MUTAGEN_INSTABILITY_TARGET)
			continue
		// Always keep working on the same plant: instability only pays off once it is high, so
		// spreading doses around the room would never mutate anything.
		if(growing.instability > best_instability)
			best = tray
			best_instability = growing.instability
	return best

/// Any cup, bottle or beaker we carry that still holds mutagen.
/proc/sp_find_mutagen(mob/living/carbon/human/botanist)
	for(var/obj/item/reagent_containers/cup/container as anything in botanist.get_all_contents_type(/obj/item/reagent_containers/cup))
		if(container.reagents?.has_reagent(/datum/reagent/toxin/mutagen, 5))
			return container
	return null

#undef SP_TRAY_WATER_THRESHOLD
#undef SP_TRAY_WEED_THRESHOLD
