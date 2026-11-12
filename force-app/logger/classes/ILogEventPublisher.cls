/**
 * @description Seam over `EventBus.publish` for `Log_Event__e`, so `LogBuffer` unit tests can
 * stub publish results and failures with the Stub API. The production implementation is
 * `EventBusPublisher`.
 * @group Logging
 */
public interface ILogEventPublisher {
  /**
   * @description Publishes the events in one call.
   * @param events The events to publish; never empty.
   * @return One result per event, in order.
   */
  List<Database.SaveResult> publish(List<Log_Event__e> events);
}
