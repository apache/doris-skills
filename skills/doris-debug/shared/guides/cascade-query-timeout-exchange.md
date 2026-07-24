# Cascade: Query Timeout ↔ Exchange / brpc

```
query_timeout
 → Profile EXCHANGE WaitForData ≈ timeout
 → SINK PendingFinish / RpcCount=0
 → be.WARNING: failed to send brpc when exchange | E1008 @:8060
 → SHOW BACKENDS Alive=true (misleading)
```

Skill: `query` (Cause D)  
Code: `exchange_sink_buffer.h`, `reset_rpc_channel_action.cpp`  
Mitigation: `curl http://be:8040/api/reset_rpc_channel/all` (clears internal cache only)
