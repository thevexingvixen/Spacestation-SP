// Medbay: where it is, who counts as a patient, what to do with them, and the cryo tubes.

/// Rooms inside medical that are staff-only or have nothing to do with patients: nobody waits to be seen in a morgue.
GLOBAL_LIST_INIT(sp_not_medbay_areas, typecacheof(list(
	/area/station/medical/abandoned,
	/area/station/medical/break_room,
	/area/station/medical/chem_storage,
	/area/station/medical/chemistry,
	/area/station/medical/coldroom,
	/area/station/medical/morgue,
	/area/station/medical/office,
	/area/station/medical/pharmacy,
	/area/station/medical/psychology,
	/area/station/medical/storage,
	/area/station/medical/virology,
)))

/// Medkit stacks in the order a medic reaches for them. Gauze is left out: it dresses a wound, it heals nothing.
GLOBAL_LIST_INIT(sp_medkit_preference, list(
	/obj/item/stack/medical/suture/medicated,
	/obj/item/stack/medical/suture,
	/obj/item/stack/medical/bruise_pack,
	/obj/item/stack/medical/mesh/advanced,
	/obj/item/stack/medical/mesh,
	/obj/item/stack/medical/ointment,
	/obj/item/stack/medical/bandage,
	/obj/item/stack/medical/aloe,
))

/// Patches, by the chemical that says what they are for.
GLOBAL_LIST_INIT(sp_patch_chems, list(
	/datum/reagent/medicine/c2/libital = BRUTE,
	/datum/reagent/medicine/c2/aiuri = BURN,
))

/// Whether someone standing here has come to medbay: the lobby, the treatment floor, cryo, surgery, the wards.
/proc/sp_in_medbay(atom/thing)
	var/area/here = get_area(thing)
	return istype(here, /area/station/medical) && !is_type_in_typecache(here, GLOB.sp_not_medbay_areas)

/**
 * Where a delivery for medbay should go: the lobby, which anybody bringing something over can walk into, else the
 * treatment floor. Medics notice they are out wherever they happen to be, and in the first round with them roaming
 * one asked cargo from the fitness room and the other asked botany from the cargo warehouse, which is where the
 * crate and the aloe were then sent. Returns the lobby's type even on a map without one, so it reads the same in a test.
 */
/proc/sp_medbay_delivery_area()
	var/static/list/candidates = list(/area/station/medical/medbay/lobby, /area/station/medical/medbay/central)
	for(var/area_type in candidates)
		if(GLOB.areas_by_type[area_type])
			return area_type
	return candidates[1]

/// Brute plus burn: the damage a medkit, a patch or the cryo tubes can do something about.
/proc/sp_patch_damage(mob/living/patient)
	return patient.get_brute_loss() + patient.get_fire_loss()

/// Whether this crew member has something worth walking to medbay about.
/proc/sp_needs_checkup(mob/living/carbon/patient)
	if(!iscarbon(patient) || patient.stat == DEAD)
		return FALSE
	return sp_patch_damage(patient) >= SP_CHECKUP_DAMAGE || length(patient.all_wounds)

/// Whether anyone in medical, AI or player, is on their feet on this z-level to see a patient.
/proc/sp_medic_on_duty(atom/near)
	var/turf/here = get_turf(near)
	if(isnull(here))
		return FALSE
	for(var/mob/living/carbon/human/staff as anything in GLOB.human_list)
		if(staff == near || staff.stat != STABLE)
			continue
		var/datum/job/role = staff.mind?.assigned_role
		if(isnull(role) || !(/datum/job_department/medical in role.departments_list))
			continue
		var/turf/there = get_turf(staff)
		if(there?.z == here.z)
			return TRUE
	return FALSE

/**
 * Asks an AI patient to stay where they are while a medic works on them: a patient who wanders off
 * mid-stitch breaks the do_after and the medic has to start again. Players are left to their own judgement.
 */
/proc/sp_hold_still(mob/living/patient, mob/living/carer, duration = 30 SECONDS)
	var/datum/ai_controller/sp_crew/controller = patient?.ai_controller
	if(!istype(controller))
		return FALSE
	controller.set_blackboard_key(BB_SP_CARER, carer)
	controller.set_blackboard_key(BB_SP_CARE_UNTIL, world.time + duration)
	return TRUE

/// Lets a patient go again, if it was us holding them, and sees them out of medbay if they are inside it.
/proc/sp_release_patient(mob/living/patient, mob/living/carer)
	var/datum/ai_controller/sp_crew/controller = patient?.ai_controller
	if(!istype(controller))
		return
	sp_see_out(patient)
	if(controller.blackboard[BB_SP_CARER] != carer)
		return
	controller.clear_blackboard_key(BB_SP_CARER)
	controller.clear_blackboard_key(BB_SP_CARE_UNTIL)

/**
 * Lets a patient back out of medbay. Medics drag the badly hurt through doors only staff can open, into the cryo
 * tubes and onto the operating table, and a quartermaster who came out of cryo at full health spent the rest of the
 * round standing in the cryo room, unable to walk back to their console, while cargo's orders went unplaced. For a
 * few minutes their route may go through medbay's doors, and a medbay door they walk into opens for them, as if
 * the desk had buzzed them through (sp_buzz_through()).
 */
/proc/sp_see_out(mob/living/patient)
	var/datum/ai_controller/sp_crew/controller = patient?.ai_controller
	var/area/here = get_area(patient)
	if(!istype(controller) || !istype(here, /area/station/medical))
		return
	controller.set_blackboard_key(BB_SP_SHOWN_OUT_UNTIL, world.time + SP_SHOWN_OUT_TIME)

/**
 * A medbay door opening for a patient on their way out, the way the desk buzzes people through. Only medbay's own
 * doors, only while they are being seen out, and never one that is bolted or has no power. Returns TRUE if it opens.
 */
/proc/sp_buzz_through(mob/living/walker, obj/machinery/door/airlock/door)
	var/datum/ai_controller/sp_crew/controller = walker?.ai_controller
	if(!istype(controller) || controller.blackboard[BB_SP_SHOWN_OUT_UNTIL] <= world.time)
		return FALSE
	if(!door.density || door.locked || door.operating || !door.hasPower() || door.allowed(walker))
		return FALSE
	if(!door.check_access_list(SSid_access.get_region_access_list(list(REGION_MEDBAY))))
		return FALSE
	INVOKE_ASYNC(door, TYPE_PROC_REF(/obj/machinery/door, open))
	sp_record("crew.buzzed_through")
	log_sp("[walker.real_name] was buzzed through [door] in [get_area_name(door)]")
	return TRUE

// --- Restocking ------------------------------------------------------------------------------------

/// Uses of treatment a medic is carrying: every charge on every medical stack, plus one for each patch.
/proc/sp_medic_supply_count(mob/living/carbon/human/medic)
	. = 0
	for(var/obj/item/stack/medical/supplies as anything in medic.get_all_contents_type(/obj/item/stack/medical))
		. += supplies.amount
	. += length(medic.get_all_contents_type(/obj/item/reagent_containers/applicator/patch))

/// Whether a medic is low enough on treatment to go and find more of it.
/proc/sp_medic_low_on_supplies(mob/living/carbon/human/medic)
	return sp_medic_supply_count(medic) < SP_MEDIC_LOW_SUPPLIES

/// Whether a medic would restock with this: a medical stack, a patch, or a whole medkit.
/proc/sp_counts_as_supplies(obj/item/thing)
	return istype(thing, /obj/item/stack/medical) || istype(thing, /obj/item/reagent_containers/applicator/patch) || istype(thing, /obj/item/storage/medkit)

/// What in a locker or crate a medic would restock with.
/proc/sp_supplies_inside(obj/structure/closet/container)
	var/list/obj/item/found = list()
	for(var/obj/item/thing in container.contents)
		if(sp_counts_as_supplies(thing))
			found += thing
	return found

/**
 * Somewhere to restock from: the nearest locker or crate in sight with treatment supplies in it that we could
 * open, else supplies somebody left for us by name, else a crate cargo delivered for medbay.
 */
/proc/sp_find_supply_store(mob/living/carbon/human/medic, list/ignored, datum/ai_controller/controller)
	var/atom/movable/best
	var/best_distance = INFINITY
	for(var/obj/structure/closet/candidate in oview(SP_MEDIC_SIGHT, medic))
		if(!sp_worth_a_look(candidate, medic) || (ignored?[candidate] > world.time))
			continue
		if(!length(sp_supplies_inside(candidate)))
			continue
		var/distance = get_dist(medic, candidate)
		if(distance < best_distance)
			best = candidate
			best_distance = distance
	if(!isnull(best))
		return best
	var/turf/here = get_turf(medic)
	// Something left for us by name, botany's burn cream say, lying wherever the courier could get to.
	var/list/left_for_us = controller?.blackboard[BB_SP_LEFT_FOR_ME]
	for(var/obj/item/thing as anything in left_for_us)
		if(left_for_us[thing] < world.time || QDELETED(thing) || !isturf(thing.loc) || (ignored?[thing] > world.time))
			continue
		if(isnull(here) || thing.z != here.z || !sp_counts_as_supplies(thing))
			continue
		var/distance = get_dist(medic, thing)
		if(distance < best_distance)
			best = thing
			best_distance = distance
	if(!isnull(best))
		return best
	// Out of sight is fine for a crate cargo brought over for medbay: somebody asked for it, and the technician said
	// on the radio where it was left, which is often the far side of a door they could not open. Not while it is
	// still being dragged over, though.
	for(var/obj/structure/closet/crate/crate as anything in sp_delivered_crates(/datum/supply_pack/medical/supplies))
		if(!isnull(crate.pulledby) || !sp_worth_a_look(crate, medic) || (ignored?[crate] > world.time))
			continue
		var/turf/crate_turf = get_turf(crate)
		if(isnull(here) || crate_turf?.z != here.z || !length(sp_supplies_inside(crate)))
			continue
		var/distance = get_dist(medic, crate)
		if(distance < best_distance)
			best = crate
			best_distance = distance
	return best

/**
 * Empties what a medic needs out of a locker or crate: stacks, patches and medkits, up to a few. Returns
 * how many things were taken. Sleeps: a locked closet takes one click to unlock and another to open.
 */
/proc/sp_restock_from(datum/ai_controller/controller, obj/structure/closet/container)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || QDELETED(container) || !container.Adjacent(pawn))
		return 0
	sp_free_hands(pawn)
	// What we want, before it is opened: a closet tips everything onto the floor as it opens.
	var/list/obj/item/wanted = sp_supplies_inside(container)
	var/unlocked_it = FALSE
	if(container.locked)
		sp_ai_click(controller, container, list(RIGHT_CLICK = "1"))
		unlocked_it = !container.locked
	if(!container.opened)
		sp_ai_click(controller, container)
	if(!container.opened)
		sp_relock(controller, container, unlocked_it)
		return 0
	var/taken = 0
	var/list/names = list()
	for(var/obj/item/thing as anything in wanted)
		if(taken >= SP_RESTOCK_TAKE_LIMIT)
			break
		if(QDELETED(thing))
			continue
		if(!(pawn.back && thing.forceMove(pawn.back)) && !pawn.put_in_hands(thing))
			continue
		names |= thing.name
		taken++
	if(container.opened)
		sp_ai_click(controller, container)
	sp_relock(controller, container, unlocked_it)
	if(taken)
		sp_record("med.restocked", taken)
		log_sp("[pawn.real_name] restocked with [english_list(names)] from [container.name] in [get_area_name(container)]")
	return taken

/// Picks up supplies that were left out for us, botany's cream on a lobby table say. Returns 1 if we have them.
/proc/sp_pick_up_left_supplies(datum/ai_controller/controller, obj/item/thing)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || QDELETED(thing) || !isturf(thing.loc) || !thing.Adjacent(pawn))
		return 0
	var/where = get_area_name(thing)
	var/what = thing.name
	if(!(pawn.back && thing.forceMove(pawn.back)) && !pawn.put_in_hands(thing))
		return 0
	controller.remove_thing_from_blackboard_key(BB_SP_LEFT_FOR_ME, thing)
	sp_record("med.restocked")
	log_sp("[pawn.real_name] restocked with [what] left for them in [where]")
	return 1

// --- Triage ---------------------------------------------------------------------------------------

/// Whether a patient needs a medic at all: hurt enough to matter, bleeding, or down.
/proc/sp_needs_medic(mob/living/carbon/patient)
	if(!iscarbon(patient) || patient.stat == DEAD)
		return FALSE
	if(patient.stat != STABLE)
		return TRUE
	if(patient.get_brute_loss() >= SP_TREAT_DAMAGE || patient.get_fire_loss() >= SP_TREAT_DAMAGE)
		return TRUE
	if(patient.get_tox_loss() + patient.get_oxy_loss() >= SP_CRYO_INTERNAL_DAMAGE)
		return TRUE
	if(sp_needs_surgery(patient))
		return TRUE
	return patient.is_bleeding()

/**
 * What to do with a patient once they have been looked over. Serious cases go in the cryo tube when one is
 * ready. A surgeon operates on broken and dislocated bones, and on serious cases when no tube is ready.
 * Everybody else gets whatever the medkit has.
 */
/proc/sp_triage(mob/living/carbon/patient, cryo_ready = FALSE, can_operate = FALSE)
	if(!sp_needs_medic(patient))
		return SP_TRIAGE_NONE
	var/serious = patient.stat != STABLE || sp_patch_damage(patient) >= SP_CRYO_DAMAGE
	if(patient.get_tox_loss() + patient.get_oxy_loss() >= SP_CRYO_INTERNAL_DAMAGE)
		serious = TRUE
	if(serious && cryo_ready)
		return SP_TRIAGE_CRYO
	if(can_operate && (serious || sp_needs_surgery(patient)))
		return SP_TRIAGE_SURGERY
	return SP_TRIAGE_TREAT

/// How badly a limb wants seeing to: its damage, with bleeding counted heavily.
/proc/sp_limb_urgency(obj/item/bodypart/limb)
	return limb.brute_dam + limb.burn_dam + limb.cached_bleed_rate * 10

/proc/cmp_sp_limb_urgency(obj/item/bodypart/a, obj/item/bodypart/b)
	return sp_limb_urgency(b) - sp_limb_urgency(a)

/// The patient's limbs, worst first. Built fresh, because sorting the real list would reorder their body.
/proc/sp_limbs_by_damage(mob/living/carbon/patient)
	var/list/obj/item/bodypart/limbs = list()
	for(var/obj/item/bodypart/limb as anything in patient.get_bodyparts())
		limbs += limb
	return sortTim(limbs, GLOBAL_PROC_REF(cmp_sp_limb_urgency))

/// What a medic says reading a scan back to the patient: "25 brute, mostly your left arm".
/proc/sp_describe_injuries(mob/living/carbon/patient)
	var/list/parts = list()
	var/brute = round(patient.get_brute_loss(), 1)
	var/burn = round(patient.get_fire_loss(), 1)
	var/toxin = round(patient.get_tox_loss(), 1)
	var/suffocation = round(patient.get_oxy_loss(), 1)
	if(brute)
		parts += "[brute] brute"
	if(burn)
		parts += "[burn] burn"
	if(toxin)
		parts += "[toxin] toxin"
	if(suffocation)
		parts += "[suffocation] suffocation"
	if(patient.is_bleeding())
		parts += "some bleeding"
	if(LAZYLEN(patient.all_wounds))
		for(var/datum/wound/blunt/bone/bone in patient.all_wounds)
			parts += "a [LOWER_TEXT(bone.name)] in your [bone.limb.plaintext_zone]"
	if(!length(parts))
		return "not a scratch on you"
	. = english_list(parts)
	var/list/obj/item/bodypart/limbs = sp_limbs_by_damage(patient)
	var/obj/item/bodypart/worst = length(limbs) ? limbs[1] : null
	if(worst && worst.brute_dam + worst.burn_dam >= SP_TREAT_DAMAGE)
		. += ", mostly your [worst.plaintext_zone]"

/// Whether this medic carries anything to look a patient over or treat them with.
/proc/sp_medic_equipped(mob/living/carbon/human/medic)
	if(length(medic.get_all_contents_type(/obj/item/healthanalyzer)))
		return TRUE
	for(var/remedy_type in GLOB.sp_medkit_preference)
		if(length(medic.get_all_contents_type(remedy_type)))
			return TRUE
	return length(medic.get_all_contents_type(/obj/item/reagent_containers/applicator/patch)) > 0

/// Whether another AI medic already has this patient.
/proc/sp_patient_taken(mob/living/patient, mob/living/doctor)
	for(var/mob/living/carbon/human/other as anything in SSspacestation_sp.ai_crew)
		if(other == doctor || other.stat != STABLE)
			continue
		var/datum/ai_controller/their_ai = other.ai_controller
		if(their_ai && their_ai.blackboard[BB_SP_PATIENT] == patient)
			return TRUE
	return FALSE

/**
 * Who to see next: anybody hurt who has come into medbay, anybody hurt within sight of wherever we are, and
 * any player standing in medbay we have not scanned lately, so a player walking in gets looked at like
 * anyone else. Somebody down comes before everybody standing; then the worst hurt; then the nearest.
 */
/proc/sp_find_patient(mob/living/carbon/human/doctor, datum/ai_controller/controller)
	var/turf/here = get_turf(doctor)
	if(isnull(here))
		return null
	var/list/mob/living/carbon/human/candidates = list()
	for(var/mob/living/carbon/human/person in oview(SP_MEDIC_SIGHT, doctor))
		candidates |= person
	for(var/mob/living/carbon/human/person as anything in GLOB.human_list)
		if(person.z == here.z && sp_in_medbay(person))
			candidates |= person
	var/list/ignored = controller.blackboard[BB_SP_PATIENT_IGNORE]
	var/list/scanned = controller.blackboard[BB_SP_SCANNED]
	var/mob/living/carbon/human/best
	var/best_score = -INFINITY
	for(var/mob/living/carbon/human/person as anything in candidates)
		if(person == doctor || person.stat == DEAD || !isturf(person.loc))
			continue
		if(LAZYACCESS(ignored, person) > world.time || sp_patient_taken(person, doctor))
			continue
		var/score
		if(sp_needs_medic(person))
			// A broken bone and nothing else is the surgeon's; anybody else would only look and walk away.
			if(!sp_is_surgeon(doctor) && sp_only_needs_surgery(person))
				continue
			score = 100 + sp_patch_damage(person) + person.get_tox_loss() + person.get_oxy_loss()
			if(person.stat != STABLE)
				score += 400
		else if(person.client && sp_in_medbay(person) && world.time > (LAZYACCESS(scanned, person) || -SP_RESCAN_TIME) + SP_RESCAN_TIME)
			score = 0
		else
			continue
		score -= get_dist(doctor, person)
		if(score > best_score)
			best = person
			best_score = score
	return best

/// Stops working on a patient for a while: we could not get to them, or nothing we had would help.
/proc/sp_give_up_on_patient(datum/ai_controller/controller, mob/living/patient, reason, duration = SP_PATIENT_IGNORE_TIME)
	controller.set_blackboard_key_assoc_lazylist(BB_SP_PATIENT_IGNORE, patient, world.time + duration)
	controller.clear_blackboard_key(BB_SP_PATIENT)
	controller.clear_blackboard_key(BB_SP_PATIENT_ATTEMPT)
	controller.clear_blackboard_key(BB_SP_TREATMENT)
	controller.clear_blackboard_key(BB_SP_CRYO_CELL)
	sp_release_patient(patient, controller.pawn)
	log_sp("[controller.pawn] is leaving [patient] be for now: [reason]")

// --- Treatment ------------------------------------------------------------------------------------

/**
 * Whether a medkit stack would do anything for that part of the patient, as the stack itself judges it:
 * damage it heals, a burn it dresses, bleeding it stops, and skin it can get at through their clothes.
 */
/proc/sp_stack_can_treat(obj/item/stack/medical/stack, mob/living/doctor, mob/living/carbon/patient, zone)
	var/obj/item/stack/medical/mesh/mesh = stack
	if(istype(mesh) && !mesh.is_open)
		// A full mesh comes sealed in its packet, which the stack reads as unusable. Tearing it open is part
		// of using it, so judge it as the open mesh it is about to be.
		var/obj/item/bodypart/limb = patient.get_bodypart(zone)
		return !isnull(limb) && IS_ORGANIC_LIMB(limb) && limb.burn_dam > 0 && patient.try_inject(doctor, zone)
	return stack.try_heal_checks(patient, doctor, zone, silent = TRUE)

/// Whether a patch is worth putting on that limb: it treats what the limb has, and none is on there already.
/proc/sp_patch_can_treat(obj/item/reagent_containers/applicator/patch/patch, mob/living/carbon/patient, obj/item/bodypart/limb)
	if(!IS_ORGANIC_LIMB(limb))
		return FALSE
	if(LAZYLEN(limb.embedded_objects) && (locate(/obj/item/reagent_containers/applicator/patch) in limb.embedded_objects))
		return FALSE
	for(var/chem in GLOB.sp_patch_chems)
		if(!patch.reagents?.has_reagent(chem) || patient.reagents?.get_reagent_amount(chem) >= 5)
			continue
		var/damage = GLOB.sp_patch_chems[chem] == BRUTE ? limb.brute_dam : limb.burn_dam
		if(damage >= SP_TREAT_DAMAGE)
			return TRUE
	return FALSE

/**
 * The best thing we carry for the worst limb we can do anything about, as list(item, zone), or null.
 * Stacks first, since they work on the spot; patches for whatever the stacks cannot reach.
 */
/proc/sp_pick_treatment(mob/living/carbon/human/doctor, mob/living/carbon/patient)
	var/list/obj/item/stack/medical/stacks = list()
	for(var/remedy_type in GLOB.sp_medkit_preference)
		for(var/obj/item/stack/medical/stack as anything in doctor.get_all_contents_type(remedy_type))
			if(stack.amount > 0 && !(stack in stacks))
				stacks += stack
	var/list/obj/item/reagent_containers/applicator/patch/patches = doctor.get_all_contents_type(/obj/item/reagent_containers/applicator/patch)
	for(var/obj/item/bodypart/limb as anything in sp_limbs_by_damage(patient))
		for(var/obj/item/stack/medical/stack as anything in stacks)
			if(sp_stack_can_treat(stack, doctor, patient, limb.body_zone))
				return list(stack, limb.body_zone)
		for(var/obj/item/reagent_containers/applicator/patch/patch as anything in patches)
			if(sp_patch_can_treat(patch, patient, limb))
				return list(patch, limb.body_zone)
	return null

/// Puts one particular item we carry into our active hand, making room if we must. TRUE if it is there.
/proc/sp_take_in_hand(mob/living/carbon/human/pawn, obj/item/thing)
	if(QDELETED(thing))
		return FALSE
	if(pawn.get_active_held_item() == thing)
		return TRUE
	if(!pawn.is_holding(thing))
		var/obj/item/active = pawn.get_active_held_item()
		if(active && !(pawn.back && pawn.transferItemToLoc(active, pawn.back, silent = TRUE)))
			pawn.dropItemToGround(active)
		if(!pawn.put_in_active_hand(thing))
			return FALSE
	if(pawn.get_active_held_item() != thing)
		pawn.swap_hand()
	return pawn.get_active_held_item() == thing

/**
 * One round of treatment: aims at the worst limb we can do something for, puts the right thing in hand and
 * applies it. Sutures and mesh carry on across the body by themselves once started, so this waits for the
 * medic's hands to be free again before returning. Returns the type of what was used, or null if nothing we
 * carry would help. Sleeps.
 */
/proc/sp_treat_round(datum/ai_controller/controller, mob/living/carbon/patient)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/list/choice = sp_pick_treatment(pawn, patient)
	if(isnull(choice))
		return null
	var/obj/item/remedy = choice[1]
	var/zone = choice[2]
	var/remedy_type = remedy.type
	sp_hold_still(patient, pawn)
	if(!sp_take_in_hand(pawn, remedy))
		return null
	var/obj/item/stack/medical/mesh/mesh = remedy
	if(istype(mesh) && !mesh.is_open)
		// Clicking what is in your own hand uses it on itself, which tears the packet open.
		sp_ai_click(controller, mesh)
	// The heal goes wherever the medic is aiming. Nothing used to set this for AI medics, so they always aimed
	// at the chest, and a patient whose chest was fine — a cut arm, say — got no treatment at all.
	pawn.zone_selected = zone
	pawn.face_atom(patient)
	sp_ai_click(controller, patient)
	// A medkit stack runs its heal loop after the click returns; a patch is on by the time the click is done.
	var/give_up_at = world.time + 30 SECONDS
	while(!QDELETED(pawn) && !QDELETED(patient) && DOING_INTERACTION_WITH_TARGET(pawn, patient) && world.time < give_up_at)
		sleep(0.5 SECONDS)
	return remedy_type

// --- Cryo -----------------------------------------------------------------------------------------

/// The tube's own gas: what its occupant breathes, and what cools them.
/proc/sp_cryo_air(obj/machinery/cryo_cell/cryo)
	var/datum/gas_machine_connector/connector = cryo.internal_connector
	if(isnull(connector) || isnull(connector.gas_connector))
		return null
	return connector.gas_connector.airs[1]

/// Cryoxadone in a container, in units.
/proc/sp_cryoxadone_units(atom/movable/container)
	return container?.reagents?.get_reagent_amount(/datum/reagent/medicine/cryoxadone) || 0

/// Whether the tube has medicine left to give.
/proc/sp_cryo_has_medicine(obj/machinery/cryo_cell/cryo)
	return !QDELETED(cryo.beaker) && sp_cryoxadone_units(cryo.beaker) >= SP_CRYO_MIN_REAGENT

/// Whether the loop behind a tube has gas in it and is cold enough for cryoxadone to work.
/proc/sp_cryo_gas_ready(obj/machinery/cryo_cell/cryo)
	var/datum/gas_mixture/air = sp_cryo_air(cryo)
	if(isnull(air) || isnull(cryo.internal_connector.gas_connector.nodes[1]))
		return FALSE
	return air.total_moles() >= SP_CRYO_MIN_MOLES && air.temperature < T0C

/// Whether a tube could take a patient right now: working, empty, stocked, gassed and cold.
/proc/sp_cryo_ready(obj/machinery/cryo_cell/cryo)
	if(QDELETED(cryo) || !cryo.is_operational || cryo.panel_open || !isnull(cryo.occupant))
		return FALSE
	return sp_cryo_has_medicine(cryo) && sp_cryo_gas_ready(cryo)

/// Every cryo tube in medbay on this z-level.
/proc/sp_medbay_cryo_cells(atom/near)
	var/list/obj/machinery/cryo_cell/cells = list()
	var/turf/here = get_turf(near)
	if(isnull(here))
		return cells
	for(var/obj/machinery/cryo_cell/cryo as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/cryo_cell))
		if(cryo.z == here.z && sp_in_medbay(cryo))
			cells += cryo
	return cells

/// The nearest tube ready for a patient, or null.
/proc/sp_find_cryo_cell(atom/near)
	var/obj/machinery/cryo_cell/best
	for(var/obj/machinery/cryo_cell/cryo as anything in sp_medbay_cryo_cells(near))
		if(!sp_cryo_ready(cryo))
			continue
		if(isnull(best) || get_dist(near, cryo) < get_dist(near, best))
			best = cryo
	return best

/**
 * Puts a patient we are pulling into a cryo tube the way a doctor does it: open the tube, drag them onto
 * it, shut it. The tube switches itself on once it has an occupant. Somebody out cold can be lifted in with
 * TG's drag-and-drop instead, which is only allowed for the incapacitated. Returns how they went in, or
 * null if they did not. Sleeps.
 */
/proc/sp_load_into_cryo(datum/ai_controller/controller, mob/living/carbon/patient, obj/machinery/cryo_cell/cryo)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(QDELETED(patient) || QDELETED(cryo) || !isnull(cryo.occupant))
		return null
	sp_hold_still(patient, pawn, SP_CRYO_STAY)
	if(!cryo.state_open)
		sp_ai_click(controller, cryo, list(ALT_CLICK = TRUE))
	if(!cryo.state_open)
		return null
	var/turf/tube_turf = get_turf(cryo)
	for(var/step in 1 to 3)
		if(get_turf(patient) == tube_turf || pawn.pulling != patient)
			break
		pawn.Move_Pulled(tube_turf)
		sleep(0.2 SECONDS)
	var/how
	if(get_turf(patient) == tube_turf)
		// Shutting the lid takes whoever is lying in the tube.
		sp_ai_click(controller, cryo, list(ALT_CLICK = TRUE))
		how = "dragged"
	else if(patient.incapacitated && pawn.Adjacent(patient))
		sp_ai_drag_onto(controller, patient, cryo)
		how = "lifted"
	if(pawn.pulling == patient)
		pawn.stop_pulling()
	return patient.loc == cryo ? how : null

// --- Cryo setup -----------------------------------------------------------------------------------

/// A cryoxadone container we carry with enough left in it to be worth putting in a tube.
/proc/sp_carried_cryoxadone(mob/living/carbon/human/doctor)
	for(var/obj/item/reagent_containers/cup/cup as anything in doctor.get_all_contents_type(/obj/item/reagent_containers/cup))
		if(sp_cryoxadone_units(cup) >= SP_CRYO_MIN_REAGENT)
			return cup
	return null

/// The nearest loose item of a type in a room — on the floor or a table, not in anybody's hands or bags.
/proc/sp_find_loose_in_room(area/room, z, item_type, atom/near, needs_cryoxadone = FALSE)
	var/obj/item/best
	for(var/turf/spot as anything in get_area_turfs(room.type, z))
		for(var/obj/item/thing in spot)
			if(!istype(thing, item_type))
				continue
			if(needs_cryoxadone && sp_cryoxadone_units(thing) < SP_CRYO_MIN_REAGENT)
				continue
			if(isnull(best) || get_dist(near, thing) < get_dist(near, best))
				best = thing
	return best

/// A canister in the cryo room sitting on its port but not connected: how both of MetaStation's start the shift.
/proc/sp_find_cryo_canister(area/room, z)
	for(var/obj/machinery/portable_atmospherics/canister/canister as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/portable_atmospherics/canister))
		if(canister.z != z || get_area(canister) != room || !isnull(canister.connected_port))
			continue
		if(canister.air_contents.total_moles() < 100)
			continue
		if(locate(/obj/machinery/atmospherics/components/unary/portables_connector) in get_turf(canister))
			return canister
	return null

/// The freezers in the cryo room.
/proc/sp_cryo_freezers(area/room, z)
	var/list/obj/machinery/atmospherics/components/unary/thermomachine/found = list()
	for(var/obj/machinery/atmospherics/components/unary/thermomachine/machine as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/atmospherics/components/unary/thermomachine))
		if(machine.z == z && get_area(machine) == room)
			found += machine
	return found

/**
 * The next thing the cryo tubes need before they can take a patient, as list(task, target), or null when
 * there is nothing we can do: they are ready, they are still cooling, or what they lack is not in the room.
 * Gas comes first. On MetaStation the loop starts the shift empty, with both canisters sitting on their
 * ports unconnected, and a tube with no gas throws its patient straight back out.
 */
/proc/sp_next_cryo_task(mob/living/carbon/human/doctor)
	var/list/obj/machinery/cryo_cell/cells = sp_medbay_cryo_cells(doctor)
	if(!length(cells))
		return null
	var/obj/machinery/cryo_cell/first = cells[1]
	var/area/room = get_area(first)
	var/z = first.z

	var/datum/gas_mixture/air = sp_cryo_air(first)
	if(isnull(air) || air.total_moles() < SP_CRYO_MIN_MOLES)
		var/obj/machinery/portable_atmospherics/canister/canister = sp_find_cryo_canister(room, z)
		if(canister)
			if(length(doctor.get_all_contents_type(/obj/item/wrench)))
				return list(SP_CRYO_TASK_CONNECT_GAS, canister)
			var/obj/item/wrench/wrench = sp_find_loose_in_room(room, z, /obj/item/wrench, doctor)
			if(wrench)
				return list(SP_CRYO_TASK_GET_WRENCH, wrench)

	for(var/obj/machinery/atmospherics/components/unary/thermomachine/freezer as anything in sp_cryo_freezers(room, z))
		if(!freezer.anchored || freezer.panel_open || !freezer.is_operational)
			continue
		if(!freezer.on || freezer.target_temperature != freezer.min_temperature)
			return list(SP_CRYO_TASK_FREEZER, freezer)

	for(var/obj/machinery/cryo_cell/cryo as anything in cells)
		if(!cryo.is_operational || sp_cryo_has_medicine(cryo))
			continue
		if(!isnull(sp_carried_cryoxadone(doctor)))
			return list(SP_CRYO_TASK_LOAD_BEAKER, cryo)
		var/obj/item/fresh = sp_find_loose_in_room(room, z, /obj/item/reagent_containers/cup, doctor, needs_cryoxadone = TRUE)
		if(fresh)
			return list(SP_CRYO_TASK_GET_BEAKER, fresh)
		break
	return null

/// Does one cryo setup job with the tool and the clicks a doctor would use. TRUE if it took. Sleeps.
/proc/sp_do_cryo_job(datum/ai_controller/controller, task, atom/target)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(QDELETED(target))
		return FALSE
	switch(task)
		if(SP_CRYO_TASK_GET_WRENCH, SP_CRYO_TASK_GET_BEAKER)
			// An empty hand on something lying about picks it up.
			sp_free_hands(pawn)
			sp_ai_click(controller, target)
			return pawn.is_holding(target)

		if(SP_CRYO_TASK_CONNECT_GAS)
			var/obj/machinery/portable_atmospherics/canister/canister = target
			var/list/obj/item/wrench/wrenches = pawn.get_all_contents_type(/obj/item/wrench)
			if(!length(wrenches) || !sp_take_in_hand(pawn, wrenches[1]))
				return FALSE
			sp_ai_click(controller, canister)
			return !isnull(canister.connected_port)

		if(SP_CRYO_TASK_FREEZER)
			var/obj/machinery/atmospherics/components/unary/thermomachine/freezer = target
			// Alt-click steps the target through room temperature, the machine's hottest and its coldest, in that
			// order, so a fresh freezer takes two. Stop as soon as it reads coldest rather than counting clicks.
			for(var/click in 1 to 3)
				if(freezer.target_temperature == freezer.min_temperature)
					break
				sp_ai_click(controller, freezer, list(ALT_CLICK = TRUE))
			if(!freezer.on)
				sp_ai_click(controller, freezer, list(CTRL_CLICK = TRUE))
			return freezer.on && freezer.target_temperature == freezer.min_temperature

		if(SP_CRYO_TASK_LOAD_BEAKER)
			var/obj/machinery/cryo_cell/cryo = target
			var/obj/item/reagent_containers/cup/beaker = sp_carried_cryoxadone(pawn)
			if(isnull(beaker))
				return FALSE
			if(!QDELETED(cryo.beaker))
				// A spent beaker comes out first, the way the tube's eject button would hand it over.
				var/obj/item/spent = cryo.beaker
				if(!pawn.put_in_hands(spent))
					spent.forceMove(get_turf(pawn))
			if(!sp_take_in_hand(pawn, beaker))
				return FALSE
			sp_ai_click(controller, cryo)
			return cryo.beaker == beaker
	return FALSE

/// Tells medbay the tubes are set up, once a round.
/proc/sp_announce_cryo_ready(mob/living/carbon/human/medic)
	var/static/announced = FALSE
	if(announced)
		return
	announced = TRUE
	sp_crew_speak(medic, "Cryo's set up. The loop needs a minute to get cold.", RADIO_CHANNEL_MEDICAL)

// --- Surgery --------------------------------------------------------------------------------------

/// The surgical tools a surgeon keeps about them, by tool behaviour or item type. A doctor's own medkit has
/// the first three; the rest come off a surgery tray in the theatre.
GLOBAL_LIST_INIT(sp_surgical_kit, list(
	TOOL_SCALPEL,
	TOOL_HEMOSTAT,
	TOOL_CAUTERY,
	TOOL_RETRACTOR,
	TOOL_BONESET,
	/obj/item/stack/medical/bone_gel,
))

/// Whether this medic may operate. Surgery is the doctors' and the CMO's.
/proc/sp_is_surgeon(mob/living/carbon/human/medic)
	var/datum/job/role = medic.mind?.assigned_role
	return istype(role, /datum/job/doctor) || istype(role, /datum/job/chief_medical_officer)

/// Whether a patient has something only the table fixes properly: a dislocated or broken bone.
/proc/sp_needs_surgery(mob/living/carbon/patient)
	return iscarbon(patient) && LAZYLEN(patient.all_wounds) && !isnull(locate(/datum/wound/blunt/bone) in patient.all_wounds)

/// A broken or dislocated bone and nothing a medkit or a cryo tube would be wanted for.
/proc/sp_only_needs_surgery(mob/living/carbon/patient)
	if(!sp_needs_surgery(patient) || patient.stat != STABLE || patient.is_bleeding())
		return FALSE
	if(patient.get_brute_loss() >= SP_TREAT_DAMAGE || patient.get_fire_loss() >= SP_TREAT_DAMAGE)
		return FALSE
	return patient.get_tox_loss() + patient.get_oxy_loss() < SP_CRYO_INTERNAL_DAMAGE

/// How many broken or dislocated bones a patient has.
/proc/sp_bone_wound_count(mob/living/carbon/patient)
	. = 0
	if(!iscarbon(patient) || !LAZYLEN(patient.all_wounds))
		return
	for(var/datum/wound/blunt/bone/bone in patient.all_wounds)
		.++

/// What to call a tool kind in a log line: a tool behaviour already reads as a word; an item type needs its name.
/proc/sp_tool_kind_name(kind)
	if(!ispath(kind))
		return kind
	var/obj/item/kind_type = kind
	return initial(kind_type.name)

/// Whether a tool does this job: an item of a type, or anything with that tool behaviour.
/proc/sp_tool_does(obj/item/thing, kind)
	return ispath(kind) ? istype(thing, kind) : thing.tool_behaviour == kind

/// The first thing we carry that does one of these jobs, in order of preference.
/proc/sp_find_tool(mob/living/carbon/human/surgeon, list/kinds)
	var/list/obj/item/carried = surgeon.get_all_contents_type(/obj/item)
	for(var/kind in kinds)
		for(var/obj/item/thing as anything in carried)
			if(sp_tool_does(thing, kind))
				return thing
	return null

/// The tools each procedure on this patient needs, start to finish, as a list of lists of alternatives.
/proc/sp_surgery_needs(mob/living/carbon/patient)
	var/list/needed = list()
	var/cuts = FALSE
	if(LAZYLEN(patient.all_wounds))
		for(var/datum/wound/blunt/bone/bone in patient.all_wounds)
			if(istype(bone, /datum/wound/blunt/bone/critical))
				needed += list(list(TOOL_RETRACTOR), list(TOOL_HEMOSTAT), list(TOOL_BONESET, /obj/item/stack/medical/wrap/sticky_tape/surgical), list(/obj/item/stack/medical/bone_gel, /obj/item/stack/medical/wrap/sticky_tape/surgical))
				cuts = TRUE
			else if(istype(bone, /datum/wound/blunt/bone/severe))
				needed += list(list(TOOL_SCALPEL), list(TOOL_BONESET, /obj/item/stack/medical/bone_gel, /obj/item/stack/medical/wrap/sticky_tape/surgical))
				cuts = TRUE
			else
				needed += list(list(TOOL_BONESET))
	if(sp_patch_damage(patient) >= SP_CRYO_DAMAGE)
		needed += list(list(TOOL_SCALPEL), list(TOOL_HEMOSTAT))
		cuts = TRUE
	if(cuts)
		needed += list(list(TOOL_CAUTERY, /obj/item/stack/medical/suture))
	return needed

/// Whether we carry what it takes to see this patient's operation through, so nobody is left cut open halfway.
/proc/sp_surgery_feasible(mob/living/carbon/human/surgeon, mob/living/carbon/patient)
	var/list/needed = sp_surgery_needs(patient)
	if(!length(needed))
		return FALSE
	for(var/list/any_of in needed)
		if(isnull(sp_find_tool(surgeon, any_of)))
			return FALSE
	return TRUE

/// The nearest operating table in medbay with nobody on it.
/proc/sp_find_optable(atom/near)
	var/turf/here = get_turf(near)
	if(isnull(here))
		return null
	var/obj/structure/table/optable/best
	for(var/turf/spot as anything in get_area_turfs(/area/station/medical/surgery, here.z, TRUE))
		var/obj/structure/table/optable/table = locate() in spot
		if(isnull(table) || table.has_buckled_mobs() || !isnull(table.patient))
			continue
		if(isnull(best) || get_dist(near, table) < get_dist(near, best))
			best = table
	return best

/// The tools on a surgery tray that do any of these jobs, one per job.
/proc/sp_tray_tools(obj/item/surgery_tray/tray, list/kinds)
	var/list/obj/item/found = list()
	for(var/kind in kinds)
		for(var/obj/item/thing in tray.contents)
			if(!(thing in found) && sp_tool_does(thing, kind))
				found += thing
				break
	return found

/// The jobs in the surgical kit we have nothing for.
/proc/sp_missing_surgical_kit(mob/living/carbon/human/surgeon)
	var/list/missing = list()
	for(var/kind in GLOB.sp_surgical_kit)
		if(isnull(sp_find_tool(surgeon, list(kind))))
			missing += kind
	return missing

/// The nearest surgery tray in the theatres with something on it we are missing.
/proc/sp_find_surgery_tray(atom/near, list/kinds)
	var/turf/here = get_turf(near)
	if(isnull(here) || !length(kinds))
		return null
	var/obj/item/surgery_tray/best
	for(var/turf/spot as anything in get_area_turfs(/area/station/medical/surgery, here.z, TRUE))
		for(var/obj/item/surgery_tray/tray in spot)
			if(!length(sp_tray_tools(tray, kinds)) || isnull(sp_reach_spot(tray, near)))
				continue
			if(isnull(best) || get_dist(near, tray) < get_dist(near, best))
				best = tray
	return best

/**
 * The next operation a patient on the table needs, as list(operation type, zone, tools that will do it,
 * damage type to tend), or null when there is nothing left but to let them up. Worked out afresh each time
 * from the limbs themselves — skin, vessels and bones are all recorded on the limb — so an operation that
 * is interrupted picks up where it left off. Bones first, then serious damage tended through the chest,
 * then closing up whatever is open.
 */
/proc/sp_next_operation(mob/living/carbon/patient, closing_only = FALSE)
	if(!closing_only)
		for(var/obj/item/bodypart/limb as anything in patient.get_bodyparts())
			var/datum/wound/blunt/bone/bone = LAZYLEN(limb.wounds) ? (locate(/datum/wound/blunt/bone) in limb.wounds) : null
			if(isnull(bone))
				continue
			var/zone = limb.body_zone
			var/state = limb.surgery_state
			if(istype(bone, /datum/wound/blunt/bone/critical))
				// A compound fracture has already cut the skin open for us.
				var/datum/wound/blunt/bone/critical/fracture = bone
				if(!HAS_ANY_SURGERY_STATE(state, ALL_SURGERY_SKIN_STATES))
					return list(/datum/surgery_operation/limb/incise_skin, zone, list(TOOL_SCALPEL))
				if(!HAS_SURGERY_STATE(state, SURGERY_SKIN_OPEN))
					return list(/datum/surgery_operation/limb/retract_skin, zone, list(TOOL_RETRACTOR))
				if(HAS_SURGERY_STATE(state, SURGERY_VESSELS_UNCLAMPED))
					return list(/datum/surgery_operation/limb/clamp_bleeders, zone, list(TOOL_HEMOSTAT))
				if(!fracture.reset)
					return list(/datum/surgery_operation/limb/reset_compound, zone, list(TOOL_BONESET, /obj/item/stack/medical/wrap/sticky_tape/surgical))
				return list(/datum/surgery_operation/limb/repair_compound, zone, list(/obj/item/stack/medical/bone_gel, /obj/item/stack/medical/wrap/sticky_tape/surgical))
			if(istype(bone, /datum/wound/blunt/bone/severe))
				if(!HAS_ANY_SURGERY_STATE(state, ALL_SURGERY_SKIN_STATES))
					return list(/datum/surgery_operation/limb/incise_skin, zone, list(TOOL_SCALPEL))
				return list(/datum/surgery_operation/limb/repair_hairline, zone, list(TOOL_BONESET, /obj/item/stack/medical/bone_gel, /obj/item/stack/medical/wrap/sticky_tape/surgical))
			// Anything milder is a dislocation, which a bonesetter puts back without cutting at all.
			return list(/datum/surgery_operation/limb/repair_dislocation, zone, list(TOOL_BONESET))

		var/obj/item/bodypart/chest = patient.get_bodypart(BODY_ZONE_CHEST)
		var/chest_open = LIMB_HAS_ANY_SURGERY_STATE(chest, ALL_SURGERY_SKIN_STATES)
		// Serious bruising and burns are tended through an incision in the chest; once it is open, finish the job.
		if(chest && (sp_patch_damage(patient) >= SP_CRYO_DAMAGE || (chest_open && sp_patch_damage(patient) > 0)))
			if(!chest_open)
				return list(/datum/surgery_operation/limb/incise_skin, BODY_ZONE_CHEST, list(TOOL_SCALPEL))
			return list(/datum/surgery_operation/basic/tend_wounds, BODY_ZONE_CHEST, list(TOOL_HEMOSTAT), patient.get_brute_loss() > 0 ? BRUTE : BURN)

	for(var/obj/item/bodypart/limb as anything in patient.get_bodyparts())
		if(LIMB_HAS_ANY_SURGERY_STATE(limb, ALL_SURGERY_SKIN_STATES))
			return list(/datum/surgery_operation/limb/close_skin, limb.body_zone, list(TOOL_CAUTERY, /obj/item/stack/medical/suture))
	return null

/**
 * Performs one operation on the patient with a tool we carry. TG has the surgeon pick the operation off a
 * radial menu whenever more than one fits the tool and the spot, and a mob with no client gets no menu at
 * all, so this finds the operation we want among those on offer and starts it the way the menu would.
 * Returns TRUE if it went ahead. Sleeps.
 */
/proc/sp_perform_operation(datum/ai_controller/controller, mob/living/carbon/patient, list/next_step)
	var/mob/living/carbon/human/surgeon = controller.pawn
	var/datum/surgery_operation/operation_type = next_step[1]
	var/zone = next_step[2]
	var/heal_type = length(next_step) >= 4 ? next_step[4] : null
	var/obj/item/tool = sp_find_tool(surgeon, next_step[3])
	if(isnull(tool) || !sp_take_in_hand(surgeon, tool))
		log_sp("[surgeon.real_name] has nothing to [initial(operation_type.name)] with")
		return FALSE
	surgeon.zone_selected = zone
	surgeon.face_atom(patient)
	var/list/options = surgeon.get_available_operations(patient, tool, zone)
	for(var/choice in options)
		var/list/entry = options[choice]
		var/datum/surgery_operation/operation = entry[1]
		if(!istype(operation, operation_type))
			continue
		var/list/info = entry[3]
		if(heal_type && !(info[heal_type == BRUTE ? OPERATION_BRUTE_HEAL : OPERATION_BURN_HEAL] > 0))
			continue
		info[OPERATION_TARGET_ZONE] = zone
		info[OPERATION_FORCE_FAIL] = FALSE
		var/result = operation.try_perform(entry[2], surgeon, tool, info)
		log_sp("[surgeon.real_name]: [operation.name] on [patient.real_name]'s [parse_zone(zone)] [(result & ITEM_INTERACT_SUCCESS) ? "done" : "did not take"]")
		return TRUE
	log_sp("[surgeon.real_name] could not [initial(operation_type.name)] on [patient.real_name]'s [parse_zone(zone)] with [tool.name]")
	return FALSE

/**
 * Gets clothing out of the way of the knife the way a surgeon would: a jumpsuit is rolled down off the chest
 * and arms, and anything else over the spot comes off. Returns what was moved as list(item, slot) pairs for
 * sp_redress() to put back; a null slot means rolled down. Nothing hanging off the jumpsuit — ID, belt,
 * pockets — is dropped with it.
 */
/proc/sp_expose_for_surgery(mob/living/carbon/human/surgeon, mob/living/carbon/human/patient, zone)
	var/list/moved = list()
	if(!istype(patient))
		return moved
	for(var/attempt in 1 to 5)
		if(patient.is_location_accessible(zone, IGNORED_OPERATION_CLOTHING_SLOTS))
			break
		var/obj/item/in_the_way
		for(var/obj/item/worn in patient.get_equipped_items())
			if((worn.slot_flags & IGNORED_OPERATION_CLOTHING_SLOTS) || (worn.flags_cover & ALLOW_SURGERY_THROUGH))
				continue
			if(zone in cover_flags2body_zones(worn.body_parts_covered))
				in_the_way = worn
				break
		if(isnull(in_the_way))
			break
		var/obj/item/clothing/under/jumpsuit = in_the_way
		if(istype(jumpsuit) && jumpsuit.can_adjust && jumpsuit.adjusted == NORMAL_STYLE && !jumpsuit.alt_covers_chest && (zone in list(BODY_ZONE_CHEST, BODY_ZONE_L_ARM, BODY_ZONE_R_ARM)))
			jumpsuit.toggle_jumpsuit_adjust()
			patient.update_worn_undersuit()
			surgeon.visible_message(span_notice("[surgeon] rolls down [patient]'s [jumpsuit.name]."))
			moved += list(list(jumpsuit, null))
			continue
		var/slot = patient.get_slot_by_item(in_the_way)
		if(!patient.dropItemToGround(in_the_way, silent = TRUE, invdrop = FALSE))
			break
		surgeon.visible_message(span_notice("[surgeon] takes off [patient]'s [in_the_way.name]."))
		moved += list(list(in_the_way, slot))
	return moved

/// Puts back what sp_expose_for_surgery() moved: jumpsuits rolled back up, everything else back on.
/proc/sp_redress(mob/living/carbon/human/patient, list/moved)
	if(!istype(patient))
		return
	for(var/index in length(moved) to 1 step -1)
		var/list/entry = moved[index]
		var/obj/item/thing = entry[1]
		var/slot = entry[2]
		if(QDELETED(thing))
			continue
		if(isnull(slot))
			var/obj/item/clothing/under/jumpsuit = thing
			if(istype(jumpsuit) && patient.w_uniform == jumpsuit && jumpsuit.adjusted == ALT_STYLE)
				jumpsuit.toggle_jumpsuit_adjust()
				patient.update_worn_undersuit()
			continue
		if(!isturf(thing.loc) || get_dist(thing, patient) > 1)
			continue
		patient.equip_to_slot_if_possible(thing, slot, disable_warning = TRUE, bypass_equip_delay_self = TRUE, indirect_action = TRUE)

/**
 * Steps somebody we are pulling onto a free tile beside `target` that is still beside us, the way a player
 * drags a patient into position. Returns TRUE once they are next to it. Sleeps.
 */
/proc/sp_bring_alongside(mob/living/carbon/human/pawn, mob/living/patient, atom/target)
	var/turf/target_turf = get_turf(target)
	for(var/attempt in 1 to 3)
		if(patient.Adjacent(target) || pawn.pulling != patient)
			break
		var/turf/best
		for(var/turf/open/spot in orange(1, target_turf))
			if(spot == get_turf(pawn) || get_dist(spot, pawn) > 1 || spot.is_blocked_turf(exclude_mobs = FALSE, source_atom = patient))
				continue
			if(isnull(best) || get_dist(spot, patient) < get_dist(best, patient))
				best = spot
		if(isnull(best))
			break
		pawn.Move_Pulled(best)
		sleep(0.2 SECONDS)
	return patient.Adjacent(target)

/**
 * Operates on a patient we have brought to the table: lays them on it, gets clothes out of the way, works
 * through sp_next_operation() until there is nothing left, then dresses them and lets them up. Returns how
 * many operations were done. Sleeps.
 */
/proc/sp_do_surgery(datum/ai_controller/controller, mob/living/carbon/human/patient, obj/structure/table/optable/table)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(QDELETED(patient) || QDELETED(table))
		return 0
	sp_hold_still(patient, pawn, 5 MINUTES)
	// Being strapped to the table is what readies every limb for the knife (TG's free_operation), no drapes needed.
	// TG only straps down somebody standing beside the table, and a patient in tow trails a tile behind the
	// surgeon, so they get stepped up alongside it first.
	if(patient.buckled != table)
		sp_bring_alongside(pawn, patient, table)
		sp_ai_drag_onto(controller, patient, table)
	if(pawn.pulling == patient)
		pawn.stop_pulling()
	if(patient.buckled != table)
		log_sp("[pawn.real_name] could not get [patient.real_name] onto [table.name]")
		return 0
	var/list/moved = list()
	var/operations = 0
	var/list/last_step
	var/repeats = 0
	for(var/step_number in 1 to SP_SURGERY_MAX_STEPS)
		if(QDELETED(patient) || patient.stat == DEAD || patient.buckled != table || !pawn.Adjacent(patient))
			break
		var/list/next_step = sp_next_operation(patient)
		if(isnull(next_step))
			break
		// The same step twice over means it keeps failing; give up rather than keep cutting.
		if(last_step && last_step[1] == next_step[1] && last_step[2] == next_step[2] && (length(last_step) >= 4 ? last_step[4] : null) == (length(next_step) >= 4 ? next_step[4] : null))
			if(++repeats >= 2)
				var/datum/surgery_operation/failing = next_step[1]
				log_sp("[pawn.real_name] keeps failing to [initial(failing.name)] on [patient.real_name]; closing up")
				break
		else
			repeats = 0
		last_step = next_step
		moved += sp_expose_for_surgery(pawn, patient, next_step[2])
		if(!sp_perform_operation(controller, patient, next_step))
			break
		operations++
	// Whatever else went wrong, nobody leaves the table cut open.
	for(var/closing_step in 1 to 6)
		if(QDELETED(patient) || patient.buckled != table)
			break
		var/list/closing = sp_next_operation(patient, closing_only = TRUE)
		if(isnull(closing))
			break
		moved += sp_expose_for_surgery(pawn, patient, closing[2])
		if(!sp_perform_operation(controller, patient, closing))
			break
		operations++
	if(QDELETED(patient))
		return operations
	sp_redress(patient, moved)
	if(patient.buckled == table)
		table.user_unbuckle_mob(patient, pawn)
	sp_release_patient(patient, pawn)
	return operations
