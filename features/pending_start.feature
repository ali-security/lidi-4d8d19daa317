# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
# Regression test for dispatch.rs pending_start fix (commit 5ad6823).
#
# Root cause: with two UDP ports, lidi-send spawns two independent UDP worker
# threads that both pull encoded blocks from the shared for_udp queue and each
# maintain their own block_id counter.  The OS scheduler can cause the worker
# that encoded a Data block to write to the shared for_dispatch channel before
# the worker that encoded the corresponding Start block, even though Start was
# produced first.
#
# Before the fix, dispatch.rs dropped any Data/Abort/End block whose client_id
# had no entry in active_transfers yet.  After the fix, such blocks are buffered
# in a pending_start map and consumed when the matching Start arrives.
#
# How the race is exposed here:
#   Port 5001 receives a 50 ms network delay via tc netem (limit=10000 prevents
#   queue overflow).  Whichever worker happens to pull the Start block and send
#   it to port 5001 delivers Start 50 ms later than the other worker delivers
#   Data blocks over the undelayed port 5000.  A 1 MB file produces ~55 blocks;
#   the fast worker finishes encoding all of them in ~9 ms, so both Data and End
#   arrive at dispatch ~41 ms before the 50 ms Start delay expires.  Two races
#   are triggered simultaneously and must both be handled correctly:
#
#     (a) Data before Start: a Data block arrives at dispatch when the client
#         has no active_transfers entry yet.  pending_start buffers it.
#     (b) End before Start: End also arrives before Start, meaning it too must
#         be buffered — NOT removed — from the pending_start entry so that when
#         Start finally arrives it claims the pre-filled channel (Data + End).
#
#   Without the fix: the first Data block is silently dropped, client_reorder
#   parks every subsequent block waiting for the missing seq=1 block, and the
#   transfer stalls until abort_timeout aborts it — the file is never received.
#   With the fix: Data and End are buffered in pending_start; Start claims the
#   pre-filled channel and hands it to the client which reads all blocks normally.
#
Feature: Dispatch buffers Data blocks arriving before Start (pending_start fix)

  Scenario: All files received when Start port has a network delay relative to Data port
    Given abort_timeout is configured to 5 seconds
    And lidi is started with 2 UDP ports where port 5001 has a 50ms delay
    When lidi-file-send 10 files of size 1MB
    Then lidi-file-receive all files in 30 seconds
