/**
 * @description Persists log events. All logic is in `LogEventsDomain`, bound by
 * `DI_Binding.Log_Events_Domain`; `Trigger_Setting__mdt` can switch persistence off (ADR 0005).
 */
trigger LogEventTrigger on Log_Event__e(after insert) {
  TriggerDispatcher.run();
}
