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

/**
 * The nearest tray in view that wants attention, along with the job it wants. Returns a list(tray, job).
 * `preferred_species` is a plant somebody has asked for, `ignored` trays picked too recently to pick again.
 */
/proc/sp_find_tray_job(mob/living/carbon/human/botanist, range = 12, preferred_species, list/ignored)
	// A seed somebody asked for goes in ahead of the routine work, unless it is already growing: medbay's aloe
	// packet sat in a bag for ten minutes while the botanist watered, harvested and dosed tomatoes.
	var/rush_planting = FALSE
	if(preferred_species)
		for(var/obj/item/seeds/carried in botanist.get_all_contents_type(/obj/item/seeds))
			if(carried.plantname && findtext(LOWER_TEXT(carried.plantname), preferred_species))
				rush_planting = TRUE
				break
	var/list/obj/machinery/hydroponics/trays = list()
	for(var/obj/machinery/hydroponics/tray in oview(range, botanist))
		trays += tray
		if(rush_planting && tray.myseed?.plantname && findtext(LOWER_TEXT(tray.myseed.plantname), preferred_species))
			rush_planting = FALSE
	var/obj/machinery/hydroponics/best_tray
	var/best_job
	var/best_distance = INFINITY
	for(var/obj/machinery/hydroponics/tray as anything in trays)
		if(ignored?[tray] > world.time)
			continue
		var/job = sp_tray_job(tray, botanist)
		if(isnull(job))
			continue
		var/distance = get_dist(botanist, tray)
		// Harvesting beats everything else at equal distance: ripe plants rot and block the tray.
		if(job == SP_TRAY_JOB_HARVEST || (job == SP_TRAY_JOB_PLANT && rush_planting))
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
/proc/sp_pick_seed(mob/living/carbon/human/botanist, preferred_species)
	var/list/seeds = botanist.get_all_contents_type(/obj/item/seeds)
	// Grafts and other seed subtypes that are not plantable packets would just fail on the tray.
	for(var/obj/item/seeds/candidate in seeds)
		if(isnull(candidate.plantname))
			seeds -= candidate
	// Somebody has asked for this one, so it goes into the next free tray.
	if(preferred_species)
		for(var/obj/item/seeds/wanted in seeds)
			if(findtext(LOWER_TEXT(wanted.plantname), preferred_species))
				return wanted
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

/// Plants another department can ask botany for by name. Aloe bakes into the cream medics use on burns,
/// and the clown gets through bananas faster than anybody else gets through anything.
GLOBAL_LIST_INIT(sp_requestable_plants, list(
	"aloe" = /obj/item/food/grown/aloe,
	"banana" = /obj/item/food/grown/banana,
))

/**
 * What a request is really for, when the plant is only the start of it. Medbay asks for aloe because
 * microwaved aloe is the cream they put on burns, and a raw leaf handed over is a chore handed over with it.
 */
GLOBAL_LIST_INIT(sp_request_cooked_forms, list(
	"aloe" = /obj/item/stack/medical/aloe,
))

/**
 * The plant somebody just asked botany for, or null. The line has to name botany and the plant: the crew
 * talk about food all shift, so a request is addressed, where a passing mention of aloe is not.
 */
/proc/sp_plant_asked_for(message)
	var/lowered = LOWER_TEXT(message)
	if(!findtext(lowered, "botan"))
		return null
	for(var/plant in GLOB.sp_requestable_plants)
		if(findtext(lowered, plant))
			return plant
	return null

/// Where a request says its delivery should go ("up to medbay"), as an area type, or null if it names nowhere.
/proc/sp_named_delivery_area(message)
	var/lowered = LOWER_TEXT(message)
	if(findtext(lowered, "medbay") || findtext(lowered, "medical"))
		return sp_medbay_delivery_area()
	return null

/// Whether a botanist is already working on a request for this plant.
/proc/sp_plant_requested(plant)
	for(var/mob/living/carbon/human/crew as anything in SSspacestation_sp.ai_crew)
		var/datum/ai_controller/sp_crew/botanist/controller = crew.ai_controller
		if(istype(controller) && controller.blackboard[BB_SP_PLANT_REQUEST] == plant)
			return TRUE
	return FALSE

/// Produce we are carrying that somebody asked for, if anybody has.
/proc/sp_requested_produce(mob/living/carbon/human/botanist, datum/ai_controller/sp_crew/controller)
	var/list/obj/item/carried = sp_request_items(botanist, controller)
	return length(carried) ? carried[1] : null

/// Everything we carry for the request in hand: what it cooks into, if we have made that, then the plant itself.
/proc/sp_request_items(mob/living/carbon/human/botanist, datum/ai_controller/sp_crew/controller)
	var/list/obj/item/carried = list()
	var/plant = controller?.blackboard[BB_SP_PLANT_REQUEST]
	if(isnull(plant))
		return carried
	var/cooked_type = GLOB.sp_request_cooked_forms[plant]
	if(cooked_type)
		carried += botanist.get_all_contents_type(cooked_type)
	var/produce_type = GLOB.sp_requestable_plants[plant]
	if(produce_type)
		carried += botanist.get_all_contents_type(produce_type)
	return carried

/// The raw produce we carry for a request that still wants cooking before it is handed over.
/proc/sp_request_needs_cooking(mob/living/carbon/human/botanist, datum/ai_controller/sp_crew/controller)
	var/plant = controller?.blackboard[BB_SP_PLANT_REQUEST]
	if(isnull(plant) || isnull(GLOB.sp_request_cooked_forms[plant]))
		return list()
	var/produce_type = GLOB.sp_requestable_plants[plant]
	return produce_type ? botanist.get_all_contents_type(produce_type) : list()

/// Whether a microwave would take something and cook it right now.
/proc/sp_microwave_usable(obj/machinery/microwave/microwave)
	if(QDELETED(microwave) || !microwave.anchored || microwave.operating || microwave.broken || microwave.panel_open)
		return FALSE
	if(microwave.machine_stat & (NOPOWER|BROKEN))
		return FALSE
	// 100 is the microwave's MAX_MICROWAVE_DIRTINESS, which microwave.dm undefines behind itself.
	return microwave.dirty < 100 && !microwave.vampire_charging_enabled

/**
 * The nearest microwave on our level that would cook something for us now. Not sight-limited: the kitchen's
 * pair are a wall away from the hydroponics trays.
 */
/proc/sp_find_microwave(mob/living/carbon/human/botanist)
	var/turf/origin = get_turf(botanist)
	if(isnull(origin))
		return null
	var/obj/machinery/microwave/best
	var/best_distance = INFINITY
	for(var/obj/machinery/microwave/microwave as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/microwave))
		if(!sp_microwave_usable(microwave))
			continue
		var/turf/there = get_turf(microwave)
		if(there?.z != origin.z)
			continue
		var/distance = get_dist(origin, there)
		if(distance < best_distance)
			best = microwave
			best_distance = distance
	return best

/// A table in the area that asked for produce, to leave their delivery on.
/proc/sp_find_request_table(mob/living/carbon/human/botanist, area_type)
	var/turf/origin = get_turf(botanist)
	if(isnull(origin) || !ispath(area_type, /area))
		return null
	var/obj/structure/table/best
	var/best_distance = INFINITY
	for(var/turf/candidate as anything in get_area_turfs(area_type, origin.z))
		var/obj/structure/table/table = locate() in candidate
		if(isnull(table))
			continue
		var/distance = get_dist(origin, table)
		if(distance < best_distance)
			best = table
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
/proc/sp_buy_seed_packet(mob/living/carbon/human/botanist, obj/machinery/vending/hydroseeds/vendor, preferred_species)
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

	var/datum/data/vending_product/chosen
	// If somebody has asked for a plant we do not own, that is what the wages go on.
	if(preferred_species)
		for(var/datum/data/vending_product/record as anything in affordable)
			if(findtext(LOWER_TEXT(record.name), preferred_species))
				chosen = record
				break
	if(isnull(chosen))
		chosen = pick(affordable)
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

/**
 * Puts produce in a microwave the way a player does, one item in hand at a time, starts it, waits out the cook
 * and takes whatever `cooked_type` comes out. Returns what was taken. Sleeps for the whole cook, ten seconds or
 * so on a microwave nobody has upgraded.
 */
/proc/sp_cook_in_microwave(datum/ai_controller/controller, obj/machinery/microwave/microwave, list/obj/item/raw, cooked_type)
	var/mob/living/carbon/human/pawn = controller?.pawn
	var/list/obj/item/taken = list()
	if(!istype(pawn) || !sp_microwave_usable(microwave) || !microwave.Adjacent(pawn))
		return taken
	for(var/obj/item/produce as anything in raw)
		if(QDELETED(produce) || QDELETED(microwave) || length(microwave.ingredients) >= microwave.max_n_of_items)
			continue
		sp_free_hands(pawn)
		if(!pawn.put_in_active_hand(produce))
			continue
		sp_ai_click(controller, microwave)
	sp_free_hands(pawn)
	if(QDELETED(microwave) || !length(microwave.ingredients))
		return taken
	sp_ai_click(controller, microwave, list(RIGHT_CLICK = "1"))
	var/give_up_at = world.time + SP_MICROWAVE_WAIT
	UNTIL(QDELETED(microwave) || QDELETED(pawn) || !microwave.operating || world.time > give_up_at)
	if(QDELETED(microwave) || QDELETED(pawn))
		return taken
	// Never started, or stopped part way: get the produce back out rather than leave it in there.
	if(length(microwave.ingredients) && !microwave.operating)
		microwave.eject()
	var/turf/counter = get_turf(microwave)
	for(var/obj/item/result in counter)
		if(!istype(result, cooked_type))
			continue
		if(!(pawn.back && result.forceMove(pawn.back)) && !pawn.put_in_hands(result))
			continue
		taken += result
	for(var/obj/item/produce as anything in raw)
		if(!QDELETED(produce) && produce.loc == counter && !(pawn.back && produce.forceMove(pawn.back)))
			pawn.put_in_hands(produce)
	return taken

/// A table within a couple of tiles of `spot` and in the same room, to leave a delivery on rather than the floor.
/proc/sp_table_beside(turf/spot)
	var/area/room = get_area(spot)
	var/obj/structure/table/best
	var/best_distance = INFINITY
	for(var/obj/structure/table/table in range(2, spot))
		var/area/table_room = get_area(table)
		if(table_room != room)
			continue
		var/distance = get_dist(spot, table)
		if(distance < best_distance)
			best = table
			best_distance = distance
	return best

/// Tells a crew member something was left for them, so they go and fetch it from wherever it had to be put down.
/proc/sp_leave_for(mob/living/requester, list/obj/item/items)
	var/datum/ai_controller/their_ai = QDELETED(requester) ? null : requester.ai_controller
	if(isnull(their_ai))
		return
	for(var/obj/item/thing as anything in items)
		if(!QDELETED(thing))
			their_ai.set_blackboard_key_assoc_lazylist(BB_SP_LEFT_FOR_ME, thing, world.time + SP_LEFT_FOR_TIME)
