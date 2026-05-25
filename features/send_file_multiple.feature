# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
Feature: Send several files at the same time

  Scenario: Send 10x1K file without drop
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send 10 files of size 1KB
    Then lidi-file-receive all files in 5 seconds

  Scenario: Send 10x10K file without drop
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send 10 files of size 10KB
    Then lidi-file-receive all files in 5 seconds

  Scenario: Send 10x100K file without drop
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send 10 files of size 100KB
    Then lidi-file-receive all files in 5 seconds

  Scenario: Send 10x100M file without drop
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send 10 files of size 100MB
    Then lidi-file-receive all files in 5 seconds

  Scenario: Send 100x10K files at once
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send 100 files of size 10KB
    Then lidi-file-receive all files in 30 seconds

  Scenario: Send 500x1K files at once
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send 500 files of size 1KB
    Then lidi-file-receive all files in 60 seconds

  @known-limit
  Scenario: Send 1000x1K files at once (exploratory - may hit OS limits)
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send 1000 files of size 1KB
    Then lidi-file-receive all files in 120 seconds
