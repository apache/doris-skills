# 级联：查询超时 ↔ Exchange / brpc

```
query_timeout
 → Profile EXCHANGE WaitForData ≈ 超时
 → SINK PendingFinish / RpcCount=0
 → be.WARNING: failed to send brpc when exchange | E1008 @:8060
 → SHOW BACKENDS Alive=true（易误判）
```

Skill：`query`（Cause D）  
代码：`exchange_sink_buffer.h`、`reset_rpc_channel_action.cpp`  
止血：`curl http://be:8040/api/reset_rpc_channel/all`（仅 internal cache）
