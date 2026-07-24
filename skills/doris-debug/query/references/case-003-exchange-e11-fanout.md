---
type: reference
category: query
keywords: [E11, exchange, brpc, fanout, Resource temporarily unavailable, parallel_exchange_instance_num]
---

# Case-003: 高峰期 Exchange brpc E11 — 并发 fragment 过多导致 RPC 发送侧打满

## Environment

- Doris version: 4.0.7 (cloud)
- Architecture: storage-compute separation, 3 BE in compute group

## Symptom

高峰期 10:00~10:30 大量查询和导入报错：
```
failed to send brpc when exchange, error=Resource temporarily unavailable,
error_text=[E11]Resource temporarily unavailable @10.244.0.29:8060
```
伴随 `RPC meet failed: [E11]`、`pipeline_fragment_context.cpp:171] cancel`、导入 `cancel node channel`。

## Key evidence

### 时间分布（E11 命中统计）

| 时间 | E11 日志行数 | 去重 query_id |
|------|-------------|-------------|
| 10:00 | 7,282 | 46 |
| 10:03 | 35,639 | 58 |
| 10:10 | 248 | 2 |
| 10:25 | 79,391 | 107 |
| 10:26 | 47,766 | 125 |
| 10:27 | 29,522 | 68 |

高峰集中在 10:25~10:27，全窗口去重 query_id 共 406 个。

### 目标端分布

```
10.244.0.29:8060  → 144,181 行
10.244.0.20:8060  →  55,419 行
10.244.0.10:8060  →     248 行
```

E11 集中在两台 BE，不是全集群均匀分布。发送端样例：
```
10.244.0.10 → 10.244.0.29/20
10.244.0.20 → 10.244.0.29
```

### Fragment 并发量

```
10:25:01  fragment_num: 1575 / 1556 / 1326  (三台BE)
10:25:21  fragment_num: 2056  (10.244.0.10)
10:26:42  fragment_num: 2108
10:27:12  fragment_num: 2444
```

BE `fragment_mgr.cpp` 每分钟启动 fragment 行数：
```
10:17: 15,296
10:20:  9,020
10:25:  7,994
10:26:  6,902
10:27:  8,046
```

### 并行度配置

```sql
parallel_exchange_instance_num         = 100    ← 关键
parallel_fragment_exec_instance_num    = 8
parallel_pipeline_task_num             = 0
```

### 排除项

日志中未检索到以下信号：
- `pthread_create failed` / `failed to create thread` → 不是线程池耗尽
- `queue is full` / `EOVERCROWDED` → 不是队列溢出
- `too many open files` → 不是 FD 耗尽
- `MEM_LIMIT_EXCEEDED` → 不是内存限制

## Investigation

### Step 1: 确认错误来源

代码路径（4.0.7）：
```
be/src/pipeline/exec/exchange_sink_buffer.h
  ExchangeSendCallback::call()
    → brpc::Controller::Failed()
    → "failed to send brpc when exchange, error={}, error_text={}"
```

这是 BE-BE exchange RPC 发送路径失败，不是 SQL 语义错误，也不是 FE thrift/mysql 线程池拒绝。

### Step 2: 区分 E11 brpc vs pthread_create EAGAIN

两者都显示 "Resource temporarily unavailable"，但含义完全不同：

| 信号 | 含义 |
|------|------|
| `[E11]` + `failed to send brpc when exchange` | brpc socket 发送侧 EAGAIN，socket send buffer 满或对端接收慢 |
| `pthread_create failed (EAGAIN)` + `cgroup: fork rejected by pids controller` | 线程/pids 限制打满 |

当前日志是前者，不应按线程池扩容处理。

### Step 3: 判断故障范围

E11 集中在两台 BE（29 和 20），BE 10 几乎不受影响。且同窗口 FE load job dispatch 每分钟 398~1360 次，导入与查询同时高并发。

## Root Cause

高并发 LOAD + SELECT 叠加，`parallel_exchange_instance_num=100` + 默认 pipeline 并行度，导致真实同时执行的 fragment/exchange RPC 数远超 brpc socket 处理能力。发送侧 socket send buffer 满 → brpc controller 返回 E11 → query/load cancel。

这是已知问题族，历史同类 case 均通过降低 exchange/pipeline 并行度缓解。

## Fix

- **短期**: 调小 `parallel_exchange_instance_num`（100 → 50 或 32），控制 exchange fanout
- **中期**: 对高峰期 workload 加 Workload Group 并发/排队限制
- **长期**: backport apache/doris PR #50113（one rpc send multi blocks，减少 RPC 次数）

调参顺序：
1. 先只调 `parallel_exchange_instance_num`: 100 → 50 观察
2. 如仍复现 → 继续降到 32 或配合降低 `parallel_pipeline_task_num` 到 1
3. 不要盲目增大线程池参数（当前没有线程池 reject 证据，增线程只会放大 E11）

## Key diagnostic actions

1. 确认错误前缀是 `failed to send brpc when exchange`（能确认是 exchange brpc 路径）
2. 统计 E11 目标 BE 分布：单点 vs 全集群（不同处理方向）
3. 提取窗口内 fragment_num / fragment 启动量（确认 fanout 规模）
4. 检索排除 pthread_create / pids / FD 耗尽信号
5. 确认 `parallel_exchange_instance_num` / `parallel_pipeline_task_num` 当前值
6. 历史同类案例检索：`failed to send brpc when exchange, [E11]` 问题族
