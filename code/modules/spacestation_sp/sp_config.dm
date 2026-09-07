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
