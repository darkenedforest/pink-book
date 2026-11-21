# Write and read using two separate processes, using the production ReaderStore.
file(REMOVE "${CHECKPOINT}")
execute_process(COMMAND "${READER}" --check-progress write "${CHECKPOINT}" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${READER}" --check-progress read "${CHECKPOINT}" COMMAND_ERROR_IS_FATAL ANY)
file(REMOVE "${CHECKPOINT}")
