/// Number of AI crew members to spawn automatically when the round starts. 0 disables.
/// Config key: SP_AUTOPOPULATE <number>
/datum/config_entry/number/sp_autopopulate
	default = 0
	integer = TRUE
	min_val = 0
	max_val = 200
