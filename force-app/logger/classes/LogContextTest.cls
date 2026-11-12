@IsTest
private class LogContextTest {
  @IsTest
  static void nextSequence_repeatedCalls_countsUpFromCurrent() {
    Integer first = LogContext.nextSequence();
    Integer second = LogContext.nextSequence();
    Integer third = LogContext.nextSequence();

    Assert.areEqual(first + 1, second, 'Each call claims the next number');
    Assert.areEqual(second + 1, third, 'Each call claims the next number');
  }

  @IsTest
  static void requestId_withinTransaction_isStableAndMatchesRequest() {
    String requestId = LogContext.requestId();

    Assert.isFalse(String.isBlank(requestId), 'A request Id is always available');
    Assert.areEqual(Request.getCurrent().getRequestId(), requestId, 'It is the Apex request Id');
    Assert.areEqual(requestId, LogContext.requestId(), 'It is read once and stays the same');
  }

  @IsTest
  static void quiddity_inTestContext_namesTheContext() {
    Assert.areEqual(Request.getCurrent().getQuiddity().name(), LogContext.quiddity(), 'The Quiddity name');
  }
}
