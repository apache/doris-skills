# Case: Timeout = EXCHANGE WaitForData + E1008

## Symptom
Receiver WaitForData≈timeout, sender scan ms-level, RpcCount=0. Alive=true.

## Root cause
brpc `:8060` path stuck; not SQL/CPU.

## Fix direction
`log-grep --pack exchange`; `reset_rpc_channel/all`; `enable_brpc_connection_check`; verify `priority_networks`.

Source: `exchange_sink_buffer.h`, `reset_rpc_channel_action.cpp`.
