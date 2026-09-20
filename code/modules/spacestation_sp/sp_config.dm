/// Number of AI crew members to spawn automatically when the round starts. 0 disables.
/// Config key: SP_AUTOPOPULATE <number>
/datum/config_entry/number/sp_autopopulate
	default = 0
	integer = TRUE
	min_val = 0
	max_val = 200

/// EXPERIMENTAL: let AI engineers fire the real emitters and run the crystal (needs a correct coolant loop
/// on the map; MetaStation's waste filters still need work). Off by default: the engine is simulated instead.
/// Config key: SP_ENGINE_REAL_EMITTERS
/datum/config_entry/flag/sp_engine_real_emitters

/// Simulated engine output in kilowatts, fed into the station SMES units while an AI engineer has the
/// engine "online" (coolant loop set up, chamber full of nitrogen). Config key: SP_ENGINE_SIMULATED_OUTPUT <kW>
/datum/config_entry/number/sp_engine_simulated_output
	default = 1500
	integer = TRUE
	min_val = 0
	max_val = 100000

/// Debug: punch this many hull breaches a minute after round start, to exercise the repair behaviour
/// in headless tests. 0 (the default) disables it. Config key: SP_DEBUG_BREACH_COUNT <number>
/datum/config_entry/number/sp_debug_breach_count
	default = 0
	integer = TRUE
	min_val = 0
	max_val = 50

/// Debug: two minutes into the round, have a random non-cargo crew member ask cargo for a crate, so the
/// request-and-deliver path can be exercised without waiting for a department to want something.
/// Config key: SP_DEBUG_SUPPLY_REQUEST
/datum/config_entry/flag/sp_debug_supply_request

/// Debug: a minute into the round, lay a set of ready-made components out on the chef's prep table, so
/// the cooking and serving half of the kitchen can be exercised without first waiting out the whole
/// cutting, mixing and baking chain. Config key: SP_DEBUG_KITCHEN_STOCK
/datum/config_entry/flag/sp_debug_kitchen_stock

/// Debug: ninety seconds into the round, hurt a few crew members — a cut arm, a burned leg, and one
/// badly enough to need cryo — so triage, treatment and the cryo tubes can be watched without waiting
/// for an accident. Config key: SP_DEBUG_MEDICAL_PATIENTS
/datum/config_entry/flag/sp_debug_medical_patients

/// Debug: two minutes in, empty the medics' pockets of treatment supplies, so restocking out of a locker,
/// from cargo and from botany can be watched without waiting for a shift's worth of patients to use them
/// up. Config key: SP_DEBUG_MEDBAY_DRY
/datum/config_entry/flag/sp_debug_medbay_dry

/// Whether the greytide's malicious streak is switched on: some assistants breaking a light tube here and
/// there, on top of the harmless pranks. On by default; it is still gated per-assistant and never turns
/// violent. Config key: SP_GREYTIDE_MALICE
/datum/config_entry/flag/sp_greytide_malice
	default = TRUE

/// Debug: shortly into the round, turn one random AI crew member into a thief with a scheme, so the
/// antagonist path can be watched in a headless round. Config key: SP_DEBUG_ANTAGONIST
/datum/config_entry/flag/sp_debug_antagonist

/// Whether an SP antagonist should also be given a silent TG traitor datum, so the rest of the game counts
/// them as a real antagonist (codewords, round-end report). Off by default: with no client the round-end
/// report prints a blank key and codewords are broadcast to a crew of NPCs. The scheme drives behaviour
/// either way. Config key: SP_ANTAG_TG_DATUM
/datum/config_entry/flag/sp_antag_tg_datum

/// How many AI assistants join the station at roundstart, on top of SP_AUTOPOPULATE: a random number between
/// these two. They are the station's greytide (sp_greytide.dm). Config keys: SP_ASSISTANTS_MIN, SP_ASSISTANTS_MAX
/datum/config_entry/number/sp_assistants_min
	default = 1
	integer = TRUE
	min_val = 0
	max_val = 20

/datum/config_entry/number/sp_assistants_max
	default = 3
	integer = TRUE
	min_val = 0
	max_val = 20

/// Debug: a couple of minutes in, convince the head of security the shift has turned badly, so the alert
/// ladder, the armoury and the arming orders can all be watched without waiting on a real fight.
/// Config key: SP_DEBUG_SECURITY_ALARM
/datum/config_entry/flag/sp_debug_security_alarm

/// Debug: three minutes in, give somebody a record worth arresting them over and send an officer to have a
/// word, so the arrest ladder, the cuffs and the cell can be watched without waiting on the greytide to
/// misbehave three times in front of a witness. Config key: SP_DEBUG_ARREST
/datum/config_entry/flag/sp_debug_arrest
