// Behaviour-tree leaves, decorators and subtrees for medbay: the patient's side of it, and the staff's.

// --- Subtree declarations (trees live next to this file) --------------------------------------

/// A medic is working on us, or we are lying in a cryo tube or on the operating table: hold still.
/datum/bt_node/subtree/sp_crew_patient
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_patient.bt.json"

/// Nothing better to do and carrying an injury: walk to medbay and wait to be seen.
/datum/bt_node/subtree/sp_crew_checkup
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_checkup.bt.json"

/// Medical: see to the worst-off patient — walk over, look them over, then patch them up or take them to cryo.
/datum/bt_node/subtree/sp_medical_patient
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_medical_patient.bt.json"

/// Medical: get the cryo tubes ready — gas on, freezer cold, a beaker in every tube.
/datum/bt_node/subtree/sp_medical_cryo_setup
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_medical_cryo_setup.bt.json"

/// Surgeons: fetch the tools a doctor's medkit does not have from a surgery tray in the theatre.
/datum/bt_node/subtree/sp_medical_surgical_kit
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_medical_surgical_kit.bt.json"

// --- The patient's side -----------------------------------------------------------------------

/**
 * Passes while we are being treated. TG's escape_captivity subtree reads a cryo tube as a box to break
 * out of and an operating table as restraints, so without this an AI patient climbs straight back out of
 * cryo. It also passes while a medic has asked us to hold still, so nobody wanders off mid-stitch.
 */
/datum/bt_node/decorator/sp_under_care

/datum/bt_node/decorator/sp_under_care/check_condition(datum/ai_controller/controller)
	var/mob/living/pawn = controller.pawn
	var/obj/machinery/cryo_cell/cryo = pawn.loc
	if(istype(cryo) && cryo.on)
		return TRUE
	if(istype(pawn.buckled, /obj/structure/table/optable) || istype(pawn.buckled, /obj/machinery/stasis))
		return TRUE
	var/until = controller.blackboard[BB_SP_CARE_UNTIL]
	if(isnull(until) || world.time > until)
		return FALSE
	var/mob/living/carer = controller.blackboard[BB_SP_CARER]
	return !QDELETED(carer) && carer.stat == STABLE

/// Stays put for the medic: faces them and does nothing else for a moment.
/datum/bt_node/ai_behavior/sp_hold_still
	time_between_perform = 1 SECONDS

/datum/bt_node/ai_behavior/sp_hold_still/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/pawn = controller.pawn
	var/mob/living/carer = controller.blackboard[BB_SP_CARER]
	if(isturf(pawn.loc) && !QDELETED(carer) && carer != pawn)
		pawn.face_atom(carer)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Hurt, not badly enough to drop everything, and somebody in medical is about to see to it.
/datum/bt_node/decorator/sp_wants_checkup

/datum/bt_node/decorator/sp_wants_checkup/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	// Medical staff are already where the help is; they get seen to where they stand.
	if(!istype(pawn) || istype(controller, /datum/ai_controller/sp_crew/medical))
		return FALSE
	if(sp_in_medbay(pawn) || !sp_needs_checkup(pawn))
		return FALSE
	return sp_medic_on_duty(pawn)

/datum/bt_node/ai_behavior/sp_say/want_checkup
	lines = list(
		"Could somebody take a look at this?",
		"Doc, have you got a minute? I've hurt myself.",
		"I think I need this looked at.",
		"Anyone in? I could use some patching up.",
	)

/datum/bt_node/ai_behavior/sp_say/want_checkup/perform(seconds_per_tick, datum/ai_controller/controller)
	. = ..()
	sp_record("crew.checkup")

/**
 * Waits in medbay to be seen: succeeds once we are patched up, gives up after SP_CHECKUP_PATIENCE.
 * This replaced a fixed fifteen-second wait, after which the safety subtree's cooldown sent the patient
 * back towards their own department for twenty seconds before walking them to medbay all over again.
 */
/datum/bt_node/ai_behavior/sp_await_treatment
	time_between_perform = 2 SECONDS
	/// world.time at which we stop waiting.
	VAR_PRIVATE/give_up_at = 0

/datum/bt_node/ai_behavior/sp_await_treatment/setup(datum/ai_controller/controller)
	give_up_at = world.time + SP_CHECKUP_PATIENCE
	return TRUE

/datum/bt_node/ai_behavior/sp_await_treatment/perform(seconds_per_tick, datum/ai_controller/controller)
	if(!sp_needs_checkup(controller.pawn))
		sp_record("crew.seen_to")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	if(world.time > give_up_at)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return AI_BEHAVIOR_DELAY

/datum/bt_node/ai_behavior/sp_await_treatment/reset_tick_state()
	give_up_at = 0
	..()

// --- The medic's side: patients ---------------------------------------------------------------

/// Picks who to see next (sp_find_patient) into BB_SP_PATIENT. Fails when there is nobody.
/datum/bt_node/ai_behavior/sp_find_patient
	time_between_perform = 2 SECONDS

/datum/bt_node/ai_behavior/sp_find_patient/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	// A medic with nothing to scan and nothing to treat with is no use to a patient; leave them to one who is.
	if(!istype(pawn) || !sp_medic_equipped(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/mob/living/carbon/human/patient = sp_find_patient(pawn, controller)
	if(isnull(patient))
		controller.clear_blackboard_key(BB_SP_PATIENT)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Some patients cannot be got to, and some keep walking off. Give up on one after a while and let them be.
	if(controller.blackboard[BB_SP_PATIENT_ATTEMPT] != patient)
		controller.set_blackboard_key(BB_SP_PATIENT_ATTEMPT, patient)
		controller.set_blackboard_key(BB_SP_PATIENT_ATTEMPT_AT, world.time)
	else if(world.time - controller.blackboard[BB_SP_PATIENT_ATTEMPT_AT] > SP_PATIENT_ATTEMPT_TIMEOUT)
		sp_give_up_on_patient(controller, patient, "could not get to them")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_PATIENT, patient)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Looks the patient over — with a health analyzer if we have one, which the patient sees us do — decides
 * what to do with them (sp_triage), and tells them.
 */
/datum/bt_node/ai_behavior/sp_examine_patient
	/// Who we are looking at, held across the async half.
	var/mob/living/carbon/patient

/datum/bt_node/ai_behavior/sp_examine_patient/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	patient = controller.blackboard[BB_SP_PATIENT]
	if(!istype(pawn) || QDELETED(patient) || !pawn.Adjacent(patient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_examine_patient/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	sp_hold_still(patient, pawn)
	pawn.face_atom(patient)
	if(!isnull(sp_equip_from_inventory(pawn, list(/obj/item/healthanalyzer))))
		sp_ai_click(controller, patient)
		controller.set_blackboard_key_assoc_lazylist(BB_SP_SCANNED, patient, world.time)
		sp_record("med.scanned")
	// Whoever we were called to has been seen.
	if(controller.blackboard[BB_SP_HOUSE_CALL] == patient)
		sp_record("med.house_call_seen")
		sp_house_call_over(controller, "looked them over")
	sp_free_hands(pawn)
	if(!async_still_valid() || QDELETED(patient))
		// finish_async() no-ops once the action is no longer valid, so it is safe on every exit. Without it a
		// patient deleted mid-scan left this leaf RUNNING for good and the medic stuck with it.
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	var/obj/machinery/cryo_cell/cryo = sp_find_cryo_cell(pawn)
	var/obj/structure/table/optable/table = sp_is_surgeon(pawn) ? sp_find_optable(pawn) : null
	var/can_operate = !isnull(table) && sp_surgery_feasible(pawn, patient)
	var/injuries = sp_describe_injuries(patient)
	// A broken bone and no bonesetter on us: go and get the tools off a theatre tray, then come back to them,
	// rather than reaching for a medkit that can do nothing for a fracture.
	if(!can_operate && !isnull(table) && sp_only_needs_surgery(patient) && !isnull(sp_find_surgery_tray(pawn, sp_missing_surgical_kit(pawn))))
		log_sp("[pawn.real_name] looked [patient.real_name] over: [injuries] -> surgery, once they have their tools")
		sp_crew_speak(pawn, "[capitalize(injuries)]. That needs surgery, and I need my tools. Wait here.")
		controller.clear_blackboard_key(BB_SP_SURGICAL_KIT_COOLDOWN)
		sp_give_up_on_patient(controller, patient, "fetching surgical tools first", SP_FETCH_TOOLS_TIME)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	var/plan = sp_triage(patient, !isnull(cryo), can_operate)
	log_sp("[pawn.real_name] looked [patient.real_name] over: [injuries] -> [plan]")
	if(plan == SP_TRIAGE_NONE)
		sp_crew_speak(pawn, pick("Clean bill of health.", "You're in good shape. Off you go.", "Nothing wrong with you that I can see."))
		sp_release_patient(patient, pawn)
		controller.clear_blackboard_key(BB_SP_PATIENT)
		controller.clear_blackboard_key(BB_SP_PATIENT_ATTEMPT)
		// Nothing to do ends the visit here; there is no treatment below for the tree to carry on to.
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	controller.set_blackboard_key(BB_SP_TREATMENT, plan)
	if(plan == SP_TRIAGE_CRYO)
		controller.set_blackboard_key(BB_SP_CRYO_CELL, cryo)
		sp_crew_speak(pawn, "[capitalize(injuries)]. That wants the cryo tube. Come with me.")
	else if(plan == SP_TRIAGE_SURGERY)
		controller.set_blackboard_key(BB_SP_OPTABLE, table)
		sp_crew_speak(pawn, "[capitalize(injuries)]. That needs surgery. Come with me, up on the table.")
	else
		sp_crew_speak(pawn, "[capitalize(injuries)]. Hold still, I'll patch you up.")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/// Passes when the medic has settled on this treatment for the patient.
/datum/bt_node/decorator/sp_treatment_is
	/// One of the SP_TRIAGE_* values.
	var/plan

/datum/bt_node/decorator/sp_treatment_is/check_condition(datum/ai_controller/controller)
	return controller.blackboard[BB_SP_TREATMENT] == plan

/**
 * Works through the patient with whatever we carry, a round at a time (sp_treat_round), until there is
 * nothing more we can do for them or they are done.
 */
/datum/bt_node/ai_behavior/sp_treat_patient
	/// Who we are treating, held across the async half.
	var/mob/living/carbon/patient

/datum/bt_node/ai_behavior/sp_treat_patient/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	patient = controller.blackboard[BB_SP_PATIENT]
	if(!istype(pawn) || QDELETED(patient) || !pawn.Adjacent(patient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_treat_patient/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/damage_before = sp_patch_damage(patient)
	var/bleeding_before = patient.is_bleeding()
	var/patched = FALSE
	var/list/used = list()
	for(var/treatment_round in 1 to SP_TREAT_MAX_ROUNDS)
		if(QDELETED(patient) || patient.stat == DEAD || !pawn.Adjacent(patient))
			break
		var/progress_before = sp_patch_damage(patient) + patient.get_total_bleed_rate()
		var/obj/item/remedy_type = sp_treat_round(controller, patient)
		if(isnull(remedy_type) || !async_still_valid())
			break
		used |= initial(remedy_type.name)
		// A patch does its work slowly once it is on, so one is enough for this visit.
		if(ispath(remedy_type, /obj/item/reagent_containers/applicator/patch))
			patched = TRUE
			break
		// Anything else that changed nothing is not going to on the next go either.
		if(QDELETED(patient) || sp_patch_damage(patient) + patient.get_total_bleed_rate() >= progress_before)
			break
	if(!async_still_valid())
		return
	if(QDELETED(patient))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	var/damage_after = sp_patch_damage(patient)
	controller.clear_blackboard_key(BB_SP_TREATMENT)
	if(!patched && damage_after >= damage_before && !(bleeding_before && !patient.is_bleeding()))
		sp_give_up_on_patient(controller, patient, length(used) ? "what I had made no difference" : "nothing I carry would help")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_release_patient(patient, pawn)
	controller.clear_blackboard_key(BB_SP_PATIENT)
	controller.clear_blackboard_key(BB_SP_PATIENT_ATTEMPT)
	sp_record("med.treated")
	log_sp("[pawn.real_name] treated [patient.real_name] with [english_list(used)]: [round(damage_before, 1)] -> [round(damage_after, 1)] brute and burn")
	if(damage_after < SP_TREAT_DAMAGE)
		// A word of advice, where one is written for the two of them -- and "You again?" for a face they have seen before.
		if(isnull(sp_talk_about(pawn, patient, "treated")))
			sp_crew_speak(pawn, pick("All done. Try to stay in one piece.", "There. You're patched up.", "That's you sorted."))
	else
		sp_crew_speak(pawn, "That's as much as I can do with what I've got.")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/// Takes hold of the patient to walk them over to the cryo tube in BB_SP_CRYO_CELL.
/datum/bt_node/ai_behavior/sp_bring_to_cryo

/datum/bt_node/ai_behavior/sp_bring_to_cryo/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/carbon/patient = controller.blackboard[BB_SP_PATIENT]
	var/obj/machinery/cryo_cell/cryo = controller.blackboard[BB_SP_CRYO_CELL]
	if(!istype(pawn) || QDELETED(patient) || !pawn.Adjacent(patient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(!sp_cryo_ready(cryo))
		// Somebody else got there first, or it ran out since we looked. Another tube, or the medkit.
		cryo = sp_find_cryo_cell(pawn)
		if(isnull(cryo))
			controller.set_blackboard_key(BB_SP_TREATMENT, SP_TRIAGE_TREAT)
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		controller.set_blackboard_key(BB_SP_CRYO_CELL, cryo)
	sp_hold_still(patient, pawn, 2 MINUTES)
	if(pawn.pulling != patient && !pawn.start_pulling(patient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// At the tube with the patient in tow: puts them in (sp_load_into_cryo).
/datum/bt_node/ai_behavior/sp_load_cryo
	/// Who is going in, and where, held across the async half.
	var/mob/living/carbon/patient
	var/obj/machinery/cryo_cell/cryo

/datum/bt_node/ai_behavior/sp_load_cryo/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	patient = controller.blackboard[BB_SP_PATIENT]
	cryo = controller.blackboard[BB_SP_CRYO_CELL]
	if(!istype(pawn) || QDELETED(patient) || QDELETED(cryo) || !pawn.Adjacent(cryo))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_load_cryo/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/damage = sp_patch_damage(patient)
	var/how = sp_load_into_cryo(controller, patient, cryo)
	if(!async_still_valid())
		return
	if(isnull(how))
		log_sp("[pawn.real_name] could not get [patient.real_name] into [cryo.name] (tube [cryo.state_open ? "open" : "shut"], patient at [AREACOORD(patient)])")
		// Better the medkit than nothing, if they are still to hand.
		controller.set_blackboard_key(BB_SP_TREATMENT, SP_TRIAGE_TREAT)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	controller.clear_blackboard_key(BB_SP_PATIENT)
	controller.clear_blackboard_key(BB_SP_PATIENT_ATTEMPT)
	controller.clear_blackboard_key(BB_SP_TREATMENT)
	controller.clear_blackboard_key(BB_SP_CRYO_CELL)
	var/datum/ai_controller/sp_crew/medical/medic = controller
	if(istype(medic))
		medic.watch_cryo(cryo)
	sp_record("med.cryo_loaded")
	log_sp("[pawn.real_name] [how] [patient.real_name] into [cryo.name] with [round(damage, 1)] brute and burn")
	sp_crew_speak(pawn, pick("In you go. The tube will let you out once you're mended.", "Deep breaths. You'll be out when you're fixed up."))
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

// --- The medic's side: setting up cryo ----------------------------------------------------------

/// Passes while the cryo tubes still need something doing that we can do, and no other AI medic is on it.
/datum/bt_node/decorator/sp_cryo_needs_setup

/datum/bt_node/decorator/sp_cryo_needs_setup/check_condition(datum/ai_controller/controller)
	if(world.time < (controller.blackboard[BB_SP_CRYO_SETUP_RETRY] || 0))
		return FALSE
	var/mob/living/carbon/human/pawn = controller.pawn
	for(var/mob/living/carbon/human/other as anything in SSspacestation_sp.ai_crew)
		if(other == pawn || other.stat != STABLE)
			continue
		var/datum/ai_controller/their_ai = other.ai_controller
		if(their_ai && their_ai.blackboard[BB_SP_CRYO_TASK] && world.time - their_ai.blackboard[BB_SP_CRYO_ATTEMPT_AT] < SP_CRYO_ATTEMPT_TIMEOUT)
			return FALSE
	if(isnull(sp_next_cryo_task(pawn)))
		// Ready, still cooling, or short of something we cannot fetch. No need to go over the room every tick.
		controller.set_blackboard_key(BB_SP_CRYO_SETUP_RETRY, world.time + SP_CRYO_SETUP_IDLE_TIME)
		return FALSE
	return TRUE

/// Picks the next cryo setup job (sp_next_cryo_task) into BB_SP_CRYO_TASK and BB_SP_CRYO_TARGET.
/datum/bt_node/ai_behavior/sp_plan_cryo_task

/datum/bt_node/ai_behavior/sp_plan_cryo_task/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/list/next = sp_next_cryo_task(pawn)
	if(isnull(next))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/atom/target = next[2]
	// A job that keeps not getting done — something we cannot path to, a machine that will not take — is left
	// alone for a while rather than walked at forever.
	if(controller.blackboard[BB_SP_CRYO_ATTEMPT] != target)
		controller.set_blackboard_key(BB_SP_CRYO_ATTEMPT, target)
		controller.set_blackboard_key(BB_SP_CRYO_ATTEMPT_AT, world.time)
	else if(world.time - controller.blackboard[BB_SP_CRYO_ATTEMPT_AT] > SP_CRYO_ATTEMPT_TIMEOUT)
		controller.clear_blackboard_key(BB_SP_CRYO_ATTEMPT)
		controller.set_blackboard_key(BB_SP_CRYO_SETUP_RETRY, world.time + SP_CRYO_SETUP_RETRY_TIME)
		log_sp("[pawn.real_name] gave up trying to [next[1]] ([target]) for now")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_CRYO_TASK, next[1])
	controller.set_blackboard_key(BB_SP_CRYO_TARGET, target)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Does the planned cryo setup job (sp_do_cryo_job) once we are standing by it.
/datum/bt_node/ai_behavior/sp_do_cryo_task
	/// The job and what it is done to, held across the async half.
	var/task
	var/atom/target

/datum/bt_node/ai_behavior/sp_do_cryo_task/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	task = controller.blackboard[BB_SP_CRYO_TASK]
	target = controller.blackboard[BB_SP_CRYO_TARGET]
	if(!istype(pawn) || isnull(task) || QDELETED(target) || !pawn.Adjacent(target))
		controller.clear_blackboard_key(BB_SP_CRYO_TASK)
		controller.clear_blackboard_key(BB_SP_CRYO_TARGET)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_do_cryo_task/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/done = sp_do_cryo_job(controller, task, target)
	if(!async_still_valid())
		return
	controller.clear_blackboard_key(BB_SP_CRYO_TASK)
	controller.clear_blackboard_key(BB_SP_CRYO_TARGET)
	if(!done)
		controller.set_blackboard_key(BB_SP_CRYO_SETUP_RETRY, world.time + SP_CRYO_SETUP_RETRY_TIME)
		log_sp("[pawn.real_name] tried to [task] ([target]) for cryo, and it did not take")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	controller.clear_blackboard_key(BB_SP_CRYO_ATTEMPT)
	sp_record("med.cryo_setup")
	log_sp("[pawn.real_name] cryo setup: [task] ([target])")
	if(isnull(sp_next_cryo_task(pawn)))
		sp_announce_cryo_ready(pawn)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

// --- The medic's side: surgery ------------------------------------------------------------------

/// Takes hold of the patient to walk them over to the operating table in BB_SP_OPTABLE.
/datum/bt_node/ai_behavior/sp_bring_to_table

/datum/bt_node/ai_behavior/sp_bring_to_table/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/carbon/patient = controller.blackboard[BB_SP_PATIENT]
	var/obj/structure/table/optable/table = controller.blackboard[BB_SP_OPTABLE]
	if(!istype(pawn) || QDELETED(patient) || !pawn.Adjacent(patient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(QDELETED(table) || table.has_buckled_mobs() || !isnull(table.patient))
		// Somebody else is on it now. Another table, or the medkit.
		table = sp_find_optable(pawn)
		if(isnull(table))
			controller.set_blackboard_key(BB_SP_TREATMENT, SP_TRIAGE_TREAT)
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		controller.set_blackboard_key(BB_SP_OPTABLE, table)
	sp_hold_still(patient, pawn, 5 MINUTES)
	if(pawn.pulling != patient && !pawn.start_pulling(patient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// At the table with the patient in tow: operates (sp_do_surgery).
/datum/bt_node/ai_behavior/sp_operate
	/// Who is on the table, and which table, held across the async half.
	var/mob/living/carbon/human/patient
	var/obj/structure/table/optable/table

/datum/bt_node/ai_behavior/sp_operate/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	patient = controller.blackboard[BB_SP_PATIENT]
	table = controller.blackboard[BB_SP_OPTABLE]
	if(!istype(pawn) || !istype(patient) || QDELETED(table) || !pawn.Adjacent(table))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_operate/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/bones_before = sp_bone_wound_count(patient)
	var/damage_before = sp_patch_damage(patient)
	var/operations = sp_do_surgery(controller, patient, table)
	if(!async_still_valid())
		return
	controller.clear_blackboard_key(BB_SP_OPTABLE)
	controller.clear_blackboard_key(BB_SP_TREATMENT)
	if(QDELETED(patient))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!operations)
		sp_give_up_on_patient(controller, patient, "could not operate")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	controller.clear_blackboard_key(BB_SP_PATIENT)
	controller.clear_blackboard_key(BB_SP_PATIENT_ATTEMPT)
	sp_record("med.surgery")
	sp_record("med.operations", operations)
	log_sp("[pawn.real_name] operated on [patient.real_name]: [operations] step(s), bones [bones_before] -> [sp_bone_wound_count(patient)], brute and burn [round(damage_before, 1)] -> [round(sp_patch_damage(patient), 1)]")
	sp_crew_speak(pawn, pick("All done. Take it easy for a while.", "That's you fixed. Go gently on it.", "Done. You can get up now."))
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/// Surgeons short of a tool in GLOB.sp_surgical_kit, with a tray in the theatre that has it.
/datum/bt_node/decorator/sp_needs_surgical_kit

/datum/bt_node/decorator/sp_needs_surgical_kit/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || !sp_is_surgeon(pawn))
		return FALSE
	var/list/missing = sp_missing_surgical_kit(pawn)
	return length(missing) && !isnull(sp_find_surgery_tray(pawn, missing))

/// Picks the surgery tray to fetch tools from into BB_SP_SURGERY_TRAY.
/datum/bt_node/ai_behavior/sp_find_surgery_tray

/datum/bt_node/ai_behavior/sp_find_surgery_tray/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/list/missing = sp_missing_surgical_kit(pawn)
	var/obj/item/surgery_tray/tray = sp_find_surgery_tray(pawn, missing)
	if(isnull(tray))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_SURGERY_TRAY, tray)
	controller.set_blackboard_key(BB_SP_SURGERY_TRAY_SPOT, sp_reach_spot(tray, pawn))
	var/list/names = list()
	for(var/kind in missing)
		names += sp_tool_kind_name(kind)
	log_sp("[pawn.real_name] fetching [english_list(names)] from [tray.name] at [AREACOORD(tray)]")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Takes what we are missing off the tray, the way the tray's storage lets anyone take one thing at a time.
/datum/bt_node/ai_behavior/sp_take_surgical_tools

/datum/bt_node/ai_behavior/sp_take_surgical_tools/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/item/surgery_tray/tray = controller.blackboard[BB_SP_SURGERY_TRAY]
	controller.clear_blackboard_key(BB_SP_SURGERY_TRAY)
	controller.clear_blackboard_key(BB_SP_SURGERY_TRAY_SPOT)
	if(!istype(pawn) || QDELETED(tray) || !pawn.Adjacent(tray) || isnull(tray.atom_storage))
		log_sp("[pawn?.real_name] could not get at [tray || "the surgery tray"] (adjacent: [pawn && tray ? pawn.Adjacent(tray) : "n/a"])")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/taken = list()
	for(var/obj/item/tool as anything in sp_tray_tools(tray, sp_missing_surgical_kit(pawn)))
		if(!tray.atom_storage.remove_single(pawn, tool, get_turf(pawn), silent = TRUE))
			continue
		if(!(pawn.back && pawn.transferItemToLoc(tool, pawn.back, silent = TRUE)))
			pawn.put_in_hands(tool)
		taken += tool.name
	if(!length(taken))
		log_sp("[pawn.real_name] found nothing they needed on [tray.name]")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_record("med.surgical_kit")
	log_sp("[pawn.real_name] took [english_list(taken)] off [tray.name] for surgery")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Restocking ------------------------------------------------------------------------------------

/// Medical: top up on treatment supplies, out of a locker, from cargo, or by asking botany for aloe.
/datum/bt_node/subtree/sp_medical_restock
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_medical_restock.bt.json"

/// True when a medic has too little left on them to treat anybody with.
/datum/bt_node/decorator/sp_needs_restock

/datum/bt_node/decorator/sp_needs_restock/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	return istype(pawn) && sp_medic_low_on_supplies(pawn)

/// Finds a locker or crate of supplies worth opening.
/datum/bt_node/ai_behavior/sp_find_supply_store
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_supply_store/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/atom/movable/store = sp_find_supply_store(pawn, controller.blackboard[BB_SP_RESTOCK_IGNORE], controller)
	if(isnull(store))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Picked, so not picked again for a while however the walk goes: a crate left somewhere we cannot reach
	// would otherwise send us at the same door every half minute.
	controller.set_blackboard_key_assoc_lazylist(BB_SP_RESTOCK_IGNORE, store, world.time + SP_RESTOCK_IGNORE_TIME)
	controller.set_blackboard_key(BB_SP_RESTOCK_TARGET, store)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Standing by it: opens it and takes what we need. Async, because a locked closet takes two clicks.
/datum/bt_node/ai_behavior/sp_take_supplies
	/// Held across the async half: a locker or crate, or something left out for us.
	VAR_PRIVATE/atom/movable/supply_store

/datum/bt_node/ai_behavior/sp_take_supplies/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	supply_store = controller.blackboard[BB_SP_RESTOCK_TARGET]
	controller.clear_blackboard_key(BB_SP_RESTOCK_TARGET)
	if(!istype(pawn) || QDELETED(supply_store) || !supply_store.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// However it goes, we have had our look inside this one.
	controller.set_blackboard_key_assoc_lazylist(BB_SP_RESTOCK_IGNORE, supply_store, world.time + SP_RESTOCK_IGNORE_TIME)
	return start_async()

/datum/bt_node/ai_behavior/sp_take_supplies/perform_async(datum/ai_controller/controller)
	var/taken = isitem(supply_store) ? sp_pick_up_left_supplies(controller, supply_store) : sp_restock_from(controller, supply_store)
	if(!async_still_valid())
		return
	finish_async(taken ? (AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED) : (AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED))

/datum/bt_node/ai_behavior/sp_take_supplies/finish_action(datum/ai_controller/controller, succeeded)
	supply_store = null
	return ..()

/// Asks cargo for a crate of medical supplies, at most every ten minutes.
/datum/bt_node/ai_behavior/sp_ask_cargo_for_supplies

/datum/bt_node/ai_behavior/sp_ask_cargo_for_supplies/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || world.time < (controller.blackboard[BB_SP_CARGO_ASK_COOLDOWN] || 0))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Somebody in medbay has already asked, and the crate is on its way.
	if(sp_supplies_on_order(/datum/supply_pack/medical/supplies))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_CARGO_ASK_COOLDOWN, world.time + SP_CARGO_ASK_TIME)
	// To medbay, not to wherever we are standing: we may well have noticed we were out halfway across the station.
	if(isnull(sp_request_supplies(/datum/supply_pack/medical/supplies, pawn, sp_medbay_delivery_area())))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_record("med.restock_asked")
	log_sp("[pawn.real_name] asked cargo for a medical supplies crate")
	sp_crew_speak(pawn, pick(
		"Cargo, medbay is low on supplies. Could we get a crate?",
		"We are out of sutures down here. Cargo, a medical crate when you can.",
	), RADIO_CHANNEL_COMMON)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Asks botany for aloe, at most every ten minutes: baked aloe is the cream medics treat burns with.
/datum/bt_node/ai_behavior/sp_ask_botany_for_aloe

/datum/bt_node/ai_behavior/sp_ask_botany_for_aloe/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || world.time < (controller.blackboard[BB_SP_BOTANY_ASK_COOLDOWN] || 0))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Botany already has the request from somebody else in medbay.
	if(sp_plant_requested("aloe"))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_BOTANY_ASK_COOLDOWN, world.time + SP_BOTANY_ASK_TIME)
	sp_record("med.botany_asked")
	log_sp("[pawn.real_name] asked botany for aloe")
	sp_crew_speak(pawn, pick(
		"Botany, could you send some aloe up to medbay? We are short on burn cream.",
		"Any aloe going spare, botany? Medbay could use it.",
	), RADIO_CHANNEL_COMMON)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
