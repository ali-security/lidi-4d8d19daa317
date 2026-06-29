Feature: Incomplete transfer cleanup

  # A transfer interrupted before its announced length is fully
  # received used to leave a partial, corrupted file on the receiving side.
  # lidi-clients/src/file/receive.rs now removes that partial file and logs
  # the failure as an error instead.
  Scenario: An interrupted transfer must not leave a partial file behind
    # Client 1 sends a 5MB file: on loopback this is large enough that
    # lidi-file-send is still blocked writing to the socket (backpressure
    # from the throttled UDP link) when it gets killed after 1 second, so
    # the transfer is genuinely interrupted mid-stream rather than already
    # finished.
    Given lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_partial" of size 5MB
    And client 1 is killed after 1 seconds
    Then lidi-file-receive log should report an error for an incomplete transfer
    And file "input_partial" should not be received
