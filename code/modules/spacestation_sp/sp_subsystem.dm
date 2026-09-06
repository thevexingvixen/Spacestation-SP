/**
 * Spacestation SP coordinator.
 *
 * Holds SP-wide state (the list of AI crew) and hooks round start so the station can be
 * auto-populated with AI crew via the SP_AUTOPOPULATE config entry.
 */
SUBSYSTEM_DEF(spacestation_sp)
	name = "Spacestation SP"
	ss_flags = SS_NO_FIRE
	/// Every AI crew member we have spawned this round (weakref-free: cleaned via COMSIG_QDELETING).
	var/list/mob/living/carbon/human/ai_crew = list()

/datum/controller/subsystem/spacestation_sp/Initialize()
	SSticker.OnRoundstart(CALLBACK(src, PROC_REF(on_roundstart)))
	return SS_INIT_SUCCESS

/datum/controller/subsystem/spacestation_sp/stat_entry(msg)
	msg = "AI crew: [length(ai_crew)]"
	return ..()

/// Fires once the round has started and player characters have been placed.
/datum/controller/subsystem/spacestation_sp/proc/on_roundstart()
	var/count = CONFIG_GET(number/sp_autopopulate)
	if(count <= 0)
		return
	var/spawned = sp_populate_station(count)
	log_sp("auto-populated the station with [spawned]/[count] AI crew")

/// Registers a spawned AI crew member so we can track and clean it up.
/datum/controller/subsystem/spacestation_sp/proc/register_crew(mob/living/carbon/human/crew)
	ai_crew |= crew
	RegisterSignal(crew, COMSIG_QDELETING, PROC_REF(on_crew_deleted))

/datum/controller/subsystem/spacestation_sp/proc/on_crew_deleted(datum/source)
	SIGNAL_HANDLER
	ai_crew -= source
